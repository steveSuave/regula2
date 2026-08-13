/// Circle constructions as projective conics.
///
/// A real circle is exactly a real conic through the circular points I and
/// J (`conic_matrix.dart`), so every Euclidean circle construction has a
/// polynomial formula in homogeneous coordinates. Everything here follows
/// the layer conventions (`euclidean.dart`): holomorphic — no conjugation,
/// no division, no square roots — and multihomogeneous in each argument,
/// so rescaling an input rescales the output and the projective value is
/// invariant. Degenerate inputs propagate as the zero matrix or a
/// degenerate conic (rank < 3) instead of throwing; in particular the
/// classical "no circle exists" configurations become *degenerate conics*
/// — a collinear circumcircle is the line-pair (line, ℓ∞), a rim at
/// infinity gives the double line ℓ∞ — which project to a null `CircleEq`
/// (undefined for rendering) while keeping a projective value.
///
/// Exactness note: with finite unit-`w` inputs every constructor puts the
/// (equal) quadratic entries `xx = yy` at a product of the parents' `w`s,
/// so `ConicMatrix.toCircleEq`'s raw-ratio projection recovers integer
/// centers and radii exactly — tests may compare those with `==`.
library;

import 'complex.dart';
import 'conic_matrix.dart';
import 'proj_line.dart';
import 'proj_point.dart';

/// The zero-radius circle at [a]: the (complex) pair of isotropic lines
/// through [a] — the joins of [a] with I and J — whose only real point is
/// [a] itself. Rank 2 for a finite [a].
///
/// For [a] at infinity this degenerates to the double line ℓ∞ scaled by
/// `x² + y²`, hence the zero matrix in the isotropic directions (I, J
/// themselves); for the zero triple it is the zero matrix.
ConicMatrix pointCircleAt(ProjPoint a) {
  final w2 = a.w * a.w;
  return ConicMatrix(
    w2,
    Complex.zero,
    w2,
    -(a.x * a.w),
    -(a.y * a.w),
    a.x * a.x + a.y * a.y,
  );
}

/// The circle around [center] with the given real [radius] —
/// [pointCircleAt] inflated by `radius²·w²`:
/// `(wx − cx·w)² + (wy − cy·w)² − radius²·wc²·w² = 0`.
///
/// Quadratic in [center]. A center at infinity gives the double line ℓ∞
/// scaled by `x² + y²` (zero matrix in the isotropic directions), as with
/// [pointCircleAt]. Negative [radius] is not rejected — the formula only
/// sees `radius²` — and a non-finite radius poisons the entries to
/// non-finite values (rank 0) rather than throwing.
ConicMatrix circleWithRadius(ProjPoint center, double radius) {
  final w2 = center.w * center.w;
  return ConicMatrix(
    w2,
    Complex.zero,
    w2,
    -(center.x * center.w),
    -(center.y * center.w),
    center.x * center.x + center.y * center.y - w2.scale(radius * radius),
  );
}

/// The circle around [center] through [rim].
///
/// Bidegree (2, 2) in ([center], [rim]). A [rim] at infinity gives the
/// double line ℓ∞ (an "infinite radius" circle); a [center] at infinity
/// gives the exact zero matrix — no circle has its center at infinity.
/// Coincident center and rim give [pointCircleAt] the shared point.
ConicMatrix circleThrough(ProjPoint center, ProjPoint rim) {
  final rw2 = rim.w * rim.w;
  final quad = rw2 * (center.w * center.w);
  final dx = center.w * rim.x - center.x * rim.w;
  final dy = center.w * rim.y - center.y * rim.w;
  return ConicMatrix(
    quad,
    Complex.zero,
    quad,
    -(rw2 * (center.w * center.x)),
    -(rw2 * (center.w * center.y)),
    rw2 * (center.x * center.x + center.y * center.y) - (dx * dx + dy * dy),
  );
}

/// The compass circle: around [center], with the distance from [p] to [q]
/// as radius — `|pq|²` carried as the numerator/denominator pair of a
/// squared distance, so the formula stays polynomial.
///
/// Bidegree (2, 2, 2) in the three arguments. Coincident [p] and [q] give
/// [pointCircleAt] the center; [p] or [q] at infinity gives the double
/// line ℓ∞ (infinite radius); a [center] at infinity gives the double
/// line ℓ∞ scaled by the distance denominator.
ConicMatrix compassCircleOf(ProjPoint center, ProjPoint p, ProjPoint q) {
  final n = _squaredDistanceNumerator(p, q);
  final wpq = p.w * q.w;
  final d = wpq * wpq;
  final quad = d * (center.w * center.w);
  return ConicMatrix(
    quad,
    Complex.zero,
    quad,
    -(d * (center.w * center.x)),
    -(d * (center.w * center.y)),
    d * (center.x * center.x + center.y * center.y) - n * (center.w * center.w),
  );
}

/// The circle with the span from [p] to [q] as a diameter — the locus of
/// X with `(X − p)·(X − q) = 0`, homogenized bilinearly:
/// `(w₁x − x₁w)(w₂x − x₂w) + (w₁y − y₁w)(w₂y − y₂w) = 0`.
///
/// Bilinear in each point. Coincident points give [pointCircleAt] the
/// shared point; one point at infinity gives the line pair of ℓ∞ with the
/// perpendicular to that direction through the finite point (the limit
/// shape — a Thales angle at infinity is a right angle); both at infinity
/// give the double line ℓ∞, or the zero matrix for perpendicular
/// directions.
ConicMatrix diameterCircleOf(ProjPoint p, ProjPoint q) => ConicMatrix(
  p.w * q.w,
  Complex.zero,
  p.w * q.w,
  (p.x * q.w + q.x * p.w).scale(-0.5),
  (p.y * q.w + q.y * p.w).scale(-0.5),
  p.x * q.x + p.y * q.y,
);

