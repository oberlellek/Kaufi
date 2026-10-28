import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kaufi/ui/dial_tracker.dart';

void main() {
  const center = Offset(200, 400);
  Offset onCircle(double degrees, [double r = 80]) {
    final a = degrees * math.pi / 180;
    return center + Offset(math.cos(a), math.sin(a)) * r;
  }

  DialTracker tracker({int count = 5, int index = 0}) =>
      DialTracker(center: center, count: count, index: index, step: math.pi / 4);

  test('nothing happens before the finger reaches the dial', () {
    final t = tracker();
    expect(t.update(const Offset(350, 700)), isFalse);
    expect(t.update(const Offset(300, 600)), isFalse);
    expect(t.entered, isFalse);
    expect(t.index, 0);
  });

  test('clockwise moves forward, counter-clockwise back, wrapping around', () {
    final t = tracker();
    t.update(onCircle(0));
    expect(t.entered, isTrue);
    for (var d = 10; d <= 100; d += 10) {
      t.update(onCircle(d.toDouble()));
    }
    expect(t.index, 2); // 100 degrees = two 45 degree steps
    for (var d = 90; d >= -100; d -= 10) {
      t.update(onCircle(d.toDouble()));
    }
    // 200 degrees back from 100 degrees: index 2 - 4 = -2, wraps to 3.
    expect(t.index, 3);
  });

  test('turning through the 180 degree seam counts correctly', () {
    final t = tracker(count: 10);
    t.update(onCircle(150));
    for (var d = 160; d <= 250; d += 10) {
      t.update(onCircle(d.toDouble()));
    }
    expect(t.index, 2);
  });

  test('the centre is a dead zone', () {
    final t = tracker();
    t.update(onCircle(0));
    t.update(center + const Offset(3, 2));
    t.update(onCircle(170));
    expect(t.index, 0, reason: 'jumping across the centre is not a rotation');
  });
}
