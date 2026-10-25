import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/app/controller.dart';
import 'package:swiftdrop/app/shell.dart';

import 'support/secrets.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('responsive navigation at $size', (tester) async {
      late Directory root;
      late AppController controller;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('swiftdrop-ui-');
        controller = AppController(secrets: MemorySecrets());
        await controller.initialize(
          supportOverride: root,
          destinationOverride: Directory('${root.path}/received'),
        );
      });
      expect(controller.ready, isTrue, reason: controller.error);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        // Shell dispose closes the controller and its timers before deletion.
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(SwiftDropApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Your files. Without the cloud.'), findsOneWidget);
      await tester.ensureVisible(find.text('Push files to GitHub'));
      await tester.tap(find.text('Push files to GitHub'));
      await tester.pumpAndSettle();
      expect(find.text('Personal access token'), findsOneWidget);
      expect(find.text('Existing branch'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose files to send'));
      await tester.tap(find.text('Choose files to send'));
      await tester.pumpAndSettle();
      expect(find.text('Send something great.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width > 860) {
        await tester.tap(find.text('Receive files').first);
        await tester.pumpAndSettle();
        expect(find.text('Make room for good things.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
