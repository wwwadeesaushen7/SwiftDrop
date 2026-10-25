import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/protocol.dart';
import '../features/discovery/discovery.dart';
import '../features/github/github_controller.dart';
import '../features/pairing/identity.dart';
import '../features/storage/store.dart';
import '../features/transfer/receiver.dart';
import '../features/transfer/sender.dart';

class AppController extends ChangeNotifier {
  late final Store store;
  late final Identity identity;
  final SecretStore secrets;
  final String profile;
  late final Sender sender;
  late final Discovery discovery;
  late final GitHubController github;
  late Directory support;
  Directory? destination;
  Receiver? receiver;
  Consent? ask;
  bool ready = false, busy = false, visible = true;
  String name = Platform.localHostname, theme = 'system';
  String? error;
  List<InternetAddress> interfaces = [];
  InternetAddress? selectedInterface;
  List<SourceFile> selection = [];
  Map<String, int> selectedSizes = {};
  List<Peer> peers = [];
  Peer? selectedPeer;
  TransferProgress? progress;
  final Stopwatch _receiveClock = Stopwatch()..start();
  final Map<String, ({int bytes, int micros, double speed})> _receiveSamples =
      {};
  PairingInvite? invite;
  Timer? _networkTimer;
  bool _checking = false;
  AppController({SecretStore? secrets, this.profile = 'default'})
    : secrets = secrets ?? PlatformSecrets(namespace: profile);
  List<Map<String, dynamic>> get history => ready ? store.all('history') : [];
  List<Map<String, dynamic>> get pending => ready ? store.all('outgoing') : [];
  int get selectionBytes => selectedSizes.values.fold(0, (a, b) => a + b);

