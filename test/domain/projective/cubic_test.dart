import 'package:glados/glados.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/cubic.dart';

Complex cval(double re, [double im = 0]) => Complex(re, im);

extension on Any {
  /// A grid complex number in [-8, 8] per component — small enough that root
  /// reconstruction from Vieta coefficients stays well conditioned.
  Generator<Complex> get gridComplex => combine2(
        intInRange(-800, 801).map((i) => i / 100),
        intInRange(-800, 801).map((i) => i / 100),
        Complex.new,
      );
}

void main() {
  group('solveCubic', () {
    test('distinct real roots', () {
      // (λ−1)(λ−2)(λ−3) = λ³ − 6λ² + 11λ − 6
      final roots = solveCubic(cval(1), cval(-6), cval(11), cval(-6));
      expect(roots, hasLength(3));
      for (final expected in const [1.0, 2.0, 3.0]) {
        expect(
          roots.any((r) => r.closeTo(Complex(expected), 1e-10)),
          isTrue,
          reason: 'missing root $expected in $roots',
        );
      }
    });

    test('complex roots', () {
      // (λ² + 1)(λ − 2) = λ³ − 2λ² + λ − 2
      final roots = solveCubic(cval(1), cval(-2), cval(1), cval(-2));
      expect(roots, hasLength(3));
      for (final expected in [Complex.i, -Complex.i, cval(2)]) {
        expect(roots.any((r) => r.closeTo(expected, 1e-10)), isTrue);
      }
    });

    test('degree drop to quadratic and linear', () {
      // 0·λ³ + (λ−1)(λ−2)
      final quad = solveCubic(Complex.zero, cval(1), cval(-3), cval(2));
      expect(quad, hasLength(2));
      expect(quad.any((r) => r.closeTo(cval(1), 1e-10)), isTrue);
      expect(quad.any((r) => r.closeTo(cval(2), 1e-10)), isTrue);
      final lin = solveCubic(Complex.zero, Complex.zero, cval(2), cval(-6));
      expect(lin, hasLength(1));
      expect(lin.single.closeTo(cval(3), 1e-10), isTrue);
      expect(solveCubic(Complex.zero, Complex.zero, Complex.zero, cval(1)),
          isEmpty);
    });

    test('double root at reduced accuracy', () {
      // (λ−1)²(λ−2) = λ³ − 4λ² + 5λ − 2
      final roots = solveCubic(cval(1), cval(-4), cval(5), cval(-2));
      expect(roots, hasLength(3));
      expect(roots.where((r) => r.closeTo(cval(1), 1e-6)), hasLength(2));
      expect(roots.where((r) => r.closeTo(cval(2), 1e-9)), hasLength(1));
    });

    test('triple root', () {
      // (λ−1)³ = λ³ − 3λ² + 3λ − 1
      final roots = solveCubic(cval(1), cval(-3), cval(3), cval(-1));
      expect(roots, hasLength(3));
      for (final r in roots) {
        expect(r.closeTo(cval(1), 1e-4), isTrue, reason: '$r');
      }
    });

    test('non-finite coefficients yield no roots instead of throwing', () {
      expect(
        solveCubic(cval(1), cval(double.nan), cval(1), cval(1)),
        isEmpty,
      );
      expect(
        solveCubic(cval(double.infinity), cval(1), cval(1), cval(1)),
        isEmpty,
      );
    });

    Glados3(any.gridComplex, any.gridComplex, any.gridComplex)
        .test('reconstructs grid roots from Vieta coefficients', (r1, r2, r3) {
      final c2 = -(r1 + r2 + r3);
      final c1 = r1 * r2 + r1 * r3 + r2 * r3;
      final c0 = -(r1 * r2 * r3);
      final roots = solveCubic(Complex.one, c2, c1, c0);
      expect(roots, hasLength(3));
      for (final expected in [r1, r2, r3]) {
        expect(
          roots.any((r) => r.closeTo(expected, 1e-5)),
          isTrue,
          reason: 'missing root $expected in $roots',
        );
      }
    });
  });

  group('solveQuadratic', () {
    test('distinct real roots', () {
      // (λ−3)(λ+2) = λ² − λ − 6
      final roots = solveQuadratic(cval(1), cval(-1), cval(-6));
      expect(roots, hasLength(2));
      expect(roots.any((r) => r.closeTo(cval(3), 1e-12)), isTrue);
      expect(roots.any((r) => r.closeTo(cval(-2), 1e-12)), isTrue);
    });

    test('conjugate pair', () {
      final roots = solveQuadratic(cval(1), cval(0), cval(1));
      expect(roots, hasLength(2));
      expect(roots.any((r) => r.closeTo(Complex.i, 1e-12)), isTrue);
      expect(roots.any((r) => r.closeTo(-Complex.i, 1e-12)), isTrue);
    });

    test('degree drop to linear and constant', () {
      final lin = solveQuadratic(Complex.zero, cval(2), cval(-6));
      expect(lin, hasLength(1));
      expect(lin.single.closeTo(cval(3), 1e-12), isTrue);
      expect(solveQuadratic(Complex.zero, Complex.zero, cval(1)), isEmpty);
      expect(
          solveQuadratic(Complex.zero, Complex.zero, Complex.zero), isEmpty);
    });

    test('explicit scale controls degree-drop detection', () {
      // Against its own coefficients λ² is significant; against a larger
      // external scale it is negligible and the equation reads as linear.
      final own = solveQuadratic(cval(1e-10), cval(1), cval(1));
      expect(own, hasLength(2));
      final scaled = solveQuadratic(cval(1e-10), cval(1), cval(1), 1e4);
      expect(scaled, hasLength(1));
      expect(scaled.single.closeTo(cval(-1), 1e-12), isTrue);
    });

    Glados2(any.gridComplex, any.gridComplex)
        .test('reconstructs grid roots from Vieta coefficients', (r1, r2) {
      final roots = solveQuadratic(Complex.one, -(r1 + r2), r1 * r2);
      expect(roots, hasLength(2));
      for (final expected in [r1, r2]) {
        expect(
          roots.any((r) => r.closeTo(expected, 1e-7)),
          isTrue,
          reason: 'missing root $expected in $roots',
        );
      }
    });
  });
}
