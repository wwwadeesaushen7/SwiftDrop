import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/features/github/github_api.dart';
import 'package:swiftdrop/features/github/github_controller.dart';
import 'package:swiftdrop/features/storage/store.dart';

import 'support/secrets.dart';

const pullToken = 'github_pat_pull_fixture_only';
String oid(String text) => sha1.convert(utf8.encode(text)).toString();
String gitHash(List<int> content) => sha1.convert([
  ...utf8.encode('blob ${content.length}\x00'),
  ...content,
]).toString();

class PullFixture {
  late HttpServer server;
  final commit = oid('immutable-commit'),
      tree = oid('root-tree'),
      subTree = oid('folder-tree');
  final blobs = <String, List<int>>{};
  final directories = <String, List<Map<String, dynamic>>>{};
  final calls = <String>[];
  final errors = <Object>[];
  List<int>? lfsBytes;
  Uri? lfsUrl;
  bool corrupt = false, truncate = false, lfsCorrupt = false;
  bool allowDisconnect = false;
  int objectRequests = 0;

  Map<String, dynamic> file(String name, List<int> bytes) {
    final sha = gitHash(bytes);
    blobs[sha] = bytes;
    return {
      'path': name,
      'type': 'blob',
      'mode': '100644',
      'sha': sha,
      'size': bytes.length,
    };
  }

  Future<void> start() async {
    directories[tree] = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await handle(request);
      } catch (e) {
        if (allowDisconnect && (e is HttpException || e is SocketException)) {
          return;
        }
        errors.add(e);
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  GitHubApi client([String token = pullToken]) =>
      GitHubApi.forTesting(token, Uri.parse('http://127.0.0.1:${server.port}'));

  Future<void> raw(HttpRequest request, List<int> bytes) async {
    request.response.headers.contentType = ContentType.binary;
    for (var offset = 0; offset < bytes.length; offset += 16384) {
      request.response.add(
        bytes.sublist(offset, (offset + 16384).clamp(0, bytes.length)),
      );
      await request.response.flush();
    }
    await request.response.close();
  }

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    calls.add('${request.method} $path');
    final auth = request.headers.value('authorization');
    if (path.startsWith('/repos/')) {
      expect(auth, anyOf(isNull, 'Bearer $pullToken'));
    }
    Object result;
    if (path == '/repos/me/files/git/ref/heads/main') {
      result = {
        'object': {'sha': commit},
      };
    } else if (path == '/repos/me/files/git/commits/$commit') {
      result = {
        'tree': {'sha': tree},
      };
    } else if (path.startsWith('/repos/me/files/git/trees/')) {
      result = {'truncated': false, 'tree': directories[path.split('/').last]};
    } else if (path.startsWith('/repos/me/files/git/blobs/')) {
      expect(
        request.headers.value('accept'),
        'application/vnd.github.raw+json',
      );
      var content = List<int>.of(blobs[path.split('/').last]!);
      if (corrupt && content.isNotEmpty) content[0] ^= 1;
      if (truncate && content.isNotEmpty) content.removeLast();
      await raw(request, content);
      return;
    } else if (path == '/me/files.git/info/lfs/objects/batch') {
      expect(request.method, 'POST');
      expect(
        auth,
        'Basic ${base64.encode(utf8.encode('x-access-token:$pullToken'))}',
      );
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      expect(body['operation'], 'download');
      final object = (body['objects'] as List).single as Map;
      expect(object['oid'], sha256.convert(lfsBytes!).toString());
      result = {
        'objects': [
          {
            ...object,
            'actions': {
              'download': {
                'href':
                    (lfsUrl ??
                            Uri.parse(
                              'http://127.0.0.1:${server.port}/lfs/download',
                            ))
                        .toString(),
                'header': {
                  'Authorization': 'RemoteAuth temporary-object-credential',
                },
              },
            },
          },
        ],
      };
    } else if (path == '/lfs/download') {
      objectRequests++;
      expect(auth, 'RemoteAuth temporary-object-credential');
      expect(auth, isNot(contains(pullToken)));
      final content = List<int>.of(lfsBytes!);
      if (lfsCorrupt && content.isNotEmpty) content[0] ^= 1;
      await raw(request, content);
      return;
    } else {
      throw StateError('Unexpected request ${request.method} $path');
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result));
    await request.response.close();
  }

  List<int> pointer(List<int> contents) => utf8.encode(
    'version https://git-lfs.github.com/spec/v1\noid sha256:${sha256.convert(contents)}\nsize ${contents.length}\n',
  );
}

