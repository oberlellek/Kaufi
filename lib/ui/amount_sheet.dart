import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/units.dart';
import '../logic/kaufi.dart';
import 'app.dart';

/// Long press on a row: "I take more" or "the package here is different".
/// Loose items get a single amount; for packaged items the package size is
/// remembered for the next trip.
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
  /// Package size, or the whole amount for loose items.
  late double _size;
  late int _count;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final pack = item.pack;
    if (!item.exact) {
      _size = pack!;
      _count = math.max(1, (item.buy / pack - 1e-6).ceil());
    } else {
      _size = item.buy > 0 ? item.buy : _sizeStep(0);
      _count = 1;
    }
  }

  double _sizeStep(double size) {
    if (widget.item.def.unit == Dim.count) return 1;
    if (size < 100) return 10;
    if (size < 1000) return 50;
    return 250;
  }

  void _changeSize(int dir) {
    setState(() {
      final step = _sizeStep(dir < 0 ? _size - 1 : _size);
      _size = math.max(step, ((_size + dir * step) / step).round() * step);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.read(context);
    final item = widget.item;
    final def = item.def;
    final theme = Theme.of(context);
    final home = item.checked ? item.atHome - item.buy : item.atHome;
    // "1 Knolle" reads better than "10 Zehen" when it is the usual package.
    final packLabel = def.packLabel;
    final total = !item.exact && packLabel != null && (_size - (def.pack ?? 0)).abs() < 1e-6
        ? '$_count ${_count == 1 ? packLabel.$1 : packLabel.$2}'
        : def.format(_size * _count);
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
            const SizedBox(height: 20),
            _Stepper(
              label: item.exact ? 'Menge' : 'Packungsgröße',
              value: def.format(_size),
              onMinus: _size > _sizeStep(_size - 1) ? () => _changeSize(-1) : null,
              onPlus: () => _changeSize(1),
            ),
            if (!item.exact) ...[
              const SizedBox(height: 12),
              _Stepper(
                label: 'Anzahl',
                value: '$_count',
                onMinus: _count > 1 ? () => setState(() => _count--) : null,
                onPlus: () => setState(() => _count++),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () {
                if (item.exact) {
                  c.buyAmount(item.key, _size);
                } else {
                  c.buyPacks(item.key, _size, _count);
                }
                Navigator.pop(context);
              },
              child: Text('$total in den Korb'),
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
