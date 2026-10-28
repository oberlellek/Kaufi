import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../logic/kaufi.dart';
import '../model/app_state.dart';
import 'app.dart';

/// The upcoming meals by day. Plans change: hold a meal and drag it to another
/// day, or push everything from a day onwards. The shopping list follows.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final meals = c.kaufi.upcomingMeals;
    final today = c.today;
    final last = meals.isEmpty ? today : meals.last.day;
    final end = [last, today + (c.state.shoppingDays - 1)].reduce((a, b) => a > b ? a : b);
    final byDay = <Day, List<Meal>>{};
    for (final m in meals) {
      byDay.putIfAbsent(m.day, () => []).add(m);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Essensplan')),
      body: meals.isEmpty
          ? const Center(child: Text('Kein Plan. Importiere einen über das Menü.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'Halte ein Gericht gedrückt und zieh es auf einen anderen Tag.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                for (var d = today; d <= end; d = d + 1)
                  _DaySection(day: d, today: today, meals: byDay[d] ?? const []),
              ],
            ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.today, required this.meals});

  final Day day;
  final Day today;
  final List<Meal> meals;

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final theme = Theme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => c.kaufi.meal(d.data)?.day != day,
      onAcceptWithDetails: (d) {
        HapticFeedback.mediumImpact();
        c.moveMeal(d.data, day);
      },
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? theme.colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(formatDayRelative(day, today),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: theme.colorScheme.primary)),
                    ),
                    if (meals.isNotEmpty)
                      PopupMenuButton<int>(
                        tooltip: 'Ab hier verschieben',
                        onSelected: (delta) => c.shiftFrom(day, delta),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 1, child: Text('Ab hier alles 1 Tag später')),
                          if (day > today)
                            const PopupMenuItem(value: -1, child: Text('Ab hier alles 1 Tag früher')),
                        ],
                      ),
                  ],
                ),
              ),
              if (meals.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Text('Nichts geplant',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              for (final m in meals) _MealCard(meal: m, today: today),
            ],
          ),
        );
      },
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.today});

  final Meal meal;
  final Day today;

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final theme = Theme.of(context);
    final card = Card(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: ExpansionTile(
        shape: const Border(),
        title: Text(meal.name),
        subtitle: Text('${meal.needs.length} Zutaten'),
        leading: const Icon(Icons.drag_indicator),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'earlier':
                c.moveMeal(meal.id, meal.day - 1);
              case 'later':
                c.moveMeal(meal.id, meal.day + 1);
              case 'delete':
                c.deleteMeal(meal.id);
            }
          },
          itemBuilder: (_) => [
            if (meal.day > today) const PopupMenuItem(value: 'earlier', child: Text('Einen Tag früher')),
            const PopupMenuItem(value: 'later', child: Text('Einen Tag später')),
            const PopupMenuItem(value: 'delete', child: Text('Löschen')),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in meal.needs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${c.kaufi.def(n.key).name} · ${formatNeed(c.kaufi.def(n.key), n.amount, whole: false)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
    return LongPressDraggable<String>(
      data: meal.id,
      hapticFeedbackOnStart: true,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Text(meal.name, style: theme.textTheme.titleMedium),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}
