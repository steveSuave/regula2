import 'package:glados/glados.dart';
import 'package:regula/domain/math/harmonic.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';

import 'generators.dart';

/// Relative tolerance for single-operation projective predicates.
const eps = 1e-9;

void main() {
  group('lift and construction', () {
    test('lift gives [x, y, 1]', () {
      final p = ProjPoint.lift(const Vec2(3, -4));
      expect(p.x, const Complex(3));
      expect(p.y, const Complex(-4));
      expect(p.w, Complex.one);
    });

    test('real constructor, w defaulting to 1', () {
      final p = ProjPoint.real(1, 2, 3);
      expect(p.x, const Complex(1));
      expect(p.y, const Complex(2));
      expect(p.w, const Complex(3));
      expect(ProjPoint.real(1, 2).w, Complex.one);
    });

    test('== is exact component equality, not projective', () {
      expect(ProjPoint.real(1, 2, 1), ProjPoint.real(1, 2, 1));
      expect(
        ProjPoint.real(1, 2, 1).hashCode,
        ProjPoint.real(1, 2, 1).hashCode,
      );
      expect(ProjPoint.real(1, 2, 1), isNot(ProjPoint.real(2, 4, 2)));
    });
  });

  group('normalization and scaling', () {
    test('normalized divides by the largest-magnitude coordinate', () {
      final n = ProjPoint.real(3, -4, 0).normalized;
      expect(n.x, const Complex(-0.75));
      expect(n.y, Complex.one);
      expect(n.w, Complex.zero);
    });

    test('normalized removes phase', () {
      final n = ProjPoint(Complex.i, const Complex(0, 2), Complex.i).normalized;
      expect(n.x.closeTo(const Complex(0.5), eps), isTrue);
      expect(n.y, Complex.one);
      expect(n.w.closeTo(const Complex(0.5), eps), isTrue);
    });

    test('normalized is the identity on the zero triple', () {
      const zero = ProjPoint(Complex.zero, Complex.zero, Complex.zero);
      expect(zero.normalized, zero);
    });

    Glados(any.projPoint).test(
      'normalized is projectively equal to the input',
      (p) {
        expect(p.normalized.closeTo(p, eps), isTrue);
      },
    );
  });

  group('projective equality (closeTo)', () {
    test('complex-scaled copies are the same point', () {
      final p = ProjPoint.real(1, 2, 3);
      expect(p.closeTo(p.scaledBy(const Complex(2, -1)), eps), isTrue);
    });

    test('distinct points are not close', () {
      expect(
        ProjPoint.real(1, 2, 1).closeTo(ProjPoint.real(1, 2.001, 1), eps),
        isFalse,
      );
    });

    test('the zero triple is close to nothing, not even itself', () {
      const zero = ProjPoint(Complex.zero, Complex.zero, Complex.zero);
      expect(zero.closeTo(zero, eps), isFalse);
      expect(zero.closeTo(ProjPoint.real(1, 2, 3), eps), isFalse);
      expect(ProjPoint.real(1, 2, 3).closeTo(zero, eps), isFalse);
    });
  });

  group('realness, finiteness, projection', () {
    test('real finite point round-trips through toVec2', () {
      expect(ProjPoint.real(3, -4, 2).toVec2(), const Vec2(1.5, -2));
    });

    test('point at infinity: real, not finite, projects to null', () {
      final p = ProjPoint.real(1, 2, 0);
      expect(p.isReal(), isTrue);
      expect(p.isFinite(), isFalse);
      expect(p.toVec2(), isNull);
    });

    test('genuinely complex point: not real, projects to null', () {
      const p = ProjPoint(Complex.one, Complex.i, Complex.one);
      expect(p.isReal(), isFalse);
      expect(p.toVec2(), isNull);
    });

    test('circular point I = (1, i, 0) is neither real nor finite', () {
      const i = ProjPoint(Complex.one, Complex.i, Complex.zero);
      expect(i.isReal(), isFalse);
      expect(i.isFinite(), isFalse);
      expect(i.toVec2(), isNull);
    });

    test('projectively real point (real only after phase removal)', () {
      const p = ProjPoint(Complex.i, Complex(0, 2), Complex.i);
      expect(p.isReal(), isTrue);
      expect(p.isFinite(), isTrue);
      expect(p.toVec2()!.closeTo(const Vec2(1, 2), 1e-12), isTrue);
    });

    test('zero triple fails every predicate', () {
      const zero = ProjPoint(Complex.zero, Complex.zero, Complex.zero);
      expect(zero.isReal(), isFalse);
      expect(zero.isFinite(), isFalse);
      expect(zero.toVec2(), isNull);
    });

    test('NaN coordinates fail every predicate instead of throwing', () {
      final p = ProjPoint(const Complex(double.nan), Complex.one, Complex.one);
      expect(p.isReal(), isFalse);
      expect(p.isFinite(), isFalse);
      expect(p.toVec2(), isNull);
    });
  });

  group('join and incidence', () {
    test('join of two lifted points is the affine line through them', () {
      final l = ProjPoint.real(0, 0).join(ProjPoint.real(1, 0));
      // The x-axis: y = 0.
      expect(l.a, Complex.zero);
      expect(l.b, Complex.one);
      expect(l.c, Complex.zero);
    });

    test('join of projectively equal points is the zero line', () {
      final p = ProjPoint.real(1, 2, 3);
      expect(p.join(p.scaledBy(const Complex(2))).norm2, lessThan(1e-20));
    });

    Glados2(any.projPoint, any.projPoint).test(
      'both points are incident to their join',
      (p, q) {
        if (p.closeTo(q, 1e-6)) return;
        final l = p.join(q);
        expect(p.isIncidentTo(l, eps), isTrue);
        expect(q.isIncidentTo(l, eps), isTrue);
      },
    );

    Glados2(any.projPoint, any.projPoint).test(
      'join is projectively antisymmetric',
      (p, q) {
        if (p.closeTo(q, 1e-6)) return;
        expect(p.join(q).closeTo(q.join(p), eps), isTrue);
      },
    );

    Glados3(any.projPoint, any.projPoint, any.projPoint).test(
      'meet of two joins through p recovers p',
      (p, q, r) {
        if (p.closeTo(q, 1e-3) || p.closeTo(r, 1e-3) || q.closeTo(r, 1e-3)) {
          return;
        }
        final l1 = p.join(q);
        final l2 = p.join(r);
        if (l1.closeTo(l2, 1e-3)) return; // collinear triple: joins coincide
        expect(l1.meet(l2).closeTo(p, 1e-6), isTrue);
      },
    );
  });

  group('invariance under complex rescaling (glados)', () {
    Glados2(any.projPoint, any.nonZeroComplex).test(
      'closeTo: a scaled copy is the same point',
      (p, k) {
        expect(p.scaledBy(k).closeTo(p, eps), isTrue);
      },
    );

    Glados2(any.projPoint, any.nonZeroComplex).test(
      'isReal and isFinite are scale-invariant',
      (p, k) {
        final scaled = p.scaledBy(k);
        expect(scaled.isReal(), p.isReal());
        expect(scaled.isFinite(), p.isFinite());
      },
    );

    Glados2(any.projPoint, any.nonZeroComplex).test(
      'toVec2 is scale-invariant',
      (p, k) {
        final v = p.toVec2();
        final vScaled = p.scaledBy(k).toVec2();
        if (v == null) {
          expect(vScaled, isNull);
        } else {
          expect(vScaled, isNotNull);
          expect(vScaled!.closeTo(v, 1e-6), isTrue);
        }
      },
    );

    Glados3(any.projPoint, any.projPoint, any.nonZeroComplex).test(
      'incidence with a join is scale-invariant',
      (p, q, k) {
        if (p.closeTo(q, 1e-6)) return;
        final l = p.join(q);
        expect(p.scaledBy(k).isIncidentTo(l, eps), isTrue);
        expect(p.scaledBy(k).isIncidentTo(l.scaledBy(k), eps), isTrue);
      },
    );
  });

  group('lift ∘ project = id', () {
    Glados(any.vec2).test('toVec2 of a lifted point is the point', (v) {
      expect(ProjPoint.lift(v).toVec2()!.closeTo(v, 1e-12), isTrue);
    });

    Glados2(any.vec2, any.nonZeroComplex).test(
      '…even after complex rescaling',
      (v, k) {
        final back = ProjPoint.lift(v).scaledBy(k).toVec2();
        expect(back, isNotNull);
        expect(back!.closeTo(v, 1e-6), isTrue);
      },
    );
  });

  group('harmonicConjugateOf', () {
    Glados3(any.vec2, any.vec2, any.component).test(
      'agrees with the V1 affine harmonicConjugate',
      (a, b, t0) {
        final t = t0 / 1000; // [-1, 1] grid
        if (a.closeTo(b, 1e-3) || (2 * t - 1).abs() < 1e-3) {
          return;
        }
        final c = a.lerp(b, t);
        final expected = harmonicConjugate(a, b, c);
        if (expected == null) {
          return; // V1's own degeneracy tolerance; boundary cases skipped.
        }
        final d = harmonicConjugateOf(
          ProjPoint.lift(a),
          ProjPoint.lift(b),
          ProjPoint.lift(c),
        );
        final got = d.toVec2();
        expect(got, isNotNull);
        final tol = 1e-8 * (1 + expected.norm + got!.norm);
        expect(got.distanceTo(expected), lessThanOrEqualTo(tol));
      },
    );

    Glados3(any.vec2, any.vec2, any.component).test(
      'is an involution (totally — through infinity included)',
      (a, b, t0) {
        final t = t0 / 1000;
        if (a.closeTo(b, 1e-3)) {
          return;
        }
        final pa = ProjPoint.lift(a);
        final pb = ProjPoint.lift(b);
        final pc = ProjPoint.lift(a.lerp(b, t));
        final d = harmonicConjugateOf(pa, pb, pc);
        if (d.isZero) {
          return;
        }
        expect(harmonicConjugateOf(pa, pb, d).closeTo(pc), isTrue);
      },
    );

    test('the midpoint conjugates to the join\'s point at infinity, '
        'endpoints to themselves', () {
      final a = ProjPoint.real(1, 1);
      final b = ProjPoint.real(5, 3);
      final mid = ProjPoint.real(3, 2);
      final d = harmonicConjugateOf(a, b, mid);
      expect(d.isReal(), isTrue);
      expect(d.isFinite(), isFalse);
      expect(
        d.closeTo(ProjPoint.real(4, 2, 0)),
        isTrue,
        reason: 'the direction of AB',
      );
      expect(harmonicConjugateOf(a, b, a).closeTo(a), isTrue);
      expect(harmonicConjugateOf(a, b, b).closeTo(b), isTrue);
    });

    Glados2(any.vec2, any.nonZeroComplex).test(
      'is projectively invariant under rescaling any argument',
      (v, k) {
        final a = ProjPoint.lift(v);
        final b = ProjPoint.real(4, -1);
        final c = ProjPoint.lift(v.lerp(const Vec2(4, -1), 0.25));
        if (a.closeTo(b)) {
          return;
        }
        final d = harmonicConjugateOf(a, b, c);
        if (d.isZero) {
          return;
        }
        expect(harmonicConjugateOf(a.scaledBy(k), b, c).closeTo(d), isTrue);
        expect(harmonicConjugateOf(a, b.scaledBy(k), c).closeTo(d), isTrue);
        expect(harmonicConjugateOf(a, b, c.scaledBy(k)).closeTo(d), isTrue);
      },
    );
  });
}
