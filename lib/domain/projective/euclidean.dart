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
