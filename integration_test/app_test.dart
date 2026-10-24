import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swiftdrop/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real app initializes and navigates to send and receive', (
    tester,
  ) async {
    await app.main();
    // RSA key generation, secure storage and native initialization are real.
    for (
      var i = 0;
      i < 120 && find.text('Your files. Without the cloud.').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Your files. Without the cloud.'), findsOneWidget);
    await tester.tap(find.text('Choose files to send'));
    await tester.pumpAndSettle();
    expect(find.text('Send something great.'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
  });
}
