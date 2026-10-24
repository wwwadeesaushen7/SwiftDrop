import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'app/shell.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile =
      args
          .where((arg) => arg.startsWith('--profile='))
          .firstOrNull
          ?.substring(10) ??
      'default';
  final controller = AppController(profile: profile);
  runApp(SwiftDropApp(controller: controller));
  await controller.initialize();
}
