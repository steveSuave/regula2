import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/conics.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import 'generators.dart';

/// Real finite chart points sampled around the whole curve of [conic].
List<Vec2> _sweep(ConicMatrix conic, {int count = 24}) {
  final shape = ConicShape.of(conic);
  return [
    for (var i = 0; i < count; i++) ?shape.chartPointAt(math.pi * i / count),
  ];
}

void main() {
  group('focalConicOf', () {
    test('the textbook parabola: focus (0,0), directrix x = −1', () {
      final k = focalConicOf(
        ProjPoint.real(0, 0),
        ProjLine.real(1, 0, 1),
        Complex.one,
      );
      // y² = 2x + 1 — vertex (−½, 0), which is where it must be.
      expect(k.closeTo(ConicMatrix.coefficients(0, 0, 1, -2, 0, -1)), isTrue);
      expect(ConicShape.of(k).kind, ConicClass.parabola);
    });

    test('every swept point is |XF| = e·d(X, ℓ), by construction', () {
      // The defining property, checked on the curve the constructor
      // produced rather than on the algebra that produced it.
      for (final e in const [0.35, 0.8, 1.0, 1.6, 3.0]) {
        final focus = const Vec2(2, -1);
        final line = ProjLine.real(3, -4, 5); // 3x − 4y + 5 = 0
        final k = focalConicOf(ProjPoint.lift(focus), line, Complex(e));
        final points = _sweep(k);
        expect(points, isNotEmpty, reason: 'e = $e produced no curve');
        for (final x in points) {
          final toDirectrix = (3 * x.x - 4 * x.y + 5).abs() / 5;
          expect(
            x.distanceTo(focus),
            closeTo(e * toDirectrix, 1e-6 * (1 + x.norm)),
            reason: 'e = $e at $x',
          );
        }
      }
    });

    test('the eccentricity picks the class', () {
      ConicClass classOf(double e) => ConicShape.of(
        focalConicOf(
          ProjPoint.real(2, -1),
          ProjLine.real(3, -4, 5),
          Complex(e),
        ),
      ).kind;
      expect(classOf(0.5), ConicClass.ellipse);
      expect(classOf(1), ConicClass.parabola);
      expect(classOf(2), ConicClass.hyperbola);
    });

    test('e = 0 is the focus as a zero-radius circle', () {
      // |XF| = 0 — the isotropic line pair through F, whose only real
      // point is F. Not drawable, and correctly so.
      final k = focalConicOf(
        ProjPoint.real(2, -1),
        ProjLine.real(1, 0, 1),
        Complex.zero,
      );
      expect(ConicShape.of(k).kind, ConicClass.isolatedPoint);
      expect(
        ConicShape.of(k).basePoint!.toVec2()!.closeTo(const Vec2(2, -1)),
        isTrue,
      );
    });

    test('a focus at infinity collapses onto the line at infinity', () {
      final k = focalConicOf(
        const ProjPoint(Complex.one, Complex.zero, Complex.zero),
        ProjLine.real(1, 0, 1),
        Complex.one,
      );
      expect(k.isZero, isFalse);
      expect(
        k.closeTo(ConicMatrix.linePair(ProjLine.infinity, ProjLine.infinity)),
        isTrue,
      );
    });

    test('a zero focus or a zero directrix gives the zero matrix', () {
      const zeroPoint = ProjPoint(Complex.zero, Complex.zero, Complex.zero);
      const zeroLine = ProjLine(Complex.zero, Complex.zero, Complex.zero);
      expect(
        focalConicOf(zeroPoint, ProjLine.real(1, 0, 1), Complex.one).isZero,
        isTrue,
      );
      expect(
        focalConicOf(ProjPoint.real(0, 0), zeroLine, Complex.one).isZero,
        isTrue,
      );
    });

    Glados2(any.nonZeroComplex, any.nonZeroComplex).test(
      'rescaling either parent rescales the conic, so its value is fixed',
      (focusScale, lineScale) {
        final reference = focalConicOf(
          ProjPoint.real(2, -1),
          ProjLine.real(3, -4, 5),
          const Complex(1.4),
        );
        final scaled = focalConicOf(
          ProjPoint.real(2, -1).scaledBy(focusScale),
          ProjLine.real(3, -4, 5).scaledBy(lineScale),
          const Complex(1.4),
        );
        expect(scaled.closeTo(reference), isTrue);
      },
    );
  });

  group('bifocalConicOf', () {
    const f1 = Vec2(-3, 0);
    const f2 = Vec2(3, 0);

    test('the textbook ellipse: foci (±3, 0) through (5, 0)', () {
      final k = bifocalConicOf(f1, f2, const Vec2(5, 0), difference: false);
      // x²/25 + y²/16 = 1
      expect(
        k.closeTo(ConicMatrix.coefficients(1 / 25, 0, 1 / 16, 0, 0, -1)),
        isTrue,
      );
      expect(ConicShape.of(k).kind, ConicClass.ellipse);
    });

    test('the textbook hyperbola: foci (±5, 0) through (3, 0)', () {
      final k = bifocalConicOf(
        const Vec2(-5, 0),
        const Vec2(5, 0),
        const Vec2(3, 0),
        difference: true,
      );
      // x²/9 − y²/16 = 1
      expect(
        k.closeTo(ConicMatrix.coefficients(1 / 9, 0, -1 / 16, 0, 0, -1)),
        isTrue,
      );
      expect(ConicShape.of(k).kind, ConicClass.hyperbola);
    });

    test('every swept point holds the defining sum or difference', () {
      // The bifocal property itself, on the curve as built — including a
      // rotated, off-centre focal pair, which is what the axis algebra
      // could plausibly get wrong.
      const a = Vec2(1, 2);
      const b = Vec2(6, 5);
      for (final p in const [Vec2(0, 7), Vec2(9, 1), Vec2(-2, -1)]) {
        for (final difference in const [false, true]) {
          final k = bifocalConicOf(a, b, p, difference: difference);
          final target = difference
              ? (p.distanceTo(a) - p.distanceTo(b)).abs()
              : p.distanceTo(a) + p.distanceTo(b);
          final points = _sweep(k);
          expect(points, isNotEmpty);
          for (final x in points) {
            final value = difference
                ? (x.distanceTo(a) - x.distanceTo(b)).abs()
                : x.distanceTo(a) + x.distanceTo(b);
            expect(
              value,
              closeTo(target, 1e-6 * (1 + x.norm)),
              reason: 'difference: $difference, p: $p, at $x',
            );
          }
        }
      }
    });

    test('the conic passes through the point that defined it', () {
      const p = Vec2(1, 4);
      for (final difference in const [false, true]) {
        final k = bifocalConicOf(f1, f2, p, difference: difference);
        expect(
          ConicShape.of(k).distanceTo(p),
          lessThan(1e-9),
          reason: 'difference: $difference',
        );
      }
    });

    test('sum branch, point on the segment: the major axis doubled', () {
      // |PF₁| + |PF₂| = |F₁F₂|, so a = c and the ellipse flattens onto
      // the focal line. The honest limit, unbanded.
      final k = bifocalConicOf(f1, f2, const Vec2(1, 0), difference: false);
      expect(ConicShape.of(k).kind, ConicClass.doubleLine);
      expect(
        ConicShape.of(k).lines.single.closeTo(ProjLine.real(0, 1, 0)),
        isTrue,
        reason: 'the x-axis, which carries both foci',
      );
    });

    test('difference branch, point equidistant: the bisector doubled', () {
      // a = 0, and |XF₁| = |XF₂| *is* the perpendicular bisector — the
      // set the difference branch asked for, not a failure of it.
      final k = bifocalConicOf(f1, f2, const Vec2(0, 4), difference: true);
      expect(ConicShape.of(k).kind, ConicClass.doubleLine);
      expect(
        ConicShape.of(k).lines.single.closeTo(ProjLine.real(1, 0, 0)),
        isTrue,
        reason: 'the y-axis, equidistant from (±3, 0)',
      );
    });

    test('coincident foci give the zero matrix — the caller guards', () {
      expect(
        bifocalConicOf(f1, f1, const Vec2(5, 0), difference: false).isZero,
        isTrue,
      );
    });

    Glados2(any.vec2, any.vec2).test(
      'the defining property survives any focal pair and point',
      (p, offset) {
        const a = Vec2(-2, 1);
        final b = a + offset / 100;
        final point = p / 100;
        if (a.distanceTo(b) < 1e-3) return;
        for (final difference in const [false, true]) {
          final k = bifocalConicOf(a, b, point, difference: difference);
          if (ConicShape.of(k).kind != ConicClass.ellipse &&
              ConicShape.of(k).kind != ConicClass.hyperbola) {
            continue; // a degenerate limit; pinned by the tests above
          }
          final target = difference
              ? (point.distanceTo(a) - point.distanceTo(b)).abs()
              : point.distanceTo(a) + point.distanceTo(b);
          for (final x in _sweep(k, count: 8)) {
            final value = difference
                ? (x.distanceTo(a) - x.distanceTo(b)).abs()
                : x.distanceTo(a) + x.distanceTo(b);
            expect(value, closeTo(target, 1e-6 * (1 + x.norm)));
          }
        }
      },
    );
  });
}
