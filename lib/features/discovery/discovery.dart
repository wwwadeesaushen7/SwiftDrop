import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

import '../../core/protocol.dart';

class NearbyDevice {
  final String name, host, platform;
  final int port;
  NearbyDevice(this.name, this.host, this.port, this.platform);
}

class Discovery {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final Map<String, NearbyDevice> devices = {};
  final void Function() changed;
  final void Function(String) error;
  Discovery(this.changed, this.error);
  Future<void> start(String name, int port, String fingerprint) async {
    await stop();
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: name,
        type: '_swiftdrop._tcp',
        port: port,
        attributes: {
          'v': '$protocolVersion',
          'platform': Platform.operatingSystem,
          'id': fingerprint,
        },
      ),
      printLogs: false,
    );
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
    final discovery = BonsoirDiscovery(
      type: '_swiftdrop._tcp',
      printLogs: false,
    );
    _discovery = discovery;
    await discovery.initialize();
    _subscription = discovery.eventStream?.listen(
      (event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          unawaited(
            event.service.resolve(discovery.serviceResolver).catchError((
              Object e,
            ) {
              error(
                'Could not resolve a nearby device. Try its pairing invitation.',
              );
            }),
          );
        } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
            event is BonsoirDiscoveryServiceUpdatedEvent) {
          final service = event.service;
          if (service == null || service.attributes['id'] == fingerprint) {
            return;
          }
          final addresses = service.hostAddresses
              .map(InternetAddress.tryParse)
              .whereType<InternetAddress>()
              .where(isPrivateAddress)
              .toList();
          if (addresses.isNotEmpty) {
            devices[service.name] = NearbyDevice(
              service.name,
              addresses.first.address,
              service.port,
              service.attributes['platform'] ?? 'device',
            );
            changed();
          }
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          devices.remove(event.service.name);
          changed();
        }
      },
      onError: (Object e) =>
          error('Discovery unavailable. Use QR or manual pairing.'),
    );
    await discovery.start();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final discovery = _discovery;
    _discovery = null;
    final broadcast = _broadcast;
    _broadcast = null;
    if (discovery?.isReady ?? false) await discovery!.stop();
    if (broadcast?.isReady ?? false) await broadcast!.stop();
    devices.clear();
    changed();
  }
}
