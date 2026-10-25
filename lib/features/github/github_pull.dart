part of 'github_api.dart';

class GitHubRemoteEntry {
  final String path, sha;
  final int size;
  final bool isDirectory;
  const GitHubRemoteEntry(this.path, this.sha, this.size, this.isDirectory);
  String get name => path.split('/').last;
}

class GitHubListing {
  final GitHubTarget target;
  final String commit;
  final List<GitHubRemoteEntry> entries;
  const GitHubListing(this.target, this.commit, this.entries);
}

class GitHubPullResult {
  final String path;
  final int files, bytes;
  const GitHubPullResult(this.path, this.files, this.bytes);
}

class _LfsPointer {
  final String oid;
  final int size;
  const _LfsPointer(this.oid, this.size);
  static _LfsPointer? parse(List<int> bytes) {
    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\r\n', '\n');
    if (!text.startsWith('version https://git-lfs.github.com/spec/')) {
      return null;
    }
    final match = RegExp(
      r'^version https://git-lfs.github.com/spec/v1\noid sha256:([a-f0-9]{64})\nsize ([0-9]+)\n?$',
    ).firstMatch(text);
    final size = int.tryParse(match?.group(2) ?? '');
    if (match == null || size == null || size < 0 || size > 1 << 50) {
      throw const GitHubFailure(
        'Unsupported or invalid Git LFS pointer. No pointer file was saved as your download.',
      );
    }
    return _LfsPointer(match.group(1)!, size);
  }
}

