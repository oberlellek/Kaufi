import 'package:flutter/material.dart';

import 'state/controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.load();
  runApp(KaufiApp(controller: controller));
}
