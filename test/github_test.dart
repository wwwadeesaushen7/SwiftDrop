import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/features/github/github_api.dart';
import 'package:swiftdrop/features/github/github_controller.dart';
import 'package:swiftdrop/features/storage/store.dart';
import 'package:swiftdrop/features/transfer/sender.dart';

import 'support/secrets.dart';

const token = 'github_pat_test_only_not_a_real_secret';
String objectId(String value) => sha1.convert(utf8.encode(value)).toString();
String blobId(List<int> bytes) => sha1.convert([
  ...utf8.encode('blob ${bytes.length}\x00'),
  ...bytes,
]).toString();

/// Real HTTP sockets and file streams, with a deterministic GitHub API fixture.
/// These tests do not assert authorization against the live GitHub service.
class GitHubFixture {
  late HttpServer server;
  final oldHead = objectId('old-head'), rootTree = objectId('root-tree');
  final newCommit = objectId('new-commit');
  final blobs = <String, List<int>>{};
  final calls = <String>[];
  final treeEntries = <Map<String, dynamic>>[];
  final failures = <Object>[];
  List<Map<String, dynamic>> existing = [];
  String? published;
  bool changed = false, corruptBlob = false, rejectPublish = false;
  bool allowDisconnect = false;
  int? status;
  Uri? redirect;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await handle(request);
      } catch (e) {
        if (allowDisconnect && e is HttpException) return;
        failures.add(e);
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
  }

  GitHubApi client() =>
      GitHubApi.forTesting(token, Uri.parse('http://127.0.0.1:${server.port}'));

  Future<void> handle(HttpRequest request) async {
    expect(request.headers.value('authorization'), 'Bearer $token');
    expect(request.headers.value('x-github-api-version'), '2022-11-28');
    final path = request.uri.path;
    calls.add('${request.method} $path');
    final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final body = bytes.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (redirect != null) {
      request.response.statusCode = 307;
      request.response.headers.set('location', redirect.toString());
      await request.response.close();
      return;
    }
    if (status != null) {
      request.response.statusCode = status!;
      request.response.write(
        jsonEncode({'message': 'Never show upstream $token'}),
      );
      await request.response.close();
      return;
    }
    Object response;
    if (request.method == 'GET' && path == '/repos/me/files') {
      response = {'private': false};
    } else if (request.method == 'GET' &&
        path.startsWith('/repos/me/files/git/ref/heads/')) {
      response = {
        'object': {'sha': changed ? objectId('other-head') : oldHead},
      };
    } else if (request.method == 'GET' &&
        path.endsWith('/git/commits/$oldHead')) {
      response = {
        'tree': {'sha': rootTree},
      };
    } else if (request.method == 'GET' &&
        path.endsWith('/git/trees/$rootTree')) {
      response = {'truncated': false, 'tree': existing};
    } else if (request.method == 'POST' && path.endsWith('/git/blobs')) {
      expect(body['encoding'], 'base64');
      final content = base64.decode(body['content'] as String);
      final sha = blobId(content);
      blobs[sha] = content;
      response = {'sha': corruptBlob ? objectId('corrupt') : sha};
    } else if (request.method == 'POST' && path.endsWith('/git/trees')) {
      expect(body['base_tree'], rootTree); // Preserve all unselected files.
      treeEntries.addAll((body['tree'] as List).cast<Map<String, dynamic>>());
      response = {'sha': objectId('new-tree')};
    } else if (request.method == 'POST' && path.endsWith('/git/commits')) {
      expect(body['parents'], [oldHead]);
      expect(body['message'], 'Test upload');
      response = {'sha': newCommit};
    } else if (request.method == 'PATCH' &&
        path.startsWith('/repos/me/files/git/refs/heads/')) {
      expect(body['force'], false); // Never force-push over concurrent work.
      if (rejectPublish) {
        request.response.statusCode = 422;
        request.response.write('{}');
        await request.response.close();
        return;
      }
      published = body['sha'] as String;
      response = {
        'object': {'sha': published},
      };
    } else {
      throw StateError('Unexpected route: ${request.method} $path');
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }
}

