import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/units.dart';
import '../logic/kaufi.dart';
import 'app.dart';

/// Long press on a row: "the package here is different" or "I take two".
/// The package size is remembered for the next trip.
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
  late double _size;
  late int _count;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final pack = item.pack;
    if (pack != null && pack > 0) {
      _size = pack;
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
    final theme = Theme.of(context);
    final unit = item.def.unit;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.def.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Bedarf ${formatAmount(item.need, unit)} · zu Hause ${formatAmount(item.checked ? item.atHome - item.buy : item.atHome, unit)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _Stepper(
              label: 'Packungsgröße',
              value: formatAmount(_size, unit),
              onMinus: _size > _sizeStep(_size - 1) ? () => _changeSize(-1) : null,
              onPlus: () => _changeSize(1),
            ),
            const SizedBox(height: 12),
            _Stepper(
              label: 'Anzahl',
              value: '$_count',
              onMinus: _count > 1 ? () => setState(() => _count--) : null,
              onPlus: () => setState(() => _count++),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () {
                c.buyPacks(item.key, _size, _count);
                Navigator.pop(context);
              },
              child: Text('${formatAmount(_size * _count, unit)} in den Korb'),
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
