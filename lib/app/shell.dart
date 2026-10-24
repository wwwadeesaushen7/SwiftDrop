import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/transfer/sender.dart';
import 'controller.dart';

const brand = Color(0xFF6754E8);
String bytesLabel(num value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var unit = 0;
  var amount = value.toDouble();
  while (amount >= 1000 && unit < units.length - 1) {
    amount /= 1000;
    unit++;
  }
  return '${amount.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class SwiftDropApp extends StatelessWidget {
  final AppController controller;
  const SwiftDropApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      ThemeData theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brand,
          brightness: brightness,
        ),
        scaffoldBackgroundColor: brightness == Brightness.dark
            ? const Color(0xFF10121C)
            : const Color(0xFFF5F6FB),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      );
      return MaterialApp(
        title: 'SwiftDrop',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: switch (controller.theme) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        },
        home: SwiftDropShell(controller: controller),
      );
    },
  );
}

class SwiftDropShell extends StatefulWidget {
  final AppController controller;
  const SwiftDropShell({super.key, required this.controller});
  @override
  State<SwiftDropShell> createState() => _SwiftDropShellState();
}

class _SwiftDropShellState extends State<SwiftDropShell>
    with WidgetsBindingObserver {
  AppController get c => widget.controller;
  int page = 0;
  bool dragging = false;
  final invitation = TextEditingController();
  final deviceName = TextEditingController();
  final manualHost = TextEditingController();
  final manualPort = TextEditingController();
  final manualFingerprint = TextEditingController();
  final manualToken = TextEditingController();
  final manualExpiry = TextEditingController();
  Timer? _clock;
  static const pages = [
    'Home',
    'Send files',
    'Receive files',
    'Nearby devices',
    'Pair devices',
    'Transfers',
    'History',
    'Settings',
    'Connection help',
  ];
  static const icons = [
    Icons.grid_view_rounded,
    Icons.north_east_rounded,
    Icons.south_west_rounded,
    Icons.devices_rounded,
    Icons.qr_code_rounded,
    Icons.swap_vert_rounded,
    Icons.history_rounded,
    Icons.tune_rounded,
    Icons.help_outline_rounded,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.ask = _consent;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && page == 4) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    c.ask = null;
    invitation.dispose();
    deviceName.dispose();
    manualHost.dispose();
    manualPort.dispose();
    manualFingerprint.dispose();
    manualToken.dispose();
    manualExpiry.dispose();
    unawaited(c.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && c.ready) {
      unawaited(c.refreshInterfaces());
    }
  }

  Future<bool> _consent(String title, String details) async {
    if (!mounted) return false;
    final deadline = DateTime.now().add(const Duration(seconds: 55));
    // Dialog expires before the network consent timeout; no stale approval can
    // authorize a request after its caller has already rejected it.
    Timer? expiry;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        expiry ??= Timer(deadline.difference(DateTime.now()), () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop(false);
        });
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(details)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                DateTime.now().isBefore(deadline),
              ),
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
    expiry?.cancel();
    return result ?? false;
  }

  void navigate(int value) => setState(() => page = value);
  Widget button(String text, IconData icon, Future<void> Function() action) =>
      FilledButton.icon(
        onPressed: c.busy ? null : () => unawaited(c.guard(action)),
        icon: Icon(icon),
        label: Text(text),
      );
  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(24)}) =>
      Card(
        child: Padding(padding: padding, child: child),
      );
  Widget title(String heading, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: brand),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'SwiftDrop',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            if (wide)
              const Text(
                'LOCAL. PRIVATE. YOURS.',
                style: TextStyle(fontSize: 10, letterSpacing: 2),
              ),
          ],
        ),
        actions: [
          if (c.ready && !wide)
            IconButton(
              onPressed: () => navigate(2),
              tooltip: c.receiver == null ? 'Sharing off' : 'Receiving on',
              icon: Icon(
                c.receiver == null ? Icons.shield_outlined : Icons.wifi_rounded,
              ),
            ),
          if (c.ready && wide)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: Icon(
                  c.receiver == null
                      ? Icons.shield_outlined
                      : Icons.wifi_rounded,
                  size: 16,
                ),
                label: Text(
                  c.receiver == null ? 'Sharing off' : 'Receiving on',
                ),
              ),
            ),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    const ListTile(
                      title: Text(
                        'SwiftDrop',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (var i = 0; i < pages.length; i++)
                      ListTile(
                        leading: Icon(icons[i]),
                        title: Text(pages[i]),
                        selected: page == i,
                        onTap: () {
                          Navigator.pop(context);
                          navigate(i);
                        },
                      ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page <= 3 ? page : 0,
              onDestinationSelected: navigate,
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationDestination(
                    icon: Icon(icons[i]),
                    label: ['Home', 'Send', 'Receive', 'Nearby'][i],
                  ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width > 1200,
              selectedIndex: page,
              onDestinationSelected: navigate,
              destinations: [
                for (var i = 0; i < pages.length; i++)
                  NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(pages[i]),
                  ),
              ],
            ),
          Expanded(
            child: Column(
              children: [
                if (c.busy) const LinearProgressIndicator(minHeight: 2),
                if (c.error != null)
                  MaterialBanner(
                    content: Text(c.error!),
                    leading: const Icon(Icons.info_outline),
                    actions: [
                      TextButton(
                        onPressed: () {
                          c.error = null;
                          c.changed();
                        },
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(
                  child: !c.ready
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              c.busy
                                  ? 'Preparing your private device identity…'
                                  : 'Setup could not complete. ${c.error ?? 'Restart the app after checking platform dependencies.'}',
                            ),
                          ),
                        )
                      : DropTarget(
                          enable:
                              !c.busy &&
                              (Platform.isWindows ||
                                  Platform.isLinux ||
                                  Platform.isMacOS),
                          onDragEntered: (_) => setState(() => dragging = true),
                          onDragExited: (_) => setState(() => dragging = false),
                          onDragDone: (details) {
                            setState(() {
                              dragging = false;
                              page = 1;
                            });
                            unawaited(
                              c.guard(
                                () => c.addPaths(
                                  details.files
                                      .map((file) => file.path)
                                      .toList(),
                                ),
                              ),
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              border: dragging
                                  ? Border.all(color: brand, width: 3)
                                  : null,
                            ),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(wide ? 36 : 20),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1100,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: KeyedSubtree(
                                      key: ValueKey(page),
                                      child: content(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget content() => switch (page) {
    0 => home(),
    1 => send(),
    2 => receive(),
    3 => nearby(),
    4 => pairing(),
    5 => transfers(),
    6 => history(),
    7 => settings(),
    _ => help(),
  };

  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Your files. Without the cloud.',
        'Fast, encrypted sharing across your local network.',
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6754E8), Color(0xFF3445AF)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.bolt_rounded, color: Colors.white, size: 46),
            const SizedBox(height: 16),
            const Text(
              'Big files. Short distance.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This device · ${c.name}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () => navigate(1),
              icon: const Icon(Icons.add),
              label: const Text('Choose files to send'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final item in [
              (
                1,
                'Send files',
                'Pick files or drop a folder',
                Icons.north_east_rounded,
              ),
              (
                2,
                'Receive files',
                'You approve every transfer',
                Icons.south_west_rounded,
              ),
              (
                3,
                'Nearby devices',
                'Find your next connection',
                Icons.devices_rounded,
              ),
            ])
              SizedBox(
                width: constraints.maxWidth > 650
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => navigate(item.$1),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(item.$4, color: brand, size: 32),
                          const SizedBox(height: 18),
                          Text(
                            item.$2,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(item.$3),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      panel(
        const Row(
          children: [
            Icon(Icons.lock_outline, color: brand),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Direct TLS connections • Certificate-pinned pairing • No accounts\nKeep mobile sessions in the foreground while sharing.',
              ),
            ),
          ],
        ),
      ),
      if (c.progress != null) ...[
        const SizedBox(height: 24),
        progressCard(c.progress!),
      ],
    ],
  );

  Widget send() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Send something great.',
        'Original files. Original quality. Direct to their device.',
      ),
      panel(
        Column(
          children: [
            const Icon(Icons.upload_file_rounded, size: 56, color: brand),
            const SizedBox(height: 16),
            const Text('Drop files and folders here on desktop'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                button('Choose files', Icons.add, c.pickFiles),
                if (!Platform.isAndroid && !Platform.isIOS)
                  OutlinedButton.icon(
                    onPressed: c.busy
                        ? null
                        : () => unawaited(c.guard(c.pickFolder)),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Choose folder'),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (c.selection.isNotEmpty)
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.selection.length} files · ${bytesLabel(c.selectionBytes)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: c.sender.running ? null : c.clearSelection,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              for (final file in c.selection.take(100))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(file.relativePath),
                  trailing: Text(
                    bytesLabel(c.selectedSizes[file.relativePath] ?? 0),
                  ),
                ),
              if (c.selection.length > 100)
                Text('And ${c.selection.length - 100} more files'),
            ],
          ),
        ),
      const SizedBox(height: 20),
      if (c.peers.isEmpty)
        OutlinedButton.icon(
          onPressed: () => navigate(4),
          icon: const Icon(Icons.qr_code),
          label: const Text('Pair a destination'),
        )
      else
        DropdownButtonFormField<String>(
          initialValue: c.selectedPeer?.fingerprint,
          decoration: const InputDecoration(labelText: 'Send to paired device'),
          items: c.peers
              .map(
                (p) => DropdownMenuItem(
                  value: p.fingerprint,
                  child: Text('${p.name} · ${p.host}:${p.port}'),
                ),
              )
              .toList(),
          onChanged: c.sender.running
              ? null
              : (value) {
                  c.selectedPeer = c.peers.firstWhere(
                    (p) => p.fingerprint == value,
                  );
                  c.changed();
                },
        ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: c.busy || c.selection.isEmpty || c.selectedPeer == null
            ? null
            : () {
                navigate(5);
                unawaited(c.guard(() => c.send()));
              },
        icon: const Icon(Icons.north_east),
        label: const Text('Request transfer'),
      ),
    ],
  );

  Widget receive() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Make room for good things.',
        'Enable receiving only on a network you trust.',
      ),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Receive on this network'),
              subtitle: const Text(
                'A private local interface only. Every incoming batch requires your approval.',
              ),
              value: c.receiver != null,
              onChanged: c.busy
                  ? null
                  : (value) => unawaited(
                      c.guard(value ? c.enableSharing : c.disableSharing),
                    ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: c.selectedInterface?.address,
              decoration: const InputDecoration(
                labelText: 'Local Wi-Fi / hotspot interface',
              ),
              items: c.interfaces
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.address,
                      child: Text(a.address),
                    ),
                  )
                  .toList(),
              onChanged: c.receiver != null
                  ? null
                  : (value) {
                      c.selectedInterface = c.interfaces.firstWhere(
                        (a) => a.address == value,
                      );
                      c.changed();
                    },
            ),
            const SizedBox(height: 12),
            Text('Save to: ${c.destination?.path}'),
            if (c.receiver != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                'Listening at ${c.receiver!.address}:${c.receiver!.port}',
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => navigate(4),
                icon: const Icon(Icons.qr_code),
                label: const Text('Show pairing invitation'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Files become available after SHA-256 verification. Partial files remain separate until complete. Incoming batches get separate folders to avoid overwriting your files.',
            ),
            if (Platform.isAndroid)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Android: received files are kept in app documents. Export verified batches to Downloads from History.',
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (c.progress != null) progressCard(c.progress!),
    ],
  );

  Widget nearby() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'A little closer.',
        'Discovery helps you find devices. Pairing establishes trust.',
      ),
      Wrap(
        spacing: 12,
        children: [
          button('Refresh', Icons.refresh, () async {
            await c.refreshInterfaces();
            if (c.receiver != null && c.visible) {
              await c.discovery.start(
                c.name,
                c.receiver!.port,
                c.identity.fingerprint,
              );
            }
          }),
          OutlinedButton(
            onPressed: () => navigate(4),
            child: const Text('Pair manually / QR'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (c.receiver == null)
        panel(
          const Text(
            'Enable receiving to advertise and discover nearby devices. You can always pair with a full invitation manually.',
          ),
        ),
      for (final device in c.discovery.devices.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: panel(
            ListTile(
              leading: Icon(
                device.platform == 'android' || device.platform == 'ios'
                    ? Icons.phone_android
                    : Icons.computer,
              ),
              title: Text(device.name),
              subtitle: Text(
                '${device.platform} · ${device.host}:${device.port}',
              ),
              trailing: TextButton(
                onPressed: () {
                  navigate(4);
                  c.setError(
                    'Open Pair devices on ${device.name}, then scan or paste its invitation. A discovered address alone is not trusted.',
                  );
                },
                child: const Text('Pair'),
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        '${c.peers.length} paired devices',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (final peer in c.peers)
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(peer.name),
          subtitle: Text('${peer.host}:${peer.port}'),
          trailing: IconButton(
            tooltip: 'Forget outgoing pairing',
            icon: const Icon(Icons.link_off),
            onPressed: c.sender.running
                ? null
                : () => unawaited(c.guard(() => c.forgetPeer(peer))),
          ),
        ),
    ],
  );

  Widget pairing() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'A trusted connection.',
        'Share an invitation privately. Approve the device on the receiver.',
      ),
      if (c.invite != null)
        panel(
          Column(
            children: [
              const Text('Scan on the sending device'),
              const SizedBox(height: 16),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: c.invite!.encode(), size: 200),
              ),
              const SizedBox(height: 12),
              Text(
                c.invite!.expires.isAfter(DateTime.now())
                    ? 'Expires in ${c.invite!.expires.difference(DateTime.now()).inSeconds}s · single use'
                    : 'Expired — create a new invitation',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: c.invite!.encode()),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Invitation copied. Share privately; it expires in 5 minutes.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy invitation'),
                  ),
                  TextButton(
                    onPressed: c.newInvite,
                    child: const Text('New invitation'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Certificate fingerprint\n${c.identity.fingerprint}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
      else
        button('Enable receiving to create QR', Icons.qr_code, c.enableSharing),
      const SizedBox(height: 24),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect to a receiver',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: invitation,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Paste full swiftdrop:// invitation',
                helperText: 'Contains local IP, port, certificate fingerprint and expiring token',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                button(
                  'Pair securely',
                  Icons.link,
                  () => c.pair(invitation.text),
                ),
                if (Platform.isAndroid || Platform.isIOS)
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Enter IP and security details manually'),
              children: [
                const Text(
                  'Read these values from the receiver invitation. Never accept a fingerprint supplied only by an untrusted discovered device.',
                ),
                for (final entry in [
                  (manualHost, 'Private IP address'),
                  (manualPort, 'Port'),
                  (manualFingerprint, 'SHA-256 certificate fingerprint'),
                  (manualToken, 'Invitation token'),
                  (manualExpiry, 'Expiry (Unix milliseconds from invitation)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: entry.$1,
                      decoration: InputDecoration(labelText: entry.$2),
                    ),
                  ),
                const SizedBox(height: 12),
                button('Connect manually', Icons.security, () async {
                  final uri = Uri(
                    scheme: 'swiftdrop',
                    host: manualHost.text.trim(),
                    port: int.parse(manualPort.text),
                    queryParameters: {
                      'v': '1',
                      'fp': manualFingerprint.text.trim(),
                      'token': manualToken.text.trim(),
                      'expires': manualExpiry.text.trim(),
                    },
                  );
                  await c.pair(uri.toString());
                }),
              ],
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> scanQr() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (value != null) {
      invitation.text = value;
      await c.guard(() => c.pair(value));
    }
  }

  Widget progressCard(TransferProgress value) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.swap_vert, color: brand),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value.state,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text('${(value.fraction * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: value.state == 'Hashing' || value.state == 'Awaiting approval'
              ? null
              : value.fraction,
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 16),
        Text(value.file),
        const SizedBox(height: 8),
        Text(
          '${bytesLabel(value.bytes)} / ${bytesLabel(value.total)} · ${bytesLabel(value.bytesPerSecond)}/s · ETA ${value.eta == null ? '—' : '${value.eta!.inSeconds}s'}',
        ),
        if (c.sender.running) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  if (value.state == 'Paused') {
                    c.sender.resume();
                  } else {
                    c.sender.pause();
                  }
                },
                icon: Icon(
                  value.state == 'Paused' ? Icons.play_arrow : Icons.pause,
                ),
                label: Text(
                  value.state == 'Paused'
                      ? 'Resume'
                      : 'Pause after current chunk',
                ),
              ),
              TextButton.icon(
                onPressed: c.sender.cancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  Widget transfers() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Every byte accounted for.',
        'Pause after the current chunk. Retry interrupted batches from durable checkpoints.',
      ),
      if (c.progress != null)
        progressCard(c.progress!)
      else
        panel(
          const Text(
            'No active transfers. Select files and a paired device to begin.',
          ),
        ),
      const SizedBox(height: 24),
      for (final pending in c.pending)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: panel(
            ListTile(
              title: Text('Interrupted batch ${pending['id']}'),
              subtitle: const Text(
                'Source files and the receiver session must still be available.',
              ),
              trailing: FilledButton(
                onPressed: c.busy
                    ? null
                    : () =>
                          unawaited(c.guard(() => c.send(checkpoint: pending))),
                child: const Text('Retry / resume'),
              ),
            ),
          ),
        ),
    ],
  );

  Widget history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Delivered, and remembered.',
        'Local history stays on this device. Received files never open automatically.',
      ),
      if (c.history.isEmpty)
        panel(const Text('Completed transfers will appear here.')),
      for (final item in c.history)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item['direction'] == 'Sent'
                        ? Icons.north_east
                        : Icons.south_west,
                  ),
                  title: Text('${item['direction']} · ${item['peer']}'),
                  subtitle: Text(
                    '${item['files']} files · ${bytesLabel(item['bytes'] as num)}\n${item['time']}',
                  ),
                ),
                if (item['path'] != null) ...[
                  SelectableText(item['path'] as String),
                  const SizedBox(height: 12),
                  if (Platform.isAndroid)
                    button('Export verified files to Downloads', Icons.save_alt, () async {
                      final count =
                          await const MethodChannel('app.swiftdrop/files')
                              .invokeMethod<int>('exportBatch', {
                                'path': item['path'],
                              });
                      c.setError(
                        'Exported $count files to Downloads/SwiftDrop. Existing files are preserved by Android.',
                      );
                    })
                  else if (!Platform.isIOS)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                        c.guard(() async {
                          if (!await launchUrl(
                            Uri.directory(item['path'] as String),
                          )) {
                            throw StateError('Could not open folder');
                          }
                        }),
                      ),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open saved location'),
                    ),
                ],
              ],
            ),
          ),
        ),
      if (c.history.isNotEmpty)
        TextButton.icon(
          onPressed: () async {
            if (await _consent(
              'Clear transfer history?',
              'This removes local history entries. Saved files and interrupted-transfer checkpoints remain.',
            )) {
              c.store.clearHistory();
              c.changed();
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear history'),
        ),
    ],
  );

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Make it yours.',
        'A few thoughtful defaults. You stay in control.',
      ),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device identity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: deviceName,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: 'Device name',
                hintText: c.name,
              ),
            ),
            button(
              'Save device name',
              Icons.check,
              () => c.updateName(deviceName.text),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: c.theme,
              decoration: const InputDecoration(labelText: 'Appearance'),
              items: [
                for (final mode in ['system', 'light', 'dark'])
                  DropdownMenuItem(value: mode, child: Text(mode)),
              ],
              onChanged: (value) {
                if (value != null) c.setTheme(value);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visible to nearby devices'),
              subtitle: const Text(
                'Hides discovery without disabling an active receiver.',
              ),
              value: c.visible,
              onChanged: c.busy
                  ? null
                  : (value) => unawaited(c.guard(() => c.setVisible(value))),
            ),
            const Divider(height: 32),
            Text('Receive folder: ${c.destination?.path}'),
            if (!Platform.isAndroid && !Platform.isIOS)
              OutlinedButton.icon(
                onPressed: c.busy
                    ? null
                    : () => unawaited(c.guard(c.chooseDestination)),
                icon: const Icon(Icons.folder_open),
                label: const Text('Change receive folder'),
              ),
            const Divider(height: 32),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_outlined),
              title: Text('Incoming approval is always required'),
              subtitle: Text(
                'Automatic acceptance is intentionally unavailable.',
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.notifications_none),
              title: Text('In-app transfer status'),
              subtitle: Text(
                'System notifications and background transfer services are not implemented in this initial build. Keep mobile apps foregrounded.',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: c.busy
                  ? null
                  : () async {
                      if (await _consent(
                        'Revoke incoming pairings?',
                        'Previously paired senders will need a new invitation. Active uploads should be stopped by disabling receiving first.',
                      )) {
                        await c.guard(() async {
                          await c.disableSharing();
                          await c.revokeIncomingPairings();
                        });
                      }
                    },
              icon: const Icon(Icons.link_off),
              label: const Text('Revoke all incoming pairings'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => navigate(8),
              child: const Text('Permissions & connection troubleshooting'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget help() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Let’s get connected.',
        'Local network issues usually come down to permissions or isolation.',
      ),
      for (final section in [
        (
          'Same local network',
          'Connect both devices to the same Wi-Fi or phone hotspot. Guest networks, AP/client isolation and some hotspots prevent peers from talking. Try a trusted router or another hotspot.',
        ),
        (
          'Windows Defender Firewall',
          'Allow SwiftDrop on Private networks only. If discovery fails, allow mDNS UDP 5353 and the TCP port shown on Receive. Never disable the firewall or open a router port. Verify the selected adapter is your Wi-Fi/hotspot, not a VPN.',
        ),
        (
          'Android permissions',
          'Use the system file picker. Grant camera only when scanning QR. Local network access may require an OS prompt on newer Android releases. If denied, open Settings → Apps → SwiftDrop → Permissions. Keep transfers foregrounded; there is no background-service guarantee.',
        ),
        (
          'Network changes',
          'Receiving stops if its selected IP disappears. Enable it again on the new interface and share a new invitation. After an IP/port change, pair again before retrying a pending batch.',
        ),
        (
          'Interrupted or large transfers',
          'Retry uses the receiver’s flushed checkpoint, then validates SHA-256. Both devices and original source files must still exist. FAT32 cannot store files larger than 4 GB; use NTFS/exFAT or another suitable filesystem. SAF selections may need a durable local copy and additional disk space.',
        ),
        (
          'Privacy and trust',
          'An invitation is a one-time secret and expires in five minutes. Share it privately. Discovery is not proof of identity. Never open unexpected executable files. Files are never executed automatically.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.$1, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(section.$2),
              ],
            ),
          ),
        ),
      button('Refresh network interfaces', Icons.refresh, c.refreshInterfaces),
    ],
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final scanner = MobileScannerController();
  bool scanned = false;
  @override
  void dispose() {
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan SwiftDrop invitation')),
    body: MobileScanner(
      controller: scanner,
      errorBuilder: (context, error) => const Center(
        child: Text(
          'Camera unavailable. Grant camera permission in Settings, or paste an invitation.',
        ),
      ),
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (!scanned && raw != null && raw.startsWith('swiftdrop://')) {
          scanned = true;
          Navigator.pop(context, raw);
        }
      },
    ),
  );
}
