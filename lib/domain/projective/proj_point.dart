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

  /// The same projective point with any *global phase* removed: divides
  /// by the unit phase of the largest-magnitude coordinate, leaving scale
  /// alone. Identity on the zero triple.
  ///
  /// Weaker than [normalized] on purpose, and the difference is
  /// load-bearing (Phase 125): dividing by the unit *phase* is exact for
  /// every case that matters — a real triple divides by ±1 and an
  /// i-scaled one by ±i, both bit-exact — where dividing by the component
  /// itself rescales and rounds. A CK construction takes a square root of
  /// a form that is negative inside the absolute and hands back real
  /// elements scaled by `i`, so removing that phase is what makes the
  /// answer real again; a canonicalization that turned an exact zero into
  /// 2.7e-17 in the process would lose every right angle it touched.
  ProjPoint get dephased {
    var pivot = x;
    if (y.abs2 > pivot.abs2) pivot = y;
    if (w.abs2 > pivot.abs2) pivot = w;
    if (pivot.abs2 == 0) return this;
    final magnitude = pivot.abs;
    final phase = Complex(pivot.re / magnitude, pivot.im / magnitude);
    return ProjPoint(x / phase, y / phase, w / phase);
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

/// The harmonic conjugate of [c] with respect to [a] and [b] — the fourth
/// point `D` on the line AB with cross-ratio `(A,B;C,D) = −1`.
///
/// Division-free: writing `C = α·A + β·B`, the conjugate is
/// `D = α·A − β·B`, and `α`, `β` are read off cross products against the
/// join (`C×B = α·(A×B)`, `C×A = −β·(A×B)`) at the join's
/// largest-magnitude coordinate. Polynomial in all three inputs, so the
/// projective value is invariant under rescaling any of them.
///
/// `C` at the midpoint of AB conjugates to the join's point at infinity;
/// `C` at an endpoint is its own conjugate. Only meaningful for [c] on the
/// line AB — for other inputs the result is still *a* point of AB, and
/// callers wanting V1's semantics must gate on incidence themselves.
/// Degenerate inputs (projectively equal [a] and [b], zero triples) give
/// unreliable output rather than an error; callers guard with
/// [ProjPoint.closeTo] first, per the layer convention on coincidence.
ProjPoint harmonicConjugateOf(ProjPoint a, ProjPoint b, ProjPoint c) {
  final n = a.join(b);
  final cb = c.join(b);
  final ca = c.join(a);
  final ns = [n.a, n.b, n.c];
  final cbs = [cb.a, cb.b, cb.c];
  final cas = [ca.a, ca.b, ca.c];
  var i = 0;
  if (ns[1].abs2 > ns[i].abs2) i = 1;
  if (ns[2].abs2 > ns[i].abs2) i = 2;
  final alpha = cbs[i];
  final beta = cas[i];
  return ProjPoint(
    a.x * alpha + b.x * beta,
    a.y * alpha + b.y * beta,
    a.w * alpha + b.w * beta,
  );
}
