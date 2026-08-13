import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/canvas/large_radius_arc.dart';

void main() {
  const size = Size(800, 600);

  group('visibleAngularWindow', () {
    test('is null for a circle far off screen', () {
      final window = visibleAngularWindow(
        center: const Offset(100000, 0),
        radius: 3000,
        size: size,
        margin: 2,
      );
      expect(window, isNull);
    });

    test('is null when the viewport sits deep inside the disc', () {
      final window = visibleAngularWindow(
        center: const Offset(400, -100000),
        radius: 150000,
        size: size,
        margin: 2,
      );
      expect(window, isNull);
    });

    test('is the full circle when center and rim are both near the canvas', () {
      final window = visibleAngularWindow(
        center: const Offset(200, 300),
        radius: 400,
        size: size,
        margin: 2,
      );
      expect(window, isNotNull);
      expect(window!.halfWidth, math.pi);
    });

    test('is null when the center is on canvas but the rim is far away', () {
      final window = visibleAngularWindow(
        center: const Offset(400, 300),
        radius: 50000,
        size: size,
        margin: 2,
      );
      expect(window, isNull);
    });

    test('covers every rim point that lands on the padded canvas', () {
      // Rim passes through the canvas center from far below.
      const center = Offset(400, 50300);
      const radius = 50000.0;
      const margin = 2.0;
      final window = visibleAngularWindow(
        center: center,
        radius: radius,
        size: size,
        margin: margin,
      )!;
      expect(window.halfWidth, lessThan(math.pi / 2));
      final rect = (Offset.zero & size).inflate(margin);
      var onCanvas = 0;
      for (var i = 0; i < 10000; i++) {
        final angle = -math.pi + 2 * math.pi * i / 10000;
        final point =
            center + Offset(math.cos(angle), math.sin(angle)) * radius;
        if (!rect.contains(point)) {
          continue;
        }
        onCanvas++;
        var diff = (angle - window.center) % (2 * math.pi);
        if (diff > math.pi) {
          diff -= 2 * math.pi;
        }
        expect(diff.abs(), lessThanOrEqualTo(window.halfWidth));
      }
      expect(onCanvas, greaterThan(0));
    });
  });

  group('arcWindowOverlap', () {
    const window = (center: 0.0, halfWidth: 0.5);

    test('clamps an arc straddling the window', () {
      final pieces = arcWindowOverlap(start: -2, sweep: 4, window: window);
      expect(pieces, [(start: -0.5, end: 0.5)]);
    });

    test('is empty for a disjoint arc', () {
      final pieces = arcWindowOverlap(start: 1, sweep: 1, window: window);
      expect(pieces, isEmpty);
    });

    test('normalizes a negative sweep', () {
      final pieces = arcWindowOverlap(start: 0.3, sweep: -0.2, window: window);
      expect(pieces, hasLength(1));
      expect(pieces.single.start, closeTo(0.1, 1e-12));
      expect(pieces.single.end, closeTo(0.3, 1e-12));
    });

    test('finds the arc across the ±pi wraparound', () {
      // Window hugs +pi; the arc's angles hug -pi. Same rim stretch.
      final pieces = arcWindowOverlap(
        start: -math.pi,
        sweep: 0.2,
        window: (center: 3.0, halfWidth: 0.4),
      );
      // The shifted window [2.6 - 2pi, 3.4 - 2pi] contains the whole arc.
      expect(pieces, hasLength(1));
      expect(pieces.single.start, closeTo(-math.pi, 1e-12));
      expect(pieces.single.end, closeTo(-math.pi + 0.2, 1e-12));
    });

    test('returns ascending subintervals of the arc', () {
      // A near-full arc against a window whose shifted copies both hit it.
      final pieces = arcWindowOverlap(
        start: -3,
        sweep: 6,
        window: (center: 3.0, halfWidth: 0.4),
      );
      expect(pieces, hasLength(2));
      expect(pieces[0].start, lessThan(pieces[1].start));
      for (final piece in pieces) {
        expect(piece.start, greaterThanOrEqualTo(-3));
        expect(piece.end, lessThanOrEqualTo(3));
        expect(piece.end, greaterThan(piece.start));
      }
    });
  });

  group('addSampledArc', () {
    test('keeps every vertex on the circle and the sagitta invisible', () {
      const center = Offset(400, 50300);
      const radius = 50000.0;
      final path = Path();
      addSampledArc(
        path,
        center,
        radius,
        -math.pi / 2 - 0.02,
        -math.pi / 2 + 0.02,
      );
      final metric = path.computeMetrics().single;
      expect(metric.length, greaterThan(0));
      // Walk the polyline: every position stays within a sagitta of the
      // true circle.
      for (var d = 0.0; d <= metric.length; d += metric.length / 200) {
        final position = metric.getTangentForOffset(d)!.position;
        expect(
          ((position - center).distance - radius).abs(),
          lessThanOrEqualTo(maxSagitta * 1.01),
        );
      }
    });

    test('continues the current contour with startWithMove false', () {
      final path = Path()..moveTo(0, 0);
      addSampledArc(
        path,
        const Offset(0, 5000),
        5000,
        -math.pi / 2 - 0.01,
        -math.pi / 2 + 0.01,
        startWithMove: false,
      );
      expect(path.computeMetrics().length, 1);
    });

    test('caps the segment count for a full huge circle', () {
      final path = Path();
      addSampledArc(path, Offset.zero, 1e7, 0, 2 * math.pi);
      // A cap of maxArcSegments chords each shorter than the circle's
      // circumference / maxArcSegments — just assert the path is finite
      // and closed back to its start.
      final metric = path.computeMetrics().single;
      expect(metric.length, lessThan(2 * math.pi * 1e7 * 1.01));
      final first = metric.getTangentForOffset(0)!.position;
      final last = metric.getTangentForOffset(metric.length)!.position;
      expect((last - first).distance, lessThan(1e-3));
    });
  });
}
