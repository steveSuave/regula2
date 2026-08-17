/// Euclidean and affine constructions in the complex projective plane.
///
/// The projective plane has no parallels, midpoints or right angles of its
/// own; those come from distinguished objects. The *affine* structure
/// (directions, parallels, midpoints, centroids) comes from the line at
/// infinity `[0 : 0 : 1]`; the *Euclidean* structure (perpendicularity)
/// from the circular points I, J on it — a perpendicular direction is the
/// conjugate of a direction w.r.t. the degenerate conic {I, J}, which for
/// `[d : e : 0]` is `[−e : d : 0]`.
///
/// Everything here is polynomial in the inputs' homogeneous coordinates —
/// holomorphic, no conjugation, no division — so each function is
/// multilinear in its arguments: scaling an input scales the output, and
/// the projective value is invariant. Degenerate inputs propagate as zero
/// triples instead of throwing, per the layer convention.
library;

import 'complex.dart';
import 'proj_line.dart';
import 'proj_point.dart';

/// The point at infinity of [l] — its meet with the line at infinity,
/// `[b : −a : 0]`, the direction of the affine line. The zero triple when
/// [l] is the line at infinity itself (or zero).
ProjPoint directionOf(ProjLine l) => ProjPoint(l.b, -l.a, Complex.zero);

/// The point at infinity of the directions perpendicular to [l] —
/// `[a : b : 0]`, the conjugate of [directionOf] w.r.t. the circular
/// points I, J. The zero triple when [l] is the line at infinity (or zero).
ProjPoint normalDirectionOf(ProjLine l) => ProjPoint(l.a, l.b, Complex.zero);

/// The line through [p] parallel to [l]: the join of [p] with [l]'s point
/// at infinity. The zero triple when [p] *is* that point at infinity (any
/// parallel through it would do) or [l] is the line at infinity.
ProjLine parallelThrough(ProjPoint p, ProjLine l) => p.join(directionOf(l));

/// The line through [p] perpendicular to [l]: the join of [p] with the
/// conjugate direction. The zero triple when [p] is the conjugate point at
/// infinity itself or [l] is the line at infinity.
ProjLine perpendicularThrough(ProjPoint p, ProjLine l) =>
    p.join(normalDirectionOf(l));

/// The midpoint of [p] and [q] — the affine `(p + q) / 2` homogenized:
/// `[x₁w₂ + x₂w₁ : y₁w₂ + y₂w₁ : 2·w₁w₂]`.
///
/// Bilinear, so well-defined projectively. The midpoint of a point with
/// itself is the point; the midpoint with a point at infinity is that
/// point at infinity (the affine limit); the midpoint of two points at
/// infinity is the zero triple.
ProjPoint midpointOf(ProjPoint p, ProjPoint q) => ProjPoint(
  p.x * q.w + q.x * p.w,
  p.y * q.w + q.y * p.w,
  const Complex(2) * (p.w * q.w),
);

/// The centroid of [a], [b] and [c] — the affine `(a + b + c) / 3`
/// homogenized: `[Σ xᵢwⱼwₖ : Σ yᵢwⱼwₖ : 3·w₁w₂w₃]`.
///
/// Trilinear, so well-defined projectively. With one vertex at infinity
/// the centroid is that point at infinity (the affine limit); with two or
/// more it is the zero triple.
ProjPoint centroidOf(ProjPoint a, ProjPoint b, ProjPoint c) {
  final wbc = b.w * c.w;
  final wca = c.w * a.w;
  final wab = a.w * b.w;
  return ProjPoint(
    a.x * wbc + b.x * wca + c.x * wab,
    a.y * wbc + b.y * wca + c.y * wab,
    const Complex(3) * (a.w * wbc),
  );
}

/// The perpendicular bisector of [p] and [q]: the perpendicular to their
/// join through their midpoint. The zero triple when the points are
/// projectively equal (zero join) or both at infinity.
ProjLine perpendicularBisectorOf(ProjPoint p, ProjPoint q) =>
    midpointOf(p, q).join(normalDirectionOf(p.join(q)));

