import 'dart:math' as math;
import 'dart:ui';

/// Turns a finger path into steps on a rotary dial.
///
/// The finger first has to arrive near [center] ([enterRadius]); from then on,
/// every [step] radians of rotation around the center move [index] by one,
/// clockwise forward, wrapping around. Rotation is relative, so it does not
/// matter where on the circle the finger is, only how far it turns. Close to
/// the center ([deadZone]) the angle is too jumpy and is ignored.
class DialTracker {
  DialTracker({
    required this.center,
    required this.count,
    required this.index,
    this.enterRadius = 120,
    this.deadZone = 28,
    this.step = math.pi / 5,
  }) : assert(count > 0);

  final Offset center;
  final int count;
  final double enterRadius;
  final double deadZone;
  final double step;

  int index;
  bool entered = false;
  double? _lastAngle;
  double _accumulated = 0;

  /// Feeds the next finger position. Returns whether [index] changed.
  bool update(Offset position) {
    final v = position - center;
    final distance = v.distance;
    if (!entered) {
      if (distance > enterRadius) return false;
      entered = true;
      _lastAngle = distance > deadZone ? v.direction : null;
      return false;
    }
    if (distance < deadZone) {
      _lastAngle = null;
      return false;
    }
    final angle = v.direction;
    final last = _lastAngle;
    _lastAngle = angle;
    if (last == null) return false;

    var delta = angle - last;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _accumulated += delta;

    final before = index;
    while (_accumulated >= step) {
      index = (index + 1) % count;
      _accumulated -= step;
    }
    while (_accumulated <= -step) {
      index = (index - 1 + count) % count;
      _accumulated += step;
    }
    return index != before;
  }
}
