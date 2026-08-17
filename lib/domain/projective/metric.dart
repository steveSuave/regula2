/// Metric constructions in the complex projective plane, against an
/// [Absolute] (PLAN §"M-CK — Cayley–Klein").
///
/// The projective plane has no parallels, midpoints or right angles of its
/// own; those come from a distinguished conic. Under the Euclidean
/// absolute the *affine* structure (directions, parallels, midpoints,
/// centroids) comes from the line at infinity `[0 : 0 : 1]` and the
/// *Euclidean* structure (perpendicularity) from the circular points I, J
/// on it — a perpendicular direction is the conjugate of a direction
/// w.r.t. {I, J}, which for `[d : e : 0]` is `[−e : d : 0]`. Both are
/// special cases of "conjugate with respect to the absolute", which is why
/// most of this file generalizes by substitution rather than by rewriting.
///
/// **Two constructions here are the same construction, dually** — see
/// [midpointOf] and [twoLineBisectorOf]. A midpoint is the pair harmonic
/// to `{P, Q}` and to the absolute's two points on the line `PQ`; an angle
/// bisector is the pair harmonic to `{ℓ, m}` and to the two tangents to
/// the absolute through their meet. The same algebra solves both, in the
/// point conic and in the dual respectively, and each collapses to the
/// familiar Euclidean formula when the absolute degenerates.
///
/// **Euclidean keeps its own formulas where they are exact**, per the rule
/// Phases 122 and 124 set: the general form is the definition, the
/// specialization is what runs. Here it is not only about speed — the
/// general form picks a *pair* and the Euclidean representative-based
/// formula picks which member of it is "the" midpoint (the finite one),
/// which is a ray concept the projective pair does not carry.
///
/// Everything here is polynomial in the inputs' homogeneous coordinates —
/// holomorphic, no conjugation, no division — so each function is
/// multilinear in its arguments: scaling an input scales the output, and
/// the projective value is invariant. Degenerate inputs propagate as zero
/// triples instead of throwing, per the layer convention.
library;

import 'absolute.dart';
import 'complex.dart';
import 'proj_line.dart';
import 'proj_point.dart';

/// The point at infinity of [l] — its meet with the line at infinity,
/// `[b : −a : 0]`, the direction of the affine line. The zero triple when
/// [l] is the line at infinity itself (or zero).
ProjPoint directionOf(ProjLine l) => ProjPoint(l.b, -l.a, Complex.zero);

/// The pole of [l] with respect to [absolute] — under the Euclidean one,
/// the point at infinity `[a : b : 0]` of the directions perpendicular to
/// [l], the conjugate of [directionOf] w.r.t. the circular points I, J.
///
/// This is [Absolute.poleOf] under its geometric name, and the single
/// operation the whole perpendicularity family reduces to. The zero
/// triple when [l] is the absolute's own degenerate direction (for
/// Euclidean, the line at infinity) or zero.
ProjPoint normalDirectionOf(
  ProjLine l, [
  Absolute absolute = Absolute.euclidean,
]) => absolute.isEuclidean
    ? ProjPoint(l.a, l.b, Complex.zero)
    : absolute.poleOf(l);

/// The line through [p] parallel to [l]: the join of [p] with [l]'s point
/// at infinity. The zero triple when [p] *is* that point at infinity (any
/// parallel through it would do) or [l] is the line at infinity.
///
/// **Euclidean only, and refused rather than approximated elsewhere** —
/// the zero triple under a proper absolute (PLAN §"Four tiers of kind").
/// "The parallel through `P`" is a *uniqueness*, and it is precisely the
/// uniqueness hyperbolic geometry exists to deny: through a point off a
/// line there pass infinitely many lines missing it, and exactly two
/// limiting ones that meet it on the absolute. There is no line here to
/// return, so returning one would be inventing an answer. Elliptic
/// geometry denies it from the other side — every two lines meet, so
/// there are no parallels at all.
///
/// The parameter is taken rather than the caller checking, so that the
/// refusal lives with the construction it is about.
ProjLine parallelThrough(
  ProjPoint p,
  ProjLine l, [
  Absolute absolute = Absolute.euclidean,
]) => absolute.isEuclidean
    ? p.join(directionOf(l))
    : const ProjLine(Complex.zero, Complex.zero, Complex.zero);

