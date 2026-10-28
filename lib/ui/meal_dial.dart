import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/day.dart';
import '../model/app_state.dart';
import '../state/controller.dart';
import 'app.dart';
import 'dial_tracker.dart';

class _Entry {
  const _Entry(this.meal, this.title, this.subtitle);

  /// Null for "all ingredients", i.e. no filter.
  final Meal? meal;
  final String title;
  final String subtitle;
}

List<_Entry> _entries(AppController c) {
  final list = c.shoppingList;
  String missing(Meal m) {
    final keys = {for (final n in m.needs) n.key};
    final n = list.open.where((i) => keys.contains(i.key)).length;
    return n == 0 ? 'alles da' : '$n fehlen';
  }

  return [
    const _Entry(null, 'Alle Zutaten', 'Sortiert nach deinem Weg durch den Laden'),
    for (final m in c.kaufi.mealsInWindow(c.today))
      _Entry(m, m.name, '${formatDayShort(m.day)} · ${missing(m)}'),
  ];
}

/// The meal filter. Hold it, drag it to the middle of the screen and turn the
/// dial that appears; letting go picks the meal shown. Tapping turns an
/// active filter off, or opens a plain list to pick from.
class MealDialButton extends StatefulWidget {
  const MealDialButton({super.key});

  @override
  State<MealDialButton> createState() => _MealDialButtonState();
}

class _MealDialButtonState extends State<MealDialButton> {
  OverlayEntry? _overlay;
  DialTracker? _tracker;
  List<_Entry> _items = const [];

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _close() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    _tracker = null;
  }

  void _start(DragStartDetails d) {
    final c = KaufiScope.read(context);
    _items = _entries(c);
    final current = _items.indexWhere((e) => e.meal?.id == c.filteredMeal?.id);
    final size = MediaQuery.sizeOf(context);
    final count = _items.length;
    _tracker = DialTracker(
      // A little above the middle, where a thumb reaches comfortably.
      center: Offset(size.width / 2, size.height * 0.45),
      count: count,
      index: math.max(0, current),
      step: (2 * math.pi / count).clamp(math.pi / 7, math.pi / 3),
    );
    _overlay = OverlayEntry(builder: (_) => _DialOverlay(tracker: _tracker!, items: _items));
    Overlay.of(context).insert(_overlay!);
    HapticFeedback.mediumImpact();
  }

  void _update(DragUpdateDetails d) {
    final t = _tracker;
    if (t == null) return;
    final wasEntered = t.entered;
    if (t.update(d.globalPosition)) HapticFeedback.selectionClick();
    if (!wasEntered && t.entered) HapticFeedback.lightImpact();
    _overlay?.markNeedsBuild();
  }

  void _end() {
    final t = _tracker;
    if (t != null && t.entered) {
      KaufiScope.read(context).setMealFilter(_items[t.index].meal?.id);
      HapticFeedback.mediumImpact();
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final c = KaufiScope.of(context);
    final meal = c.filteredMeal;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        if (meal != null) {
          HapticFeedback.selectionClick();
          c.setMealFilter(null);
        } else {
          _showPicker(context);
        }
      },
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: (_) => _end(),
      onPanCancel: _close,
      child: Semantics(
        button: true,
        label: meal == null ? 'Nach Gericht filtern' : 'Filter ${meal.displayName} aufheben',
        child: Material(
          elevation: 3,
          color: meal == null ? scheme.primaryContainer : scheme.secondaryContainer,
          shape: const StadiumBorder(),
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
  final items = _entries(c);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Tipp: Knopf gedrückt halten, in die Mitte ziehen und drehen. Loslassen wählt aus.',
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
            ),
            for (final e in items)
              ListTile(
                leading: Icon(e.meal == null ? Icons.list : Icons.restaurant),
                title: Text(e.title),
                subtitle: Text(e.subtitle),
                onTap: () {
                  c.setMealFilter(e.meal?.id);
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _DialOverlay extends StatelessWidget {
  const _DialOverlay({required this.tracker, required this.items});

  final DialTracker tracker;
  final List<_Entry> items;

  static const radius = 150.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = items[tracker.index];
    final center = tracker.center;
    final n = items.length;
    final prev = items[(tracker.index - 1 + n) % n];
    final next = items[(tracker.index + 1) % n];
    final hint = tracker.entered
        ? 'Drehen zum Wechseln · Loslassen wählt aus'
        : 'In die Mitte ziehen';
    final hintStyle = theme.textTheme.titleMedium?.copyWith(color: Colors.white);
    final sideStyle = theme.textTheme.bodyMedium?.copyWith(color: Colors.white70);

    return IgnorePointer(
      child: Material(
        color: Colors.black.withValues(alpha: 0.8),
        child: Stack(
          children: [
            Positioned(
              left: 24,
              right: 24,
              top: center.dy - radius - 96,
              child: Column(
                children: [
                  Text(hint, textAlign: TextAlign.center, style: hintStyle),
                  const SizedBox(height: 12),
                  if (n > 1) _Neighbour(icon: Icons.rotate_left, title: prev.title, style: sideStyle),
                ],
              ),
            ),
            Positioned(
              left: center.dx - radius,
              top: center.dy - radius,
              width: radius * 2,
              height: radius * 2,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 120),
                scale: tracker.entered ? 1 : 0.92,
                child: CustomPaint(
                  painter: _RingPainter(
                    count: n,
                    index: tracker.index,
                    fill: scheme.surface,
                    ring: scheme.outlineVariant,
                    dot: scheme.outline,
                    active: scheme.primary,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(entry.meal == null ? Icons.list : Icons.restaurant, color: scheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          entry.title,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (n > 2)
              Positioned(
                left: 24,
                right: 24,
                top: center.dy + radius + 16,
                child: _Neighbour(icon: Icons.rotate_right, title: next.title, style: sideStyle),
              ),
          ],
        ),
      ),
    );
  }
}

/// The previous or next entry, so it is clear which way to turn.
class _Neighbour extends StatelessWidget {
  const _Neighbour({required this.icon, required this.title, required this.style});

  final IconData icon;
  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: style?.color),
        const SizedBox(width: 6),
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.count,
    required this.index,
    required this.fill,
    required this.ring,
    required this.dot,
    required this.active,
  });

  final int count;
  final int index;
  final Color fill;
  final Color ring;
  final Color dot;
  final Color active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = fill);
    canvas.drawCircle(
        c,
        r - 14,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / count;
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 14);
      final selected = i == index;
      canvas.drawCircle(p, selected ? 9 : 4, Paint()..color = selected ? active : dot);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.index != index || old.count != count || old.fill != fill;
}
