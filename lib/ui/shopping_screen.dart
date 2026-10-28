import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../logic/kaufi.dart';
import '../model/app_state.dart';
import 'amount_sheet.dart';
import 'app.dart';
import 'basket_flight.dart';
import 'import_flow.dart';
import 'meal_filter.dart';
import 'menu_sheet.dart';
import 'swipe_row.dart';
import 'trip_check.dart';

String formatEuro(double v) => v.round().toString();

/// The home screen: what to buy now, in the order of the store.
///
/// Built for one hand: everything interactive is either a whole row (tap to
/// put it into the basket, pull it towards the hand for "I have it already")
/// or sits in the bottom bar within reach of the thumb, including undo.
class ShoppingScreen extends StatelessWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final full = c.shoppingList;
    final meal = c.filteredMeal;
    final list = meal == null ? full : full.forMeal(meal);
    final theme = Theme.of(context);

    Widget body;
    if (!c.hasPlan && list.isEmpty) {
      body = const _NoPlan();
    } else {
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(list: full)),
          if (meal != null) SliverToBoxAdapter(child: _MealBanner(list: list)),
          if (list.open.isEmpty)
            SliverToBoxAdapter(
              child: meal == null
                  ? _AllThere(days: c.state.shoppingDays, anyChecked: list.checked.isNotEmpty)
                  : const _MealComplete(),
            ),
          SliverList.builder(
            itemCount: list.open.length,
            itemBuilder: (context, i) =>
                _OpenRow(key: ValueKey('open-${list.open[i].key}'), item: list.open[i], meal: meal),
          ),
          if (list.checked.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                child: Text('Im Korb · ${list.checked.length}',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
            ),
          SliverList.builder(
            itemCount: list.checked.length,
            itemBuilder: (context, i) => _CheckedRow(item: list.checked[list.checked.length - 1 - i]),
          ),
          if (list.covered.isNotEmpty) SliverToBoxAdapter(child: _Covered(items: list.covered)),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: c.kaufi.mealsInWindow(c.today).isEmpty ? null : const MealFilterButton(),
      bottomNavigationBar: const _BottomBar(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.list});

  final ShoppingList list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = list.open.length + list.checked.length;
    final range = list.from == list.to
        ? formatDayShort(list.from)
        : '${formatDayShort(list.from)} – ${formatDayShort(list.to)}';
    final price = list.priceMax > 0
        ? 'ca. ${formatEuro(list.priceMin)}–${formatEuro(list.priceMax)} €'
            '${list.unpriced > 0 ? ' (+${list.unpriced} ohne Preis)' : ''}'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Einkauf', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            [range, if (total > 0) '${list.checked.length} von $total', ?price].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MealBanner extends StatelessWidget {
  const _MealBanner({required this.list});

  final ShoppingList list;

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meal = list.meal!;
    final home = list.alreadyHome;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            children: [
              Icon(Icons.restaurant, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meal.name,
                        style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSecondaryContainer)),
                    Text(
                      [
                        formatDayRelative(meal.day, c.today),
                        if (home > 0) '$home ${home == 1 ? 'Zutat ist' : 'Zutaten sind'} schon da',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Filter aus',
                onPressed: () => c.setMealFilter(null),
                icon: Icon(Icons.close, color: scheme.onSecondaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealComplete extends StatelessWidget {
  const _MealComplete();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Icon(Icons.task_alt, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Für dieses Gericht ist alles da.', style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class _OpenRow extends StatelessWidget {
  const _OpenRow({super.key, required this.item, this.meal});

  final ShoppingItem item;

  /// The meal the list is filtered to, if any.
  final Meal? meal;

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final def = item.def;
    final forMeal = meal?.needs.where((n) => n.key == item.key).firstOrNull;
    final others = [for (final u in item.usedIn) if (u != meal?.displayName) u];
    final detail = [
      if (item.atHome > 0) '${def.format(item.atHome)} zu Hause',
      if (forMeal != null) 'hier ${formatNeed(def, forMeal.amount, whole: false)}',
      if (forMeal != null && others.isNotEmpty) 'auch für ${others.join(', ')}',
      if (forMeal == null && item.usedIn.isNotEmpty) 'für ${item.usedIn.join(', ')}',
    ].join(' · ');

    // Pulled towards the hand that holds the phone.
    final toRight = !c.state.leftHanded;
    return SwipeRow(
      toRight: toRight,
      background: _SwipeBackground(
        color: scheme.tertiaryContainer,
        onColor: scheme.onTertiaryContainer,
        icon: Icons.home_outlined,
        label: 'Hab ich schon',
        alignment: toRight ? Alignment.centerLeft : Alignment.centerRight,
      ),
      onSwipe: () {
        HapticFeedback.lightImpact();
        c.markAtHome(item.key);
      },
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          final box = context.findRenderObject() as RenderBox;
          final from = box.localToGlobal(Offset(box.size.width * 0.35, box.size.height / 2));
          final overlay = Overlay.of(context);
          c.check(item.key);
          flyToBasket(overlay, item.def.name, from);
        },
        onLongPress: () => showAmountSheet(context, item),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.radio_button_unchecked, size: 30, color: scheme.outline),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.def.name, style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
                      if (detail.isNotEmpty)
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(item.needLabel, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckedRow extends StatelessWidget {
  const _CheckedRow({required this.item});

  final ShoppingItem item;

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final stillMissing = item.missing > 0;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        c.uncheck(item.key);
      },
      onLongPress: () => showAmountSheet(context, item),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 30, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.def.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: muted,
                          decoration: TextDecoration.lineThrough,
                        )),
                    if (stillMissing)
                      Text('Es fehlen noch ${item.needLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                  ],
                ),
              ),
              Text(item.buyLabel, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What Kaufi believes is at home, so the user can catch it when it is not.
class _Covered extends StatefulWidget {
  const _Covered({required this.items});

  final List<ShoppingItem> items;

  @override
  State<_Covered> createState() => _CoveredState();
}

class _CoveredState extends State<_Covered> {
  var _open = false;

  void _notThere(ShoppingItem item) {
    HapticFeedback.lightImpact();
    KaufiScope.read(context).notAtHome(item.key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Hast du laut Kaufi noch · ${widget.items.length}',
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: scheme.primary),
              ],
            ),
          ),
        ),
        if (_open) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Ist etwas nicht mehr da, tipp drauf. Dann kommt es wieder auf die Liste.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
          for (final item in widget.items)
            InkWell(
              onTap: () => _notThere(item),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.home_outlined, size: 26, color: muted),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.def.name, style: theme.textTheme.titleMedium),
                            if (item.usedIn.isNotEmpty)
                              Text('für ${item.usedIn.join(', ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(item.def.format(item.atHome), style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final Color onColor;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: onColor),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
    ];
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft ? children : children.reversed.toList(),
      ),
    );
  }
}

