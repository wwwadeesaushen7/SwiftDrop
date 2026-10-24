import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

import '../../core/protocol.dart';
import '../pairing/identity.dart';
import '../storage/store.dart';

typedef Consent = Future<bool> Function(String title, String details);
typedef ReceiverUpdate = void Function(
  String id,
  int bytes,
  int total,
  String state,
);

class Receiver {
  final Identity identity;
  final SecretStore secrets;
  final Store store;
  final Consent consent;
  final ReceiverUpdate onUpdate;
  final String name;
  final Directory destination;
  HttpServer? _server;
  String? _invite;
  DateTime? _expiry;
  final Set<String> _busy = {};
  final Set<String> _cancelled = {};
  int _activeRequests = 0;
  bool _asking = false;
  Receiver({
    required this.identity,
    required this.secrets,
    required this.store,
    required this.name,
    required this.destination,
    required this.consent,
    required this.onUpdate,
  });
  int get port => _server!.port;
  String? get address => _server?.address.address;
  bool get running => _server != null;

  Future<void> start(InternetAddress address, {int port = 0}) async {
    if (!isPrivateAddress(address) ||
        address.isLoopback && !const bool.fromEnvironment('SWIFTDROP_TEST')) {
      throw const FormatException('Choose a private LAN interface');
    }
    await stop();
    await destination.create(recursive: true);
    _server = await HttpServer.bindSecure(
      address,
      port,
      identity.context,
      shared: false,
      backlog: 16,
    );
    _server!.idleTimeout = const Duration(seconds: 30);
    _server!.listen((request) async {
      if (_activeRequests >= 4 ||
          !isPrivateAddress(request.connectionInfo!.remoteAddress)) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      _activeRequests++;
      try {
        await _handle(request);
      } on TimeoutException {
        request.response.statusCode = HttpStatus.requestTimeout;
      } on FormatException catch (e) {
        await _reply(request, 400, {'error': e.message});
      } on FileSystemException {
        await _reply(request, 507, {
          'error':
              'Cannot save file. Check free space and destination permissions.',
        });
      } catch (_) {
        await _reply(request, 400, {
          'error': 'Request failed; reconnect or check transfer state.',
        });
      } finally {
        _activeRequests--;
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  PairingInvite invite() {
    if (_server == null) throw StateError('Enable receiving first');
    _invite = randomToken();
    _expiry = DateTime.now().add(const Duration(minutes: 5));
    return PairingInvite(
      address!,
      port,
      identity.fingerprint,
      _invite!,
      _expiry!,
    );
  }

  Future<void> _reply(
    HttpRequest r,
    int code,
    Map<String, dynamic> body,
  ) async {
    r.response.statusCode = code;
    r.response.headers.contentType = ContentType.json;
    r.response.write(jsonEncode(body));
  }

  Future<void> _handle(HttpRequest r) async {
    final segments = r.uri.pathSegments;
    if (r.method == 'POST' && r.uri.path == '/v1/pair') {
      final value = await readJson(
        r.timeout(const Duration(seconds: 15)),
        limit: 2048,
      );
      final token = value['token'] as String? ?? '';
      final sender = value['name'] as String? ?? '';
      if (_invite == null ||
          _expiry!.isBefore(DateTime.now()) ||
          !constantTimeEquals(_invite!, token) ||
          sender.isEmpty ||
          sender.length > 100 ||
          _asking) {
        await _reply(r, 403, {'error': 'Invalid, used or expired invitation'});
        return;
      }
      _invite = null; // Single-use, consumed before any asynchronous consent.
      _asking = true;
      bool accepted;
      try {
        accepted = await consent(
          'Pair with $sender?',
          'Only approve if you shared this invitation with this device. It will be able to request transfers; each transfer still needs approval.',
        ).timeout(const Duration(seconds: 60), onTimeout: () => false);
      } finally {
        _asking = false;
      }
      if (!accepted) {
        await _reply(r, 403, {'error': 'Pairing rejected'});
        return;
      }
      final credential = randomToken();
      final hash = await _credentialHash(credential);
      await secrets.write('authorized_$hash', sender);
      final authorized = jsonDecode(
        store.setting('authorized') ?? '{}',
      ) as Map<String, dynamic>;
      authorized[hash] = sender;
      store.setSetting('authorized', jsonEncode(authorized));
      await _reply(r, 200, {'credential': credential, 'name': name});
      return;
    }
    final auth = r.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final credential = auth.startsWith('Bearer ') ? auth.substring(7) : '';
    if (credential.length != 43) {
      await _reply(r, 401, {'error': 'Pairing required'});
      return;
    }
    final owner = await _credentialHash(credential);
    final senderName = await secrets.read('authorized_$owner');
    if (senderName == null || senderName.isEmpty) {
      await _reply(r, 401, {'error': 'Device is not paired'});
      return;
    }
    if (r.method == 'GET' && r.uri.path == '/v1/info') {
      await _reply(r, 200, {'name': name, 'version': protocolVersion});
      return;
    }
    if (r.method == 'POST' && r.uri.path == '/v1/offers') {
      final manifest = Manifest.fromJson(
        await readJson(r.timeout(const Duration(seconds: 20))),
      );
      final existing = store.get('transfers', manifest.id);
      if (existing != null) {
        if (existing['owner'] != owner ||
            jsonEncode(existing['manifest']) != jsonEncode(manifest.toJson())) {
          await _reply(r, 409, {'error': 'Transfer identity mismatch'});
          return;
        }
        if (!_busy.contains(manifest.id)) await _recoverCompleted(existing);
        await _reply(r, 200, _status(existing));
        return;
      }
      if (_asking) {
        await _reply(r, 429, {'error': 'Another approval is pending'});
        return;
      }
      _asking = true;
      bool accepted;
      try {
        accepted = await consent(
          'Receive from $senderName?',
          '${manifest.files.length} files · ${manifest.total} bytes\n${manifest.files.take(5).map((f) => f.path).join('\n')}',
        ).timeout(const Duration(seconds: 60), onTimeout: () => false);
      } finally {
        _asking = false;
      }
      if (!accepted) {
        await _reply(r, 403, {'error': 'Receiver rejected transfer'});
        return;
      }
      final root = Directory(
        p.join(destination.path, 'SwiftDrop-${manifest.id}'),
      );
      if (await root.exists()) {
        await _reply(r, 409, {'error': 'Destination already exists'});
        return;
      }
      await root.create();
      await Directory(p.join(root.path, 'parts')).create();
      await Directory(p.join(root.path, 'files')).create();
      final record = <String, dynamic>{
        'owner': owner,
        'manifest': manifest.toJson(),
        'root': await root.resolveSymbolicLinks(),
        'offsets': List.filled(manifest.files.length, 0),
        'done': List.filled(manifest.files.length, false),
        'state': 'accepted',
      };
      store.put('transfers', manifest.id, record);
      onUpdate(manifest.id, 0, manifest.total, 'Receiving');
      await _reply(r, 200, _status(record));
      return;
    }
    if (segments.length < 3 ||
        segments[0] != 'v1' ||
        segments[1] != 'transfers') {
      await _reply(r, 404, {'error': 'Unknown endpoint'});
      return;
    }
    final id = segments[2];
    final record = store.get('transfers', id);
    if (record == null || record['owner'] != owner) {
      await _reply(r, 404, {'error': 'Unknown transfer'});
      return;
    }
    if (r.method == 'DELETE' && segments.length == 3) {
      if (_busy.contains(id)) _cancelled.add(id);
      record['state'] = 'cancelled';
      store.put('transfers', id, record);
      onUpdate(
        id,
        _bytes(record),
        Manifest.fromJson(record['manifest'] as Map<String, dynamic>).total,
        'Cancelled',
      );
      // Retain partial files for local inspection; cancelled IDs cannot resume.
      await _reply(r, 200, _status(record));
      return;
    }
    if (_busy.contains(id)) {
      await _reply(r, 409, {'error': 'Transfer busy; retry'});
      return;
    }
    if (r.method == 'GET' && segments.length == 3) {
      await _recoverCompleted(record);
      await _reply(r, 200, _status(record));
      return;
    }
    if (r.method != 'PUT' ||
        segments.length != 5 ||
        segments[3] != 'files' ||
        record['state'] == 'cancelled') {
      await _reply(r, 409, {'error': 'Transfer cannot accept data'});
      return;
    }
    _busy.add(id);
    try {
      await _upload(r, id, record, senderName);
    } finally {
      _busy.remove(id);
      _cancelled.remove(id);
    }
  }

  Future<void> _upload(
    HttpRequest r,
    String id,
    Map<String, dynamic> record,
    String senderName,
  ) async {
    await _recoverCompleted(record);
    final index = int.tryParse(r.uri.pathSegments[4]) ?? -1;
    final manifest = Manifest.fromJson(
      Map<String, dynamic>.from(record['manifest'] as Map),
    );
    if (index < 0 || index >= manifest.files.length) {
      throw const FormatException('Invalid file index');
    }
    final entry = manifest.files[index];
    final offsets = List<int>.from(record['offsets'] as List);
    final done = List<bool>.from(record['done'] as List);
    final offset = int.tryParse(r.headers.value('x-offset') ?? '') ?? -1;
    if (offset != offsets[index] ||
        done[index] ||
        r.contentLength < 0 ||
        r.contentLength > chunkSize ||
        offset + r.contentLength > entry.size ||
        r.contentLength == 0 && entry.size > offset) {
      await _reply(r, 409, {
        'error': 'Offset or length mismatch',
        ..._status(record),
      });
      return;
    }
    final root = record['root'] as String;
    await _checkDirectory(root, root);
    final parts = p.join(root, 'parts');
    await _checkDirectory(root, parts);
    final partial = File(p.join(parts, '$index.part'));
    if (await FileSystemEntity.type(partial.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Symbolic links are not allowed');
    }
    // A crash may have flushed bytes before committing SQLite. Truncate back
    // to the committed offset rather than appending duplicated bytes.
    final output = await partial.open(mode: FileMode.append);
    var count = 0;
    try {
      if (await output.length() < offset) {
        throw const FormatException('Checkpoint file is truncated');
      }
      await output.truncate(offset);
      await output.setPosition(offset);
      await for (final block in r.timeout(const Duration(seconds: 20))) {
        count += block.length;
        if (count > r.contentLength || count > chunkSize) {
          throw const FormatException('Chunk too large');
        }
        await output.writeFrom(block);
      }
      if (count != r.contentLength) {
        throw const FormatException('Truncated chunk');
      }
      await output.flush();
    } finally {
      await output.close();
    }
    offsets[index] += count;
    record['offsets'] = offsets;
    store.put('transfers', id, record);
    if (offsets[index] == entry.size) {
      onUpdate(id, _bytes(record), manifest.total, 'Verifying SHA-256');
      if (await hashFile(partial, cancelled: () => _cancelled.contains(id)) !=
          entry.digest) {
        offsets[index] = 0;
        record['offsets'] = offsets;
        store.put('transfers', id, record);
        await partial.writeAsBytes([], flush: true);
        await _reply(r, 422, {
          'error': 'SHA-256 mismatch; source may have changed',
        });
        return;
      }
      final filesRoot = p.join(root, 'files');
      await _checkDirectory(root, filesRoot);
      var parent = filesRoot;
      final components = entry.path.split('/');
      for (final component in components.take(components.length - 1)) {
        parent = p.join(parent, component);
        if (await FileSystemEntity.type(parent, followLinks: false) ==
            FileSystemEntityType.notFound) {
          await Directory(parent).create();
        }
        await _checkDirectory(root, parent);
      }
      final target = p.join(parent, components.last);
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        // Recover crash after rename but before SQLite commit, only if exact.
        if (await FileSystemEntity.type(target, followLinks: false) !=
                FileSystemEntityType.file ||
            await File(target).length() != entry.size ||
            await hashFile(File(target)) != entry.digest) {
          throw const FormatException(
            'Destination collision; file was not overwritten',
          );
        }
        await partial.delete();
      } else {
        await partial.rename(target);
      }
      done[index] = true;
      record['done'] = done;
      if (done.every((v) => v)) {
        record['state'] = 'complete';
        store.put('history', id, {
          'id': id,
          'direction': 'Received',
          'peer': senderName,
          'bytes': manifest.total,
          'files': manifest.files.length,
          'path': filesRoot,
          'time': DateTime.now().toIso8601String(),
        });
      }
      store.put('transfers', id, record);
    }
    onUpdate(
      id,
      _bytes(record),
      manifest.total,
      record['state'] == 'complete' ? 'Complete' : 'Receiving',
    );
    await _reply(r, 200, _status(record));
  }

  Future<void> _recoverCompleted(Map<String, dynamic> record) async {
    if (record['state'] == 'cancelled' || record['state'] == 'complete') return;
    final manifest = Manifest.fromJson(
      Map<String, dynamic>.from(record['manifest'] as Map),
    );
    final offsets = List<int>.from(record['offsets'] as List);
    final done = List<bool>.from(record['done'] as List);
    final root = record['root'] as String;
    var changed = false;
    for (var i = 0; i < done.length; i++) {
      if (done[i] || offsets[i] != manifest.files[i].size) continue;
      final part = File(p.join(root, 'parts', '$i.part'));
      final target = File(
        p.joinAll([root, 'files', ...manifest.files[i].path.split('/')]),
      );
      if (!await part.exists() &&
          await FileSystemEntity.type(target.path, followLinks: false) ==
              FileSystemEntityType.file) {
        await _checkDirectory(root, root);
        var parent = root;
        for (final component in [
          'files',
          ...manifest.files[i].path
              .split('/')
              .take(manifest.files[i].path.split('/').length - 1),
        ]) {
          parent = p.join(parent, component);
          await _checkDirectory(root, parent);
        }
        if (await target.length() == manifest.files[i].size &&
            await hashFile(target) == manifest.files[i].digest) {
          done[i] = true;
          changed = true;
        }
      }
    }
    if (!changed) return;
    record['done'] = done;
    if (done.every((v) => v)) {
      record['state'] = 'complete';
      store.put('history', manifest.id, {
        'id': manifest.id,
        'direction': 'Received',
        'peer': manifest.sender,
        'bytes': manifest.total,
        'files': done.length,
        'path': p.join(root, 'files'),
        'time': DateTime.now().toIso8601String(),
      });
    }
    store.put('transfers', manifest.id, record);
  }

  Future<void> _checkDirectory(String root, String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.isWithin(root, path) && root != path ||
        await Directory(path).resolveSymbolicLinks() != path) {
      throw const FormatException(
        'Destination changed or contains symbolic links',
      );
    }
  }

  int _bytes(Map<String, dynamic> record) =>
      (record['offsets'] as List).cast<int>().fold(0, (a, b) => a + b);
  Map<String, dynamic> _status(Map<String, dynamic> record) => {
    'offsets': record['offsets'],
    'done': record['done'],
    'state': record['state'],
  };
  Future<String> _credentialHash(String credential) async {
    // Never store the reusable bearer credential in the history database.
    return sha256.convert(utf8.encode(credential)).toString();
  }

  Future<void> stop() async {
    _invite = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
