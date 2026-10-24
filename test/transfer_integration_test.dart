// Real TLS sockets and disk files. No mocked HTTP, progress, or transferred bytes.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/core/protocol.dart';
import 'package:swiftdrop/features/pairing/identity.dart';
import 'package:swiftdrop/features/storage/store.dart';
import 'package:swiftdrop/features/transfer/receiver.dart';
import 'package:swiftdrop/features/transfer/sender.dart';

import 'support/secrets.dart';

void main() {
  late Directory root;
  late Store receivingStore, sendingStore;
  late MemorySecrets secrets;
  late Identity identity;
  late Receiver receiver;
  late Peer peer;
  var accept = true;
  setUpAll(() async {
    identity = await Identity.load(MemorySecrets());
  });
  Future<void> startReceiver() async {
    receiver = Receiver(
      identity: identity,
      secrets: secrets,
      store: receivingStore,
      name: 'Receiver',
      destination: Directory('${root.path}/received'),
      consent: (_, _) async => accept,
      onUpdate: (_, _, _, _) {},
    );
    await receiver.start(InternetAddress.loopbackIPv4);
  }

  setUp(() async {
    accept = true;
    root = await Directory.systemTemp.createTemp('swiftdrop-transfer-');
    receivingStore = Store('${root.path}/receiver.sqlite');
    sendingStore = Store('${root.path}/sender.sqlite');
    secrets = MemorySecrets();
    await startReceiver();
    peer = await Sender.pair(receiver.invite(), 'Sender');
  });
  tearDown(() async {
    await receiver.stop();
    receivingStore.close();
    sendingStore.close();
    await root.delete(recursive: true);
  });
  Future<({int code, Map<String, dynamic> body})> request(
    String method,
    String path, {
    Map<String, dynamic>? json,
    List<int>? bytes,
    int? offset,
    String? credential,
  }) async {
    final client = pinnedClient(identity.fingerprint);
    try {
      final r = await client.openUrl(
        method,
        Uri(
          scheme: 'https',
          host: '127.0.0.1',
          port: receiver.port,
          path: path,
        ),
      );
      r.headers.set('Authorization', 'Bearer ${credential ?? peer.credential}');
      if (offset != null) r.headers.set('x-offset', '$offset');
      if (json != null) {
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(json));
      }
      if (bytes != null) {
        r.contentLength = bytes.length;
        r.add(bytes);
      }
      final response = await r.close();
      return (code: response.statusCode, body: await readJson(response));
    } finally {
      client.close(force: true);
    }
  }

  test('multiple files, bounded chunks, Unicode, folders and empty file transfer exactly', () async {
    final data = List<int>.generate(chunkSize * 2 + 73, (i) => i % 251);
    final input = File('${root.path}/source.bin');
    await input.writeAsBytes(data);
    final empty = File('${root.path}/empty');
    await empty.writeAsBytes([]);
    final events = <TransferProgress>[];
    final sender = Sender(sendingStore, events.add);
    await sender.send(peer, 'Sender', [
      SourceFile(input.path, '旅行/data.bin'),
      SourceFile(empty.path, 'empty'),
    ]);
    expect(events.last.state, 'Complete');
    expect(
      events.where((e) => e.state == 'Sending').length,
      greaterThanOrEqualTo(4),
    );
    final saved = receivingStore.all('history').single;
    expect(await File('${saved['path']}/旅行/data.bin').readAsBytes(), data);
    expect(await File('${saved['path']}/empty').length(), 0);
    expect(sendingStore.all('outgoing'), isEmpty);
  });
  test(
    'receiver reject writes no payload and unauthorized clients cannot offer',
    () async {
      accept = false;
      final manifest = Manifest(randomToken(18), 'Sender', [
        FileEntry('secret', 3, sha256.convert([1, 2, 3]).toString()),
      ]);
      expect(
        (await request('POST', '/v1/offers', json: manifest.toJson())).code,
        403,
      );
      expect(receivingStore.all('transfers'), isEmpty);
      expect(
        (await request(
          'POST',
          '/v1/offers',
          json: manifest.toJson(),
          credential: randomToken(),
        )).code,
        401,
      );
    },
  );
  test('unapproved transfer cannot receive bytes', () async {
    final id = randomToken(18);
    expect(
      (await request(
        'PUT',
        '/v1/transfers/$id/files/0',
        bytes: [1],
        offset: 0,
      )).code,
      404,
    );
  });
  test(
    'wrong certificate pin fails before an invitation is disclosed',
    () async {
      final invite = receiver.invite();
      await expectLater(
        Sender.pair(
          PairingInvite(
            invite.host,
            invite.port,
            '0' * 64,
            invite.token,
            invite.expires,
          ),
          'Attacker',
        ),
        throwsA(isA<HandshakeException>()),
      );
    },
  );
  test(
    'invitation is single-use and explicit pairing rejection works',
    () async {
      final invite = receiver.invite();
      await Sender.pair(invite, 'Another');
      await expectLater(
        Sender.pair(invite, 'Another'),
        throwsA(isA<TransferException>()),
      );
      accept = false;
      await expectLater(
        Sender.pair(receiver.invite(), 'Rejected'),
        throwsA(isA<TransferException>()),
      );
    },
  );
  test(
    'durable checkpoint survives restart and rejects duplicated offset',
    () async {
      final data = List<int>.generate(chunkSize + 27, (i) => i % 233);
      final manifest = Manifest(randomToken(18), 'Sender', [
        FileEntry('resumed.bin', data.length, sha256.convert(data).toString()),
      ]);
      expect(
        (await request('POST', '/v1/offers', json: manifest.toJson())).code,
        200,
      );
      expect(
        (await request(
          'PUT',
          '/v1/transfers/${manifest.id}/files/0',
          bytes: data.sublist(0, chunkSize),
          offset: 0,
        )).code,
        200,
      );
      expect(
        (await request(
          'PUT',
          '/v1/transfers/${manifest.id}/files/0',
          bytes: [1],
          offset: 0,
        )).code,
        409,
      );
      await receiver.stop();
      receivingStore.close();
      receivingStore = Store('${root.path}/receiver.sqlite');
      await startReceiver();
      final state = await request('GET', '/v1/transfers/${manifest.id}');
      expect(state.body['offsets'], [chunkSize]);
      final source = File('${root.path}/resume-source');
      await source.writeAsBytes(data);
      final updated = Peer(
        peer.name,
        peer.host,
        receiver.port,
        peer.fingerprint,
        peer.credential,
      );
      await Sender(sendingStore, (_) {}).send(updated, 'Sender', [
        SourceFile(source.path, 'resumed.bin'),
      ], resumeId: manifest.id);
      expect(
        await File(
          '${receivingStore.all('history').single['path']}/resumed.bin',
        ).readAsBytes(),
        data,
      );
    },
  );
  test('hash mismatch resets checkpoint and publishes no final file', () async {
    final manifest = Manifest(randomToken(18), 'Sender', [
      FileEntry('bad', 3, sha256.convert([1, 2, 3]).toString()),
    ]);
    await request('POST', '/v1/offers', json: manifest.toJson());
    final bad = await request(
      'PUT',
      '/v1/transfers/${manifest.id}/files/0',
      bytes: [1, 2, 4],
      offset: 0,
    );
    expect(bad.code, 422);
    final record = receivingStore.get('transfers', manifest.id)!;
    expect(record['offsets'], [0]);
    expect(receivingStore.all('history'), isEmpty);
    expect(await File('${record['root']}/files/bad').exists(), isFalse);
  });
  test('cancelled IDs cannot be resumed', () async {
    final manifest = Manifest(randomToken(18), 'Sender', [
      FileEntry('a', 3, sha256.convert([1, 2, 3]).toString()),
    ]);
    await request('POST', '/v1/offers', json: manifest.toJson());
    expect((await request('DELETE', '/v1/transfers/${manifest.id}')).code, 200);
    expect(
      (await request(
        'PUT',
        '/v1/transfers/${manifest.id}/files/0',
        bytes: [1, 2, 3],
        offset: 0,
      )).code,
      409,
    );
  });
  test('invalid path rejected before approval or disk writes', () async {
    final value = Manifest(randomToken(18), 'Sender', [
      FileEntry('valid', 0, sha256.convert([]).toString()),
    ]).toJson();
    (value['files'] as List).first['path'] = '../escape';
    expect((await request('POST', '/v1/offers', json: value)).code, 400);
    expect(receivingStore.all('transfers'), isEmpty);
  });
  test(
    'source collection excludes symlinks and preserves folder paths',
    () async {
      final folder = await Directory('${root.path}/folder').create();
      await File('${folder.path}/a').writeAsString('a');
      if (!Platform.isWindows) {
        await Link('${folder.path}/link').create('${root.path}/sender.sqlite');
      }
      final files = await collectSources([folder.path]);
      expect(files.map((f) => f.relativePath), ['folder/a']);
    },
  );
  test('sender pause and resume uses actual chunk boundary', () async {
    final data = List<int>.generate(chunkSize * 2 + 1, (i) => i % 239);
    final source = File('${root.path}/pause');
    await source.writeAsBytes(data);
    late Sender sender;
    var paused = false;
    sender = Sender(sendingStore, (value) {
      if (!paused && value.state == 'Sending') {
        paused = true;
        sender.pause();
        Future<void>.delayed(const Duration(milliseconds: 350), sender.resume);
      }
    });
    await sender.send(peer, 'Sender', [SourceFile(source.path, 'pause')]);
    expect(paused, isTrue);
    expect(receivingStore.all('history').length, 1);
  });
  test('rename-before-commit crash recovers verified file', () async {
    final data = [7, 8, 9];
    final manifest = Manifest(randomToken(18), 'Sender', [
      FileEntry('recovered', data.length, sha256.convert(data).toString()),
    ]);
    await request('POST', '/v1/offers', json: manifest.toJson());
    final record = receivingStore.get('transfers', manifest.id)!;
    await File('${record['root']}/files/recovered')
        .writeAsBytes(data, flush: true);
    record['offsets'] = [data.length];
    receivingStore.put('transfers', manifest.id, record);
    final status = await request('GET', '/v1/transfers/${manifest.id}');
    expect(status.body['state'], 'complete');
    expect(status.body['done'], [true]);
    expect(receivingStore.all('history').length, 1);
  });
  test('uncommitted tail is truncated to the durable checkpoint', () async {
    final data = List<int>.generate(chunkSize + 31, (i) => i % 241);
    final manifest = Manifest(randomToken(18), 'Sender', [
      FileEntry('tail', data.length, sha256.convert(data).toString()),
    ]);
    await request('POST', '/v1/offers', json: manifest.toJson());
    await request(
      'PUT',
      '/v1/transfers/${manifest.id}/files/0',
      bytes: data.sublist(0, chunkSize),
      offset: 0,
    );
    final record = receivingStore.get('transfers', manifest.id)!;
    await File('${record['root']}/parts/0.part')
        .writeAsBytes([99, 99, 99], mode: FileMode.append, flush: true);
    final source = File('${root.path}/tail-source');
    await source.writeAsBytes(data);
    await Sender(sendingStore, (_) {}).send(peer, 'Sender', [
      SourceFile(source.path, 'tail'),
    ], resumeId: manifest.id);
    expect(await File('${record['root']}/files/tail').readAsBytes(), data);
  });
  test('concurrent duplicate chunks cannot race a checkpoint', () async {
    final data = List<int>.filled(chunkSize * 2, 23);
    final manifest = Manifest(randomToken(18), 'Sender', [
      FileEntry('concurrent', data.length, sha256.convert(data).toString()),
    ]);
    await request('POST', '/v1/offers', json: manifest.toJson());
    final results = await Future.wait([
      request(
        'PUT',
        '/v1/transfers/${manifest.id}/files/0',
        bytes: data.sublist(0, chunkSize),
        offset: 0,
      ),
      request(
        'PUT',
        '/v1/transfers/${manifest.id}/files/0',
        bytes: data.sublist(0, chunkSize),
        offset: 0,
      ),
    ]);
    expect(results.map((r) => r.code).toList()..sort(), [200, 409]);
    expect(receivingStore.get('transfers', manifest.id)!['offsets'], [
      chunkSize,
    ]);
  });
  test('sender cancellation gives no false completion', () async {
    final source = File('${root.path}/cancel-source');
    await source.writeAsBytes(List<int>.filled(chunkSize * 2, 31));
    late Sender sender;
    TransferProgress? last;
    sender = Sender(sendingStore, (value) {
      last = value;
      if (value.state == 'Sending') sender.cancel();
    });
    await sender.send(peer, 'Sender', [SourceFile(source.path, 'cancelled')]);
    expect(last!.state, startsWith('Cancelled'));
    expect(receivingStore.all('transfers').single['state'], 'cancelled');
    expect(receivingStore.all('history'), isEmpty);
    expect(sendingStore.all('history'), isEmpty);
  });
  test('reconnecting to same certificate preserves authorization', () async {
    final updated = await Sender.reconnect(receiver.invite(), peer);
    expect(updated.credential, peer.credential);
    expect(updated.fingerprint, peer.fingerprint);
  });
}