void main() {
  test('validates repository, branch and destination paths', () {
    final target = GitHubTarget(
      'https://github.com/me/files.git',
      'feature/upload',
      '资料',
    );
    expect(target.name, 'me/files');
    expect(target.pathFor(SourceFile('local', 'photo.bin')), '资料/photo.bin');
    for (final repo in [
      'https://evil.example/me/files',
      'me/files/extra',
      '../files',
    ]) {
      expect(
        () => GitHubTarget(repo, 'main', ''),
        throwsA(isA<GitHubFailure>()),
      );
    }
    for (final branch in [
      '../main',
      'a..b',
      'a b',
      '-bad/',
      'a.lock',
      'a@{b',
      'a[b',
    ]) {
      expect(
        () => GitHubTarget('me/files', branch, ''),
        throwsA(isA<GitHubFailure>()),
      );
    }
    for (final folder in ['/etc', '../secret', '.git/hooks', r'a\b']) {
      expect(() => GitHubTarget('me/files', 'main', folder), throwsA(anything));
    }
    expect(
      () => GitHubApi.forTesting(token, Uri.parse('http://example.com')),
      throwsArgumentError,
    );
    expect(() => GitHubApi('bad\r\ntoken'), throwsA(isA<GitHubFailure>()));
  });

  group('GitHub HTTP upload', () {
    late Directory root;
    late GitHubFixture fixture;
    late GitHubApi api;
    final target = GitHubTarget('me/files', 'feature/upload', '');
    Future<SourceFile> source(String name, List<int> bytes) async {
      final file = File('${root.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      return SourceFile(file.path, name);
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('swiftdrop-github-');
      fixture = GitHubFixture();
      await fixture.start();
      api = fixture.client();
    });
    tearDown(() async {
      api.close();
      await fixture.server.close(force: true);
      await root.delete(recursive: true);
      expect(fixture.failures, isEmpty);
    });

    test(
      'streams binary, Unicode and zero-byte files into one atomic commit',
      () async {
        final binary = List<int>.generate(3 * 65536 + 17, (i) => i % 256);
        final files = [
          await source('你好.bin', binary),
          await source('empty.txt', []),
        ];
        final plan = await api.preview(target, files);
        expect(fixture.blobs, isEmpty); // Review never changes the repository.
        expect(plan.isPrivate, isFalse);
        final progress = <GitHubProgress>[];
        final url = await api.upload(plan, 'Test upload', progress.add);
        expect(fixture.blobs[blobId(binary)], binary);
        expect(fixture.blobs[blobId([])], isEmpty);
        expect(fixture.treeEntries.map((e) => e['path']), [
          '你好.bin',
          'empty.txt',
        ]);
        expect(fixture.published, fixture.newCommit);
        expect(url, 'https://github.com/me/files/commit/${fixture.newCommit}');
        expect(progress.last.state, 'Complete');
        expect(progress.last.bytes, binary.length);
        expect(progress.last.canCancel, isFalse);
        expect(
          progress.where((p) => p.state == 'Uploading').length,
          greaterThan(1),
        );
      },
    );

    test('reviews replacement and preserves executable mode', () async {
      fixture.existing = [
        {
          'path': 'run.sh',
          'type': 'blob',
          'mode': '100755',
          'sha': objectId('old-file'),
        },
      ];
      final plan = await api.preview(target, [
        await source('run.sh', [1]),
      ]);
      expect(plan.replacements, 1);
      await api.upload(plan, 'Test upload', (_) {});
      expect(fixture.treeEntries.single['mode'], '100755');
    });

    test(
      'rejects files larger than 100 MiB before contacting GitHub',
      () async {
        final file = File('${root.path}/big.bin');
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(githubMaxFileBytes + 1);
        await handle.close();
        await expectLater(
          api.preview(target, [SourceFile(file.path, 'big.bin')]),
          throwsA(isA<GitHubFailure>()),
        );
        expect(fixture.calls, isEmpty);
      },
    );

    test(
      'rejects duplicate paths and selected file/folder conflicts',
      () async {
        final file = await source('one', [1]);
        await expectLater(
          api.preview(target, [file, SourceFile(file.localPath, 'ONE')]),
          throwsA(isA<GitHubFailure>()),
        );
        await expectLater(
          api.preview(target, [file, SourceFile(file.localPath, 'one/child')]),
          throwsA(isA<GitHubFailure>()),
        );
        expect(fixture.calls, isEmpty);
      },
    );

    test('will not replace symlinks, directories or file ancestors', () async {
      final file = await source('one', [1]);
      for (final existing in [
        {
          'path': 'one',
          'type': 'blob',
          'mode': '120000',
          'sha': objectId('link'),
        },
        {
          'path': 'one',
          'type': 'tree',
          'mode': '040000',
          'sha': objectId('dir'),
        },
      ]) {
        fixture.existing = [existing];
        await expectLater(
          api.preview(target, [file]),
          throwsA(isA<GitHubFailure>()),
        );
      }
      fixture.existing = [
        {
          'path': 'one',
          'type': 'blob',
          'mode': '100644',
          'sha': objectId('file'),
        },
      ];
      await expectLater(
        api.preview(target, [SourceFile(file.localPath, 'one/child')]),
        throwsA(isA<GitHubFailure>()),
      );
      expect(fixture.blobs, isEmpty);
    });

    test('detects source changes and branch changes after review', () async {
      final file = await source('one', [1]);
      final plan = await api.preview(target, [file]);
      await File(file.localPath).writeAsBytes([1, 2]);
      await expectLater(
        api.upload(plan, 'Test upload', (_) {}),
        throwsA(isA<GitHubFailure>()),
      );
      fixture.changed = true;
      await expectLater(
        api.upload(plan, 'Test upload', (_) {}),
        throwsA(isA<GitHubFailure>()),
      );
      expect(fixture.blobs, isEmpty);
    });

    test('hash mismatch prevents tree, commit and branch updates', () async {
      fixture.corruptBlob = true;
      final plan = await api.preview(target, [
        await source('one', [1, 2, 3]),
      ]);
      await expectLater(
        api.upload(plan, 'Test upload', (_) {}),
        throwsA(isA<GitHubFailure>()),
      );
      expect(fixture.treeEntries, isEmpty);
      expect(fixture.published, isNull);
    });

    test(
      'non-fast-forward rejection retains a link without claiming success',
      () async {
        fixture.rejectPublish = true;
        final plan = await api.preview(target, [await source('one', [])]);
        await expectLater(
          api.upload(plan, 'Test upload', (_) {}),
          throwsA(isA<GitHubFailure>()),
        );
        expect(fixture.published, isNull);
        expect(api.recoveryUrl, endsWith(fixture.newCommit));
      },
    );

    test(
      'cancellation before publishing leaves the branch unchanged',
      () async {
        fixture.allowDisconnect = true;
        final plan = await api.preview(target, [
          await source('one', List.filled(65536 * 3, 7)),
        ]);
        await expectLater(
          api.upload(plan, 'Test upload', (_) => api.cancel()),
          throwsA(anything),
        );
        expect(fixture.published, isNull);
        expect(fixture.treeEntries, isEmpty);
      },
    );

    test(
      'does not follow redirects or disclose upstream error content',
      () async {
        var leaked = false;
        final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        other.listen((r) async {
          leaked = true;
          await r.response.close();
        });
        try {
          fixture.redirect = Uri.parse('http://127.0.0.1:${other.port}/steal');
          await expectLater(
            api.preview(target, [await source('one', [])]),
            throwsA(isA<GitHubFailure>()),
          );
          expect(leaked, isFalse);
          fixture.redirect = null;
          fixture.status = 401;
          await expectLater(
            api.preview(target, [await source('one', [])]),
            throwsA(
              isA<GitHubFailure>().having(
                (e) => e.message,
                'safe error',
                isNot(contains(token)),
              ),
            ),
          );
        } finally {
          await other.close(force: true);
        }
      },
    );

    test(
      'stores tokens only with opt-in and forgets them from the vault',
      () async {
        final secrets = MemorySecrets();
        final store = Store('${root.path}/state.sqlite');
        final c = GitHubController(
          secrets,
          store,
          apiFactory: (_) => fixture.client(),
        );
        try {
          await c.initialize();
          c.repository = 'me/files';
          c.token = token;
          final files = [await source('one', [])];
          await c.preview(files);
          expect(c.error, isNull);
          expect(secrets.values['github.token'], '');
          await c.setRememberToken(true);
          await c.preview(files);
          expect(secrets.values['github.token'], token);
          expect(store.setting('github.token'), isNull);
          await c.setRememberToken(false);
          expect(secrets.values['github.token'], '');
          expect(
            c.token,
            token,
          ); // Session still works until forgotten or exited.
          await c.forgetToken();
          expect(c.token, '');
        } finally {
          c.dispose();
          store.close();
        }
      },
    );
  });
}
