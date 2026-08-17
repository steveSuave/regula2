// Complex polynomial root solving for the projective kernel, up to cubics —
// productionized from the Phase 102 pencil spike, where the recipe was
// validated (see docs/STATUS.md session 101 and `conic_intersection.dart`,
// its main consumer).

import 'dart:math' as math;

import 'complex.dart';
import 'tolerances.dart';

/// All complex roots of `c3·λ³ + c2·λ² + c1·λ + c0 = 0`.
///
/// Degree drops (leading coefficients negligible relative to the largest
/// coefficient, at [polynomialDegreeDropEpsilon]) fall through to the
/// quadratic / linear cases, so the list has 3, 2, 1, or 0 entries — 0 only
/// for the (near-)constant polynomial, including all-zero and non-finite
/// coefficients. Cardano on the depressed cubic, taking the larger-magnitude
/// resolvent root to avoid cancellation; every root gets one Newton polish
/// step on the original polynomial. Multiple roots are returned with
/// multiplicity, at the reduced accuracy inherent to them (a double root is
/// only good to ~sqrt(machine eps), a triple root to ~cbrt).
List<Complex> solveCubic(Complex c3, Complex c2, Complex c1, Complex c0) {
  final scale = math.max(math.max(c3.abs, c2.abs), math.max(c1.abs, c0.abs));
  if (scale == 0 || !scale.isFinite) return const [];
  if (c3.abs <= polynomialDegreeDropEpsilon * scale) {
    return solveQuadratic(c2, c1, c0, scale);
  }

  final a2 = c2 / c3;
  final a1 = c1 / c3;
  final a0 = c0 / c3;
  // Depress: λ = t − a2/3 ⇒ t³ + pt + q.
  final p = a1 - (a2 * a2).scale(1 / 3);
  final q = (a2 * a2 * a2).scale(2 / 27) - (a2 * a1).scale(1 / 3) + a0;
  final hq = q.scale(0.5);
  final p3 = p.scale(1 / 3);
  final s = (hq * hq + p3 * p3 * p3).sqrt;
  final plus = -hq + s;
  final minus = -hq - s;
  final u3 = plus.abs2 >= minus.abs2 ? plus : minus;
  final shift = a2.scale(1 / 3);
  if (u3.abs2 == 0) {
    // p = q = 0: triple root at −a2/3.
    final r = -shift;
    return [r, r, r];
  }
  final u = _cbrt(u3);
  final roots = <Complex>[];
  var w = u;
  const omega = Complex(-0.5, 0.8660254037844386);
  for (var k = 0; k < 3; k++) {
    final root = w - p3 / w - shift;
    roots.add(_polishPolyRoot(root, c3, c2, c1, c0));
    w = w * omega;
  }
  return roots;
}

/// All complex roots of `a·λ² + b·λ + c = 0`.
///
/// Degree drop is detected relative to [scale] when given (callers embedding
/// this in a larger computation pass that computation's coefficient scale),
/// else to the largest coefficient. Roots come from the cancellation-free
/// pair `(q/a, c/q)` with `q = −(b ± sqrt(b² − 4ac))/2`, the sign chosen to
/// grow `|b + s|`.
List<Complex> solveQuadratic(Complex a, Complex b, Complex c, [double? scale]) {
  final relativeTo = scale ?? math.max(a.abs, math.max(b.abs, c.abs));
  if (relativeTo == 0 || !relativeTo.isFinite) return const [];
  if (a.abs <= polynomialDegreeDropEpsilon * relativeTo) {
    if (b.abs <= polynomialDegreeDropEpsilon * relativeTo) return const [];
    return [-c / b];
  }
  final s0 = (b * b - (a * c).scale(4)).sqrt;
  // Choose the sign that grows |b + s| (avoids catastrophic cancellation).
  final s = (b.re * s0.re + b.im * s0.im) >= 0 ? s0 : -s0;
  final q = (b + s).scale(-0.5);
  if (q.abs2 == 0) return [Complex.zero, Complex.zero];
  return [q / a, c / q];
}

Complex _cbrt(Complex z) {
  final m = z.abs;
  if (m == 0) return Complex.zero;
  return Complex.polar(math.exp(math.log(m) / 3), z.arg / 3);
}

Complex _polishPolyRoot(
  Complex x,
  Complex c3,
  Complex c2,
  Complex c1,
  Complex c0,
) {
  final f = ((c3 * x + c2) * x + c1) * x + c0;
  final fp = (c3.scale(3) * x + c2.scale(2)) * x + c1;
  if (fp.abs2 < 1e-30) return x;
  return x - f / fp;
}
