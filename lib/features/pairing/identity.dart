import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/protocol.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PlatformSecrets implements SecretStore {
  final String namespace;
  PlatformSecrets({this.namespace = 'default'});
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) =>
      storage.read(key: 'swiftdrop.$namespace.$key');
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: 'swiftdrop.$namespace.$key', value: value);
}

class Identity {
  final String certificate;
  final String privateKey;
  Identity(this.certificate, this.privateKey);
  String get fingerprint => sha256
      .convert(
        base64.decode(
          certificate
              .replaceAll('-----BEGIN CERTIFICATE-----', '')
              .replaceAll('-----END CERTIFICATE-----', '')
              .replaceAll(RegExp(r'\s'), ''),
        ),
      )
      .toString();
  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));
  static Future<Identity> load(SecretStore secrets) async {
    final saved = await secrets.read('identity');
    if (saved != null) {
      final value = jsonDecode(saved) as Map<String, dynamic>;
      return Identity(value['cert'] as String, value['key'] as String);
    }
    final generated = await Isolate.run(() {
      final keys = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final private = keys.privateKey as RSAPrivateKey;
      final public = keys.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'SwiftDrop'},
        private,
        public,
      );
      return Identity(
        X509Utils.generateSelfSignedCertificate(
          private,
          csr,
          3650,
          serialNumber: DateTime.now().microsecondsSinceEpoch.toString(),
        ),
        CryptoUtils.encodeRSAPrivateKeyToPem(private),
      );
    });
    await secrets.write(
      'identity',
      jsonEncode({'cert': generated.certificate, 'key': generated.privateKey}),
    );
    return generated;
  }
}

class PairingInvite {
  final String host;
  final int port;
  final String fingerprint;
  final String token;
  final DateTime expires;
  PairingInvite(
    this.host,
    this.port,
    this.fingerprint,
    this.token,
    this.expires,
  );
  String encode() => Uri(
    scheme: 'swiftdrop',
    host: host,
    port: port,
    queryParameters: {
      'v': '$protocolVersion',
      'fp': fingerprint,
      'token': token,
      'expires': '${expires.millisecondsSinceEpoch}',
    },
  ).toString();
  factory PairingInvite.parse(String text) {
    final uri = Uri.parse(text.trim());
    final q = uri.queryParameters;
    final address = InternetAddress.tryParse(uri.host);
    final expires = DateTime.fromMillisecondsSinceEpoch(
      int.parse(q['expires'] ?? '0'),
    );
    if (uri.scheme != 'swiftdrop' ||
        q['v'] != '$protocolVersion' ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        address == null ||
        !isPrivateAddress(address) ||
        uri.port < 1 ||
        uri.port > 65535 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(q['fp'] ?? '') ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(q['token'] ?? '') ||
        !expires.isAfter(DateTime.now()) ||
        expires.isAfter(DateTime.now().add(const Duration(minutes: 6)))) {
      throw const FormatException(
        'Invalid or expired local pairing invitation',
      );
    }
    return PairingInvite(uri.host, uri.port, q['fp']!, q['token']!, expires);
  }
}

class Peer {
  final String name, host, fingerprint, credential;
  final int port;
  Peer(this.name, this.host, this.port, this.fingerprint, this.credential);
  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'credential': credential,
  };
  factory Peer.fromJson(Map<String, dynamic> value) => Peer(
    value['name'] as String,
    value['host'] as String,
    value['port'] as int,
    value['fingerprint'] as String,
    value['credential'] as String,
  );
}

HttpClient pinnedClient(String fingerprint) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.connectionTimeout = const Duration(seconds: 10);
  client.idleTimeout = const Duration(seconds: 15);
  client.maxConnectionsPerHost = 2;
  // Local LAN traffic must not use an Internet proxy.
  client.findProxy = (_) => 'DIRECT';
  client.badCertificateCallback = (certificate, host, port) =>
      constantTimeEquals(
        sha256.convert(certificate.der).toString(),
        fingerprint,
      );
  return client;
}
