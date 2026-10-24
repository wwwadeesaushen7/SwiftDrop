import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/core/protocol.dart';
import 'package:swiftdrop/features/pairing/identity.dart';

void main() {
  test('portable paths accept Unicode and nested files', () {
    for (final path in ['a.txt', '旅行/写真.jpg', 'folder/zero', 'Résumé.pdf']) {
      expect(safeRelativePath(path), path);
    }
  });
  test(
    'reject traversal, Windows aliases, ADS, absolute and ambiguous paths',
    () {
      for (final path in [
        '',
        '..',
        '../x',
        '/etc/passwd',
        'C:/x',
        r'a\b',
        'a//b',
        './a',
        'a/../b',
        'a/./b',
        'a/',
        'a\u0000',
        'CON',
        'con.txt',
        'a/LPT1.bin',
        'file:stream',
        'trailing.',
        'trailing ',
        'a?b',
        'a|b',
      ]) {
        expect(
          () => safeRelativePath(path),
          throwsFormatException,
          reason: path,
        );
      }
    },
  );
  test('metadata preserves 64 bit sizes and zero-byte files', () {
    final manifest = Manifest(randomToken(18), 'Desktop', [
      FileEntry('large.bin', 5 * 1024 * 1024 * 1024, 'a' * 64),
      FileEntry('empty', 0, sha256.convert([]).toString()),
    ]);
    final decoded = Manifest.fromJson(
      jsonDecode(jsonEncode(manifest.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.files.first.size, 5368709120);
    expect(decoded.files.last.size, 0);
  });
  test('reject duplicate names and directory/file conflicts', () {
    expect(
      () => Manifest(randomToken(18), 'PC', [
        FileEntry('a', 0, 'a' * 64),
        FileEntry('A', 0, 'a' * 64),
      ]),
      throwsFormatException,
    );
    expect(
      () => Manifest(randomToken(18), 'PC', [
        FileEntry('a', 0, 'a' * 64),
        FileEntry('a/b', 0, 'a' * 64),
      ]),
      throwsFormatException,
    );
  });
  test('reject unsupported protocol, negative length and bad hashes', () {
    expect(() => Manifest.fromJson({'version': 2}), throwsFormatException);
    for (final value in [
      {'path': 'a', 'size': -1, 'sha256': 'a' * 64},
      {'path': 'a', 'size': 1, 'sha256': 'not a hash'},
    ]) {
      expect(() => FileEntry.fromJson(value), throwsFormatException);
    }
  });
  test(
    'HTTP JSON metadata handles arbitrary framing and enforces bound',
    () async {
      final encoded = utf8.encode('{"name":"旅行"}');
      final result = await readJson(
        Stream.fromIterable(encoded.map((b) => [b])),
      );
      expect(result['name'], '旅行');
      await expectLater(
        readJson(Stream.value(List.filled(30, 1)), limit: 29),
        throwsFormatException,
      );
      await expectLater(
        readJson(Stream.value(utf8.encode('[]'))),
        throwsFormatException,
      );
    },
  );
  test(
    'streamed hashing matches SHA-256 reference including empty files',
    () async {
      final root = await Directory.systemTemp.createTemp('swiftdrop-hash-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/file');
      await file.writeAsString('abc');
      expect(
        await hashFile(file),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      await file.writeAsBytes([]);
      expect(await hashFile(file), sha256.convert([]).toString());
    },
  );
  test('pairing invitation roundtrip, expiry and public-host rejection', () {
    final invite = PairingInvite(
      '192.168.1.23',
      45893,
      'a' * 64,
      randomToken(),
      DateTime.now().add(const Duration(minutes: 5)),
    );
    expect(
      PairingInvite.parse(invite.encode()).fingerprint,
      invite.fingerprint,
    );
    expect(
      () => PairingInvite.parse(
        invite.encode().replaceFirst('192.168.1.23', '8.8.8.8'),
      ),
      throwsFormatException,
    );
    expect(
      () => PairingInvite.parse(
        PairingInvite(
          '192.168.1.23',
          45893,
          'a' * 64,
          randomToken(),
          DateTime.now().subtract(const Duration(seconds: 1)),
        ).encode(),
      ),
      throwsFormatException,
    );
  });
  test('constant-time equality handles differing lengths', () {
    expect(constantTimeEquals('abc', 'abc'), isTrue);
    expect(constantTimeEquals('abc', 'abcd'), isFalse);
    expect(constantTimeEquals('abc', 'abd'), isFalse);
  });
}
