import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/units.dart';
import '../logic/kaufi.dart';
import 'app.dart';

/// Long press on a row, or a tap in the check at the end of a trip: "I took
/// something else". Kaufi learns from the answer how the item is bought, so
/// the next guess fits.
Future<void> showAmountSheet(BuildContext context, ShoppingItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AmountSheet(item: item),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.item});

  final ShoppingItem item;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late double _amount;

  @override
  void initState() {
    super.initState();
    _amount = widget.item.buy > 0 ? widget.item.buy : _step(0);
  }

  double _step(double amount) {
    if (widget.item.def.unit == Dim.count) return 1;
    if (amount < 100) return 10;
    if (amount < 1000) return 50;
    return 250;
  }

  void _change(int dir) {
    setState(() {
      final step = _step(dir < 0 ? _amount - 1 : _amount);
      _amount = math.max(step, ((_amount + dir * step) / step).round() * step);
    });
  }

  /// Quick picks: exactly what was missing, and one or two packages.
  List<(String, double)> _options(double missing) {
    final item = widget.item;
    final def = item.def;
    final out = <(String, double)>[];
    void add(String label, double amount) {
      if (amount > 0 && !out.any((o) => (o.$2 - amount).abs() < 0.01)) out.add((label, amount));
    }

    if (missing > 0) add('Was fehlt · ${def.format(roundUpToWhole(missing))}', roundUpToWhole(missing));
    final pack = item.pack ?? def.pack;
    if (pack != null && pack > 0) {
      final first = math.max(1, (missing / pack - 1e-6).ceil());
      for (final n in item.exact ? [first] : [first, first + 1]) {
        final label = def.packLabel != null && (pack - (def.pack ?? -1)).abs() < 1e-6
            ? formatBought(def, pack, n * pack)
            : '$n ${n == 1 ? 'Packung' : 'Packungen'} · ${def.format(n * pack)}';
        add(label, n * pack);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final item = widget.item;
    final def = item.def;
    final theme = Theme.of(context);
    final home = item.checked ? item.atHome - item.buy : item.atHome;
    final missing = math.max(0.0, item.need - home);
    final options = _options(missing);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(def.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              [
                'Bedarf ${formatNeed(def, item.need, whole: false)}',
                if (home > 0) 'zu Hause ${def.format(home)}',
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Wie viel nimmst du?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, amount) in options)
                  ChoiceChip(
                    label: Text(label),
                    selected: (amount - _amount).abs() < 0.01,
                    onSelected: (_) => setState(() => _amount = amount),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Stepper(
              label: 'Andere Menge',
              value: def.format(_amount),
              onMinus: _amount > _step(_amount - 1) ? () => _change(-1) : null,
              onPlus: () => _change(1),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () {
                c.setBought(item.key, _amount);
                Navigator.pop(context);
              },
              child: Text(item.checked
                  ? 'Ich habe ${formatBought(def, item.pack ?? def.pack, _amount)}'
                  : '${formatBought(def, item.pack ?? def.pack, _amount)} in den Korb'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, this.onMinus, this.onPlus});

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        IconButton.filledTonal(
          style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
          onPressed: onMinus,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 104,
          child: Text(value, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        ),
        IconButton.filledTonal(
          style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
          onPressed: onPlus,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
