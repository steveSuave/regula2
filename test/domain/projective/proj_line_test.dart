import 'package:glados/glados.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import 'generators.dart';

/// Relative tolerance for single-operation projective predicates.
const eps = 1e-9;

void main() {
  group('lift and construction', () {
    test('lift copies the (already normalized) LineEq coefficients', () {
      final l = ProjLine.lift(LineEq(3, 4, 5));
      // LineEq normalizes to a unit normal: (0.6, 0.8, 1).
      expect(l.a, const Complex(0.6));
      expect(l.b, const Complex(0.8));
      expect(l.c, Complex.one);
    });

    test('== is exact component equality, not projective', () {
      expect(ProjLine.real(1, 2, 3), ProjLine.real(1, 2, 3));
      expect(ProjLine.real(1, 2, 3).hashCode, ProjLine.real(1, 2, 3).hashCode);
      expect(ProjLine.real(1, 2, 3), isNot(ProjLine.real(2, 4, 6)));
    });
  });

  group('the line at infinity', () {
    test('is real, not finite, projects to null', () {
      expect(ProjLine.infinity.isReal(), isTrue);
      expect(ProjLine.infinity.isFinite(), isFalse);
      expect(ProjLine.infinity.toLineEq(), isNull);
    });

    test('contains exactly the points at infinity', () {
      expect(ProjLine.infinity.contains(ProjPoint.real(1, 2, 0)), isTrue);
      expect(
        ProjLine.infinity.contains(
          const ProjPoint(Complex.one, Complex.i, Complex.zero),
        ),
        isTrue,
      );
      expect(ProjLine.infinity.contains(ProjPoint.real(1, 2, 1)), isFalse);
    });
  });

  group('meet and incidence', () {
    test('x-axis meets y-axis at the origin', () {
      final m = ProjLine.real(0, 1, 0).meet(ProjLine.real(1, 0, 0));
      expect(m.closeTo(ProjPoint.real(0, 0), eps), isTrue);
    });

    test('meet of projectively equal lines is the zero point', () {
      final l = ProjLine.real(1, 2, 3);
      expect(l.meet(l.scaledBy(const Complex(0, 2))).norm2, lessThan(1e-20));
    });

    test('incidence delegates to the point side', () {
      final l = ProjLine.real(1, 2, 3);
      final p = ProjPoint.real(4, 5, 6);
      expect(l.incidence(p), p.incidence(l));
    });

    Glados2(any.projLine, any.projLine).test(
      'line∩line is always one point, on both lines',
      (l, m) {
        if (l.closeTo(m, 1e-6)) return;
        final p = l.meet(m);
        expect(p.isZero, isFalse);
        expect(l.contains(p, eps), isTrue);
        expect(m.contains(p, eps), isTrue);
      },
    );

    Glados3(any.projLine, any.projLine, any.projLine).test(
      'join of two meets on l recovers l (duality)',
      (l, m, n) {
        if (l.closeTo(m, 1e-3) || l.closeTo(n, 1e-3) || m.closeTo(n, 1e-3)) {
          return;
        }
        final p = l.meet(m);
        final q = l.meet(n);
        if (p.closeTo(q, 1e-3)) return; // concurrent triple: meets coincide
        expect(p.join(q).closeTo(l, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'parallel lifted lines meet at [d.x, d.y, 0]',
      (p1, p2, d) {
        if (d.normSquared < 1e-6) return;
        final l1 = LineEq.pointDirection(p1, d);
        final l2 = LineEq.pointDirection(p2, d);
        // Same construction ⇒ same oriented normal; distinct parallels differ
        // exactly in the offset c.
        if ((l1.c - l2.c).abs() < 1e-3) return;
        final m = ProjLine.lift(l1).meet(ProjLine.lift(l2));
        expect(m.closeTo(ProjPoint.real(d.x, d.y, 0), 1e-6), isTrue);
        expect(m.isFinite(), isFalse);
      },
    );
  });

  group('realness, finiteness, projection', () {
    test('genuinely complex line: not real, projects to null', () {
      const l = ProjLine(Complex.one, Complex.i, Complex.zero);
      expect(l.isReal(), isFalse);
      expect(l.toLineEq(), isNull);
    });

    test('projectively real line (real only after phase removal)', () {
      const l = ProjLine(Complex.i, Complex.zero, Complex(0, 2));
      expect(l.isReal(), isTrue);
      expect(l.isFinite(), isTrue);
      // x + 2 = 0, the vertical line at x = −2.
      expect(l.toLineEq()!.closeTo(LineEq(1, 0, 2), eps), isTrue);
    });

    test('zero triple fails every predicate', () {
      const zero = ProjLine(Complex.zero, Complex.zero, Complex.zero);
      expect(zero.isReal(), isFalse);
      expect(zero.isFinite(), isFalse);
      expect(zero.toLineEq(), isNull);
      expect(zero.closeTo(zero, eps), isFalse);
    });

    test('NaN coefficients fail every predicate instead of throwing', () {
      final l = ProjLine(const Complex(double.nan), Complex.one, Complex.one);
      expect(l.isReal(), isFalse);
      expect(l.isFinite(), isFalse);
      expect(l.toLineEq(), isNull);
    });
  });

  group('toOrientedLineEq (Phase 137)', () {
    test('the implicit form is a positive multiple of a real '
        'representative', () {
      final l = ProjLine.real(3, -4, 7);
      final chart = l.toOrientedLineEq()!;
      // LineEq normalizes the normal to unit length, so a positive
      // multiple means (0.6, −0.8, 1.4).
      expect(chart.a, closeTo(0.6, 1e-15));
      expect(chart.b, closeTo(-0.8, 1e-15));
      expect(chart.c, closeTo(1.4, 1e-15));
    });

    test('negating the representative negates the chart orientation', () {
      final l = ProjLine.real(3, -4, 7);
      final flipped = l.scaledBy(const Complex(-1));
      final chart = l.toOrientedLineEq()!;
      final flippedChart = flipped.toOrientedLineEq()!;
      expect(flippedChart.a, -chart.a);
      expect(flippedChart.b, -chart.b);
      expect(flippedChart.c, -chart.c);
    });

    test('an i-scaled real representative keeps its orientation', () {
      // The phase carries the sign: i·(3, −4, 7) dephases back to the
      // same oriented line, via the imaginary-parts fallback.
      final l = ProjLine.real(3, -4, 7).scaledBy(Complex.i);
      final chart = l.toOrientedLineEq()!;
      expect(chart.a, closeTo(0.6, 1e-15));
      expect(chart.b, closeTo(-0.8, 1e-15));
    });

    Glados(any.projLine).test('null exactly where toLineEq is', (l) {
      expect(l.toOrientedLineEq() == null, l.toLineEq() == null);
    });

    Glados(any.projLine)
        .test('the chart direction points along the representative', (l) {
          final chart = l.toOrientedLineEq();
          if (chart == null || !l.isReal(1e-12)) return;
          final reNorm = l.a.re * l.a.re + l.b.re * l.b.re;
          final imNorm = l.a.im * l.a.im + l.b.im * l.b.im;
          final along = reNorm >= imNorm
              ? chart.direction.x * l.b.re - chart.direction.y * l.a.re
              : chart.direction.x * l.b.im - chart.direction.y * l.a.im;
          expect(along, greaterThanOrEqualTo(0));
        });

    Glados2(any.projLine, any.positiveDouble).test(
      'orientation is invariant under positive real rescaling',
      (l, k) {
        final chart = l.toOrientedLineEq();
        final scaled = l.scaledBy(Complex(k)).toOrientedLineEq();
        if (chart == null || scaled == null) return;
        expect(scaled.a, closeTo(chart.a, 1e-9));
        expect(scaled.b, closeTo(chart.b, 1e-9));
      },
    );
  });

  group('invariance under complex rescaling (glados)', () {
    Glados2(any.projLine, any.nonZeroComplex).test(
      'closeTo: a scaled copy is the same line',
      (l, k) {
        expect(l.scaledBy(k).closeTo(l, eps), isTrue);
      },
    );

    Glados2(any.projLine, any.nonZeroComplex).test(
      'isReal and isFinite are scale-invariant',
      (l, k) {
        final scaled = l.scaledBy(k);
        expect(scaled.isReal(), l.isReal());
        expect(scaled.isFinite(), l.isFinite());
      },
    );

    Glados2(any.projLine, any.nonZeroComplex).test(
      'toLineEq is scale-invariant',
      (l, k) {
        final e = l.toLineEq();
        final eScaled = l.scaledBy(k).toLineEq();
        if (e == null) {
          expect(eScaled, isNull);
        } else {
          expect(eScaled, isNotNull);
          expect(eScaled!.closeTo(e, 1e-6), isTrue);
        }
      },
    );
  });

  group('lift ∘ project = id', () {
    Glados2(any.vec2, any.vec2).test('toLineEq of a lifted line is the line', (
      p,
      q,
    ) {
      if (p.closeTo(q, 1e-3)) return;
      final l = LineEq.throughPoints(p, q);
      final back = ProjLine.lift(l).toLineEq();
      expect(back, isNotNull);
      expect(back!.closeTo(l, eps), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      '…even after complex rescaling',
      (p, q, k) {
        if (p.closeTo(q, 1e-3)) return;
        final l = LineEq.throughPoints(p, q);
        final back = ProjLine.lift(l).scaledBy(k).toLineEq();
        expect(back, isNotNull);
        expect(back!.closeTo(l, 1e-6), isTrue);
      },
    );
  });
}
