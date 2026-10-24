import 'package:swiftdrop/features/pairing/identity.dart';

/// Test-only vault. Production always uses the OS secure-storage implementation.
class MemorySecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
