// Explicit stress check, kept outside the default quick test suite.
// Requires at least 6 GiB of free space. The input is sparse; output is real.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/core/protocol.dart';
import 'package:swiftdrop/features/pairing/identity.dart';
import 'package:swiftdrop/features/storage/store.dart';
import 'package:swiftdrop/features/transfer/receiver.dart';
import 'package:swiftdrop/features/transfer/sender.dart';

import '../test/support/secrets.dart';

void main() {
  test('real TLS transfer crosses 4 GiB without truncation', () async {
    final root = await Directory.systemTemp.createTemp('swiftdrop-large-');
    final secrets = MemorySecrets();
    final identity = await Identity.load(secrets);
    final receiving = Store('${root.path}/receiver.sqlite');
    final sending = Store('${root.path}/sender.sqlite');
    final receiver = Receiver(
      identity: identity,
      secrets: secrets,
      store: receiving,
      name: 'Receiver',
      destination: Directory('${root.path}/in'),
      consent: (_, _) async => true,
      onUpdate: (_, _, _, _) {},
    );
    try {
      final source = File('${root.path}/source.bin');
      final handle = await source.open(mode: FileMode.write);
      const size = 4 * 1024 * 1024 * 1024 + 17;
      await handle.truncate(size);
      await handle.setPosition(size - 1);
      await handle.writeByte(193);
      await handle.close();
      await receiver.start(InternetAddress.loopbackIPv4);
      final peer = await Sender.pair(receiver.invite(), 'Sender');
      TransferProgress? finalProgress;
      await Sender(sending, (value) {
        finalProgress = value;
      }).send(peer, 'Sender', [SourceFile(source.path, 'large.bin')]);
      expect(finalProgress!.state, 'Complete');
      expect(finalProgress!.bytes, size);
      final record = receiving.all('transfers').single;
      final saved = File('${record['root']}/files/large.bin');
      expect(await saved.length(), size);
      final expected = (record['manifest'] as Map)['files'][0]['sha256'];
      expect(await hashFile(saved), expected);
    } finally {
      await receiver.stop();
      receiving.close();
      sending.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
