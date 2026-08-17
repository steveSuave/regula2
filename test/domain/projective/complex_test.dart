import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/projective/complex.dart';

import 'generators.dart';

/// Relative tolerance for single arithmetic identities.
const eps = 1e-12;

/// Looser tolerance for identities that chain several operations
/// (sqrt, polar round-trips) where error compounds.
const looseEps = 1e-9;

Matcher closeToComplex(Complex expected, [double tolerance = eps]) => predicate(
  (Complex z) => z.closeTo(expected, tolerance),
  'is within $tolerance of $expected',
);

void main() {
  group('Complex unit tests', () {
    test('arithmetic operators on known values', () {
      const a = Complex(3, 4);
      const b = Complex(-1, 2);
      expect(a + b, const Complex(2, 6));
      expect(a - b, const Complex(4, 2));
      expect(-a, const Complex(-3, -4));
      expect(a * b, const Complex(-11, 2));
      expect(a.scale(2), const Complex(6, 8));
    });

    test('i squared is -1', () {
      expect(Complex.i * Complex.i, const Complex(-1, 0));
    });

    test('division on known values', () {
      // (3+4i)/(1+2i) = (3+4i)(1-2i)/5 = (11-2i)/5
      expect(
        const Complex(3, 4) / const Complex(1, 2),
        closeToComplex(const Complex(2.2, -0.4)),
      );
      expect(
        const Complex(1) / Complex.i,
        closeToComplex(const Complex(0, -1)),
      );
    });

    test('division by zero yields non-finite components, not a throw', () {
      final z = const Complex(1, 1) / Complex.zero;
      expect(z.isFinite, isFalse);
    });

    test('conj, abs, abs2 on known values', () {
      const z = Complex(3, 4);
      expect(z.conj, const Complex(3, -4));
      expect(z.abs, 5);
      expect(z.abs2, 25);
    });

    test('arg convention: (−π, π], arg(-1) = π', () {
      expect(const Complex(1).arg, 0);
      expect(const Complex(0, 1).arg, math.pi / 2);
      expect(const Complex(-1).arg, math.pi);
      expect(const Complex(0, -1).arg, -math.pi / 2);
      expect(const Complex(1, 1).arg, closeTo(math.pi / 4, eps));
    });

    test('polar constructor on known values', () {
      expect(Complex.polar(2, 0), closeToComplex(const Complex(2)));
      expect(
        Complex.polar(2, math.pi / 2),
        closeToComplex(const Complex(0, 2)),
      );
      expect(Complex.polar(1, math.pi), closeToComplex(const Complex(-1)));
    });

    test('sqrt on known values', () {
      expect(const Complex(4).sqrt, closeToComplex(const Complex(2)));
      expect(const Complex(0, 2).sqrt, closeToComplex(const Complex(1, 1)));
      expect(Complex.zero.sqrt, Complex.zero);
    });

    test('sqrt branch cut: negative reals map to +i·sqrt(|x|)', () {
      expect(const Complex(-4).sqrt, closeToComplex(const Complex(0, 2)));
      expect(const Complex(-4, -0.0).sqrt, closeToComplex(const Complex(0, 2)));
      expect(const Complex(-1).sqrt, closeToComplex(Complex.i));
    });

    test('sqrt is discontinuous across the negative real axis', () {
      // Just above the cut → near +2i; just below → near −2i.
      const delta = 1e-12;
      final above = const Complex(-4, delta).sqrt;
      final below = const Complex(-4, -delta).sqrt;
      expect(above, closeToComplex(const Complex(0, 2), 1e-6));
      expect(below, closeToComplex(const Complex(0, -2), 1e-6));
    });

    test('isRealWithin: hybrid absolute/relative tolerance', () {
      expect(const Complex(5).isRealWithin(1e-9), isTrue);
      expect(const Complex(5, 1e-10).isRealWithin(1e-9), isTrue);
      expect(const Complex(5, 1e-7).isRealWithin(1e-9), isFalse);
      // Relative for large magnitudes: |im| ≤ eps·|re|.
      expect(const Complex(1e12, 1).isRealWithin(1e-9), isTrue);
      expect(const Complex(1e12, 1e4).isRealWithin(1e-9), isFalse);
      // Absolute near zero: max(1, |re|) floors the scale at 1.
      expect(const Complex(0, 1e-10).isRealWithin(1e-9), isTrue);
      expect(const Complex(0, 1e-8).isRealWithin(1e-9), isFalse);
    });

    test('value equality and hashCode', () {
      expect(const Complex(1, 2), const Complex(1, 2));
      expect(const Complex(1, 2).hashCode, const Complex(1, 2).hashCode);
      expect(const Complex(1, 2), isNot(const Complex(2, 1)));
    });
  });

  group('field axioms (up to eps)', () {
    Glados2(any.complex, any.complex).test('addition commutes', (a, b) {
      expect(a + b, closeToComplex(b + a));
    });

    Glados3(any.complex, any.complex, any.complex).test('addition associates', (
      a,
      b,
      c,
    ) {
      expect((a + b) + c, closeToComplex(a + (b + c)));
    });

    Glados(any.complex).test('additive identity and inverse', (a) {
      expect(a + Complex.zero, a);
      expect(a + (-a), closeToComplex(Complex.zero));
    });

    Glados2(any.complex, any.complex).test('multiplication commutes', (a, b) {
      expect(a * b, closeToComplex(b * a));
    });

    Glados3(any.complex, any.complex, any.complex).test(
      'multiplication associates',
      (a, b, c) {
        expect((a * b) * c, closeToComplex(a * (b * c), looseEps));
      },
    );

    Glados(any.complex).test('multiplicative identity', (a) {
      expect(a * Complex.one, a);
    });

    Glados(any.nonZeroComplex).test('multiplicative inverse', (a) {
      expect(a * (Complex.one / a), closeToComplex(Complex.one));
    });

    Glados3(any.complex, any.complex, any.complex).test(
      'multiplication distributes over addition',
      (a, b, c) {
        expect(a * (b + c), closeToComplex(a * b + a * c, looseEps));
      },
    );

    Glados2(any.complex, any.nonZeroComplex).test(
      'division inverts multiplication',
      (a, b) {
        expect((a * b) / b, closeToComplex(a, looseEps));
      },
    );
  });

  group('conjugation and modulus identities', () {
    Glados(any.complex).test('conjugation is an involution', (z) {
      expect(z.conj.conj, z);
    });

    Glados2(any.complex, any.complex).test(
      'conjugation distributes over + and *',
      (z, w) {
        expect((z + w).conj, closeToComplex(z.conj + w.conj));
        expect((z * w).conj, closeToComplex(z.conj * w.conj));
      },
    );

    Glados(any.complex).test('z·conj(z) is real and equals |z|²', (z) {
      final p = z * z.conj;
      expect(p.isRealWithin(eps), isTrue);
      expect(p.re, closeTo(z.abs2, math.max(1, z.abs2) * eps));
    });

    Glados(any.complex).test('|conj z| = |z| and |−z| = |z|', (z) {
      expect(z.conj.abs, z.abs);
      expect((-z).abs, z.abs);
    });

    Glados2(any.complex, any.complex).test('modulus is multiplicative', (z, w) {
      expect(
        (z * w).abs,
        closeTo(z.abs * w.abs, math.max(1, z.abs * w.abs) * looseEps),
      );
    });

    Glados2(any.complex, any.complex).test('triangle inequality', (z, w) {
      expect((z + w).abs, lessThanOrEqualTo(z.abs + w.abs + eps));
    });
  });

  group('sqrt and polar properties', () {
    Glados(any.complex).test('sqrt(z)·sqrt(z) ≈ z', (z) {
      expect(z.sqrt * z.sqrt, closeToComplex(z, looseEps));
    });

    Glados(any.complex).test('principal branch: Re(sqrt z) ≥ 0', (z) {
      expect(z.sqrt.re, greaterThanOrEqualTo(0));
    });

    Glados(any.complex).test('arg lies in (−π, π]', (z) {
      if (z == Complex.zero) return;
      expect(z.arg, greaterThan(-math.pi));
      expect(z.arg, lessThanOrEqualTo(math.pi));
    });

    Glados(any.complex).test('polar(|z|, arg z) round-trips', (z) {
      expect(Complex.polar(z.abs, z.arg), closeToComplex(z, looseEps));
    });

    Glados(any.complex).test('closeTo is reflexive and symmetric', (z) {
      expect(z.closeTo(z, 0), isTrue);
      final w = z + const Complex(eps / 2, -eps / 2);
      expect(z.closeTo(w, eps), w.closeTo(z, eps));
    });
  });

  group('cos and sin (Phase 116b)', () {
    test('bitwise real on the real axis: cos/sin of Complex(a) have '
        're == math.cos/sin(a) exactly and zero imaginary part', () {
      for (final a in [0.0, 0.3, -1.7, math.pi / 2, 12.34, -0.0]) {
        final z = Complex(a);
        expect(z.cos.re, math.cos(a));
        expect(z.cos.im.abs(), 0.0);
        expect(z.sin.re, math.sin(a));
        expect(z.sin.im.abs(), 0.0);
      }
    });

    test('known complex values against the hyperbolic identities', () {
      // cos(i) = cosh 1, sin(i) = i·sinh 1.
      final cosh1 = (math.exp(1) + math.exp(-1)) / 2;
      final sinh1 = (math.exp(1) - math.exp(-1)) / 2;
      expect(Complex.i.cos, closeToComplex(Complex(cosh1)));
      expect(Complex.i.sin, closeToComplex(Complex(0, sinh1)));
    });

    Glados(any.complex).test('Pythagorean identity: sin²z + cos²z = 1', (z) {
      // The identity cancels terms of size ~e^{2|im|}, so bound |im| to
      // keep the cancellation error under the tolerance (cosh/sinh grow
      // exponentially).
      if (z.im.abs() > 5) return;
      final s = z.sin;
      final c = z.cos;
      expect(s * s + c * c, closeToComplex(Complex.one, looseEps));
    });

    Glados2(any.complex, any.complex).test(
      'angle addition: sin(z+w) = sin z·cos w + cos z·sin w',
      (z, w) {
        if (z.im.abs() > 5 || w.im.abs() > 5) return;
        expect(
          (z + w).sin,
          closeToComplex(z.sin * w.cos + z.cos * w.sin, looseEps),
        );
      },
    );

    Glados(any.complex).test('conjugate symmetry: cos(conj z) = conj(cos z)', (
      z,
    ) {
      if (z.im.abs() > 20) return;
      expect(z.conj.cos, closeToComplex(z.cos.conj));
      expect(z.conj.sin, closeToComplex(z.sin.conj));
    });
  });
}
