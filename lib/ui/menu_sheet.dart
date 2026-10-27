import 'package:flutter/material.dart';

import 'import_flow.dart';
import 'pantry_screen.dart';
import 'plan_screen.dart';

/// Everything besides shopping, in a sheet that opens from the bottom bar so
/// it stays within thumb reach.
Future<void> showMenuSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      void go(Widget screen) {
        Navigator.pop(sheet);
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Essensplan'),
              subtitle: const Text('Gerichte auf andere Tage schieben'),
              onTap: () => go(const PlanScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.kitchen_outlined),
              title: const Text('Vorrat'),
              subtitle: const Text('Was gerade zu Hause ist'),
              onTap: () => go(const PantryScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Plan importieren'),
              onTap: () {
                Navigator.pop(sheet);
                showImportSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Prompt für deine KI kopieren'),
              onTap: () {
                Navigator.pop(sheet);
                copyLlmPrompt(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Über Kaufi'),
              onTap: () {
                Navigator.pop(sheet);
                showAboutDialog(
                  context: context,
                  applicationName: 'Kaufi',
                  applicationVersion: '0.1.0',
                  children: const [
                    Text('Kaufi speichert alles nur auf diesem Gerät. Es gibt kein Konto, '
                        'keine Werbung und keine Verbindung ins Internet.\n\n'
                        'Preise sind grobe Schätzungen für deutsche Supermärkte.'),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
