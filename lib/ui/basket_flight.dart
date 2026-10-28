import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The basket in the bottom bar. Flights land there.
final basketKey = GlobalKey(debugLabel: 'basket');

/// Counts landings, so the basket can give a little hop.
final basketLandings = ValueNotifier<int>(0);

/// Lets [label] fly from [from] (global coordinates) into the basket: a small
/// confirmation that stays out of the way of the list.
void flyToBasket(OverlayState overlay, String label, Offset from) {
  // The basket may only appear with the next frame, when the first item of a
  // trip goes in.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = basketKey.currentContext?.findRenderObject() as RenderBox?;
    if (target == null || !target.attached || !overlay.mounted) return;
    final to = target.localToGlobal(target.size.center(Offset.zero));
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Flight(
        key: ValueKey('flight-$label'),
        label: label,
        from: from,
        to: to,
        onDone: () {
          entry.remove();
          entry.dispose();
          basketLandings.value++;
        },
      ),
    );
    overlay.insert(entry);
  });
}

class _Flight extends StatefulWidget {
  const _Flight({super.key, required this.label, required this.from, required this.to, required this.onDone});

  final String label;
  final Offset from;
  final Offset to;
  final VoidCallback onDone;

  @override
  State<_Flight> createState() => _FlightState();
}

class _FlightState extends State<_Flight> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) {
          final t = _t.value;
          // Sideways first, then down: a short arc into the basket.
          final x = widget.from.dx + (widget.to.dx - widget.from.dx) * Curves.easeOut.transform(t);
          final y = widget.from.dy + (widget.to.dy - widget.from.dy) * Curves.easeInCubic.transform(t);
          final scale = 1 - 0.6 * Curves.easeIn.transform(t);
          final opacity = t < 0.8 ? 1.0 : math.max(0.0, (1 - t) / 0.2);
          return Stack(
            children: [
              Positioned(
                left: x,
                top: y,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: child),
                  ),
                ),
              ),
            ],
          );
        },
        child: Material(
          color: scheme.primaryContainer,
          elevation: 4,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The basket icon with the number of items in it. Hops when something lands.
class BasketIcon extends StatelessWidget {
  const BasketIcon({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: basketLandings,
      builder: (context, landings, child) => TweenAnimationBuilder<double>(
        key: ValueKey(landings),
        tween: Tween(begin: landings == 0 ? 1 : 1.35, end: 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: child,
      ),
      child: Badge(
        key: basketKey,
        label: Text('$count'),
        child: const Icon(Icons.shopping_basket_outlined),
      ),
    );
  }
}
