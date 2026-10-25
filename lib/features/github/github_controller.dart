import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../pairing/identity.dart';
import '../storage/store.dart';
import '../transfer/sender.dart';
import 'github_api.dart';

class GitHubController extends ChangeNotifier {
  final SecretStore secrets;
  final Store store;
  final GitHubApi Function(String) createApi;
  String repository = '', branch = 'main', folder = '', token = '';
  bool rememberToken = false, busy = false;
  String? error, commitUrl, recoveryUrl;
  GitHubPlan? plan;
  GitHubProgress? progress;
  GitHubApi? _active;
  bool _closed = false;
  GitHubController(
    this.secrets,
    this.store, {
    GitHubApi Function(String)? apiFactory,
  }) : createApi = apiFactory ?? GitHubApi.new;

  Future<void> initialize() async {
    repository = store.setting('github.repository') ?? '';
    branch = store.setting('github.branch') ?? 'main';
    folder = store.setting('github.folder') ?? '';
    try {
      token = await secrets.read('github.token') ?? '';
      rememberToken = token.isNotEmpty;
    } catch (_) {
      error = 'Could not read the GitHub token from secure storage. Enter it again.';
    }
  }

  void invalidate() {
    if (busy) return;
    plan = null;
    commitUrl = null;
    recoveryUrl = null;
    progress = null;
    error = null;
    _changed();
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> _run(Future<void> Function(GitHubApi) work) async {
    if (busy || _closed) return;
    busy = true;
    error = null;
    recoveryUrl = null;
    _changed();
    try {
      final api = createApi(token);
      _active = api;
      await work(api);
    } catch (e) {
      recoveryUrl = _active?.recoveryUrl;
      error = switch (e) {
        GitHubFailure() => e.message,
        SocketException() || TimeoutException() => 'GitHub connection interrupted. Check internet access and retry after reviewing the files.',
        HandshakeException() => 'GitHub TLS verification failed. Check your clock, network and trusted certificates.',
        FileSystemException() => 'Cannot read a selected file. Check permissions and available disk space.',
        _ => 'GitHub operation failed. Check the token, repository and connection, then review again.',
      };
      if (_active?.cancelled == true && recoveryUrl == null) {
        error = 'GitHub upload cancelled. No batch was published.';
      }
      if (recoveryUrl != null) {
        error =
            '$error The final update could not be confirmed. Check the commit and branch on GitHub before retrying.';
      }
      plan = null;
    } finally {
      _active?.close();
      _active = null;
      busy = false;
      _changed();
    }
  }

  Future<void> preview(List<SourceFile> sources) async {
    await _run((api) async {
      plan = null;
      commitUrl = null;
      progress = const GitHubProgress(
        'Checking repository and files',
        '',
        0,
        0,
      );
      _changed();
      final target = GitHubTarget(repository, branch, folder);
      final result = await api.preview(target, List.of(sources));
      // Tokens are never put in SQLite or the repository. An empty vault value
      // revokes the remembered token without affecting pairing credentials.
      await secrets.write('github.token', rememberToken ? token.trim() : '');
      store.setSetting('github.repository', target.name);
      store.setSetting('github.branch', target.branch);
      store.setSetting('github.folder', target.folder);
      plan = result;
      progress = null;
    });
  }

  Future<void> upload(String message) async {
    final reviewed = plan;
    if (reviewed == null) return;
    await _run((api) async {
      var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      commitUrl = await api.upload(reviewed, message, (value) {
        progress = value;
        final now = DateTime.now();
        if (!value.canCancel ||
            now.difference(lastUpdate).inMilliseconds >= 100) {
          lastUpdate = now;
          _changed();
        }
      });
      plan = null;
    });
  }

  void cancel() {
    if (progress?.canCancel != false) _active?.cancel();
  }

  Future<void> setRememberToken(bool value) async {
    if (busy) return;
    try {
      if (!value) await secrets.write('github.token', '');
      rememberToken = value;
      invalidate();
    } catch (_) {
      error = 'Could not update secure storage. Try again.';
      _changed();
    }
  }

  Future<void> forgetToken() async {
    if (busy) return;
    try {
      await secrets.write('github.token', '');
      token = '';
      rememberToken = false;
      invalidate();
    } catch (_) {
      error = 'Could not remove the remembered token from secure storage. Try again.';
      _changed();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _active?.cancel();
    token = '';
    super.dispose();
  }
}
