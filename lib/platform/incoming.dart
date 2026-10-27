import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plans handed to Kaufi by other apps: "Teilen → Kaufi" or opening a .json
/// file. The Android side lives in MainActivity.kt.
class IncomingImports {
  static const _channel = MethodChannel('kaufi/import');

  static void listen(void Function(String text) onText) {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'importText' && call.arguments is String) {
        onText(call.arguments as String);
      }
    });
  }

  /// The plan the app was launched with, if any. Returns it only once.
  static Future<String?> takePending() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('takePendingImport');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
