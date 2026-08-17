import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/triangle_centers.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/circles.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_intersection.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../v1_oracle/circle_relations.dart';
import 'generators.dart';

void main() {
  const i = circularPointI;
  const j = circularPointJ;

  /// Every construction below must produce a circle-shaped conic: through
  /// I and J *exactly* (the quadratic entries are bit-identical and `xy`
  /// is bit-zero, so the evaluation cancels without tolerance).
  void expectThroughIJ(ConicMatrix k) {
    expect(k.evaluate(i), Complex.zero);
    expect(k.evaluate(j), Complex.zero);
  }

  group('pointCircleAt', () {
    test('is the zero-radius circle at the point', () {
      final k = pointCircleAt(ProjPoint.real(3, -2));
      expect(k.containsPoint(ProjPoint.real(3, -2)), isTrue);
      expectThroughIJ(k);
      expect(k.rank(), 2);
      final circle = k.toCircleEq()!;
      expect(circle.center, const Vec2(3, -2));
      expect(circle.radius, 0);
    });

    test('is the pair of isotropic lines through the point', () {
      final a = ProjPoint.real(1, 2);
      final expected = ConicMatrix.linePair(a.join(i), a.join(j));
      expect(pointCircleAt(a).closeTo(expected), isTrue);
    });

    test('a point at infinity gives a multiple of the double line at '
        'infinity (zero for isotropic directions)', () {
      final k = pointCircleAt(
        const ProjPoint(Complex(2), Complex(1), Complex.zero),
      );
      expect(
        k.closeTo(ConicMatrix.linePair(ProjLine.infinity, ProjLine.infinity)),
        isTrue,
      );
      expect(pointCircleAt(i).isZero, isTrue);
    });
  });

  group('circleWithRadius', () {
    test('matches the lifted CircleEq', () {
      final k = circleWithRadius(ProjPoint.real(2, -1), 3);
      expect(
        k.closeTo(ConicMatrix.lift(CircleEq(const Vec2(2, -1), 3))),
        isTrue,
      );
      expectThroughIJ(k);
      final circle = k.toCircleEq()!;
      expect(circle.center, const Vec2(2, -1));
      expect(circle.radius, 3);
    });

    test('a center at infinity degenerates', () {
      final k = circleWithRadius(
        const ProjPoint(Complex.one, Complex.zero, Complex.zero),
        2,
      );
      expect(k.isDegenerate(), isTrue);
      expect(k.toCircleEq(), isNull);
    });
  });

  group('circleThrough', () {
    test('projects exactly on integer data', () {
      final k = circleThrough(ProjPoint.real(2, 1), ProjPoint.real(7, 1));
      final circle = k.toCircleEq()!;
      expect(circle.center, const Vec2(2, 1));
      expect(circle.radius, 5);
      expect(k.containsPoint(ProjPoint.real(7, 1)), isTrue);
      expectThroughIJ(k);
    });

    test('coincident center and rim give the exact point circle', () {
      final k = circleThrough(ProjPoint.real(4, -3), ProjPoint.real(4, -3));
      expect(k.toCircleEq()!.radius, 0);
    });

    test('a rim at infinity gives the double line at infinity', () {
      final k = circleThrough(
        ProjPoint.real(1, 1),
        const ProjPoint(Complex.one, Complex(2), Complex.zero),
      );
      expect(
        k.closeTo(ConicMatrix.linePair(ProjLine.infinity, ProjLine.infinity)),
        isTrue,
      );
      expect(k.toCircleEq(), isNull);
    });

    test('a center at infinity gives the exact zero matrix', () {
      final k = circleThrough(
        const ProjPoint(Complex.one, Complex(2), Complex.zero),
        ProjPoint.real(1, 1),
      );
      expect(k.isZero, isTrue);
    });

    Glados2(any.vec2, any.vec2).test('agrees with CircleEq.centerAndPoint', (
      c,
      p,
    ) {
      final k = circleThrough(ProjPoint.lift(c), ProjPoint.lift(p));
      expect(
        k.closeTo(ConicMatrix.lift(CircleEq.centerAndPoint(c, p)), 1e-9),
        isTrue,
      );
      expectThroughIJ(k);
    });
  });

  group('compassCircleOf', () {
    test('carries the distance as radius', () {
      final k = compassCircleOf(
        ProjPoint.real(10, -4),
        ProjPoint.real(0, 0),
        ProjPoint.real(3, 4),
      );
      final circle = k.toCircleEq()!;
      expect(circle.center, const Vec2(10, -4));
      expect(circle.radius, 5);
    });

    test('coincident radius points give the exact point circle', () {
      final k = compassCircleOf(
        ProjPoint.real(1.5, 2.5),
        ProjPoint.real(-3.25, 7),
        ProjPoint.real(-3.25, 7),
      );
      expect(k.toCircleEq()!.radius, 0);
    });

    test('a radius point at infinity gives the double line at infinity', () {
      final k = compassCircleOf(
        ProjPoint.real(0, 0),
        const ProjPoint(Complex.one, Complex.zero, Complex.zero),
        ProjPoint.real(1, 1),
      );
      expect(
        k.closeTo(ConicMatrix.linePair(ProjLine.infinity, ProjLine.infinity)),
        isTrue,
      );
    });

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'agrees with CircleEq of the measured distance',
      (c, p, q) {
        final k = compassCircleOf(
          ProjPoint.lift(c),
          ProjPoint.lift(p),
          ProjPoint.lift(q),
        );
        expect(
          k.closeTo(ConicMatrix.lift(CircleEq(c, p.distanceTo(q))), 1e-9),
          isTrue,
        );
        expectThroughIJ(k);
      },
    );
  });

  group('diameterCircleOf', () {
    test('projects exactly on integer data', () {
      final k = diameterCircleOf(ProjPoint.real(0, 0), ProjPoint.real(6, 8));
      final circle = k.toCircleEq()!;
      expect(circle.center, const Vec2(3, 4));
      expect(circle.radius, 5);
      expectThroughIJ(k);
    });

    test('coincident endpoints give the exact point circle', () {
      final k = diameterCircleOf(
        ProjPoint.real(2.5, -1),
        ProjPoint.real(2.5, -1),
      );
      expect(k.toCircleEq()!.radius, 0);
    });

    test('one endpoint at infinity gives (perpendicular through the other, '
        'line at infinity)', () {
      final p = ProjPoint.real(1, 2);
      final direction = const ProjPoint(Complex(3), Complex(4), Complex.zero);
      final k = diameterCircleOf(p, direction);
      // Normal (3, 4) through (1, 2): 3x + 4y − 11 = 0.
      final perpendicular = ProjLine.real(3, 4, -11);
      expect(
        k.closeTo(ConicMatrix.linePair(perpendicular, ProjLine.infinity)),
        isTrue,
      );
    });

    Glados2(any.vec2, any.vec2).test(
      'agrees with the midpoint-and-half-distance circle',
      (p, q) {
        final k = diameterCircleOf(ProjPoint.lift(p), ProjPoint.lift(q));
        final expected = CircleEq(p.lerp(q, 0.5), p.distanceTo(q) / 2);
        expect(k.closeTo(ConicMatrix.lift(expected), 1e-9), isTrue);
        expect(k.containsPoint(ProjPoint.lift(p)) || p.closeTo(q), isTrue);
      },
    );
  });

  group('circumcircleOf', () {
    test('projects exactly on integer data', () {
      final k = circumcircleOf(
        ProjPoint.real(0, 0),
        ProjPoint.real(6, 0),
        ProjPoint.real(0, 8),
      );
      final circle = k.toCircleEq()!;
      expect(circle.center, const Vec2(3, 4));
      expect(circle.radius, 5);
      expectThroughIJ(k);
    });

    test('collinear distinct points give (their line, line at infinity)', () {
      final k = circumcircleOf(
        ProjPoint.real(0, 1),
        ProjPoint.real(2, 2),
        ProjPoint.real(6, 4),
      );
      final line = ProjLine.lift(
        LineEq.throughPoints(const Vec2(0, 1), const Vec2(6, 4)),
      );
      expect(k.closeTo(ConicMatrix.linePair(line, ProjLine.infinity)), isTrue);
      expect(k.toCircleEq(), isNull);
    });

    test('coincident points give the exact zero matrix', () {
      final k = circumcircleOf(
        ProjPoint.real(1, 1),
        ProjPoint.real(1, 1),
        ProjPoint.real(4, 0),
      );
      expect(k.isZero, isTrue);
    });

    test('one point at infinity gives (line through the finite two, line at '
        'infinity)', () {
      final k = circumcircleOf(
        ProjPoint.real(0, 0),
        ProjPoint.real(2, 0),
        const ProjPoint(Complex.zero, Complex.one, Complex.zero),
      );
      final line = ProjLine.lift(
        LineEq.throughPoints(const Vec2(0, 0), const Vec2(2, 0)),
      );
      expect(k.closeTo(ConicMatrix.linePair(line, ProjLine.infinity)), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'agrees with the V1 circumcenter circle',
      (a, b, c) {
        final o = circumcenter(a, b, c);
        if (o == null) {
          return;
        }
        final k = circumcircleOf(
          ProjPoint.lift(a),
          ProjPoint.lift(b),
          ProjPoint.lift(c),
        );
        // The circumcenter can be badly conditioned for near-collinear
        // triples; compare through the projected circle relative to its size.
        final projected = k.toCircleEq();
        if (projected == null) {
          return;
        }
        final expected = CircleEq.centerAndPoint(o, a);
        final scale = 1 + expected.radius + expected.center.norm;
        expect(
          projected.center.distanceTo(expected.center),
          lessThan(1e-6 * scale),
        );
        expect(
          (projected.radius - expected.radius).abs(),
          lessThan(1e-6 * scale),
        );
        expectThroughIJ(k);
      },
    );
  });

  group('apolloniusCircleOf', () {
    test('agrees with the V1 helper on a simple ratio', () {
      // C = (2, 0) has |CA| = 2, |CB| = 1 — the ratio-2 circle over (0,0),
      // (3,0) is centered at (4, 0) with radius 2.
      final k = apolloniusCircleOf(
        ProjPoint.real(0, 0),
        ProjPoint.real(3, 0),
        ProjPoint.real(2, 0),
      );
      final circle = k.toCircleEq()!;
      expect(circle.center.closeTo(const Vec2(4, 0)), isTrue);
      expect(circle.radius, closeTo(2, 1e-12));
      expectThroughIJ(k);
    });

    test('passes through the ratio point', () {
      final k = apolloniusCircleOf(
        ProjPoint.real(-1, 2),
        ProjPoint.real(5, 0),
        ProjPoint.real(2, 7),
      );
      expect(k.containsPoint(ProjPoint.real(2, 7)), isTrue);
    });

    test('an equidistant ratio point gives (perpendicular bisector, line at '
        'infinity)', () {
      final k = apolloniusCircleOf(
        ProjPoint.real(0, 0),
        ProjPoint.real(4, 0),
        ProjPoint.real(2, 3),
      );
      final bisector = ProjLine.real(1, 0, -2);
      expect(
        k.closeTo(ConicMatrix.linePair(bisector, ProjLine.infinity)),
        isTrue,
      );
      expect(k.toCircleEq(), isNull);
    });

    test('the ratio point on a base point gives that point circle', () {
      final k = apolloniusCircleOf(
        ProjPoint.real(1, 1),
        ProjPoint.real(5, 2),
        ProjPoint.real(1, 1),
      );
      expect(k.closeTo(pointCircleAt(ProjPoint.real(1, 1))), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.vec2).test('agrees with the V1 helper', (
      a,
      b,
      c,
    ) {
      final ratio = c.distanceTo(a) / c.distanceTo(b);
      final expected = apolloniusCircle(a, b, ratio);
      if (expected == null || (1 - ratio * ratio).abs() < 1e-3) {
        return;
      }
      final k = apolloniusCircleOf(
        ProjPoint.lift(a),
        ProjPoint.lift(b),
        ProjPoint.lift(c),
      );
      final projected = k.toCircleEq();
      expect(projected, isNotNull);
      final scale = 1 + expected.radius + expected.center.norm;
      expect(
        projected!.center.distanceTo(expected.center),
        lessThan(1e-6 * scale),
      );
      expect(
        (projected.radius - expected.radius).abs(),
        lessThan(1e-6 * scale),
      );
    });
  });

  group('rescaling invariance', () {
    Glados2(any.projPoint, any.nonZeroComplex).test(
      'every constructor scales multiplicatively',
      (p, k) {
        final q = ProjPoint.real(0.5, -2);
        final scaled = p.scaledBy(k);
        for (final (original, rescaled) in [
          (pointCircleAt(p), pointCircleAt(scaled)),
          (circleWithRadius(p, 1.5), circleWithRadius(scaled, 1.5)),
          (circleThrough(p, q), circleThrough(scaled, q)),
          (circleThrough(q, p), circleThrough(q, scaled)),
          (
            compassCircleOf(q, p, ProjPoint.real(1, 1)),
            compassCircleOf(q, scaled, ProjPoint.real(1, 1)),
          ),
          (diameterCircleOf(p, q), diameterCircleOf(scaled, q)),
          (
            circumcircleOf(p, q, ProjPoint.real(3, 1)),
            circumcircleOf(scaled, q, ProjPoint.real(3, 1)),
          ),
          (
            apolloniusCircleOf(p, q, ProjPoint.real(3, 1)),
            apolloniusCircleOf(scaled, q, ProjPoint.real(3, 1)),
          ),
        ]) {
          expect(
            original.isZero || rescaled.isZero,
            original.isZero && rescaled.isZero,
            reason: 'zero only together',
          );
          if (!original.isZero) {
            expect(original.closeTo(rescaled, 1e-9), isTrue);
          }
        }
      },
    );
  });

  group('ConicMatrix.poleOf', () {
    test('the pole of the line at infinity is the exact circle center', () {
      final k = ConicMatrix.lift(CircleEq(const Vec2(2, 1), 5));
      final center = k.poleOf(ProjLine.infinity);
      expect(center.toVec2(), const Vec2(2, 1));
    });

    test('inverts polarLine on a nondegenerate conic', () {
      final k = ConicMatrix.coefficients(1, 0.5, 2, -1, 3, -4);
      final p = ProjPoint.real(1.5, -2);
      final pole = k.poleOf(k.polarLine(p));
      expect(pole.closeTo(p), isTrue);
    });

    test('the center of a degenerate line-conic collapses to the zero '
        'triple', () {
      final line = ProjLine.lift(
        LineEq.throughPoints(const Vec2(0, 1), const Vec2(6, 4)),
      );
      final k = ConicMatrix.linePair(line, ProjLine.infinity);
      expect(k.poleOf(ProjLine.infinity).isZero, isTrue);
    });

    Glados(any.projLine).test('pole and polar are reciprocal on a circle', (l) {
      final k = ConicMatrix.lift(CircleEq(const Vec2(1, -2), 2));
      final pole = k.poleOf(l);
      if (pole.isZero) {
        return;
      }
      expect(k.polarLine(pole).closeTo(l, 1e-9), isTrue);
    });
  });

  group('radicalAxisOf', () {
    (CircleEq, CircleEq)? circles(Vec2 c1, Vec2 c2, double r) {
      // Two circles with positive radii, kept away from concentricity
      // (where V1 nulls).
      if (c1.distanceTo(c2) < 1e-3 * (1 + c1.norm + c2.norm)) {
        return null;
      }
      return (CircleEq(c1, 1 + r.abs() / 100), CircleEq(c2, 2 + r * r / 500));
    }

    Glados3(any.vec2, any.vec2, any.component).test(
      'agrees with V1 radicalAxis, raw orientation included',
      (p, q, r) {
        final pair = circles(p, q, r);
        if (pair == null) {
          return;
        }
        final (c1, c2) = pair;
        final axis = radicalAxisOf(ConicMatrix.lift(c1), ConicMatrix.lift(c2));
        final v1 = radicalAxis(c1, c2)!;
        final projected = axis.toLineEq();
        expect(projected, isNotNull, reason: '$c1 $c2 → $axis');
        expect(projected!.closeTo(v1), isTrue, reason: '$projected vs $v1');
        // The raw representative carries V1's orientation (its direction
        // is (b, −a)) — on unit lifts the coefficients match exactly.
        expect(Vec2(axis.b.re, -axis.a.re).dot(v1.direction), greaterThan(0));
      },
    );

    Glados3(any.vec2, any.vec2, any.component).test(
      'carries the common chord and equal-power structure: every non-I/J '
      'intersection of the circles lies on it',
      (p, q, r) {
        final pair = circles(p, q, r);
        if (pair == null) {
          return;
        }
        final (c1, c2) = pair;
        final a = ConicMatrix.lift(c1);
        final b = ConicMatrix.lift(c2);
        final axis = radicalAxisOf(a, b);
        for (final x in intersectConicConic(a, b)) {
          if (isCircularPoint(x)) {
            continue;
          }
          expect(
            x.isIncidentTo(axis, 1e-6),
            isTrue,
            reason: '$c1 ∩ $c2 → $x off $axis',
          );
        }
      },
    );

    Glados2(any.nonZeroComplex, any.nonZeroComplex).test(
      'rescaling either matrix leaves the axis invariant',
      (k1, k2) {
        final a = ConicMatrix.lift(CircleEq(const Vec2(1, 2), 2));
        final b = ConicMatrix.lift(CircleEq(const Vec2(4, -1), 1));
        final baseline = radicalAxisOf(a, b);
        expect(
          radicalAxisOf(a.scaledBy(k1), b.scaledBy(k2)).closeTo(baseline),
          isTrue,
        );
      },
    );

    test('concentric circles give ℓ∞, coincident matrices the zero triple', () {
      final a = ConicMatrix.lift(CircleEq(const Vec2(1, 2), 1));
      final b = ConicMatrix.lift(CircleEq(const Vec2(1, 2), 2));
      expect(radicalAxisOf(a, b).closeTo(ProjLine.infinity), isTrue);
      expect(radicalAxisOf(a, a.scaledBy(const Complex(2, 1))).isZero, isTrue);
    });

    test(
      'a degenerate line-conic input degenerates the axis onto its line',
      () {
        final line = ProjLine.real(3, -1, 2);
        final flattened = ConicMatrix.linePair(line, ProjLine.infinity);
        final k = ConicMatrix.lift(CircleEq(const Vec2(1, -2), 2));
        expect(radicalAxisOf(flattened, k).closeTo(line), isTrue);
        expect(radicalAxisOf(k, flattened).closeTo(line), isTrue);
      },
    );
  });
}
