import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/protocol.dart';
import '../pairing/identity.dart';
import '../storage/store.dart';

class SourceFile {
  final String localPath, relativePath;
  SourceFile(this.localPath, this.relativePath);
  Map<String, dynamic> toJson() => {
    'local': localPath,
    'relative': relativePath,
  };
}

Future<List<SourceFile>> collectSources(List<String> paths) async {
  final files = <SourceFile>[];
  for (final path in paths) {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      files.add(SourceFile(path, safeRelativePath(p.basename(path))));
    } else if (type == FileSystemEntityType.directory) {
      await for (final entity in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relative = p
              .join(p.basename(path), p.relative(entity.path, from: path))
              .split(p.separator)
              .join('/');
          files.add(SourceFile(entity.path, safeRelativePath(relative)));
        }
        if (files.length > maxFiles) {
          throw const FormatException('At most 10,000 files per batch');
        }
      }
    } else {
      throw const FormatException(
        'Only readable files and folders can be sent; symbolic links are excluded',
      );
    }
    if (files.length > maxFiles) {
      throw const FormatException('At most 10,000 files per batch');
    }
  }
  return files;
}

class TransferProgress {
  final String id, state, file;
  final int bytes, total;
  final double bytesPerSecond;
  const TransferProgress(
    this.id,
    this.state,
    this.file,
    this.bytes,
    this.total,
    this.bytesPerSecond,
  );
  double get fraction =>
      total == 0 ? (state == 'Complete' ? 1 : 0) : (bytes / total).clamp(0, 1);
  Duration? get eta => bytesPerSecond <= 0
      ? null
      : Duration(seconds: ((total - bytes) / bytesPerSecond).ceil());
}

class Sender {
  final Store store;
  final void Function(TransferProgress) onProgress;
  Sender(this.store, this.onProgress);
  bool _paused = false, _cancelled = false, _running = false;
  HttpClient? _client;
  void pause() {
    _paused = true;
  }

  void resume() {
    _paused = false;
  }

  void cancel() {
    _cancelled = true;
    _paused = false;
    _client?.close(force: true);
  }

  bool get running => _running;

