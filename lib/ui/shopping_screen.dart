import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../core/units.dart';
import '../logic/kaufi.dart';
import 'amount_sheet.dart';
import 'app.dart';
import 'import_flow.dart';
import 'menu_sheet.dart';

String formatEuro(double v) => v.round().toString();

/// The home screen: what to buy now, in the order of the store.
///
/// Built for one hand: everything interactive is either a whole row (tap to
/// put it into the basket, swipe right for the same, swipe left for "I have it
/// already") or sits in the bottom bar within reach of the thumb.
class ShoppingScreen extends StatelessWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final list = c.shoppingList;
    final theme = Theme.of(context);

    Widget body;
    if (!c.hasPlan && list.isEmpty) {
      body = const _NoPlan();
    } else {
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(list: list)),
          if (list.open.isEmpty)
            SliverToBoxAdapter(child: _AllThere(days: c.state.shoppingDays, anyChecked: list.checked.isNotEmpty)),
          SliverList.builder(
            itemCount: list.open.length,
            itemBuilder: (context, i) => _OpenRow(item: list.open[i]),
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
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: body),
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

class _OpenRow extends StatelessWidget {
  const _OpenRow({required this.item});

  final ShoppingItem item;

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unit = item.def.unit;
    final detail = [
      if (item.atHome > 0) '${formatAmount(item.atHome, unit)} zu Hause',
      if (item.usedIn.isNotEmpty) 'für ${item.usedIn.join(', ')}',
    ].join(' · ');

    return Dismissible(
      key: ValueKey('open-${item.key}'),
      background: _SwipeBackground(
        color: scheme.primaryContainer,
        onColor: scheme.onPrimaryContainer,
        icon: Icons.shopping_basket_outlined,
        label: 'In den Korb',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeBackground(
        color: scheme.tertiaryContainer,
        onColor: scheme.onTertiaryContainer,
        icon: Icons.home_outlined,
        label: 'Hab ich schon',
        alignment: Alignment.centerRight,
      ),
      onDismissed: (direction) {
        HapticFeedback.lightImpact();
        if (direction == DismissDirection.startToEnd) {
          c.check(item.key);
        } else {
          final added = c.markAtHome(item.key);
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(
            content: Text('${item.def.name}: als vorrätig gemerkt'),
            action: SnackBarAction(label: 'Rückgängig', onPressed: () => c.undoMarkAtHome(item.key, added)),
          ));
        }
      },
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          c.check(item.key);
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
                Text(item.buyLabel, style: theme.textTheme.titleMedium),
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
                      Text('Es fehlen noch ${formatAmount(item.missing, item.def.unit)}',
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
    final tripActive = c.state.trip.isNotEmpty;
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
              const SizedBox(width: 8),
              const Expanded(child: DaysControl()),
              if (tripActive) ...[
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(72, 56)),
                  onPressed: () {
                    c.finishTrip();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Einkauf abgeschlossen. Alles ist im Vorrat.')));
                  },
                  child: const Text('Fertig'),
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
            style: IconButton.styleFrom(minimumSize: const Size(52, 56)),
            tooltip: 'Einen Tag weniger',
            onPressed: days > 1 ? () => _change(-1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(days == 1 ? 'Nur heute' : 'Für $days Tage',
                    style: theme.textTheme.titleMedium, maxLines: 1),
                Text(days == 1 ? formatDayShort(until) : 'bis ${formatDayShort(until)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1),
              ],
            ),
          ),
          IconButton(
            iconSize: 28,
            style: IconButton.styleFrom(minimumSize: const Size(52, 56)),
            tooltip: 'Einen Tag mehr',
            onPressed: days < 30 ? () => _change(1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
