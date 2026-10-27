import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import '../core/units.dart';
import 'app.dart';

/// What Kaufi believes is at home. Usually right on its own; tap an entry to
/// correct it.
class PantryScreen extends StatelessWidget {
  const PantryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final items = c.kaufi.pantryItems;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vorrat')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Eingekauftes kommt automatisch hierher. Ist ein Tag vorbei, zieht Kaufi ab, '
              'was laut Plan gegessen wurde. Tippe auf eine Zutat, um die Menge zu korrigieren.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Noch nichts im Vorrat.'),
            ),
          for (final (def, amount) in items)
            ListTile(
              title: Text(def.name),
              subtitle: Text(def.category.label),
              trailing: Text(formatAmount(amount, def.unit), style: theme.textTheme.titleMedium),
              onTap: () => _edit(context, def, amount),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, IngredientDef def, double amount) async {
    final c = KaufiScope.read(context);
    final ctrl = TextEditingController(
        text: amount == amount.roundToDouble() ? amount.round().toString() : amount.toStringAsFixed(1));
    final result = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(def.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: switch (def.unit) {
              Dim.mass => 'g',
              Dim.volume => 'ml',
              Dim.count => 'Stück',
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, 0.0), child: const Text('Aufgebraucht')),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(d, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) c.setPantry(def.id, result);
  }
}