class _AllThere extends StatelessWidget {
  const _AllThere({required this.days, required this.anyChecked});

  final int days;
  final bool anyChecked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
      child: Column(
        children: [
          Icon(Icons.task_alt, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(anyChecked ? 'Alles im Korb.' : 'Alles da.', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Für ${days == 1 ? 'heute' : 'die nächsten $days Tage'} fehlt nichts. '
            'Unten kannst du weiter vorausplanen.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Hallo bei Kaufi', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Kaufi macht aus deinem Essensplan die Einkaufsliste, merkt sich, was noch '
            'zu Hause ist, und lernt deinen Weg durch den Laden.\n\n'
            'Lass dir den Plan von einer KI erstellen: Kopiere dazu den Prompt, besprich '
            'mit der KI, was du essen willst, und importiere dann ihre Antwort.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => showImportSheet(context),
            icon: const Icon(Icons.download),
            label: const Text('Plan importieren'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => copyLlmPrompt(context),
            icon: const Icon(Icons.content_copy),
            label: const Text('Prompt für deine KI kopieren'),
          ),
          const SizedBox(height: 12),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => importExample(context),
            child: const Text('Mit Beispielplan ausprobieren'),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final theme = Theme.of(context);
    final inBasket = c.state.trip.length;
    final undo = c.undoLabel;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                iconSize: 28,
                style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                tooltip: 'Menü',
                onPressed: () => showMenuSheet(context),
                icon: const Icon(Icons.menu),
              ),
              const SizedBox(width: 4),
              const Expanded(child: DaysControl()),
              IconButton(
                iconSize: 26,
                style: IconButton.styleFrom(minimumSize: const Size(48, 56)),
                tooltip: undo == null ? 'Nichts zum Rückgängigmachen' : 'Rückgängig: $undo',
                onPressed: undo == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        c.undo();
                      },
                icon: const Icon(Icons.undo),
              ),
              if (inBasket > 0) ...[
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => showTripCheck(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BasketIcon(count: inBasket),
                      const SizedBox(width: 10),
                      const Text('Fertig'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How many days ahead to buy for. Tap − / + or swipe sideways on it.
class DaysControl extends StatefulWidget {
  const DaysControl({super.key});

  @override
  State<DaysControl> createState() => _DaysControlState();
}

class _DaysControlState extends State<DaysControl> {
  static const _step = 28.0;
  double _drag = 0;

  void _change(int delta) {
    final c = KaufiScope.read(context);
    final before = c.state.shoppingDays;
    c.setShoppingDays(before + delta);
    if (c.state.shoppingDays != before) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final theme = Theme.of(context);
    final days = c.state.shoppingDays;
    final until = c.today + (days - 1);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (d) {
        _drag += d.delta.dx;
        while (_drag.abs() >= _step) {
          _change(_drag > 0 ? 1 : -1);
          _drag -= _drag.sign * _step;
        }
      },
      child: Row(
        children: [
          IconButton(
            iconSize: 28,
            style: IconButton.styleFrom(minimumSize: const Size(44, 56)),
            tooltip: 'Einen Tag weniger',
            onPressed: days > 1 ? () => _change(-1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            // Narrow phones with a full basket: shorten, then shrink.
            child: LayoutBuilder(
              builder: (context, box) {
                final title = days == 1 ? 'Nur heute' : (box.maxWidth < 90 ? '$days Tage' : 'Für $days Tage');
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(title, style: theme.textTheme.titleMedium, maxLines: 1),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(days == 1 ? formatDayShort(until) : 'bis ${formatDayShort(until)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            iconSize: 28,
            style: IconButton.styleFrom(minimumSize: const Size(44, 56)),
            tooltip: 'Einen Tag mehr',
            onPressed: days < 30 ? () => _change(1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