  Future<void> initialize({
    Directory? supportOverride,
    Directory? destinationOverride,
  }) async {
    await guard(() async {
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(profile)) {
        throw const FormatException('Invalid profile name');
      }
      support =
          supportOverride ??
          Directory(
            p.join((await getApplicationSupportDirectory()).path, profile),
          );
      await support.create(recursive: true);
      store = Store(p.join(support.path, 'swiftdrop.sqlite'));
      github = GitHubController(secrets, store);
      await github.initialize();
      name = store.setting('name') ?? name;
      if (name.length > 100) name = name.substring(0, 100);
      theme = store.setting('theme') ?? 'system';
      visible = store.setting('visible') != 'false';
      final savedDestination = store.setting('destination');
      if (destinationOverride != null) {
        destination = destinationOverride;
      } else {
        final defaults = Platform.isAndroid || Platform.isIOS
            ? await getApplicationDocumentsDirectory()
            : await getDownloadsDirectory() ??
                  await getApplicationDocumentsDirectory();
        destination = Directory(
          savedDestination ?? p.join(defaults.path, 'SwiftDrop'),
        );
      }
      identity = await Identity.load(secrets);
      final savedPeers = await secrets.read('peers');
      if (savedPeers != null) {
        peers = (jsonDecode(savedPeers) as List)
            .map((v) => Peer.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList();
      }
      selectedPeer = peers.firstOrNull;
      sender = Sender(store, (value) {
        progress = value;
        notifyListeners();
      });
      discovery = Discovery(notifyListeners, setError);
      await refreshInterfaces();
      ready = true;
      _networkTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_networkCheck()),
      );
    });
  }

  void setError(String message) {
    error = message;
    notifyListeners();
  }

  Future<void> guard(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work();
    } catch (e) {
      error = readableError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String readableError(Object e) {
    if (e is HandshakeException) {
      return 'Device certificate did not match. Create a new pairing invitation on the receiver.';
    }
    if (e is SocketException || e is TimeoutException) {
      return 'Connection interrupted. Check same Wi-Fi/hotspot, private-network firewall permission and client isolation, then retry to resume.';
    }
    if (e is FileSystemException) {
      return 'File access failed. Check free disk space and file or folder permissions.';
    }
    return e.toString().replaceFirst('FormatException: ', '');
  }

  Future<void> refreshInterfaces() async {
    interfaces = (await NetworkInterface.list(type: InternetAddressType.IPv4))
        .expand((n) => n.addresses)
        .where((a) => isPrivateAddress(a) && !a.isLoopback)
        .toList();
    selectedInterface =
        interfaces
            .where((a) => a.address == selectedInterface?.address)
            .firstOrNull ??
        interfaces.firstOrNull;
    notifyListeners();
  }

  Future<void> _networkCheck() async {
    if (_checking || !ready) return;
    _checking = true;
    try {
      final previous = receiver?.address;
      await refreshInterfaces();
      if (previous != null && !interfaces.any((a) => a.address == previous)) {
        await disableSharing();
        setError(
          'Network changed. Receiving stopped safely. Select the new interface and enable receiving again.',
        );
      }
    } catch (e) {
      setError(readableError(e));
    } finally {
      _checking = false;
    }
  }

  Future<void> ensureLocalNetworkPermission() async {
    if (Platform.isAndroid) {
      final allowed = await const MethodChannel('app.swiftdrop/files')
          .invokeMethod<bool>('requestLocalNetwork');
      if (allowed != true) {
        throw const FormatException(
          'Local network permission denied. Enable it in Android app settings.',
        );
      }
    }
  }

  void changed() => notifyListeners();
  Future<void> enableSharing() async {
    await ensureLocalNetworkPermission();
    if (selectedInterface == null) {
      throw const FormatException('Connect to Wi-Fi or a phone hotspot first');
    }
    await disableSharing();
    receiver = Receiver(
      identity: identity,
      secrets: secrets,
      store: store,
      name: name,
      destination: destination!,
      consent: (title, details) async =>
          await ask?.call(title, details) ?? false,
      onUpdate: (id, bytes, total, state) {
        final micros = _receiveClock.elapsedMicroseconds;
        final previous = _receiveSamples[id];
        var speed = previous?.speed ?? 0.0;
        if (previous != null &&
            micros > previous.micros &&
            bytes > previous.bytes) {
          final measured =
              (bytes - previous.bytes) * 1000000 / (micros - previous.micros);
          speed = speed == 0 ? measured : speed * 0.75 + measured * 0.25;
        }
        _receiveSamples[id] = (bytes: bytes, micros: micros, speed: speed);
        if (!sender.running) {
          progress = TransferProgress(id, state, '', bytes, total, speed);
        }
        if (state == 'Complete' || state == 'Cancelled') {
          _receiveSamples.remove(id);
        }
        notifyListeners();
      },
    );
    final storedPort = int.tryParse(store.setting('port') ?? '') ?? 0;
    try {
      await receiver!.start(selectedInterface!, port: storedPort);
    } on SocketException {
      await receiver!.start(selectedInterface!);
    }
    store.setSetting('port', '${receiver!.port}');
    invite = receiver!.invite();
    if (visible) {
      try {
        await discovery.start(name, receiver!.port, identity.fingerprint);
      } catch (_) {
        setError(
          'Receiving works, but discovery failed. Use the QR or manual invitation.',
        );
      }
    }
    notifyListeners();
  }

  Future<void> disableSharing() async {
    await receiver?.stop();
    receiver = null;
    invite = null;
    if (ready) await discovery.stop();
    notifyListeners();
  }

  void newInvite() {
    invite = receiver?.invite();
    notifyListeners();
  }

  Future<void> pair(String text) async {
    await ensureLocalNetworkPermission();
    final value = PairingInvite.parse(text);
    final previous = peers
        .where((peer) => peer.fingerprint == value.fingerprint)
        .firstOrNull;
    late Peer peer;
    if (previous != null) {
      try {
        peer = await Sender.reconnect(value, previous);
      } on TransferException catch (e) {
        if (e.statusCode != 401) rethrow;
        peer = await Sender.pair(value, name);
      }
    } else {
      peer = await Sender.pair(value, name);
    }
    peers.removeWhere((p) => p.fingerprint == peer.fingerprint);
    peers.add(peer);
    selectedPeer = peer;
    await secrets.write(
      'peers',
      jsonEncode(peers.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> forgetPeer(Peer peer) async {
    peers.removeWhere((p) => p.fingerprint == peer.fingerprint);
    selectedPeer = peers.firstOrNull;
    await secrets.write(
      'peers',
      jsonEncode(peers.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> pickFiles() async {
    final picked = await FilePicker.pickFiles();
    final result = <SourceFile>[];
    for (final file in picked) {
      if (file.path != null) {
        result.add(SourceFile(file.path!, safeRelativePath(file.name)));
      } else {
        // SAF content URIs are not filesystem paths. Copy with stream backpressure
        // into durable app storage so hashing and retry can seek without RAM copies.
        final root = Directory(p.join(support.path, 'outbox', randomToken(12)));
        await root.create(recursive: true);
        final path = p.join(root.path, safeRelativePath(file.name));
        final sink = File(path).openWrite();
        try {
          await sink.addStream(file.readAsByteStream());
          await sink.flush();
        } finally {
          await sink.close();
        }
        result.add(SourceFile(path, file.name));
      }
    }
    await addSources(result);
  }

  Future<void> addPaths(List<String> paths) async =>
      addSources(await collectSources(paths));
  Future<void> addSources(List<SourceFile> sources) async {
    final combined = [...selection, ...sources];
    if (combined.length > maxFiles) {
      throw const FormatException('Too many files');
    }
    final names = <String>{};
    final sizes = <String, int>{};
    for (final source in combined) {
      if (!names.add(source.relativePath.toLowerCase())) {
        throw const FormatException(
          'Two selected files have the same relative name. Send them separately or select their parent folders.',
        );
      }
      sizes[source.relativePath] = await File(source.localPath).length();
    }
    selection = combined;
    selectedSizes = sizes;
    github.invalidate();
    notifyListeners();
  }

  Future<void> pickFolder() async {
    if (Platform.isAndroid || Platform.isIOS) {
      throw const FormatException(
        'Folder selection is currently available on desktop. Select multiple files on mobile.',
      );
    }
    final path = await FilePicker.getDirectoryPath();
    if (path != null) await addPaths([path]);
  }

  void clearSelection() {
    selection = [];
    selectedSizes = {};
    github.invalidate();
    notifyListeners();
  }

  Future<void> send({Map<String, dynamic>? checkpoint}) async {
    final peer = checkpoint == null
        ? selectedPeer
        : peers.where((p) => p.fingerprint == checkpoint['peer']).firstOrNull;
    if (peer == null) {
      throw const FormatException('Pair the destination device first');
    }
    final sources = checkpoint == null
        ? selection
        : (checkpoint['sources'] as List)
              .map(
                (v) =>
                    SourceFile(v['local'] as String, v['relative'] as String),
              )
              .toList();
    await sender.send(
      peer,
      name,
      sources,
      resumeId: checkpoint?['id'] as String?,
    );
    notifyListeners();
  }

  Future<void> revokeIncomingPairings() async {
    final authorized =
        jsonDecode(store.setting('authorized') ?? '{}') as Map<String, dynamic>;
    for (final hash in authorized.keys) {
      await secrets.write('authorized_$hash', '');
    }
    store.setSetting('authorized', '{}');
    notifyListeners();
  }

  Future<void> chooseDestination() async {
    if (receiver != null) {
      throw const FormatException(
        'Disable receiving before changing destination',
      );
    }
    final path = await FilePicker.getDirectoryPath();
    if (path != null) {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw const FormatException(
          'Destination must be a local writable folder',
        );
      }
      final probe = File(p.join(path, '.swiftdrop-${randomToken(8)}'));
      await probe.writeAsString('', flush: true);
      await probe.delete();
      destination = directory;
      store.setSetting('destination', path);
      notifyListeners();
    }
  }

  Future<void> updateName(String value) async {
    value = value.trim();
    if (value.isEmpty ||
        value.length > 100 ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Use a device name of 1–100 characters');
    }
    if (receiver != null) await disableSharing();
    name = value;
    store.setSetting('name', name);
    notifyListeners();
  }

  void setTheme(String value) {
    theme = value;
    store.setSetting('theme', value);
    notifyListeners();
  }

  Future<void> setVisible(bool value) async {
    visible = value;
    store.setSetting('visible', '$value');
    if (receiver != null) {
      if (visible) {
        await discovery.start(name, receiver!.port, identity.fingerprint);
      } else {
        await discovery.stop();
      }
    }
    notifyListeners();
  }

  Future<void> close() async {
    _networkTimer?.cancel();
    if (ready) {
      github.dispose();
      sender.cancel();
      await disableSharing();
      store.close();
    }
  }
}
