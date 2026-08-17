import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

import '../domain/math/generators.dart';
import 'circle_relations.dart';
import 'intersections.dart';
import 'tangents.dart';

/// The power of [p] with respect to [c]: `|p − center|² − radius²`.
double power(CircleEq c, Vec2 p) =>
    (p - c.center).normSquared - c.radius * c.radius;

void main() {
  group('radicalAxis on canonical configurations', () {
    test('equal circles yield the perpendicular bisector of the centers', () {
      final axis = radicalAxis(
        CircleEq(Vec2.zero, 2),
        CircleEq(const Vec2(4, 0), 2),
      );
      expect(axis!.closeTo(LineEq(1, 0, -2)), isTrue);
    });

    test('unequal radii shift the axis toward the larger circle', () {
      // Powers of (1, y): 1 + y² − 1 and 9 + y² − 9 — equal along x = 1.
      final axis = radicalAxis(
        CircleEq(Vec2.zero, 1),
        CircleEq(const Vec2(4, 0), 3),
      );
      expect(axis!.closeTo(LineEq(1, 0, -1)), isTrue);
    });

    test('concentric circles have no radical axis', () {
      expect(
        radicalAxis(
          CircleEq(const Vec2(2, 3), 1),
          CircleEq(const Vec2(2, 3), 4),
        ),
        isNull,
      );
    });
  });

  group('radicalAxis properties', () {
    // Near-concentric centers make the axis shoot toward infinity, where
    // tolerances test floating point only — each property skips them.
    final axisParameter = any.intInRange(-2000, 2001).map((i) => i * 1.0);

    Glados3(any.circleEq, any.circleEq, axisParameter).test(
      'points on the axis have equal power to both circles',
      (c1, c2, t) {
        if (c1.center.closeTo(c2.center, 1e-3)) {
          return;
        }
        final p = radicalAxis(c1, c2)!.pointAt(t);
        final p1 = power(c1, p);
        final p2 = power(c2, p);
        final scale = math.max(1.0, math.max(p1.abs(), p2.abs()));
        expect((p1 - p2).abs() / scale, lessThan(1e-6));
      },
    );

    Glados2(any.circleEq, any.circleEq).test(
      'the axis carries the common chord of intersecting circles',
      (c1, c2) {
        if (c1.center.closeTo(c2.center, 1e-3)) {
          return;
        }
        final axis = radicalAxis(c1, c2)!;
        for (final p in intersectCircleCircle(c1, c2)) {
          final scale = math.max(1.0, p.norm);
          expect(axis.distanceTo(p) / scale, lessThan(1e-6));
        }
      },
    );

    Glados3(any.vec2, any.vec2, any.positiveRadius).test(
      'equal radii put the midpoint of the centers on the axis',
      (a, b, r) {
        if (a.closeTo(b, 1e-3)) {
          return;
        }
        final axis = radicalAxis(CircleEq(a, r), CircleEq(b, r))!;
        final midpoint = (a + b) * 0.5;
        final scale = math.max(1.0, midpoint.norm);
        expect(axis.distanceTo(midpoint) / scale, lessThan(1e-6));
      },
    );
  });

  group('polarLine on canonical configurations', () {
    final unit = CircleEq(Vec2.zero, 1);

    test('external pole: perpendicular chord through the inverse point', () {
      // Pole (2, 0) on the unit circle inverts to (1/2, 0): x = 1/2.
      final polar = polarLine(const Vec2(2, 0), unit);
      expect(polar!.closeTo(LineEq(1, 0, -0.5)), isTrue);
    });

    test('pole on the circle: the tangent at the pole', () {
      final polar = polarLine(const Vec2(1, 0), unit);
      expect(polar!.closeTo(LineEq(1, 0, -1)), isTrue);
    });

    test('internal pole: the polar lies outside the circle', () {
      final polar = polarLine(const Vec2(0.5, 0), unit);
      expect(polar!.closeTo(LineEq(1, 0, -2)), isTrue);
    });

    test('an off-origin circle translates the whole configuration', () {
      // n = (3, 0), n·X = n·c + r² = 6 + 4: the line x = 10/3.
      final polar = polarLine(const Vec2(5, 3), CircleEq(const Vec2(2, 3), 2));
      expect(polar!.closeTo(LineEq(3, 0, -10)), isTrue);
    });

    test('a pole on the center has no polar', () {
      expect(polarLine(Vec2.zero, unit), isNull);
      expect(
        polarLine(const Vec2(2, 3), CircleEq(const Vec2(2, 3), 4)),
        isNull,
      );
    });
  });

  group('polarLine properties', () {
    final axisParameter = any.intInRange(-2000, 2001).map((i) => i * 1.0);

    Glados2(any.circleEq, any.vec2).test(
      'perpendicular to the center–pole join at the inverse point',
      (circle, pole) {
        if (pole.closeTo(circle.center, 1e-3)) {
          return;
        }
        final polar = polarLine(pole, circle)!;
        final n = pole - circle.center;
        final inverse =
            circle.center + n * (circle.radius * circle.radius / n.normSquared);
        final scale = math.max(1.0, math.max(inverse.norm, n.norm));
        expect(polar.distanceTo(inverse) / scale, lessThan(1e-6));
        expect(
          polar.distanceTo(inverse + n.perpendicular) / scale,
          lessThan(1e-6),
          reason:
              'stepping from the inverse point perpendicular to the '
              'center–pole join must stay on the polar',
        );
      },
    );

    Glados2(any.circleEq, any.vec2).test(
      'an external pole\'s polar carries both tangent points',
      (circle, pole) {
        if (pole.closeTo(circle.center, 1e-3)) {
          return;
        }
        final polar = polarLine(pole, circle)!;
        for (final touch in tangentPointsToCircle(pole, circle)) {
          final scale = math.max(1.0, touch.norm);
          expect(polar.distanceTo(touch) / scale, lessThan(1e-6));
        }
      },
    );

    Glados3(any.circleEq, any.vec2, axisParameter).test(
      'La Hire reciprocity: Q on the polar of P puts P on the polar of Q',
      (circle, p, t) {
        if (p.closeTo(circle.center, 1e-3)) {
          return;
        }
        final q = polarLine(p, circle)!.pointAt(t);
        if (q.closeTo(circle.center, 1e-3)) {
          return;
        }
        final polarOfQ = polarLine(q, circle)!;
        final scale = math.max(1.0, math.max(p.norm, q.norm));
        expect(polarOfQ.distanceTo(p) / scale, lessThan(1e-6));
      },
    );
  });

  group('apolloniusCircle on canonical configurations', () {
    const a = Vec2.zero;
    const b = Vec2(3, 0);

    test('ratio 2 over a 3-unit base gives center (4, 0) radius 2', () {
      final circle = apolloniusCircle(a, b, 2);
      expect(circle!.closeTo(CircleEq(const Vec2(4, 0), 2), 1e-12), isTrue);
    });

    test('ratio 1 has no circle (perpendicular bisector)', () {
      expect(apolloniusCircle(a, b, 1), isNull);
    });

    test('coincident base points have no circle', () {
      expect(apolloniusCircle(a, a, 2), isNull);
    });

    test('non-positive or non-finite ratios have no circle', () {
      expect(apolloniusCircle(a, b, 0), isNull);
      expect(apolloniusCircle(a, b, -2), isNull);
      expect(apolloniusCircle(a, b, double.nan), isNull);
      expect(apolloniusCircle(a, b, double.infinity), isNull);
    });
  });

  group('apolloniusCircle properties', () {
    // Ratios near 1 send the circle toward infinity (the locus flattens
    // into the perpendicular bisector) — each property skips |k − 1| < 0.05,
    // the harmonic-conjugate midpoint guard's sibling.
    final ratio = any.intInRange(1, 5001).map((i) => i / 1000);
    bool nearOne(double k) => (k - 1).abs() < 0.05;

    Glados3(
      any.vec2,
      any.vec2,
      ratio,
    ).test('sampled circle points satisfy |PA| / |PB| = ratio', (a, b, k) {
      if (a.closeTo(b, 1e-3) || nearOne(k)) {
        return;
      }
      final circle = apolloniusCircle(a, b, k)!;
      for (final angle in [0.0, math.pi / 3, math.pi / 2, math.pi, 4.0, 5.5]) {
        final p = circle.pointAt(angle);
        expect(
          (p.distanceTo(a) / p.distanceTo(b) - k).abs() / k,
          lessThan(1e-6),
        );
      }
    });

    Glados3(any.vec2, any.vec2, ratio).test(
      'the circle cuts AB at the internal and external division points',
      (a, b, k) {
        if (a.closeTo(b, 1e-3) || nearOne(k)) {
          return;
        }
        final circle = apolloniusCircle(a, b, k)!;
        final scale = math.max(1.0, circle.radius);
        for (final t in [k / (1 + k), k / (k - 1)]) {
          final p = a + (b - a) * t;
          expect(circle.distanceTo(p) / scale, lessThan(1e-6));
        }
      },
    );

    Glados3(
      any.vec2,
      any.vec2,
      ratio,
    ).test('swapping the base points inverts the ratio', (a, b, k) {
      if (a.closeTo(b, 1e-3) || nearOne(k)) {
        return;
      }
      final circle = apolloniusCircle(a, b, k)!;
      final swapped = apolloniusCircle(b, a, 1 / k)!;
      final scale = math.max(1.0, math.max(circle.radius, circle.center.norm));
      expect(circle.closeTo(swapped, 1e-6 * scale), isTrue);
    });
  });
}
