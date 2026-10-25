import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/protocol.dart';
import '../transfer/sender.dart';

part 'github_pull.dart';

const githubMaxFileBytes = 100 * 1024 * 1024;
const githubMaxFiles = 200;

class GitHubFailure implements Exception {
  final String message;
  const GitHubFailure(this.message);
  @override
  String toString() => message;
}

class GitHubTarget {
  final String owner, repository, branch, folder;
  GitHubTarget(String repository, String branch, String folder)
    : owner = _repository(repository).$1,
      repository = _repository(repository).$2,
      branch = branch.trim(),
      folder = folder.trim() {
    final parts = this.branch.split('/');
    if (this.branch.isEmpty ||
        this.branch.length > 250 ||
        this.branch == '@' ||
        this.branch.contains('..') ||
        this.branch.contains('@{') ||
        this.branch.contains(RegExp(r'[\x00-\x20\x7f~^:?*\[\\]')) ||
        parts.any(
          (p) => p.isEmpty || p.startsWith('.') || p.endsWith('.lock'),
        ) ||
        this.branch.endsWith('.')) {
      throw const GitHubFailure('Enter a valid existing Git branch name.');
    }
    if (this.folder.isNotEmpty) githubPath(this.folder);
  }

  static (String, String) _repository(String value) {
    var name = value.trim();
    if (name.startsWith('https://github.com/')) {
      name = name.substring('https://github.com/'.length);
    }
    if (name.endsWith('/')) name = name.substring(0, name.length - 1);
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    final parts = name.split('/');
    if (parts.length != 2 ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$').hasMatch(parts[0]) ||
        !RegExp(r'^[a-zA-Z0-9_.-]{1,100}$').hasMatch(parts[1]) ||
        {'.', '..'}.contains(parts[1])) {
      throw const GitHubFailure('Use owner/repository or its github.com URL.');
    }
    return (parts[0], parts[1]);
  }

  String get name => '$owner/$repository';
  String pathFor(SourceFile file) => githubPath(
    folder.isEmpty ? file.relativePath : '$folder/${file.relativePath}',
  );
}

String githubPath(String value) {
  safeRelativePath(value);
  if (value.split('/').any((p) => p.toLowerCase() == '.git')) {
    throw const GitHubFailure('The .git directory cannot be uploaded.');
  }
  return value;
}

class GitHubUploadFile {
  final SourceFile source;
  final String path;
  final FileStat stat;
  final String mode;
  final bool replaces;
  GitHubUploadFile(this.source, this.path, this.stat, this.mode, this.replaces);
}

class GitHubPlan {
  final GitHubTarget target;
  final String head, tree;
  final bool isPrivate;
  final List<GitHubUploadFile> files;
  GitHubPlan(this.target, this.head, this.tree, this.isPrivate, this.files);
  int get totalBytes => files.fold(0, (sum, f) => sum + f.stat.size);
  int get replacements => files.where((f) => f.replaces).length;
}

class GitHubProgress {
  final String state, file;
  final int bytes, total;
  final bool canCancel;
  const GitHubProgress(
    this.state,
    this.file,
    this.bytes,
    this.total, {
    this.canCancel = true,
  });
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Git Database API: stage blobs, create one tree/commit, then fast-forward the
/// branch. An interrupted blob upload never publishes a partial batch.
class GitHubApi {
  final String _token;
  final Uri _base;
  final HttpClient _client;
  bool _cancelled = false;
  String? recoveryUrl;
  GitHubApi(String token)
    : _token = _validToken(token),
      _base = Uri.https('api.github.com'),
      _client = HttpClient() {
    _configure();
  }

  // Test transport is confined to loopback; app callers cannot select a server
  // that might capture the user's token. Production always uses GitHub HTTPS.
  GitHubApi.forTesting(String token, Uri loopback)
    : _token = _validToken(token),
      _base = loopback,
      _client = HttpClient() {
    if (loopback.scheme != 'http' ||
        InternetAddress.tryParse(loopback.host)?.isLoopback != true) {
      throw ArgumentError('Tests must use a loopback HTTP server');
    }
    _configure();
    _client.findProxy = (_) => 'DIRECT';
  }

  static String _validToken(String value) {
    final token = value.trim();
    if (token.isEmpty) return token; // Anonymous reads of public repositories.
    if (!RegExp(r'^[A-Za-z0-9_]{10,255}$').hasMatch(token)) {
      throw const GitHubFailure('Enter a valid GitHub personal access token.');
    }
    return token;
  }

  void _configure() {
    _client.connectionTimeout = const Duration(seconds: 25);
    _client.idleTimeout = const Duration(seconds: 30);
    _client.maxConnectionsPerHost = 1;
    _client.findProxy = HttpClient.findProxyFromEnvironment;
  }

  void close() => _client.close(force: true);
  bool get cancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    close();
  }

  void _checkCancelled() {
    if (_cancelled) throw const GitHubFailure('GitHub operation cancelled.');
  }

