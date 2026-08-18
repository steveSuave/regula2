import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/metric.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

/// Phase 123 (M-CK0): the fundamental conic as a value.
///
/// The load-bearing group is "Euclidean reproduces the inlined kernel" —
/// the whole milestone rests on substituting the absolute into
/// constructions that already exist, so the Euclidean instance has to give
/// back exactly what those constructions compute today. Everything else
/// here is the type's own algebra.
void main() {
  ProjLine line(double a, double b, double c) =>
      ProjLine(Complex(a), Complex(b), Complex(c));

  ProjPoint point(double x, double y, [double w = 1]) =>
      ProjPoint(Complex(x), Complex(y), Complex(w));

  // A spread that covers the cases the Euclidean absolute treats
  // differently: general lines, axis-parallel ones (a zero coefficient),
  // negative coefficients (the sign-of-zero paths), the line at infinity
  // and an isotropic line through I.
  final lines = <ProjLine>[
    line(3, -4, 5),
    line(1, 0, 0),
    line(0, 1, -7),
    line(-2, -3, 11),
    line(0, 0, 1), // ℓ∞
    ProjLine(Complex.one, Complex.i, Complex.zero), // through J
    ProjLine(const Complex(2, -1), const Complex(0, 3), const Complex(-1, 4)),
  ];

  group('Euclidean reproduces the kernel it was extracted from', () {
    test('poleOf is normalDirectionOf, component for component', () {
      for (final l in lines) {
        final pole = Absolute.euclidean.poleOf(l);
        final inlined = normalDirectionOf(l);
        expect(pole.x, inlined.x, reason: 'x of $l');
        expect(pole.y, inlined.y, reason: 'y of $l');
        expect(pole.w, inlined.w, reason: 'w of $l');
      }
    });

    test('evaluateLine is the a² + b² of focalConicOf and reflection', () {
      for (final l in lines) {
        expect(Absolute.euclidean.evaluateLine(l), l.a * l.a + l.b * l.b);
      }
    });

    test('perpendicularThrough is the join with the pole, in every case', () {
      for (final l in lines) {
        for (final p in [point(0, 0), point(3, 5), point(-2, 7, 0)]) {
          final viaAbsolute = p.join(Absolute.euclidean.poleOf(l));
          final inlined = perpendicularThrough(p, l);
          expect(viaAbsolute.a, inlined.a);
          expect(viaAbsolute.b, inlined.b);
          expect(viaAbsolute.c, inlined.c);
        }
      }
    });

    test('polarOf a finite point is the line at infinity', () {
      for (final p in [point(0, 0), point(3, -5), point(1e6, 1e-6)]) {
        final polar = Absolute.euclidean.polarOf(p);
        expect(polar.a, Complex.zero);
        expect(polar.b, Complex.zero);
        expect(polar.c.re, isNot(0));
        expect(polar.closeTo(ProjLine.infinity), isTrue);
      }
    });

    test('polarOf a point at infinity is the zero triple', () {
      // The Euclidean absolute is the *doubled* ℓ∞, so a point on it is
      // singular for the polar map. Total, not thrown — the layer rule.
      final polar = Absolute.euclidean.polarOf(point(3, 4, 0));
      expect(polar.isZero, isTrue);
    });
  });

  group('the two matrices', () {
    test('Euclidean: point conic rank 1, dual rank 2', () {
      // This is why both are stored. The adjugate of the point conic —
      // which is how a dual is normally obtained — vanishes identically
      // here, so the dual cannot be derived from it.
      expect(Absolute.euclidean.pointConic.rank(), 1);
      expect(Absolute.euclidean.dualConic.rank(), 2);
      expect(
        Absolute.euclidean.pointConic.poleOf(line(1, 2, 3)).isZero,
        isTrue,
      );
    });

    test('the proper absolutes are self-dual, and dual = adj(point)', () {
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        expect(absolute.pointConic.rank(), 3);
        expect(absolute.dualConic.rank(), 3);
        // adj(Ω) applied to a line is exactly poleOf; the dual applied to
        // the same line must agree with it projectively.
        for (final l in lines) {
          final viaAdjugate = absolute.pointConic.poleOf(l);
          final viaDual = absolute.poleOf(l);
          expect(
            viaDual.closeTo(viaAdjugate),
            isTrue,
            reason: '${absolute.metric.name} on $l',
          );
        }
      }
    });

    test('I and J are the Euclidean absolute, and nothing else is', () {
      // The point conic w² = 0 contains every point at infinity, being the
      // doubled ℓ∞; the *dual* is the point pair {I, J}, and that is what
      // distinguishes Euclidean from affine structure.
      expect(Absolute.euclidean.evaluatePoint(circularPointI), Complex.zero);
      expect(Absolute.euclidean.evaluatePoint(circularPointJ), Complex.zero);
      expect(Absolute.euclidean.evaluatePoint(point(3, 4)).re, 1);

      // The isotropic lines are exactly those through I or J.
      final throughI = circularPointI.join(point(2, 3));
      expect(Absolute.euclidean.isIsotropic(throughI), isTrue);
      expect(Absolute.euclidean.isIsotropic(line(3, -4, 5)), isFalse);
    });

    test('the unit circle is the hyperbolic absolute', () {
      for (final p in [point(1, 0), point(0, -1), point(0.6, 0.8)]) {
        expect(Absolute.hyperbolic.evaluatePoint(p).abs2, lessThan(1e-24));
      }
      expect(Absolute.hyperbolic.evaluatePoint(point(0, 0)).re, -1);
    });

    test('no real point lies on the elliptic absolute', () {
      for (final p in [
        point(0, 0),
        point(1, 0),
        point(3, -4),
        point(1, 1, 0),
      ]) {
        expect(Absolute.elliptic.evaluatePoint(p).abs2, greaterThan(0));
      }
    });
  });

  group('the type', () {
    test('of() round-trips every named metric', () {
      for (final metric in FundamentalConic.values) {
        expect(Absolute.of(metric).metric, metric);
      }
    });

    test('isEuclidean is true for exactly one of them', () {
      expect(FundamentalConic.values.where((m) => Absolute.of(m).isEuclidean), [
        FundamentalConic.euclidean,
      ]);
    });

    test('byName is the save format token, and rejects anything else', () {
      expect(FundamentalConic.byName('euclidean'), FundamentalConic.euclidean);
      expect(
        FundamentalConic.byName('hyperbolic'),
        FundamentalConic.hyperbolic,
      );
      expect(FundamentalConic.byName('elliptic'), FundamentalConic.elliptic);
      expect(FundamentalConic.byName('Euclidean'), isNull);
      expect(FundamentalConic.byName('spherical'), isNull);
    });

    test('poleOf and polarOf are inverse on a proper absolute', () {
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        for (final l in lines.where((l) => !l.isZero)) {
          final back = absolute.polarOf(absolute.poleOf(l));
          expect(back.closeTo(l), isTrue, reason: '${absolute.metric.name} $l');
        }
      }
    });

    test('every operation is total on the zero triple', () {
      const zeroLine = ProjLine(Complex.zero, Complex.zero, Complex.zero);
      const zeroPoint = ProjPoint(Complex.zero, Complex.zero, Complex.zero);
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        expect(absolute.poleOf(zeroLine).isZero, isTrue);
        expect(absolute.polarOf(zeroPoint).isZero, isTrue);
        expect(absolute.evaluateLine(zeroLine), Complex.zero);
        expect(absolute.evaluatePoint(zeroPoint), Complex.zero);
        expect(absolute.isIsotropic(zeroLine), isFalse);
      }
    });

    test('scaling a line scales the pole, so the value is projective', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        final l = line(3, -4, 5);
        const k = Complex(2, -3);
        expect(
          absolute
              .poleOf(ProjLine(l.a * k, l.b * k, l.c * k))
              .closeTo(absolute.poleOf(l)),
          isTrue,
        );
      }
    });
  });

  group('a scaled absolute (Phase 131)', () {
    test('the radius is a chart scale, not a geometry', () {
      // The claim the whole feature rests on: substituting x = R·x′ takes
      // ⟨P,Q⟩ to R² times the unit-disc form, and every measure here is a
      // ratio of such forms, so R cancels. The plane of radius R is the
      // unit plane drawn R times larger — same distances, same angles,
      // between corresponding points.
      for (final metric in [
        FundamentalConic.hyperbolic,
        FundamentalConic.elliptic,
      ]) {
        final unit = Absolute.of(metric);
        for (final r in [0.25, 3.0, 200.0]) {
          final scaled = Absolute.scaled(metric, r);
          for (final pair in [
            (const Vec2(0.1, 0), const Vec2(0.4, 0.2)),
            (const Vec2(-0.35, 0.5), const Vec2(0.2, -0.15)),
          ]) {
            final here = distanceBetween(
              unit,
              ProjPoint.lift(pair.$1),
              ProjPoint.lift(pair.$2),
            );
            final there = distanceBetween(
              scaled,
              ProjPoint.lift(pair.$1 * r),
              ProjPoint.lift(pair.$2 * r),
            );
            expect(there, closeTo(here!, 1e-9), reason: '$metric R=$r');
          }
        }
      }
    });

    test('and it really does move the boundary', () {
      // The other half: at the same *coordinates* the geometry differs,
      // which is what makes a figure drawn at Euclidean scale land inside
      // a large plane and outside a unit one.
      final far = ProjPoint.lift(const Vec2(30, 0));
      expect(
        distanceBetween(Absolute.hyperbolic, ProjPoint.lift(Vec2.zero), far),
        isNull,
        reason: 'outside the unit disc there is no hyperbolic plane',
      );
      expect(
        distanceBetween(
          Absolute.scaled(FundamentalConic.hyperbolic, 100),
          ProjPoint.lift(Vec2.zero),
          far,
        ),
        isNotNull,
      );
    });

    test('the dual stays the adjugate, as it is everywhere else', () {
      for (final metric in [
        FundamentalConic.hyperbolic,
        FundamentalConic.elliptic,
      ]) {
        final scaled = Absolute.scaled(metric, 7);
        // adj(diag(1, 1, c)) is diag(c, c, 1), so the stored dual has to
        // be that up to nothing at all — the relation holds literally.
        final c = metric == FundamentalConic.hyperbolic ? -49.0 : 49.0;
        expect(scaled.pointConic.ww.re, closeTo(c, 1e-9));
        expect(scaled.dualConic.xx.re, closeTo(c, 1e-9));
        expect(scaled.dualConic.yy.re, closeTo(c, 1e-9));
        expect(scaled.dualConic.ww.re, closeTo(1, 1e-9));
      }
    });

    test('radius 1 is the const instance, so nothing else pays for this', () {
      expect(
        Absolute.of(FundamentalConic.hyperbolic),
        same(Absolute.hyperbolic),
      );
      expect(
        Absolute.of(FundamentalConic.hyperbolic, radius: 1),
        same(Absolute.hyperbolic),
      );
      expect(Absolute.hyperbolic.radius, 1);
      expect(Absolute.euclidean.radius, 1);
    });

    test('the Euclidean absolute refuses a radius, and that is the same '
        'fact as similar triangles', () {
      // Its absolute lies on one line and has no scale — which is why
      // Euclidean geometry has no absolute unit of length in the first
      // place. Scaling it would be scaling nothing.
      expect(
        () => Absolute.scaled(FundamentalConic.euclidean, 5),
        throwsArgumentError,
      );
      expect(
        () => Absolute.of(FundamentalConic.euclidean, radius: 5),
        throwsArgumentError,
        reason: 'the same refusal through the other door',
      );
      expect(
        const DocumentKernel(
          metric: FundamentalConic.euclidean,
          radius: 5,
        ).absolute,
        same(Absolute.euclidean),
        reason:
            'and DocumentKernel is what makes sure the door is never '
            'knocked on: a Euclidean kernel with a stray radius is still '
            'the default one',
      );
    });

    test('a radius that is not a positive finite number is refused', () {
      for (final bad in [0.0, -2.0, double.nan, double.infinity]) {
        expect(
          () => Absolute.scaled(FundamentalConic.hyperbolic, bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });
  });
}