/// The line through [p] perpendicular to [l] with respect to [absolute]:
/// the join of [p] with the pole of [l].
///
/// **Generalizes verbatim** — the Euclidean formula is already this
/// construction with {I, J} substituted in, which is the audit's
/// structural result (PLAN §"The audit"). The zero triple when [p] is
/// that pole itself, or when [l] is the absolute's degenerate line.
ProjLine perpendicularThrough(
  ProjPoint p,
  ProjLine l, [
  Absolute absolute = Absolute.euclidean,
]) => p.join(normalDirectionOf(l, absolute));

/// The midpoint of [p] and [q] with respect to [absolute].
///
/// Under the Euclidean absolute this is the affine `(p + q) / 2`
/// homogenized, `[x₁w₂ + x₂w₁ : y₁w₂ + y₂w₁ : 2·w₁w₂]` — bilinear, so
/// well-defined projectively. The midpoint of a point with itself is the
/// point; the midpoint with a point at infinity is that point at infinity
/// (the affine limit); the midpoint of two points at infinity is the zero
/// triple.
///
/// **The general construction, and why the Euclidean one is a case of
/// it.** A midpoint of `P`, `Q` is a point of the pair `{M₊, M₋}`
/// harmonic both to `{P, Q}` and to the two points where the line `PQ`
/// meets the absolute. Parameterizing that line as `X(t) = P + t·Q` (so
/// `P` is `t = 0` and `Q` is `t = ∞`), the absolute meets it where
/// `⟨Q,Q⟩t² + 2⟨P,Q⟩t + ⟨P,P⟩ = 0`; being harmonic to `{0, ∞}` forces
/// `M₋ = −M₊` in `t`, and harmonic to the roots then forces
/// `t² = t₁t₂ = ⟨P,P⟩/⟨Q,Q⟩`. So
///
/// ```
/// M± = √⟨Q,Q⟩·P ± √⟨P,P⟩·Q
/// ```
///
/// Under the Euclidean absolute `⟨P,P⟩ = w²`, and the formula reads
/// `w_Q·P ± w_P·Q` — the affine midpoint, together with the point at
/// infinity in direction `P − Q`. That second root is the *external*
/// midpoint, and it being at infinity is exactly why Euclidean geometry
/// seems to have only one.
///
/// **Which member is "the" midpoint is a ray concept, not a projective
/// one**, so the Euclidean branch here uses the representatives' `w`
/// rather than `√(w²)`: the two differ by a sign whenever `w < 0`, and
/// `√` would return `|w|` and silently pick the other member. Same
/// caveat as [angleBisectorOf]'s internal/external selection, and the
/// reason this function keeps its exact Euclidean form rather than
/// routing through the general one. [midpointPairOf] exposes both.
ProjPoint midpointOf(
  ProjPoint p,
  ProjPoint q, [
  Absolute absolute = Absolute.euclidean,
]) => absolute.isEuclidean
    ? ProjPoint(
        p.x * q.w + q.x * p.w,
        p.y * q.w + q.y * p.w,
        const Complex(2) * (p.w * q.w),
      )
    : midpointPairOf(p, q, absolute).$1;