/// The internal bisector of the angle at [v] between the rays toward [a]
/// and [b].
///
/// The direction is `√(db·db)·da + √(da·da)·db` over the chart direction
/// numerators `da = (aₓ·v_w − vₓ·a_w, a_y·v_w − v_y·a_w)` (and likewise
/// `db`) — for real finite inputs that is `|da||db|·(d̂a + d̂b)`, V1's
/// internal-bisector sum of unit directions. Arms toward opposite rays
/// make the sum vanish; there the perpendicular of the difference takes
/// over (V1's conditioning rule, mirrored exactly, boundary included).
/// An arm at infinity contributes its direction — the ray toward it.
///
/// The square roots are principal, so this is holomorphic away from
/// their branch cuts (what tracing needs) but only *piecewise*
/// homogeneous: rescaling an input by a complex or negative scalar can
/// swap the internal and external bisectors — the bisector *pair* is
/// projective, the internal/external selection is a ray concept and is
/// not. Callers wanting V1's selection pass chart-canonical
/// representatives (`w = 1`, or [ProjPoint.normalized] at infinity).
/// Coincident or zero inputs give the zero line.
ProjLine angleBisectorOf(ProjPoint a, ProjPoint v, ProjPoint b) {
  final dax = a.x * v.w - v.x * a.w;
  final day = a.y * v.w - v.y * a.w;
  final dbx = b.x * v.w - v.x * b.w;
  final dby = b.y * v.w - v.y * b.w;
  final sa = (dax * dax + day * day).sqrt;
  final sb = (dbx * dbx + dby * dby).sqrt;
  final sumX = sb * dax + sa * dbx;
  final sumY = sb * day + sa * dby;
  final diffX = sb * dax - sa * dbx;
  final diffY = sb * day - sa * dby;
  // Magnitude comparison is classification, not kernel math — Hermitian
  // norms are fine here.
  final Complex dx, dy;
  if (sumX.abs2 + sumY.abs2 >= diffX.abs2 + diffY.abs2) {
    dx = sumX;
    dy = sumY;
  } else {
    dx = -diffY;
    dy = diffX;
  }
  return v.join(ProjPoint(dx, dy, Complex.zero));
}

/// One of the two bisectors of the wedges between [l1] and [l2] — a
/// perpendicular pair through their meet. [branch] 0 bisects along
/// `d̂1 + d̂2` of the *representatives'* directions (via the same
/// √-unitization as [angleBisectorOf]), 1 along `d̂1 − d̂2`.
///
/// The selection flips with either representative's sign — callers
/// holding V1's branch guarantee anchor the representatives to their
/// affine orientations first. Parallel carriers degenerate naturally:
/// one branch's direction vanishes, the other joins the meet at infinity
/// with itself — both give the zero line, as do coincident carriers
/// (zero meet).
ProjLine twoLineBisectorOf(ProjLine l1, ProjLine l2, int branch) {
  final crossing = l1.meet(l2);
  final s1 = (l1.a * l1.a + l1.b * l1.b).sqrt;
  final s2 = (l2.a * l2.a + l2.b * l2.b).sqrt;
  final dx = branch == 0 ? s2 * l1.b + s1 * l2.b : s2 * l1.b - s1 * l2.b;
  final dy = branch == 0 ? -(s2 * l1.a) - s1 * l2.a : s1 * l2.a - s2 * l1.a;
  return crossing.join(ProjPoint(dx, dy, Complex.zero));
}

/// The affine interpolation `p + t·(q − p)` homogenized:
/// `[(1−t)·x₁w₂ + t·x₂w₁ : (1−t)·y₁w₂ + t·y₂w₁ : w₁w₂]` — [midpointOf]
/// generalized to any real parameter ([t] is not clamped, so values
/// outside [0, 1] extrapolate).
///
/// Bilinear in the points, so well-defined projectively. With [q] at
/// infinity the result is [q] itself for `t ≠ 0` (the affine limit) and
/// the zero triple at `t = 0`; likewise with the roles swapped.
ProjPoint lerpOf(ProjPoint p, ProjPoint q, double t) => ProjPoint(
  (p.x * q.w).scale(1 - t) + (q.x * p.w).scale(t),
  (p.y * q.w).scale(1 - t) + (q.y * p.w).scale(t),
  p.w * q.w,
);