/// The circle through [a], [b] and [c] (their circumcircle), via the
/// classical determinant
///
/// ```
/// | x² + y²   xw   yw   w² |
/// |   s₁      x₁w₁ y₁w₁ w₁²| = 0 ,   sᵢ = xᵢ² + yᵢ²
/// |   s₂      …             |
/// |   s₃      …             |
/// ```
///
/// expanded along the first row into 3×3 minors — quadratic in each point.
///
/// Collinear (distinct, finite) points zero the quadratic minor, giving
/// the degenerate line pair (their line, ℓ∞) — the V2 replacement for
/// "undefined" (PLAN §Migration). Two coincident points make two rows
/// proportional: the exact zero matrix. One point at infinity puts three
/// of the conic's five points (it, I, J) on ℓ∞, so ℓ∞ is a component:
/// the line pair (line through the two finite points, ℓ∞).
ConicMatrix circumcircleOf(ProjPoint a, ProjPoint b, ProjPoint c) {
  final s1 = a.x * a.x + a.y * a.y;
  final s2 = b.x * b.x + b.y * b.y;
  final s3 = c.x * c.x + c.y * c.y;
  final x1 = a.x * a.w, y1 = a.y * a.w, w1 = a.w * a.w;
  final x2 = b.x * b.w, y2 = b.y * b.w, w2 = b.w * b.w;
  final x3 = c.x * c.w, y3 = c.y * c.w, w3 = c.w * c.w;
  Complex det(
    Complex a1,
    Complex a2,
    Complex a3,
    Complex b1,
    Complex b2,
    Complex b3,
    Complex c1,
    Complex c2,
    Complex c3,
  ) =>
      a1 * (b2 * c3 - b3 * c2) -
      a2 * (b1 * c3 - b3 * c1) +
      a3 * (b1 * c2 - b2 * c1);
  final m0 = det(x1, y1, w1, x2, y2, w2, x3, y3, w3);
  final m1 = det(s1, y1, w1, s2, y2, w2, s3, y3, w3);
  final m2 = det(s1, x1, w1, s2, x2, w2, s3, x3, w3);
  final m3 = det(s1, x1, y1, s2, x2, y2, s3, x3, y3);
  return ConicMatrix(
    m0,
    Complex.zero,
    m0,
    (-m1).scale(0.5),
    m2.scale(0.5),
    -m3,
  );
}

/// The Apollonius circle over [a] and [b] with the distance ratio
/// supplied by [c]: the locus of P with `|PA|·|CB| = |PB|·|CA|`, i.e.
/// `|PA|² · |CB|² − |PB|² · |CA|² = 0` — squared distances as
/// [pointCircleAt] quadratic forms, so the formula is polynomial:
/// bidegree (2, 2, 2).
///
/// [c] equidistant from [a] and [b] cancels the quadratic part, giving the
/// degenerate line pair (perpendicular bisector of ab, ℓ∞) — the V2
/// replacement for "undefined". [c] coincident with [a] (resp. [b]) gives
/// the point circle at [a] (resp. [b]); [a] coincident with [b] gives the
/// exact zero matrix (rescaled near-duplicates leave noise — guard with
/// `closeTo` first, as with `carrierThrough`).
ConicMatrix apolloniusCircleOf(ProjPoint a, ProjPoint b, ProjPoint c) {
  final nca = _squaredDistanceNumerator(c, a);
  final ncb = _squaredDistanceNumerator(c, b);
  final pa = pointCircleAt(a);
  final pb = pointCircleAt(b);
  return ConicMatrix(
    pa.xx * ncb - pb.xx * nca,
    Complex.zero,
    pa.yy * ncb - pb.yy * nca,
    pa.xw * ncb - pb.xw * nca,
    pa.yw * ncb - pb.yw * nca,
    pa.ww * ncb - pb.ww * nca,
  );
}

/// The numerator of the squared distance `|pq|²` over the denominator
/// `(w₁w₂)²`: `(x₁w₂ − x₂w₁)² + (y₁w₂ − y₂w₁)²`. Zero exactly for equal
/// representatives; proportional (coincident) points cancel only
/// algebraically, not bitwise.
Complex _squaredDistanceNumerator(ProjPoint p, ProjPoint q) {
  final dx = p.x * q.w - q.x * p.w;
  final dy = p.y * q.w - q.y * p.w;
  return dx * dx + dy * dy;
}

/// The radical axis of the circle-shaped conics [a] and [b] — the line of
/// points with equal power to both circles, carrying their common chord
/// when they cross.
///
/// It is the linear part of the unique pencil member `b.xx·A − a.xx·B`
/// whose quadratic block cancels (exactly, when both inputs have a
/// circle's exact coefficient shape — which every constructor in this
/// file emits): that member is the degenerate line pair (axis, ℓ∞).
/// Bilinear in the two matrices, so the projective value is invariant
/// under rescaling either. On unit-quadratic lifts the coefficients match
/// V1 `radicalAxis` exactly, orientation included.
///
/// Total, with the continuous limits: concentric circles give ℓ∞ (equal
/// radii and equal centers only cancel to the zero triple when the
/// matrices are exactly proportional); a degenerate line-conic input
/// (zero quadratic block) gives that conic's own linear part — the limit
/// of the axis as a circle flattens onto its line.
ProjLine radicalAxisOf(ConicMatrix a, ConicMatrix b) => ProjLine(
  (b.xx * a.xw - a.xx * b.xw).scale(2),
  (b.xx * a.yw - a.xx * b.yw).scale(2),
  b.xx * a.ww - a.xx * b.ww,
);
