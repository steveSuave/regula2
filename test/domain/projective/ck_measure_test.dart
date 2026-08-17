import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

/// Phase 124 (M-CK1): Cayley–Klein distance and angle.
///
/// Two claims carry the phase, and each has a group here. Angle is one
/// formula for all three geometries and reproduces the chart's Euclidean
/// answer. Distance is *three* formulas, because the Euclidean one is not
/// a cross-ratio at all — the group that pins that is the phase's finding,
/// not a limitation being documented.
void main() {
  ProjLine line(double a, double b, double c) =>
      ProjLine(Complex(a), Complex(b), Complex(c));

  ProjPoint point(double x, double y, [double w = 1]) =>
      ProjPoint(Complex(x), Complex(y), Complex(w));

  double artanh(double x) => 0.5 * math.log((1 + x) / (1 - x));

  group('angle: one formula, all three geometries', () {
    test('Euclidean agrees with the chart over 20k random line pairs', () {
      // The claim that makes M-CK a substitution rather than a rewrite. If
      // this drifts, every angle in every existing document has moved.
      final rnd = math.Random(7);
      var worst = 0.0;
      for (var i = 0; i < 20000; i++) {
        final a1 = rnd.nextDouble() * 8 - 4;
        final b1 = rnd.nextDouble() * 8 - 4;
        final a2 = rnd.nextDouble() * 8 - 4;
        final b2 = rnd.nextDouble() * 8 - 4;
        if (a1 * a1 + b1 * b1 < 1e-6 || a2 * a2 + b2 * b2 < 1e-6) continue;
        // A line's direction is (b, −a); compare the acute angle between
        // the two directions, which is what `AngleGeometry.betweenLines`
        // reports.
        var chart = (Vec2(b1, -a1).angle - Vec2(b2, -a2).angle).abs() % math.pi;
        if (chart > math.pi / 2) chart = math.pi - chart;
        final ck = angleBetweenLines(
          Absolute.euclidean,
          line(a1, b1, rnd.nextDouble()),
          line(a2, b2, rnd.nextDouble()),
        );
        worst = math.max(worst, (chart - ck!).abs());
      }
      expect(worst, lessThan(1e-11), reason: 'worst disagreement $worst');
    });

    test('the right angle is exactly π/2 in every geometry', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        // Perpendicularity is conjugacy: the pairing vanishes, so the
        // arccos argument is exactly 0 and the answer exactly π/2 — no
        // rounding, in any geometry.
        final l = line(1, 0, 0);
        final m = absolute == Absolute.euclidean
            ? line(0, 1, 0)
            : line(0, 1, 0);
        expect(
          angleBetweenLines(absolute, l, m),
          math.pi / 2,
          reason: absolute.metric.name,
        );
      }
    });

    test('a line makes a zero angle with itself, and with its rescalings', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        // Not 3x − 4y + 5: that one sits at distance exactly 1 from the
        // origin, so it is *tangent to the hyperbolic absolute* and has no
        // angle to anything — see the isotropy test below.
        final l = line(1, 2, 0.5);
        expect(
          angleBetweenLines(absolute, l, l),
          0,
          reason: absolute.toString(),
        );
        final scaled = ProjLine(
          l.a * const Complex(2),
          l.b * const Complex(2),
          l.c * const Complex(2),
        );
        expect(angleBetweenLines(absolute, l, scaled), 0);
      }
    });

    test('angle is elliptic in all three — the classification', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        expect(angleKindOf(absolute), MeasureKind.elliptic);
      }
    });

    test('an isotropic line has no angle to anything', () {
      // Its self-pairing vanishes, so the ratio has no denominator. Under
      // the Euclidean absolute the isotropic lines are those through I or
      // J, ℓ∞ among them.
      expect(
        angleBetweenLines(Absolute.euclidean, ProjLine.infinity, line(1, 2, 3)),
        isNull,
      );
      final throughI = ProjLine(Complex.one, Complex.i, Complex.zero);
      expect(
        angleBetweenLines(Absolute.euclidean, throughI, line(1, 2, 3)),
        isNull,
      );
    });

    test('which lines are isotropic is itself a fact about the geometry', () {
      // `3x − 4y + 5 = 0` is an ordinary line Euclidean-wise, and is
      // *tangent to the hyperbolic absolute* — its distance from the
      // origin is exactly 5/5 = 1. So it has a perfectly good Euclidean
      // angle to the x-axis and no hyperbolic angle to anything. Found by
      // a test that picked it for its integer coefficients.
      final tangent = line(3, -4, 5);
      // Direction (−4, −3) against the x-axis: acos(4/5), not acos(3/5).
      expect(
        angleBetweenLines(Absolute.euclidean, tangent, line(0, 1, 0)),
        closeTo(math.acos(0.8), 1e-12),
      );
      expect(angleBetweenLines(Absolute.hyperbolic, tangent, tangent), isNull);
      expect(Absolute.hyperbolic.isIsotropic(tangent), isTrue);
      expect(Absolute.euclidean.isIsotropic(tangent), isFalse);
    });

    test('every angle lands in [0, π/2]', () {
      final rnd = math.Random(11);
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        for (var i = 0; i < 500; i++) {
          final angle = angleBetweenLines(
            absolute,
            line(
              rnd.nextDouble() - 0.5,
              rnd.nextDouble() - 0.5,
              rnd.nextDouble(),
            ),
            line(
              rnd.nextDouble() - 0.5,
              rnd.nextDouble() - 0.5,
              rnd.nextDouble(),
            ),
          );
          if (angle == null) continue;
          expect(angle, inInclusiveRange(0, math.pi / 2));
        }
      }
    });
  });

  group('distance: Euclidean is parabolic, and that is not a gap', () {
    test('the Euclidean measure has no cross-ratio, so it answers null', () {
      // The phase's finding. A line meets the doubled ℓ∞ in one point
      // twice; a cross-ratio with a repeated point is identically 1 and
      // its log identically 0, for *every* pair, at every constant. So
      // there is nothing for this function to return, and returning 0 —
      // or the chart's answer — would be the lie.
      expect(distanceKindOf(Absolute.euclidean), MeasureKind.parabolic);
      for (final pair in [
        [point(0, 0), point(3, 4)],
        [point(-1, 2), point(-1, 2)],
        [point(1e6, 0), point(0, 1e-6)],
      ]) {
        expect(distanceBetween(Absolute.euclidean, pair[0], pair[1]), isNull);
      }
    });

    test('the algebraic form of the same fact: ⟨P,Q⟩ is w₁w₂', () {
      // The Euclidean pairing forgets where the points are, which is why
      // no formula over it can recover a distance.
      final a = Absolute.euclidean;
      expect(a.pairPoints(point(0, 0), point(3, 4)), const Complex(1));
      expect(a.pairPoints(point(-9, 17), point(1e6, 2)), const Complex(1));
      expect(a.pairPoints(point(3, 4, 2), point(5, 6, 7)), const Complex(14));
    });

    test('hyperbolic distance from the centre is artanh of the radius', () {
      for (final r in [0.1, 0.5, 0.9, 0.99, 0.999]) {
        final d = distanceBetween(
          Absolute.hyperbolic,
          point(0, 0),
          point(r, 0),
        );
        expect(d, closeTo(artanh(r), 1e-12), reason: 'r = $r');
      }
    });

    test('hyperbolic distance agrees with the cross-ratio it stands for', () {
      // (1/2)·|log CR(P, Q; M, N)| along the x-axis, whose absolute meets
      // are (±1, 0) — the definition the bilinear form is a clearing of.
      for (final (p, q) in [(0.0, 0.5), (-0.4, 0.7), (0.2, 0.95)]) {
        final cr = ((p + 1) / (p - 1)) * ((q - 1) / (q + 1));
        expect(
          distanceBetween(Absolute.hyperbolic, point(p, 0), point(q, 0)),
          closeTo(0.5 * math.log(cr).abs(), 1e-12),
          reason: '$p → $q',
        );
      }
    });

    test('the absolute is infinitely far away, and beyond it is nowhere', () {
      // A point *on* the unit circle is not in the hyperbolic plane, and
      // neither is one outside it. Both answer null rather than a large
      // number — the boundary is not somewhere you can drag a point to.
      expect(
        distanceBetween(Absolute.hyperbolic, point(0, 0), point(1, 0)),
        isNull,
      );
      expect(
        distanceBetween(Absolute.hyperbolic, point(0, 0), point(2, 0)),
        isNull,
      );
      // ...and it does diverge on the way there.
      final near = distanceBetween(
        Absolute.hyperbolic,
        point(0, 0),
        point(1 - 1e-12, 0),
      );
      expect(near, greaterThan(13));
    });

    test('hyperbolic distance is symmetric, zero only on coincidence', () {
      final rnd = math.Random(3);
      for (var i = 0; i < 300; i++) {
        final p = point(rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.5);
        final q = point(rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.5);
        final pq = distanceBetween(Absolute.hyperbolic, p, q)!;
        final qp = distanceBetween(Absolute.hyperbolic, q, p)!;
        expect(pq, closeTo(qp, 1e-12));
        expect(pq, greaterThan(0));
        expect(distanceBetween(Absolute.hyperbolic, p, p), closeTo(0, 1e-9));
      }
    });

    test('elliptic distance is bounded and periodic in the model', () {
      // No real point lies on the elliptic absolute, so every pair has a
      // distance — and it never exceeds π/2, the model's diameter.
      final rnd = math.Random(5);
      for (var i = 0; i < 300; i++) {
        final d = distanceBetween(
          Absolute.elliptic,
          point(rnd.nextDouble() * 4 - 2, rnd.nextDouble() * 4 - 2),
          point(rnd.nextDouble() * 4 - 2, rnd.nextDouble() * 4 - 2),
        );
        expect(d, isNotNull);
        expect(d, inInclusiveRange(0, math.pi / 2));
      }
      expect(
        distanceBetween(Absolute.elliptic, point(0, 0), point(1, 0)),
        closeTo(math.pi / 4, 1e-12),
      );
    });

    test('distance is invariant under rescaling of the homogeneous data', () {
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        final p = point(0.2, -0.3);
        final q = point(-0.1, 0.45);
        final scaled = ProjPoint(
          p.x * const Complex(-7),
          p.y * const Complex(-7),
          p.w * const Complex(-7),
        );
        expect(
          distanceBetween(absolute, scaled, q),
          closeTo(distanceBetween(absolute, p, q)!, 1e-12),
          reason: absolute.metric.name,
        );
      }
    });

    test('the measure kinds are the Cayley–Klein classification', () {
      expect(distanceKindOf(Absolute.euclidean), MeasureKind.parabolic);
      expect(distanceKindOf(Absolute.hyperbolic), MeasureKind.hyperbolic);
      expect(distanceKindOf(Absolute.elliptic), MeasureKind.elliptic);
    });
  });
}
