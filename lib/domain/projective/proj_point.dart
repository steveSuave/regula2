import 'dart:math' as math;

import '../math/vec2.dart';
import 'complex.dart';
import 'proj_line.dart';
import 'tolerances.dart';

/// A point of the complex projective plane, in homogeneous coordinates
/// `[x : y : w]`.
///
/// Conventions:
/// - The affine point `(x, y)` lifts to `[x, y, 1]` ([ProjPoint.lift]).
/// - Triples differing by a nonzero complex scalar are the same point —
///   compare with [closeTo]; `==` is exact component equality.
/// - `w ≈ 0` is a point at infinity in direction `(x, y)`; [isFinite] asks
///   that question at a tolerance, and [toVec2] is the total projection back
///   to the affine chart (null when the point is not drawable: complex or
///   infinite). That null is what `isDefined` projects to at the kind layer.
/// - The zero triple is not a point. Predicates return false for it (even
///   [closeTo] against itself) and [normalized] returns it unchanged;
///   operations stay total and let degenerate values propagate rather than
///   throwing.
///
/// Every operation is bilinear/holomorphic in the coordinates — there is no
/// conjugation anywhere. Holomorphy is what analytic continuation
/// (Phase 113+) requires; don't "fix" [incidence] to a Hermitian product.
class ProjPoint {
  const ProjPoint(this.x, this.y, this.w);

  /// The point with real homogeneous coordinates `[x, y, w]`.
  ProjPoint.real(double x, double y, [double w = 1])
      : this(Complex(x), Complex(y), Complex(w));

  /// Lifts the affine point [p] to `[p.x, p.y, 1]`.
  ProjPoint.lift(Vec2 p) : this(Complex(p.x), Complex(p.y), Complex.one);

  final Complex x;
  final Complex y;
  final Complex w;

  /// Squared Euclidean norm of the coordinate triple. Representation-level,
  /// not projective — use it to build relative tolerances.
  double get norm2 => x.abs2 + y.abs2 + w.abs2;

  /// Whether this is the zero triple (no point at all).
  bool get isZero => norm2 == 0;

  /// The same point with every coordinate multiplied by [k] — the projective
  /// identity when `k ≠ 0`.
  ProjPoint scaledBy(Complex k) => ProjPoint(x * k, y * k, w * k);

  /// Chart normalization: divides by the largest-magnitude coordinate, so
  /// that coordinate becomes exactly 1 and the others have magnitude ≤ 1.
  /// Removes both scale and phase (which is what makes [isReal]
  /// scale-invariant); identity on the zero triple.
  ProjPoint get normalized {
    var d = x;
    if (y.abs2 > d.abs2) d = y;
    if (w.abs2 > d.abs2) d = w;
    if (d.abs2 == 0) return this;
    return ProjPoint(x / d, y / d, w / d);
  }

  /// The line through this point and [other] (cross product of the triples).
  /// The zero line when the points are projectively equal.
  ProjLine join(ProjPoint other) => ProjLine(
        y * other.w - w * other.y,
        w * other.x - x * other.w,
        x * other.y - y * other.x,
      );

  /// The incidence form `⟨p, l⟩ = x·a + y·b + w·c` — bilinear, zero exactly
  /// when the point lies on the line.
  Complex incidence(ProjLine l) => x * l.a + y * l.b + w * l.c;

  /// Whether this point lies on [l], relatively: `|⟨p, l⟩| ≤ eps·|p|·|l|`.
  /// False when either triple is zero.
  bool isIncidentTo(ProjLine l, [double eps = projectiveEpsilon]) {
    final s2 = norm2 * l.norm2;
    if (s2 == 0) return false;
    return incidence(l).abs2 <= eps * eps * s2;
  }

  /// Projective equality: whether the triples are proportional up to [eps],
  /// measured relatively — the cross product is small against `|p|·|q|`.
  /// False when either triple is zero.
  bool closeTo(ProjPoint other, [double eps = projectiveEpsilon]) {
    if (isZero || other.isZero) return false;
    return join(other).norm2 <= eps * eps * norm2 * other.norm2;
  }

  /// Whether this point is real up to a complex scalar: after [normalized]
  /// (which removes phase), every coordinate is real within [eps]. Points at
  /// infinity can be real; the zero triple is not.
  bool isReal([double eps = projectiveEpsilon]) {
    if (isZero) return false;
    final n = normalized;
    return n.x.isRealWithin(eps) &&
        n.y.isRealWithin(eps) &&
        n.w.isRealWithin(eps);
  }

  /// Whether this point is finite in the affine chart: `|w|` is not
  /// negligible against `max(|x|, |y|)`, relatively at [eps]. False for the
  /// zero triple and for NaN/infinite coordinates.
  bool isFinite([double eps = projectiveEpsilon]) {
    if (!x.isFinite || !y.isFinite || !w.isFinite) return false;
    final m = math.max(x.abs2, y.abs2);
    if (m == 0) return w.abs2 > 0;
    return w.abs2 > eps * eps * m;
  }

  /// Projection to the affine chart — the rendering question. Returns
  /// `(x/w, y/w)` when the point is real and finite (at [eps]), else null.
  Vec2? toVec2([double eps = projectiveEpsilon]) {
    if (!isReal(eps) || !isFinite(eps)) return null;
    return Vec2((x / w).re, (y / w).re);
  }

  @override
  bool operator ==(Object other) =>
      other is ProjPoint && other.x == x && other.y == y && other.w == w;

  @override
  int get hashCode => Object.hash(x, y, w);

  @override
  String toString() => 'ProjPoint($x : $y : $w)';
}
