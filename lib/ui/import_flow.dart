import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../logic/llm_prompt.dart';
import '../logic/plan_import.dart';
import 'app.dart';

Future<void> copyLlmPrompt(BuildContext context) async {
  final c = KaufiScope.read(context);
  await Clipboard.setData(ClipboardData(text: buildLlmPrompt(c.catalog, c.today)));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('Prompt kopiert. Füge ihn in deinen KI-Chat ein und besprich dort deinen Plan.'),
  ));
}

Future<void> importExample(BuildContext context) async {
  final text = await rootBundle.loadString('examples/beispiel-plan.json');
  if (context.mounted) await startImport(context, text);
}

/// Where a plan can come from. Sharing from another app or opening a file
/// lands in [startImport] directly.
Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Aus der Zwischenablage einfügen'),
            subtitle: const Text('Antwort der KI kopieren und hier einfügen'),
            onTap: () async {
              Navigator.pop(sheet);
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text;
              if (!context.mounted) return;
              if (text == null || text.trim().isEmpty) {
                _error(context, 'Die Zwischenablage ist leer.');
                return;
              }
              await startImport(context, text);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Datei auswählen'),
            subtitle: const Text('Eine .json-Datei im Kaufi-Format'),
            onTap: () async {
              Navigator.pop(sheet);
              final file = await FilePicker.pickFile();
              if (file == null || !context.mounted) return;
              final String text;
              try {
                text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
              } catch (e) {
                if (context.mounted) _error(context, 'Die Datei konnte nicht gelesen werden.');
                return;
              }
              if (context.mounted) await startImport(context, text);
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_copy),
            title: const Text('Prompt für deine KI kopieren'),
            subtitle: const Text('Damit die KI direkt im richtigen Format antwortet'),
            onTap: () {
              Navigator.pop(sheet);
              copyLlmPrompt(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Beispielplan laden'),
            onTap: () {
              Navigator.pop(sheet);
              importExample(context);
            },
          ),
        ],
      ),
    ),
  );
}

void _error(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Import nicht möglich'),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
    ),
  );
}

/// Parses [text], shows what would be imported and applies it on confirmation.
Future<void> startImport(BuildContext context, String text) async {
  final c = KaufiScope.read(context);
  final PlanImport imp;
  try {
    imp = c.parse(text);
  } on PlanImportException catch (e) {
    _error(context, e.message);
    return;
  }
  final result = await showModalBottomSheet<_ImportChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ImportPreview(imp: imp, today: c.today, hasPlan: c.hasPlan),
  );
  if (result == null || !context.mounted) return;
  final skipped = c.applyImport(imp, result.start, replace: result.replace);
  final added = imp.meals.length - skipped;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('$added ${added == 1 ? 'Gericht' : 'Gerichte'} importiert'
        '${skipped > 0 ? ', $skipped aus der Vergangenheit übersprungen' : ''}.'),
  ));
}

class _ImportChoice {
  const _ImportChoice(this.start, this.replace);
  final Day start;
  final bool replace;
}

class _ImportPreview extends StatefulWidget {
  const _ImportPreview({required this.imp, required this.today, required this.hasPlan});

  final PlanImport imp;
  final Day today;
  final bool hasPlan;

  @override
  State<_ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<_ImportPreview> {
  late Day _start = widget.today;
  bool _replace = true;

  @override
  Widget build(BuildContext context) {
    final imp = widget.imp;
    final theme = Theme.of(context);
    final days = [for (final m in imp.meals) m.resolve(imp.startDate ?? _start)]..sort();
    final range = days.first == days.last
        ? formatDayShort(days.first)
        : '${formatDayShort(days.first)} – ${formatDayShort(days.last)}';
    final nextMonday = widget.today + (8 - widget.today.weekday);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(imp.title ?? 'Plan importieren', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '${imp.meals.length} Gerichte · ${imp.ingredientKeys.length} Zutaten · $range'
                '${imp.source != null ? '\nQuelle: ${imp.source}' : ''}'
                '${imp.shoppingDays != null ? '\nEinkauf für ${imp.shoppingDays} Tage' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              if (imp.needsStartDate) ...[
                const SizedBox(height: 20),
                Text('Wann startet der Plan?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, day) in [
                      ('Heute', widget.today),
                      ('Morgen', widget.today + 1),
                      ('Nächsten Montag', nextMonday),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _start == day,
                        onSelected: (_) => setState(() => _start = day),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.event, size: 18),
                      label: Text(formatDayShort(_start)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _start.date,
                          firstDate: widget.today.date,
                          lastDate: (widget.today + 365).date,
                        );
                        if (picked != null) setState(() => _start = Day.fromDate(picked));
                      },
                    ),
                  ],
                ),
              ],
              if (widget.hasPlan) ...[
                const SizedBox(height: 20),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Plan ersetzen')),
                    ButtonSegment(value: false, label: Text('Ergänzen')),
                  ],
                  selected: {_replace},
                  onSelectionChanged: (s) => setState(() => _replace = s.first),
                ),
              ],
              if (imp.unknownNames.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Neu für Kaufi', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${imp.unknownNames.join(', ')}\n'
                  'Diese Zutaten stehen nicht im Katalog. Kaufi führt sie unter diesem Namen '
                  'und erkennt sie beim nächsten Import wieder.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (imp.warnings.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Hinweise', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final w in imp.warnings) Text('• $w', style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.pop(context, _ImportChoice(_start, _replace)),
                child: const Text('Importieren'),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