extension GitHubPull on GitHubApi {
  Future<List<Map<String, dynamic>>> _directory(
    GitHubTarget target,
    String sha, {
    bool forDisplay = false,
  }) async {
    final data = await _json('GET', [..._root(target), 'git', 'trees', sha]);
    if (data['truncated'] != false ||
        data['tree'] is! List ||
        (forDisplay && (data['tree'] as List).length > 1000)) {
      throw const GitHubFailure(
        'This directory is too large to browse safely (maximum 1,000 entries). Enter a narrower repository folder.',
      );
    }
    return (data['tree'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  /// Folder navigation stays at one immutable commit until Refresh is pressed.
  Future<GitHubListing> browse(GitHubTarget target, {String? commit}) async {
    if (commit == null) {
      final ref = await _json('GET', _ref(target));
      commit = _sha((ref['object'] as Map)['sha']);
    } else {
      _sha(commit);
    }
    final info = await _json('GET', [
      ..._root(target),
      'git',
      'commits',
      commit,
    ]);
    var tree = _sha((info['tree'] as Map)['sha']);
    for (final folder
        in target.folder.isEmpty ? <String>[] : target.folder.split('/')) {
      final children = await _directory(target, tree);
      final entry = children.where((e) => e['path'] == folder).firstOrNull;
      if (entry == null || entry['type'] != 'tree') {
        throw const GitHubFailure(
          'Repository folder not found at this commit.',
        );
      }
      tree = _sha(entry['sha']);
    }
    final result = <GitHubRemoteEntry>[];
    for (final entry in await _directory(target, tree, forDisplay: true)) {
      final name = entry['path'];
      if (name is! String) {
        throw const GitHubFailure('Invalid repository directory entry.');
      }
      if (name.contains('/')) continue;
      final path = target.folder.isEmpty ? name : '${target.folder}/$name';
      // A repository may contain names which cannot safely be saved on Windows.
      // Omit unsupported entries rather than ever interpreting their paths.
      try {
        githubPath(path);
      } on FormatException {
        continue;
      } on GitHubFailure {
        continue;
      }
      final directory = entry['type'] == 'tree' && entry['mode'] == '040000';
      final file =
          entry['type'] == 'blob' &&
          {'100644', '100755'}.contains(entry['mode']);
      if (!directory && !file) continue; // No symlinks or submodules.
      final size = directory ? 0 : entry['size'];
      if (size is! int || size < 0 || size > githubMaxFileBytes) continue;
      result.add(GitHubRemoteEntry(path, _sha(entry['sha']), size, directory));
    }
    result.sort(
      (a, b) => a.isDirectory != b.isDirectory
          ? (a.isDirectory ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return GitHubListing(target, commit, List.unmodifiable(result));
  }

  Future<void> _streamToFile(
    HttpClientRequest request,
    File file,
    int expected,
    Hash algorithm,
    String digest,
    void Function(int) progress, {
    bool gitBlob = false,
  }) async {
    final sink = _DigestSink();
    final hash = algorithm.startChunkedConversion(sink);
    if (gitBlob) hash.add(utf8.encode('blob $expected\x00'));
    final response = await request.close().timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      request.abort();
      throw GitHubFailure(
        'GitHub download failed (HTTP ${response.statusCode}). Check repository/token access or Git LFS bandwidth.',
      );
    }
    if (response.contentLength >= 0 && response.contentLength != expected) {
      request.abort();
      throw const GitHubFailure('GitHub returned an unexpected file length.');
    }
    final output = await file.open(mode: FileMode.write);
    var count = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        _checkCancelled();
        count += chunk.length;
        if (count > expected) {
          throw const GitHubFailure('Download exceeds its declared size.');
        }
        hash.add(chunk);
        await output.writeFrom(
          chunk,
        ); // Backpressure; never buffer the entire file.
        progress(count);
      }
      hash.close();
      if (count != expected || sink.value.toString() != digest) {
        throw const GitHubFailure(
          'Download integrity check failed. Incomplete or corrupted data was discarded.',
        );
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }

  bool _trustedDownload(Uri uri) {
    if (_base.scheme == 'http') {
      return uri.scheme == 'http' &&
          uri.host == _base.host &&
          uri.port == _base.port &&
          uri.userInfo.isEmpty;
    }
    return uri.scheme == 'https' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        (uri.host == 'github.com' ||
            uri.host.endsWith('.githubusercontent.com') ||
            uri.host == 'github-cloud.s3.amazonaws.com');
  }

  Future<HttpClientRequest> _lfsDownload(
    GitHubTarget target,
    _LfsPointer pointer,
  ) async {
    _checkCancelled();
    final parts = [
      target.owner,
      '${target.repository}.git',
      'info',
      'lfs',
      'objects',
      'batch',
    ];
    final uri = _base.scheme == 'http'
        ? _base.replace(pathSegments: parts)
        : Uri.https('github.com', '/${parts.join('/')}');
    final batch = await _client.openUrl('POST', uri);
    batch.followRedirects = false;
    batch.headers.set(HttpHeaders.acceptHeader, 'application/vnd.git-lfs+json');
    batch.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/vnd.git-lfs+json',
    );
    batch.headers.set(HttpHeaders.userAgentHeader, 'SwiftDrop');
    if (_token.isNotEmpty) {
      batch.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64.encode(utf8.encode('x-access-token:$_token'))}',
      );
    }
    final body = utf8.encode(
      jsonEncode({
        'operation': 'download',
        'transfers': ['basic'],
        'ref': {'name': 'refs/heads/${target.branch}'},
        'objects': [
          {'oid': pointer.oid, 'size': pointer.size},
        ],
      }),
    );
    batch.contentLength = body.length;
    batch.add(body);
    final result = await _response(batch);
    final objects = result['objects'];
    if (objects is! List || objects.length != 1) {
      throw const GitHubFailure('Invalid Git LFS batch response.');
    }
    final object = objects.single as Map;
    if (object['error'] != null ||
        object['oid'] != pointer.oid ||
        object['size'] != pointer.size) {
      throw const GitHubFailure(
        'Git LFS object is unavailable. Check access and repository bandwidth/storage quota.',
      );
    }
    final action = (object['actions'] as Map?)?['download'] as Map?;
    final href = action?['href'];
    final url = href is String ? Uri.tryParse(href) : null;
    if (url == null || !_trustedDownload(url)) {
      throw const GitHubFailure(
        'Git LFS returned an unsupported download host.',
      );
    }
    final request = await _client.openUrl('GET', url);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, 'SwiftDrop');
    final headers = action?['header'];
    if (headers is Map) {
      for (final entry in headers.entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            !{
              'authorization',
              'accept',
            }.contains((entry.key as String).toLowerCase()) ||
            (_token.isNotEmpty && (entry.value as String).contains(_token))) {
          request.abort();
          throw const GitHubFailure('Unsafe Git LFS download headers.');
        }
        request.headers.set(entry.key as String, entry.value as String);
      }
    }
    // Signed object URLs normally return content directly. Redirects are never
    // followed; neither a GitHub token nor a storage credential can escape.
    return request;
  }

  Future<void> _safeDirectory(Directory directory) async {
    final parent = directory.parent;
    if (parent.path != directory.path) await _safeDirectory(parent);
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      await directory.create();
    } else if (type != FileSystemEntityType.directory) {
      throw const GitHubFailure(
        'Download destination contains a symbolic link or is not a folder.',
      );
    }
  }

  Future<GitHubPullResult> pull(
    GitHubListing listing,
    List<GitHubRemoteEntry> files,
    Directory destination,
    void Function(GitHubProgress) onProgress,
  ) async {
    if (files.isEmpty || files.length > githubMaxFiles) {
      throw const GitHubFailure(
        'Select between 1 and 200 repository files to pull.',
      );
    }
    final known = {for (final entry in listing.entries) entry.path: entry};
    final paths = <String>{};
    for (final entry in files) {
      githubPath(entry.path);
      if (entry.isDirectory ||
          !identical(known[entry.path], entry) ||
          !paths.add(entry.path.toLowerCase())) {
        throw const GitHubFailure(
          'Invalid, duplicate or unreviewed pull selection. Browse the repository again.',
        );
      }
    }
    final root = Directory(
      p.join(
        p.absolute(destination.path),
        'GitHub-${DateTime.now().millisecondsSinceEpoch}-${randomToken(9)}',
      ),
    );
    final stage = Directory(p.join(root.path, 'staging'));
    var success = false;
    var done = 0;
    var total = files.fold<int>(0, (sum, f) => sum + f.size);
    await _safeDirectory(Directory(p.absolute(destination.path)));
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const GitHubFailure('Download folder collision. Retry the pull.');
    }
    try {
      await stage.create(recursive: true);
      final parts = await Directory(p.join(root.path, 'parts')).create();
      for (var i = 0; i < files.length; i++) {
        _checkCancelled();
        final entry = files[i];
        final part = File(p.join(parts.path, '$i.part'));
        final request = await _open('GET', [
          ..._root(listing.target),
          'git',
          'blobs',
          entry.sha,
        ]);
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github.raw+json',
        );
        onProgress(GitHubProgress('Downloading', entry.path, done, total));
        await _streamToFile(request, part, entry.size, sha1, entry.sha, (
          bytes,
        ) {
          if (entry.size > 1024) {
            onProgress(
              GitHubProgress('Downloading', entry.path, done + bytes, total),
            );
          }
        }, gitBlob: true);
        final pointer = entry.size <= 1024
            ? _LfsPointer.parse(await part.readAsBytes())
            : null;
        var size = entry.size;
        if (pointer != null) {
          size = pointer.size;
          total += size - entry.size;
          onProgress(
            GitHubProgress('Downloading Git LFS', entry.path, done, total),
          );
          final lfs = await _lfsDownload(listing.target, pointer);
          await _streamToFile(
            lfs,
            part,
            size,
            sha256,
            pointer.oid,
            (bytes) => onProgress(
              GitHubProgress(
                'Downloading Git LFS',
                entry.path,
                done + bytes,
                total,
              ),
            ),
          );
        }
        final output = File(p.joinAll([stage.path, ...entry.path.split('/')]));
        await _safeDirectory(output.parent);
        await part.rename(output.path);
        done += size;
        onProgress(GitHubProgress('Verified', entry.path, done, total));
      }
      _checkCancelled();
      onProgress(
        GitHubProgress(
          'Finalizing download',
          '',
          done,
          total,
          canCancel: false,
        ),
      );
      final saved = await stage.rename(p.join(root.path, 'files'));
      await parts.delete();
      success = true;
      onProgress(GitHubProgress('Complete', '', done, total, canCancel: false));
      return GitHubPullResult(saved.path, files.length, done);
    } finally {
      // Only this newly created batch is removed; existing user files are never
      // overwritten. Completed downloads publish by renaming the whole stage.
      if (!success && await root.exists()) await root.delete(recursive: true);
    }
  }
}
