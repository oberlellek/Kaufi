import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A row that can be swiped left or right to trigger an action.
///
/// Unlike [Dismissible] it ignores swipes that start at the screen edge, where
/// Android's back gesture lives: otherwise going back would also mark an item.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.child,
    required this.rightBackground,
    required this.leftBackground,
    this.onSwipeRight,
    this.onSwipeLeft,
  });

  final Widget child;
  final Widget rightBackground;
  final Widget leftBackground;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onSwipeLeft;

  /// Swipes starting this close to the left or right edge are left to the
  /// system, in addition to whatever the system reports as gesture area.
  static const edgeGuard = 32.0;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dx = _backFrom * (1 - _back.value)));

  double _dx = 0;
  double _backFrom = 0;
  bool _tracking = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool _startsAtEdge(Offset global) {
    final width = MediaQuery.sizeOf(context).width;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final left = math.max(insets.left, SwipeRow.edgeGuard);
    final right = math.max(insets.right, SwipeRow.edgeGuard);
    return global.dx < left || global.dx > width - right;
  }

  void _settle() {
    _backFrom = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Report the touch-down position, not where the drag was recognised.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (d) {
        _back.stop();
        _tracking = !_startsAtEdge(d.globalPosition);
      },
      onHorizontalDragUpdate: (d) {
        if (!_tracking) return;
        var dx = _dx + d.delta.dx;
        if (widget.onSwipeRight == null) dx = math.min(dx, 0);
        if (widget.onSwipeLeft == null) dx = math.max(dx, 0);
        setState(() => _dx = dx);
      },
      onHorizontalDragEnd: (d) {
        if (!_tracking) return;
        _tracking = false;
        final v = d.primaryVelocity ?? 0;
        final far = _dx.abs() > width * 0.35;
        final fling = v.abs() > 900 && v.sign == _dx.sign && _dx.abs() > 24;
        final dx = _dx;
        _settle();
        if (far || fling) {
          if (dx > 0) widget.onSwipeRight?.call();
          if (dx < 0) widget.onSwipeLeft?.call();
        }
      },
      onHorizontalDragCancel: () {
        _tracking = false;
        _settle();
      },
      child: Stack(
        children: [
          if (_dx != 0)
            Positioned.fill(child: _dx > 0 ? widget.rightBackground : widget.leftBackground),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: Material(color: Theme.of(context).colorScheme.surface, child: widget.child),
          ),
        ],
      ),
    );
  }
}
