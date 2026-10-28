import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A row that can be pulled sideways in one direction to trigger an action.
///
/// Unlike [Dismissible] it is careful not to steal other gestures: swipes
/// that start at the screen edge belong to Android's back gesture, and drags
/// that are not clearly sideways, like a thumb scrolling in an arc, are left
/// to the list.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.child,
    required this.background,
    required this.onSwipe,
    this.toRight = true,
  });

  final Widget child;

  /// Shown behind the row while it is pulled.
  final Widget background;
  final VoidCallback onSwipe;

  /// Whether the row is pulled towards the right edge, or the left.
  final bool toRight;

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

  double get _sign => widget.toRight ? 1 : -1;

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
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _SidewaysDragRecognizer: GestureRecognizerFactoryWithHandlers<_SidewaysDragRecognizer>(
          () => _SidewaysDragRecognizer(debugOwner: this),
          (r) => r
            ..sign = _sign
            // Report the touch-down position, not where the drag was recognised.
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = (d) {
              _back.stop();
              _tracking = !_startsAtEdge(d.globalPosition);
            }
            ..onUpdate = (d) {
              if (!_tracking) return;
              final dx = _dx + d.delta.dx;
              setState(() => _dx = widget.toRight ? math.max(dx, 0) : math.min(dx, 0));
            }
            ..onEnd = (d) {
              if (!_tracking) return;
              _tracking = false;
              final v = (d.primaryVelocity ?? 0) * _sign;
              final pulled = _dx * _sign;
              final far = pulled > width * 0.35;
              final fling = v > 900 && pulled > 24;
              _settle();
              if (far || fling) widget.onSwipe();
            }
            ..onCancel = () {
              _tracking = false;
              _settle();
            },
        ),
      },
      child: Stack(
        children: [
          if (_dx != 0) Positioned.fill(child: widget.background),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: Material(color: Theme.of(context).colorScheme.surface, child: widget.child),
          ),
        ],
      ),
    );
  }
}

/// A horizontal drag that only wins against the list's scrolling when it
/// goes in the allowed direction and is at least twice as wide as it is tall.
class _SidewaysDragRecognizer extends HorizontalDragGestureRecognizer {
  _SidewaysDragRecognizer({super.debugOwner});

  /// 1 for drags to the right, -1 for drags to the left.
  double sign = 1;

  Offset _down = Offset.zero;
  Offset _last = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event.position;
    _last = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _last = event.position;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    if (!super.hasSufficientGlobalDistanceToAccept(pointerDeviceKind, deviceTouchSlop)) return false;
    final moved = _last - _down;
    return moved.dx * sign > 0 && moved.dx.abs() > 2 * moved.dy.abs();
  }
}
