import 'package:flutter/material.dart';

import 'app.dart';

/// The few settings Kaufi has. Android does not tell apps which hand the
/// user holds the phone with, so that one has to be asked.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _Settings(),
  );
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final theme = Theme.of(context);
    final left = c.state.leftHanded;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Einstellungen', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text('Mit welcher Hand hältst du das Handy beim Einkaufen?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Links')),
                ButtonSegment(value: false, label: Text('Rechts')),
              ],
              selected: {left},
              onSelectionChanged: (v) => c.setLeftHanded(v.single),
            ),
            const SizedBox(height: 12),
            Text(
              'Für „Hab ich schon“ ziehst du eine Zutat zu deiner Hand hin, '
              'also nach ${left ? 'links' : 'rechts'}.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
