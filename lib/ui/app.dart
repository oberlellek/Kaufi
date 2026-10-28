import 'package:flutter/material.dart';

import '../platform/incoming.dart';
import '../state/controller.dart';
import 'import_flow.dart';
import 'shopping_screen.dart';

/// Makes the [AppController] available to every widget below it and rebuilds
/// them when it changes.
class KaufiScope extends InheritedNotifier<AppController> {
  const KaufiScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KaufiScope>()!.notifier!;

  /// Access without subscribing to changes, for callbacks.
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<KaufiScope>()!.notifier!;
}

class KaufiApp extends StatefulWidget {
  const KaufiApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<KaufiApp> createState() => _KaufiAppState();
}

class _KaufiAppState extends State<KaufiApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Opening the app usually means "I'm in the store now": make sure the
    // list reflects today, even if the app was left open overnight.
    _lifecycle = AppLifecycleListener(onResume: widget.controller.refresh);
    IncomingImports.listen(_handleIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final text = await IncomingImports.takePending();
      if (text != null) _handleIncoming(text);
    });
  }

  void _handleIncoming(String text) {
    final context = _navigator.currentContext;
    if (context != null) startImport(context, text);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    ThemeData theme(Brightness b) {
      final base = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
        useMaterial3: true,
      );
      return base.copyWith(
        listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      );
    }

    return KaufiScope(
      controller: widget.controller,
      child: MaterialApp(
        title: 'Kaufi',
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        home: const ShoppingScreen(),
      ),
    );
  }
}