  List<String> _root(GitHubTarget target) => [
    'repos',
    target.owner,
    target.repository,
  ];
  List<String> _ref(GitHubTarget target, {bool update = false}) => [
    ..._root(target),
    'git',
    update ? 'refs' : 'ref',
    'heads',
    ...target.branch.split('/'),
  ];
  String _sha(dynamic value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(value)) {
      throw const GitHubFailure('GitHub returned an invalid object ID.');
    }
    return value;
  }

  Future<HttpClientRequest> _open(String method, List<String> path) async {
    _checkCancelled();
    final uri = _base.replace(pathSegments: path);
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false; // Never forward tokens to another host.
    if (_token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'SwiftDrop');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    return request;
  }

  Future<Map<String, dynamic>> _response(HttpClientRequest request) async {
    final response = await request.close().timeout(const Duration(minutes: 2));
    // Both success and error payloads are bounded. Do not surface server text:
    // an upstream error might contain credentials or arbitrary user content.
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        throw const GitHubFailure('GitHub response is too large.');
      }
      bytes.addAll(chunk);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        301 || 302 || 307 || 308 => 'Repository moved. Enter its current owner/repository; redirects are disabled to protect your token.',
        401 => 'GitHub rejected the token. Check its value and expiry.',
        403 || 429 => 'GitHub denied access or rate-limited requests. Check Contents permission (read for pulls, read/write for pushes), organization approval and rate limits.',
        404 => 'Repository or branch not found. Check the name, branch and token repository access.',
        409 => 'Initialize this repository with a README on GitHub, or check that the branch has not changed, then review again.',
        422 => 'GitHub rejected the update. The branch may have changed or be protected. Review again or use an existing writable branch. Workflow files need additional GitHub permission.',
        _ =>
          'GitHub request failed (HTTP ${response.statusCode}). Check your connection and try again.',
      };
      throw GitHubFailure(message);
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (result is! Map<String, dynamic>) {
      throw const GitHubFailure('Unexpected GitHub response.');
    }
    return result;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    List<String> path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = await _open(method, path);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    return _response(request);
  }

  Future<GitHubPlan> preview(
    GitHubTarget target,
    List<SourceFile> sources,
  ) async {
    if (_token.isEmpty) {
      throw const GitHubFailure(
        'A token with Contents read/write permission is required to push files.',
      );
    }
    if (sources.isEmpty || sources.length > githubMaxFiles) {
      throw const GitHubFailure(
        'Select between 1 and 200 files per GitHub commit.',
      );
    }
    final local = <(SourceFile, String, FileStat)>[];
    final paths = <String>{};
    for (final source in sources) {
      _checkCancelled();
      final path = target.pathFor(source);
      if (!paths.add(path.toLowerCase())) {
        throw const GitHubFailure(
          'Two selected files have the same destination path.',
        );
      }
      final stat = await FileStat.stat(source.localPath);
      if (await FileSystemEntity.type(source.localPath, followLinks: false) !=
              FileSystemEntityType.file ||
          stat.type != FileSystemEntityType.file) {
        throw const GitHubFailure(
          'A selected file is unavailable or is a symbolic link.',
        );
      }
      if (stat.size > githubMaxFileBytes) {
        throw GitHubFailure(
          '$path exceeds GitHub’s 100 MiB file limit. Use Git LFS outside SwiftDrop for this file.',
        );
      }
      local.add((source, path, stat));
    }
    for (final path in paths) {
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        if (paths.contains(parts.take(i).join('/'))) {
          throw const GitHubFailure(
            'A file conflicts with a selected folder path.',
          );
        }
      }
    }
    final repo = await _json('GET', _root(target));
    if (repo['archived'] == true || repo['disabled'] == true) {
      throw const GitHubFailure('This repository is archived or disabled.');
    }
    final ref = await _json('GET', _ref(target));
    final head = _sha((ref['object'] as Map)['sha']);
    final commit = await _json('GET', [
      ..._root(target),
      'git',
      'commits',
      head,
    ]);
    final tree = _sha((commit['tree'] as Map)['sha']);
    final trees = <String, List<dynamic>>{};
    Future<List<dynamic>> entries(String sha) async {
      if (!trees.containsKey(sha)) {
        final data = await _json('GET', [
          ..._root(target),
          'git',
          'trees',
          sha,
        ]);
        if (data['truncated'] != false || data['tree'] is! List) {
          throw const GitHubFailure(
            'Directory is too large to review safely. Choose a different destination.',
          );
        }
        // Large repositories can have many large sibling trees. Bound cached
        // metadata as well as file payload buffers during review.
        if (trees.length >= 4) trees.remove(trees.keys.first);
        trees[sha] = data['tree'] as List;
      }
      return trees[sha]!;
    }

    final files = <GitHubUploadFile>[];
    for (final (source, path, stat) in local) {
      var directory = tree;
      Map? existing;
      final parts = path.split('/');
      for (var i = 0; i < parts.length; i++) {
        final children = await entries(directory);
        existing = children
            .cast<Map>()
            .where((e) => e['path'] == parts[i])
            .firstOrNull;
        if (existing == null) break;
        if (i < parts.length - 1) {
          if (existing['type'] != 'tree') {
            throw GitHubFailure(
              'A repository file blocks destination folder $path.',
            );
          }
          directory = _sha(existing['sha']);
        } else if (existing['type'] != 'blob' ||
            !{'100644', '100755'}.contains(existing['mode'])) {
          throw GitHubFailure(
            'Cannot replace a folder, symbolic link or submodule: $path.',
          );
        }
      }
      files.add(
        GitHubUploadFile(
          source,
          path,
          stat,
          existing?['mode'] as String? ?? '100644',
          existing != null,
        ),
      );
    }
    return GitHubPlan(
      target,
      head,
      tree,
      repo['private'] != false,
      List.unmodifiable(files),
    );
  }

  Future<String> upload(
    GitHubPlan plan,
    String message,
    void Function(GitHubProgress) onProgress,
  ) async {
    if (message.trim().isEmpty || message.length > 1000) {
      throw const GitHubFailure('Enter a commit message of 1–1000 characters.');
    }
    final current = await _json('GET', _ref(plan.target));
    if ((current['object'] as Map)['sha'] != plan.head) {
      throw const GitHubFailure(
        'The branch changed after review. Review files again before uploading.',
      );
    }
    final entries = <Map<String, dynamic>>[];
    var completed = 0;
    for (final file in plan.files) {
      _checkCancelled();
      final source = File(file.source.localPath);
      final stat = await source.stat();
      if (stat.size != file.stat.size ||
          stat.modified != file.stat.modified ||
          await FileSystemEntity.type(source.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const GitHubFailure(
          'A source file changed after review. Review again.',
        );
      }
      final request = await _open('POST', [
        ..._root(plan.target),
        'git',
        'blobs',
      ]);
      const prefix = '{"encoding":"base64","content":"';
      const suffix = '"}';
      request.headers.contentType = ContentType.json;
      request.contentLength =
          prefix.length + ((stat.size + 2) ~/ 3) * 4 + suffix.length;
      request.write(prefix);
      // Hash the Git blob as we stream, then verify GitHub's returned object ID.
      // Base64's stream encoder carries remainder bytes across disk chunks.
      final digest = _DigestSink();
      final hash = sha1.startChunkedConversion(digest);
      hash.add(utf8.encode('blob ${stat.size}\x00'));
      var sent = 0;
      final encoded = source
          .openRead()
          .map((chunk) {
            _checkCancelled();
            sent += chunk.length;
            if (sent > stat.size) {
              throw const GitHubFailure('Source grew during upload.');
            }
            hash.add(chunk);
            onProgress(
              GitHubProgress(
                'Uploading',
                file.path,
                completed + sent,
                plan.totalBytes,
              ),
            );
            return chunk;
          })
          .transform(base64.encoder)
          .transform(utf8.encoder);
      try {
        await request.addStream(encoded).timeout(const Duration(minutes: 15));
        hash.close();
        final localSha = digest.value.toString();
        if (sent != stat.size) {
          throw const GitHubFailure('Source was truncated during upload.');
        }
        final after = await source.stat();
        if (after.size != stat.size || after.modified != stat.modified) {
          throw const GitHubFailure(
            'Source changed during upload. Review again.',
          );
        }
        request.write(suffix);
        final blob = await _response(request);
        if (_sha(blob['sha']) != localSha) {
          throw const GitHubFailure(
            'GitHub blob integrity check failed. No files were committed.',
          );
        }
        entries.add({
          'path': file.path,
          'mode': file.mode,
          'type': 'blob',
          'sha': localSha,
        });
        completed += sent;
      } catch (_) {
        request.abort();
        rethrow;
      }
    }
    _checkCancelled();
    onProgress(
      GitHubProgress('Creating commit', '', completed, plan.totalBytes),
    );
    final tree = await _json(
      'POST',
      [..._root(plan.target), 'git', 'trees'],
      {'base_tree': plan.tree, 'tree': entries},
    );
    final commit = await _json(
      'POST',
      [..._root(plan.target), 'git', 'commits'],
      {
        'message': message.trim(),
        'tree': _sha(tree['sha']),
        'parents': [plan.head],
      },
    );
    final sha = _sha(commit['sha']);
    final url = Uri.https(
      'github.com',
      '/${plan.target.name}/commit/$sha',
    ).toString();
    _checkCancelled();
    // Cancellation is disabled for the final reference update. If its response
    // is lost, retain the commit URL so the user can check before retrying.
    onProgress(
      GitHubProgress(
        'Publishing commit',
        '',
        completed,
        plan.totalBytes,
        canCancel: false,
      ),
    );
    recoveryUrl = url;
    await _json('PATCH', _ref(plan.target, update: true), {
      'sha': sha,
      'force': false,
    });
    onProgress(
      GitHubProgress(
        'Complete',
        '',
        completed,
        plan.totalBytes,
        canCancel: false,
      ),
    );
    recoveryUrl = null;
    return url;
  }
}
