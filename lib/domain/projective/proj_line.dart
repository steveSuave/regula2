import 'dart:math' as math;

import '../math/line_eq.dart';
import 'complex.dart';
import 'proj_point.dart';
import 'tolerances.dart';

/// A line of the complex projective plane, in homogeneous coordinates
/// `[a : b : c]`: the locus of points `[x : y : w]` with
/// `a·x + b·y + c·w = 0`.
///
/// Dual to [ProjPoint], with the same conventions: complex-scalar
/// equivalence ([closeTo]; `==` is exact), the zero triple is no line and
/// fails every predicate, and every operation is bilinear/holomorphic (no
/// conjugation). The affine line `a·x + b·y + c = 0` lifts coefficient-wise
/// ([ProjLine.lift]); `[0 : 0 : 1]` is the line at [infinity].
class ProjLine {
  const ProjLine(this.a, this.b, this.c);

  /// The line with real homogeneous coefficients `[a, b, c]`.
  ProjLine.real(double a, double b, double c)
    : this(Complex(a), Complex(b), Complex(c));

  /// Lifts the affine line [l] coefficient-wise.
  ProjLine.lift(LineEq l) : this(Complex(l.a), Complex(l.b), Complex(l.c));

  /// The line at infinity, `w = 0` — every point at infinity lies on it.
  static const ProjLine infinity = ProjLine(
    Complex.zero,
    Complex.zero,
    Complex.one,
  );

  final Complex a;
  final Complex b;
  final Complex c;

  /// Squared Euclidean norm of the coefficient triple. Representation-level,
  /// not projective — use it to build relative tolerances.
  double get norm2 => a.abs2 + b.abs2 + c.abs2;

  /// Whether this is the zero triple (no line at all).
  bool get isZero => norm2 == 0;

  /// The same line with every coefficient multiplied by [k] — the projective
  /// identity when `k ≠ 0`.
  ProjLine scaledBy(Complex k) => ProjLine(a * k, b * k, c * k);

  /// Chart normalization: divides by the largest-magnitude coefficient, so
  /// that coefficient becomes exactly 1 and the others have magnitude ≤ 1.
  /// Removes both scale and phase; identity on the zero triple.
  ProjLine get normalized {
    var d = a;
    if (b.abs2 > d.abs2) d = b;
    if (c.abs2 > d.abs2) d = c;
    if (d.abs2 == 0) return this;
    return ProjLine(a / d, b / d, c / d);
  }

  /// The intersection point of this line and [other] (cross product of the
  /// triples) — always exactly one point. The zero point when the lines are
  /// projectively equal.
  ProjPoint meet(ProjLine other) => ProjPoint(
    b * other.c - c * other.b,
    c * other.a - a * other.c,
    a * other.b - b * other.a,
  );

  /// The incidence form `⟨p, l⟩` — same value as `p.incidence(this)`.
  Complex incidence(ProjPoint p) => p.incidence(this);

  /// Whether [p] lies on this line, relatively: `|⟨p, l⟩| ≤ eps·|p|·|l|`.
  /// False when either triple is zero.
  bool contains(ProjPoint p, [double eps = projectiveEpsilon]) =>
      p.isIncidentTo(this, eps);

  /// Projective equality: whether the triples are proportional up to [eps],
  /// measured relatively — the cross product is small against `|l|·|m|`.
  /// False when either triple is zero.
  bool closeTo(ProjLine other, [double eps = projectiveEpsilon]) {
    if (isZero || other.isZero) return false;
    return meet(other).norm2 <= eps * eps * norm2 * other.norm2;
  }

  /// Whether this line is real up to a complex scalar: after [normalized]
  /// (which removes phase), every coefficient is real within [eps]. The line
  /// at infinity is real; the zero triple is not.
  bool isReal([double eps = projectiveEpsilon]) {
    if (isZero) return false;
    final n = normalized;
    return n.a.isRealWithin(eps) &&
        n.b.isRealWithin(eps) &&
        n.c.isRealWithin(eps);
  }

  /// Whether this line is affinely representable — not the line at infinity:
  /// the normal part `(a, b)` is not negligible against `c`, relatively at
  /// [eps]. False for the zero triple and for NaN/infinite coefficients.
  bool isFinite([double eps = projectiveEpsilon]) {
    if (!a.isFinite || !b.isFinite || !c.isFinite) return false;
    final m = math.max(a.abs2, b.abs2);
    return m > eps * eps * c.abs2;
  }

  /// Projection to the affine chart — the rendering question. Returns the
  /// implicit-form line (orientation unspecified) when this line is real and
  /// affinely representable (at [eps]), else null.
  LineEq? toLineEq([double eps = projectiveEpsilon]) {
    if (!isReal(eps) || !isFinite(eps)) return null;
    final n = normalized;
    final na = n.a.re;
    final nb = n.b.re;
    if (na == 0 && nb == 0) return null;
    return LineEq(na, nb, n.c.re);
  }

  /// [toLineEq] with the orientation carried by the representative: the
  /// implicit form is a *positive* multiple of the triple, so
  /// `LineEq.direction` points along `(b, −a)` of the representative.
  /// Null exactly where [toLineEq] is.
  ///
  /// This is what makes the representative's sign the single source of
  /// orientation (PLAN §"Orientation is the representative's sign"):
  /// every line kind projects through this, so a consumer reading the
  /// representative where the chart is missing sees the same orientation
  /// the chart would have carried. The direction is taken from the real
  /// parts, falling back to the imaginary parts for a complex-phase
  /// representative — the kernel's own rule (`intersectionCandidates`
  /// used the same one to re-anchor orderings before Phase 137 made the
  /// re-anchor a no-op).
  LineEq? toOrientedLineEq([double eps = projectiveEpsilon]) {
    final projected = toLineEq(eps);
    if (projected == null) return null;
    final d = projected.direction;
    final reNorm = a.re * a.re + b.re * b.re;
    final imNorm = a.im * a.im + b.im * b.im;
    final along = reNorm >= imNorm
        ? d.x * b.re - d.y * a.re
        : d.x * b.im - d.y * a.im;
    return along < 0
        ? LineEq(-projected.a, -projected.b, -projected.c)
        : projected;
  }

  @override
  bool operator ==(Object other) =>
      other is ProjLine && other.a == a && other.b == b && other.c == c;

  @override
  int get hashCode => Object.hash(a, b, c);

  @override
  String toString() => 'ProjLine($a : $b : $c)';
}
