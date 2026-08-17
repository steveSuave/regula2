import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_circles.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_point.dart';

/// Phase 125: Cayley–Klein circles.
///
/// The defining property is checked against `ck_measure.dart` rather than
/// against the formula that produced it — a circle is a level set of
/// distance, so "every point of it is equidistant from the centre" is the
/// only test that is not circular.
void main() {
  ProjPoint point(double x, double y, [double w = 1]) =>
      ProjPoint(Complex(x), Complex(y), Complex(w));

  final proper = [Absolute.hyperbolic, Absolute.elliptic];

  group('a circle is a level set of the distance', () {
    test('every point on it is equidistant from the centre', () {
      for (final absolute in proper) {
        final centre = point(0.1, -0.2);
        final rim = point(0.5, 0.15);
        final circle = ckCircleThrough(absolute, centre, rim);
        final radius = distanceBetween(absolute, centre, rim);
        expect(radius, isNotNull, reason: absolute.metric.name);

        // Walk the conic by intersecting it with lines through the
        // centre: take a direction, find where the conic meets that line,
        // and measure. Sampling by direction keeps this independent of
        // any parameterization the kernel might use.
        var checked = 0;
        for (var i = 0; i < 12; i++) {
          final theta = i * math.pi / 6;
          final far = point(
            centre.x.re + math.cos(theta),
            centre.y.re + math.sin(theta),
          );
          final hit = _meetAlong(circle, centre, far);
          if (hit == null) continue;
          final d = distanceBetween(absolute, centre, hit);
          if (d == null) continue;
          expect(
            d,
            closeTo(radius!, 1e-9),
            reason: '${absolute.metric.name} θ=$theta',
          );
          checked++;
        }
        expect(checked, greaterThan(6), reason: absolute.metric.name);
      }
    });

    test('the rim point itself lies on it', () {
      for (final absolute in proper) {
        final centre = point(-0.3, 0.05);
        final rim = point(0.2, 0.4);
        final circle = ckCircleThrough(absolute, centre, rim);
        expect(
          circle.evaluate(rim).abs2,
          lessThan(1e-24),
          reason: absolute.metric.name,
        );
      }
    });

    test('the compass circle agrees with the circle through a rim point', () {
      for (final absolute in proper) {
        final centre = point(0.1, 0.1);
        final p = point(-0.2, 0.3);
        final q = point(0.35, -0.1);
        final compass = ckCompassCircleOf(absolute, centre, p, q);
        // A rim point at the same distance must lie on it.
        final radius = distanceBetween(absolute, p, q)!;
        final byRadius = ckCircleWithRadius(absolute, centre, radius);
        expect(compass.closeTo(byRadius), isTrue, reason: absolute.metric.name);
      }
    });

    test('a bigger radius is a bigger circle, monotonically', () {
      final absolute = Absolute.hyperbolic;
      final centre = point(0, 0);
      double? along(double r) {
        final circle = ckCircleWithRadius(absolute, centre, r);
        final hit = _meetAlong(circle, centre, point(1, 0));
        return hit?.toVec2()?.x;
      }

      final radii = [0.2, 0.5, 1.0, 2.0];
      final xs = [for (final r in radii) along(r)];
      for (var i = 0; i < xs.length; i++) {
        expect(xs[i], isNotNull, reason: 'r = ${radii[i]}');
      }
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i]!, greaterThan(xs[i - 1]!));
      }
      // ...and never reaches the absolute. At r = 5 the Klein radius is
      // tanh(5) = 0.9999; much beyond that and `tanh` saturates to 1.0 in
      // a double, which is representation rather than geometry.
      expect(along(5)!, lessThan(1));
      expect(along(5)!, greaterThan(0.999));
    });
  });

  group('a CK circle is bitangent to the absolute', () {
    test('it meets the absolute where the centre polar does, doubled', () {
      // The defining projective description: the pencil through Ω and the
      // doubled polar of the centre. Every member is tangent to Ω along
      // that polar, so the polar's own intersections with Ω are double
      // roots of the circle too.
      // The chord of contact of a bitangent conic is the polar of the
      // centre with respect to *both* conics. That is a consequence of
      // the pencil form rather than a restatement of it: with
      // K = n·ℓℓᵀ − k·Ω and ℓ = ΩC, K·C = (n·ℓᵀC − k)·ℓ, so the circle's
      // polar of the centre is the absolute's, up to scale.
      for (final absolute in proper) {
        for (final centre in [
          point(0.2, -0.1),
          point(0, 0),
          point(-0.4, 0.3),
        ]) {
          final circle = ckCircleThrough(absolute, centre, point(0.5, 0.2));
          expect(
            circle.polarLine(centre).closeTo(absolute.polarOf(centre)),
            isTrue,
            reason: '${absolute.metric.name} at $centre',
          );
        }
      }
    });
  });

  group('the Euclidean absolute has no circle in this family', () {
    test('every entry point returns the zero matrix, deliberately', () {
      // Not an unimplemented case. Ω is the doubled line at infinity, so
      // the polar of any finite centre is ℓ∞ again and every member of
      // the pencil is a multiple of ℓ∞ — there is no circle in it. The
      // Euclidean circle is the dual statement (a conic through I and J)
      // and lives in circles.dart.
      final centre = point(1, 2);
      expect(
        ckCircleThrough(Absolute.euclidean, centre, point(4, 6)).isZero,
        isTrue,
      );
      expect(
        ckCompassCircleOf(
          Absolute.euclidean,
          centre,
          point(0, 0),
          point(3, 4),
        ).isZero,
        isTrue,
      );
      expect(ckCircleWithRadius(Absolute.euclidean, centre, 5).isZero, isTrue);
    });
  });

  group('degeneracies stay total', () {
    test('a centre on the absolute is a horocycle, not a degeneracy', () {
      // Written first as "has no circle", on the Euclidean intuition that
      // nothing is centred at infinity. That intuition belongs to the
      // *parabolic* measure: an ideal centre here gives the genuine limit
      // circle of infinite radius, tangent to the absolute at the centre.
      final ideal = point(1, 0);
      final circle = ckCircleThrough(Absolute.hyperbolic, ideal, point(0, 0));
      expect(circle.isZero, isFalse);
      expect(circle.evaluate(ideal).abs2, lessThan(1e-24));
      expect(circle.evaluate(point(0, 0)).abs2, lessThan(1e-24));
    });

    test('the zero triple propagates rather than throwing', () {
      const zero = ProjPoint(Complex.zero, Complex.zero, Complex.zero);
      for (final absolute in proper) {
        expect(ckCircleThrough(absolute, zero, point(0.2, 0)).isZero, isTrue);
      }
    });

    test('a zero radius is the centre, doubled', () {
      for (final absolute in proper) {
        final centre = point(0.2, -0.1);
        final circle = ckCircleWithRadius(absolute, centre, 0);
        expect(circle.evaluate(centre).abs2, lessThan(1e-24));
        expect(circle.isDegenerate(), isTrue, reason: absolute.metric.name);
      }
    });
  });
}

/// Where the conic [c] meets the ray from [from] towards [towards], as the
/// nearer real intersection, or null when there is none.
///
/// Deliberately a small independent solver rather than the kernel's
/// `intersectLineConic`: this file is testing the conic, so the sampler
/// should not share machinery with it.
ProjPoint? _meetAlong(ConicMatrix c, ProjPoint from, ProjPoint towards) {
  final ox = from.x.re / from.w.re;
  final oy = from.y.re / from.w.re;
  final dx = towards.x.re / towards.w.re - ox;
  final dy = towards.y.re / towards.w.re - oy;
  double at(double t) {
    final p = ProjPoint(
      Complex(ox + t * dx),
      Complex(oy + t * dy),
      Complex.one,
    );
    return c.evaluate(p).re;
  }

  final f0 = at(0);
  var lo = 0.0;
  var hi = 1e-6;
  while (hi < 1e6) {
    if (at(hi).sign != f0.sign) break;
    lo = hi;
    hi *= 1.6;
  }
  if (hi >= 1e6) return null;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    if (at(mid).sign == f0.sign) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final t = (lo + hi) / 2;
  return ProjPoint(Complex(ox + t * dx), Complex(oy + t * dy), Complex.one);
}