  static Future<Peer> pair(PairingInvite invite, String name) async {
    if (invite.expires.isBefore(DateTime.now())) {
      throw const FormatException('Invitation expired');
    }
    final client = pinnedClient(invite.fingerprint);
    try {
      final result = await _request(
        client,
        invite.host,
        invite.port,
        'POST',
        '/v1/pair',
        body: {'name': name, 'token': invite.token},
      );
      return Peer(
        result['name'] as String,
        invite.host,
        invite.port,
        invite.fingerprint,
        result['credential'] as String,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<Peer> reconnect(PairingInvite invite, Peer previous) async {
    if (invite.fingerprint != previous.fingerprint) {
      throw const FormatException('Device identity changed');
    }
    final client = pinnedClient(previous.fingerprint);
    try {
      final info = await _request(
        client,
        invite.host,
        invite.port,
        'GET',
        '/v1/info',
        credential: previous.credential,
      );
      return Peer(
        info['name'] as String,
        invite.host,
        invite.port,
        previous.fingerprint,
        previous.credential,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> send(
    Peer peer,
    String name,
    List<SourceFile> sources, {
    String? resumeId,
  }) async {
    if (_running) throw StateError('A transfer is already running');
    if (sources.isEmpty) throw const FormatException('Select files first');
    final address = InternetAddress.tryParse(peer.host);
    if (address == null || !isPrivateAddress(address)) {
      throw const FormatException('Peer must use a private LAN address');
    }
    _running = true;
    _paused = false;
    _cancelled = false;
    final id = resumeId ?? randomToken(18);
    final client = pinnedClient(peer.fingerprint);
    _client = client;
    try {
      final entries = <FileEntry>[];
      for (final source in sources) {
        await _wait(id, 0, 0, source.relativePath);
        onProgress(
          TransferProgress(id, 'Hashing', source.relativePath, 0, 0, 0),
        );
        final file = File(source.localPath);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          throw const FormatException('Source file unavailable');
        }
        final digest = await hashFile(file, cancelled: () => _cancelled);
        final after = await file.stat();
        if (stat.size != after.size || stat.modified != after.modified) {
          throw const FormatException(
            'Source changed during hashing; retry with stable files',
          );
        }
        entries.add(
          FileEntry(safeRelativePath(source.relativePath), stat.size, digest),
        );
      }
      final manifest = Manifest(id, name, entries);
      final old = store.get('outgoing', id);
      if (old != null &&
          jsonEncode(old['manifest']) != jsonEncode(manifest.toJson())) {
        throw const FormatException(
          'Source changed since checkpoint; start a new transfer',
        );
      }
      store.put('outgoing', id, {
        'id': id,
        'manifest': manifest.toJson(),
        'peer': peer.fingerprint,
        'sources': sources.map((s) => s.toJson()).toList(),
      });
      onProgress(
        TransferProgress(id, 'Awaiting approval', '', 0, manifest.total, 0),
      );
      var status = await _request(
        client,
        peer.host,
        peer.port,
        'POST',
        '/v1/offers',
        credential: peer.credential,
        body: manifest.toJson(),
      );
      if (status['state'] == 'cancelled') {
        throw const FormatException('Receiver cancelled this batch');
      }
      var offsets = List<int>.from(status['offsets'] as List);
      var completed = List<bool>.from(status['done'] as List);
      if (offsets.length != entries.length ||
          completed.length != entries.length) {
        throw const FormatException('Invalid receiver state');
      }
      final watch = Stopwatch()..start();
      var sentThisRun = 0;
      for (var i = 0; i < sources.length; i++) {
        if (completed[i]) continue;
        final entry = entries[i];
        final input = await File(sources[i].localPath).open();
        try {
          // The zero-length final chunk also finalizes an empty file or a
          // checkpoint that reached EOF before the receiver's hash/rename.
          while (!completed[i]) {
            final bytes = offsets.fold<int>(0, (a, b) => a + b);
            await _wait(id, bytes, manifest.total, entry.path);
            final offset = offsets[i];
            if (offset < 0 || offset > entry.size) {
              throw const FormatException('Invalid remote checkpoint');
            }
            await input.setPosition(offset);
            final remaining = entry.size - offset;
            final block = await input.read(
              remaining < chunkSize ? remaining : chunkSize,
            );
            if (block.isEmpty && remaining > 0) {
              throw const FormatException('Source was truncated');
            }
            final request = await client.openUrl(
              'PUT',
              Uri(
                scheme: 'https',
                host: peer.host,
                port: peer.port,
                path: '/v1/transfers/$id/files/$i',
              ),
            );
            request.followRedirects = false;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer ${peer.credential}',
            );
            request.headers.set('x-offset', '$offset');
            request.contentLength = block.length;
            request.add(block);
            final response = await request.close().timeout(
              const Duration(minutes: 10),
            );
            status = await readJson(
              response.timeout(const Duration(seconds: 30)),
              limit: 1024 * 1024,
            );
            if (response.statusCode != 200) {
              throw TransferException(
                status['error']?.toString() ?? 'Chunk rejected',
              );
            }
            offsets = List<int>.from(status['offsets'] as List);
            completed = List<bool>.from(status['done'] as List);
            sentThisRun += block.length;
            onProgress(
              TransferProgress(
                id,
                'Sending',
                entry.path,
                offsets.fold<int>(0, (a, b) => a + b),
                manifest.total,
                sentThisRun /
                    (watch.elapsedMilliseconds.clamp(1, 1 << 53) / 1000),
              ),
            );
          }
        } finally {
          await input.close();
        }
      }
      if (status['state'] != 'complete') {
        throw const FormatException('Receiver did not confirm completion');
      }
      store.put('history', id, {
        'id': id,
        'direction': 'Sent',
        'peer': peer.name,
        'bytes': manifest.total,
        'files': entries.length,
        'time': DateTime.now().toIso8601String(),
      });
      store.remove('outgoing', id);
      onProgress(
        TransferProgress(id, 'Complete', '', manifest.total, manifest.total, 0),
      );
    } catch (error) {
      if (_cancelled) {
        final cancelClient = pinnedClient(peer.fingerprint);
        try {
          await _request(
            cancelClient,
            peer.host,
            peer.port,
            'DELETE',
            '/v1/transfers/$id',
            credential: peer.credential,
          );
        } catch (_) {
          // Offline receiver retains partial files; the UI must say so.
        } finally {
          cancelClient.close(force: true);
        }
        store.remove('outgoing', id);
        onProgress(
          TransferProgress(
            id,
            'Cancelled (receiver may retain partial files)',
            '',
            0,
            0,
            0,
          ),
        );
      } else {
        onProgress(
          TransferProgress(id, 'Interrupted — retry to resume', '', 0, 0, 0),
        );
        rethrow;
      }
    } finally {
      client.close(force: true);
      _client = null;
      _running = false;
    }
  }

  Future<void> _wait(String id, int bytes, int total, String file) async {
    while (_paused && !_cancelled) {
      onProgress(TransferProgress(id, 'Paused', file, bytes, total, 0));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (_cancelled) throw const TransferException('Cancelled');
  }

  static Future<Map<String, dynamic>> _request(
    HttpClient client,
    String host,
    int port,
    String method,
    String path, {
    String? credential,
    Map<String, dynamic>? body,
  }) async {
    final request = await client.openUrl(
      method,
      Uri(scheme: 'https', host: host, port: port, path: path),
    );
    request.followRedirects = false;
    if (credential != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $credential',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(minutes: 10));
    final value = await readJson(
      response.timeout(const Duration(seconds: 30)),
      limit: 1024 * 1024,
    );
    if (response.statusCode != 200) {
      throw TransferException(
        value['error']?.toString() ??
            'Request rejected (${response.statusCode})',
        response.statusCode,
      );
    }
    return value;
  }
}

class TransferException implements Exception {
  final String message;
  final int? statusCode;
  const TransferException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}
