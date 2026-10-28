import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../model/app_state.dart';
import 'app.dart';

/// The meal filter. Tapping opens a list of the meals in the shopping window;
/// with a filter active, tapping turns it off.
class MealFilterButton extends StatelessWidget {
  const MealFilterButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final meal = c.filteredMeal;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: meal == null ? 'Nach Gericht filtern' : 'Filter ${meal.displayName} aufheben',
      child: Material(
        elevation: 3,
        color: meal == null ? scheme.primaryContainer : scheme.secondaryContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (meal != null) {
              HapticFeedback.selectionClick();
              c.setMealFilter(null);
            } else {
              _showPicker(context);
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: meal == null ? 20 : 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restaurant_menu,
                      color: meal == null ? scheme.onPrimaryContainer : scheme.onSecondaryContainer),
                  if (meal != null) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(meal.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close, size: 20, color: scheme.onSecondaryContainer),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showPicker(BuildContext context) {
  final c = KaufiScope.read(context);
  final list = c.shoppingList;
  String missing(Meal m) {
    final keys = {for (final n in m.needs) n.key};
    final n = list.open.where((i) => keys.contains(i.key)).length;
    return n == 0 ? 'alles da' : '$n fehlen';
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Alle Zutaten'),
              subtitle: const Text('Sortiert nach deinem Weg durch den Laden'),
              onTap: () {
                c.setMealFilter(null);
                Navigator.pop(sheet);
              },
            ),
            for (final m in c.kaufi.mealsInWindow(c.today))
              ListTile(
                leading: const Icon(Icons.restaurant),
                title: Text(m.name),
                subtitle: Text('${formatDayShort(m.day)} · ${missing(m)}'),
                onTap: () {
                  c.setMealFilter(m.id);
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
