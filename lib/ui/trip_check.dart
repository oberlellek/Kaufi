import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'amount_sheet.dart';
import 'app.dart';

/// "Fertig": one look at what goes into the pantry before the trip ends.
/// Kaufi guessed the amounts; whatever the user corrects here is learned, so
/// the guess fits next time and this usually takes a single tap.
Future<void> showTripCheck(BuildContext context) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _TripCheck(),
  );
  if (done != true || !context.mounted) return;
  KaufiScope.read(context).finishTrip();
}

class _TripCheck extends StatelessWidget {
  const _TripCheck();

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final theme = Theme.of(context);
    final items = c.shoppingList.checked;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Das kommt in den Vorrat', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Die Mengen hat Kaufi geschätzt. Hast du etwas anderes genommen, tipp drauf. '
                    'Kaufi merkt sich das für das nächste Mal.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text(item.def.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.buyLabel, style: theme.textTheme.titleMedium),
                          const SizedBox(width: 8),
                          Icon(Icons.edit_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                      onTap: () => showAmountSheet(context, item),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context, true);
                },
                child: const Text('Passt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