/// Both midpoints of [p] and [q] with respect to [absolute] — the pair
/// harmonic to `{p, q}` and to the absolute's two points on their join.
///
/// `(√⟨Q,Q⟩·P + √⟨P,P⟩·Q, √⟨Q,Q⟩·P − √⟨P,P⟩·Q)`. See [midpointOf] for the
/// derivation. The roots are principal, so this is holomorphic away from
/// their branch cuts and only *piecewise* homogeneous — rescaling an
/// input can exchange the two members, the pair being what is projective.
(ProjPoint, ProjPoint) midpointPairOf(
  ProjPoint p,
  ProjPoint q, [
  Absolute absolute = Absolute.euclidean,
]) {
  final sp = absolute.evaluatePoint(p).sqrt;
  final sq = absolute.evaluatePoint(q).sqrt;
  return (
    ProjPoint(sq * p.x + sp * q.x, sq * p.y + sp * q.y, sq * p.w + sp * q.w),
    ProjPoint(sq * p.x - sp * q.x, sq * p.y - sp * q.y, sq * p.w - sp * q.w),
  );
}

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
ProjLine perpendicularBisectorOf(
  ProjPoint p,
  ProjPoint q, [
  Absolute absolute = Absolute.euclidean,
]) => midpointOf(p, q, absolute).join(normalDirectionOf(p.join(q), absolute));

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
ProjLine angleBisectorOf(
  ProjPoint a,
  ProjPoint v,
  ProjPoint b, [
  Absolute absolute = Absolute.euclidean,
]) {
  if (!absolute.isEuclidean) {
    // A ray bisector is a wedge concept and the projective pair is what
    // generalizes, so a non-Euclidean caller goes through the dual
    // construction on the two arms' carriers and takes branch 0.
    return twoLineBisectorOf(v.join(a), v.join(b), 0, absolute);
  }
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
/// perpendicular pair through their meet, with respect to [absolute].
///
/// **This is [midpointOf]'s construction, dually**: the pair harmonic to
/// `{ℓ₁, ℓ₂}` and to the two tangents to the absolute through their meet,
/// which the same algebra solves in the dual conic —
/// `B± = √⟨ℓ₂,ℓ₂⟩*·ℓ₁ ± √⟨ℓ₁,ℓ₁⟩*·ℓ₂`. Under the Euclidean absolute
/// `⟨ℓ,ℓ⟩*` is `a² + b²`, and that is exactly the √-unitization below —
/// so the existing formula was already the general one with {I, J}
/// substituted in, which is why this generalizes without changing shape. [branch] 0 bisects along
/// `d̂1 + d̂2` of the *representatives'* directions (via the same
/// √-unitization as [angleBisectorOf]), 1 along `d̂1 − d̂2`.
///
/// The selection flips with either representative's sign — callers
/// holding V1's branch guarantee anchor the representatives to their
/// affine orientations first. Parallel carriers degenerate naturally:
/// one branch's direction vanishes, the other joins the meet at infinity
/// with itself — both give the zero line, as do coincident carriers
/// (zero meet).
ProjLine twoLineBisectorOf(
  ProjLine l1,
  ProjLine l2,
  int branch, [
  Absolute absolute = Absolute.euclidean,
]) {
  final s1 = absolute.evaluateLine(l1).sqrt;
  final s2 = absolute.evaluateLine(l2).sqrt;
  if (!absolute.isEuclidean) {
    // The dual of the midpoint: the pair harmonic to {ℓ₁, ℓ₂} and to the
    // two tangents to the absolute through their meet, by the same
    // algebra in the dual conic. See [midpointOf] for the derivation.
    return branch == 0
        ? ProjLine(
            s2 * l1.a + s1 * l2.a,
            s2 * l1.b + s1 * l2.b,
            s2 * l1.c + s1 * l2.c,
          )
        : ProjLine(
            s2 * l1.a - s1 * l2.a,
            s2 * l1.b - s1 * l2.b,
            s2 * l1.c - s1 * l2.c,
          );
  }
  // Euclidean: the same pair, but built through the meet and a direction
  // so that a *parallel* pair degenerates the way V1's callers expect
  // (one branch's direction vanishes, the other joins the meet at
  // infinity with itself — both the zero line). The general form above
  // would hand back ℓ∞ there instead.
  final crossing = l1.meet(l2);
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