void main() {
  late Directory root;
  late PullFixture fixture;
  late GitHubApi api;
  final target = GitHubTarget('me/files', 'main', '');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('swiftdrop-pull-');
    fixture = PullFixture();
    await fixture.start();
    api = fixture.client();
  });
  tearDown(() async {
    api.close();
    await fixture.server.close(force: true);
    await root.delete(recursive: true);
    expect(fixture.errors, isEmpty);
  });

  test('browses immutable directories and omits unsafe paths, links and submodules', () async {
    fixture.directories[fixture.tree] = [
      fixture.file('safe.txt', [1]),
      fixture.file('../escape', [1]),
      fixture.file('CON', [1]),
      {'path': '.git', 'type': 'tree', 'mode': '040000', 'sha': oid('git')},
      {
        'path': 'link',
        'type': 'blob',
        'mode': '120000',
        'sha': oid('link'),
        'size': 1,
      },
      {
        'path': 'module',
        'type': 'commit',
        'mode': '160000',
        'sha': oid('module'),
      },
      {
        'path': 'folder',
        'type': 'tree',
        'mode': '040000',
        'sha': fixture.subTree,
      },
    ];
    fixture.directories[fixture.subTree] = [
      fixture.file('child.txt', [2]),
    ];
    final listing = await api.browse(target);
    expect(listing.entries.map((e) => e.name), ['folder', 'safe.txt']);
    final sub = await api.browse(
      GitHubTarget('me/files', 'main', 'folder'),
      commit: listing.commit,
    );
    expect(sub.commit, listing.commit);
    expect(sub.entries.single.path, 'folder/child.txt');
    expect(fixture.calls.where((c) => c.contains('/git/ref/')).length, 1);
  });

  test('public browse and downloads work without a token', () async {
    api.close();
    api = fixture.client('');
    fixture.directories[fixture.tree] = [
      fixture.file('public.txt', [1, 2, 3]),
    ];
    final listing = await api.browse(target);
    final result = await api.pull(listing, listing.entries, root, (_) {});
    expect(await File('${result.path}/public.txt').readAsBytes(), [1, 2, 3]);
  });

  test(
    'large folders require narrowing but permit navigation through ancestors',
    () async {
      fixture.directories[fixture.tree] = [
        for (var i = 0; i < 1001; i++) fixture.file('file-$i', [1]),
        {
          'path': 'folder',
          'type': 'tree',
          'mode': '040000',
          'sha': fixture.subTree,
        },
      ];
      fixture.directories[fixture.subTree] = [
        fixture.file('one', [1]),
      ];
      await expectLater(api.browse(target), throwsA(isA<GitHubFailure>()));
      final listing = await api.browse(
        GitHubTarget('me/files', 'main', 'folder'),
      );
      expect(listing.entries.single.path, 'folder/one');
    },
  );

  test(
    'streams binary, Unicode and empty files and preserves local files',
    () async {
      final bytes = List<int>.generate(65536 * 4 + 17, (i) => i % 256);
      fixture.directories[fixture.tree] = [
        fixture.file('你好.bin', bytes),
        fixture.file('empty', []),
      ];
      final original = await File('${root.path}/你好.bin')
          .writeAsString('keep me');
      final listing = await api.browse(target);
      final progress = <GitHubProgress>[];
      final result = await api.pull(
        listing,
        listing.entries,
        root,
        progress.add,
      );
      expect(await File('${result.path}/你好.bin').readAsBytes(), bytes);
      expect(await File('${result.path}/empty').length(), 0);
      expect(await original.readAsString(), 'keep me');
      expect(result.bytes, bytes.length);
      expect(result.files, 2);
      expect(progress.last.state, 'Complete');
      expect(progress.where((p) => p.bytes > 0).length, greaterThan(2));
      expect(fixture.calls.every((c) => c.startsWith('GET ')), isTrue);
      expect(
        await Directory(result.path).parent.list().length,
        1,
      ); // No .part files.
    },
  );

  test(
    'preserves repository folder paths and creates separate pull batches',
    () async {
      fixture.directories[fixture.tree] = [
        {
          'path': 'folder',
          'type': 'tree',
          'mode': '040000',
          'sha': fixture.subTree,
        },
      ];
      fixture.directories[fixture.subTree] = [
        fixture.file('a.bin', [7]),
      ];
      final listing = await api.browse(
        GitHubTarget('me/files', 'main', 'folder'),
      );
      final first = await api.pull(listing, listing.entries, root, (_) {});
      final second = await api.pull(listing, listing.entries, root, (_) {});
      expect(first.path, isNot(second.path));
      expect(await File('${second.path}/folder/a.bin').readAsBytes(), [7]);
    },
  );

  for (final truncated in [false, true]) {
    test(
      '${truncated ? 'truncated' : 'corrupt'} blobs discard the entire incomplete batch',
      () async {
        fixture.directories[fixture.tree] = [
          fixture.file('a.bin', [1, 2, 3]),
        ];
        final listing = await api.browse(target);
        fixture.corrupt = !truncated;
        fixture.truncate = truncated;
        await expectLater(
          api.pull(listing, listing.entries, root, (_) {}),
          throwsA(isA<GitHubFailure>()),
        );
        expect(await root.list().length, 0);
      },
    );
  }

  test(
    'resolves Git LFS pointers into exact original file bytes with SHA256',
    () async {
      fixture.lfsBytes = List<int>.generate(250000, (i) => i % 251);
      fixture.directories[fixture.tree] = [
        fixture.file('app.apk', fixture.pointer(fixture.lfsBytes!)),
      ];
      final listing = await api.browse(target);
      final progress = <GitHubProgress>[];
      final result = await api.pull(
        listing,
        listing.entries,
        root,
        progress.add,
      );
      expect(
        await File('${result.path}/app.apk').readAsBytes(),
        fixture.lfsBytes,
      );
      expect(result.bytes, fixture.lfsBytes!.length);
      expect(progress.last.total, fixture.lfsBytes!.length);
      expect(fixture.objectRequests, 1);
    },
  );

  test('corrupt Git LFS contents are discarded', () async {
    fixture.lfsBytes = [1, 2, 3];
    fixture.lfsCorrupt = true;
    fixture.directories[fixture.tree] = [
      fixture.file('app.apk', fixture.pointer(fixture.lfsBytes!)),
    ];
    final listing = await api.browse(target);
    await expectLater(
      api.pull(listing, listing.entries, root, (_) {}),
      throwsA(isA<GitHubFailure>()),
    );
    expect(await root.list().length, 0);
  });

  test(
    'rejects unsafe LFS object hosts before sending storage credentials',
    () async {
      fixture.lfsBytes = [1];
      fixture.lfsUrl = Uri.parse('https://example.com/steal');
      fixture.directories[fixture.tree] = [
        fixture.file('app.apk', fixture.pointer(fixture.lfsBytes!)),
      ];
      final listing = await api.browse(target);
      await expectLater(
        api.pull(listing, listing.entries, root, (_) {}),
        throwsA(isA<GitHubFailure>()),
      );
      expect(fixture.objectRequests, 0);
      expect(await root.list().length, 0);
    },
  );

  test(
    'invalid LFS pointers are rejected instead of saved as APK files',
    () async {
      fixture.directories[fixture.tree] = [
        fixture.file(
          'app.apk',
          utf8.encode(
            'version https://git-lfs.github.com/spec/v1\noid sha256:bad\nsize 10\n',
          ),
        ),
      ];
      final listing = await api.browse(target);
      await expectLater(
        api.pull(listing, listing.entries, root, (_) {}),
        throwsA(isA<GitHubFailure>()),
      );
      expect(await root.list().length, 0);
    },
  );

  test(
    'cancellation discards downloaded parts without touching existing files',
    () async {
      fixture.allowDisconnect = true;
      fixture.directories[fixture.tree] = [
        fixture.file('large.bin', List.filled(65536 * 8, 7)),
      ];
      final original = await File('${root.path}/keep').writeAsString('keep');
      final listing = await api.browse(target);
      await expectLater(
        api.pull(listing, listing.entries, root, (p) {
          if (p.bytes > 0) api.cancel();
        }),
        throwsA(anything),
      );
      expect(await original.readAsString(), 'keep');
      expect(await root.list().length, 1);
    },
  );

  test('rejects duplicate or forged entries before writing files', () async {
    fixture.directories[fixture.tree] = [
      fixture.file('one', [1]),
    ];
    final listing = await api.browse(target);
    await expectLater(
      api.pull(
        listing,
        [listing.entries.single, listing.entries.single],
        root,
        (_) {},
      ),
      throwsA(isA<GitHubFailure>()),
    );
    await expectLater(
      api.pull(
        listing,
        [GitHubRemoteEntry('../escape', oid('bad'), 1, false)],
        root,
        (_) {},
      ),
      throwsA(anything),
    );
    expect(await root.list().length, 0);
  });

  test('rejects symlink destinations', () async {
    if (Platform.isWindows) {
      return; // Creating Windows links requires OS privileges.
    }
    final real = await Directory('${root.path}/real').create();
    final link = await Link('${root.path}/link').create(real.path);
    fixture.directories[fixture.tree] = [
      fixture.file('one', [1]),
    ];
    final listing = await api.browse(target);
    await expectLater(
      api.pull(listing, listing.entries, Directory(link.path), (_) {}),
      throwsA(isA<GitHubFailure>()),
    );
    expect(await real.list().length, 0);
  });

  test('controller records verified pulls in history and requires token for pushes', () async {
    fixture.directories[fixture.tree] = [
      fixture.file('one', [1]),
    ];
    final store = Store('${root.path}/state.sqlite');
    final c = GitHubController(
      MemorySecrets(),
      store,
      apiFactory: (t) => fixture.client(t),
    );
    try {
      await c.initialize();
      c.repository = 'me/files';
      c.downloadDestination = '${root.path}/saved';
      c.setPullMode(true);
      await c.loadFiles();
      expect(c.error, isNull);
      c.selectRemote('one', true);
      await c.pullSelected();
      expect(c.error, isNull);
      expect(c.pullResult!.files, 1);
      expect(store.all('history').single['bytes'], 1);
      expect(store.all('history').single['commit'], fixture.commit);
      c.setPullMode(false);
      expect(c.listing, isNull);
      expect(c.selectedRemote, isEmpty);
      await c.preview([]);
      expect(c.error, contains('token'));
    } finally {
      c.dispose();
      store.close();
    }
  });
}
