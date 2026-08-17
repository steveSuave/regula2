/// General conic constructions — the classical constructors that are not
/// `circles.dart`'s and not the purely projective five-point solve
/// (`ConicMatrix.throughFivePoints`).
///
/// Both constructors here are **metric**: a focus, a directrix, an
/// eccentricity and a pair of foci are all Euclidean data, so unlike five
/// points they are exactly what M-CK has to re-found. PLAN §"The conic
/// constructors, and where the metric enters" says which is which, and
/// this library is where the two answers sit side by side:
///
/// - [focalConicOf] is metric but still **polynomial**, so it follows the
///   layer conventions in full (`metric.dart`): holomorphic — no
///   conjugation, no division, no square roots — and multihomogeneous in
///   each argument. Its whole Euclidean content is one coefficient.
/// - [bifocalConicOf] cannot be: `|PF₁| ± |PF₂|` is a sum of square roots
///   of real distances, which has no polynomial form in the homogeneous
///   data. It therefore takes **chart points** and lives at the Phase 112
///   metric boundary, like the measurement kinds.
library;

import '../math/vec2.dart';
import 'complex.dart';
import 'conic_matrix.dart';
import 'proj_line.dart';
import 'proj_point.dart';

/// The conic of points whose distance to the focus [f] is [eccentricity]
/// times their distance to the directrix [l] — a parabola at `e = 1`, an
/// ellipse below it, a hyperbola above.
///
/// Clearing both denominators of `|XF|² = e²·d(X, ℓ)²` gives
///
/// ```
/// (a²+b²)·[(x·f_w − f_x·w)² + (y·f_w − f_y·w)²] − e²·f_w²·(a·x+b·y+c·w)²
/// ```
///
/// polynomial in `X`, in `F`, in `ℓ` and in `e`, and covariant under
/// rescaling of [f] (by `μ²`) and of [l] (by `λ²`) independently — so the
/// projective value is invariant in each.
///
/// **The Euclidean structure is the single coefficient `a² + b²`**: the
/// directrix evaluated against the degenerate dual conic `diag(1, 1, 0)`,
/// which is the dual of the circular-point pair {I, J}. Every other term
/// is incidence, so that one factor is the whole of the geometry here and
/// M-CK's only substitution in this constructor.
///
/// Total, with degenerate inputs propagating rather than throwing: a focus
/// at infinity (`f_w = 0`) collapses the form onto ℓ∞ doubled, an
/// isotropic directrix (one through I or J, `a² + b² = 0`) kills the
/// metric term and leaves the directrix's own square, and the zero triple
/// in either argument gives the zero matrix.
ConicMatrix focalConicOf(ProjPoint f, ProjLine l, Complex eccentricity) {
  // k = ℓᵀ·diag(1,1,0)·ℓ — the metric, and the only Euclidean term here.
  final k = l.a * l.a + l.b * l.b;
  final m = eccentricity * eccentricity * f.w * f.w;
  final kww = k * f.w * f.w;
  final kw = k * f.w;
  return ConicMatrix(
    kww - m * l.a * l.a,
    -(m * l.a * l.b),
    kww - m * l.b * l.b,
    -(kw * f.x) - m * l.a * l.c,
    -(kw * f.y) - m * l.b * l.c,
    k * (f.x * f.x + f.y * f.y) - m * l.c * l.c,
  );
}

/// The conic with foci [f1] and [f2] through [p] — the ellipse
/// `|XF₁| + |XF₂| = |PF₁| + |PF₂|` when [difference] is false, the
/// hyperbola `‖XF₁| − |XF₂‖ = ‖PF₁| − |PF₂‖` when it is true.
///
/// **Chart points, deliberately.** The semi-axis `a` is a sum of square
/// roots of distances and has no polynomial form in homogeneous
/// coordinates, so this constructor sits at the metric boundary of PLAN
/// §Architecture alongside the measurement kinds: callers project
/// the parents themselves and pass the affine points, and everything
/// downstream of the returned matrix is projective again.
///
/// With `O` the centre, `D = F₂ − F₁` and `c² = |D|²/4`, the conic is
///
/// ```
/// (a² − c²)·[(X−O)·D]² + a²·[(X−O)·D^⊥]² − 4c²a²(a² − c²) = 0
/// ```
///
/// — **one formula for both branches**. The sum branch always has
/// `a ≥ c` and the difference branch `a ≤ c`, both by the triangle
/// inequality, so [difference] chooses a definition rather than a case in
/// the algebra, and each branch's boundary is a genuine limit of it:
/// `a = c` ([p] on the segment `F₁F₂`, or on the focal line beyond it)
/// doubles the major axis, and `a = 0` ([p] equidistant from the foci)
/// doubles the perpendicular bisector — which is exactly the set
/// `|XF₁| = |XF₂|` the difference branch asked for.
///
/// Coincident foci give the zero matrix: the branch has no meaning there,
/// and the circle through [p] is `CircleCenterPoint`'s job rather than a
/// limit for this constructor to invent. Callers guard the case before
/// projecting (the `carrierThrough` convention), so the degeneracy is a
/// kind's decision and not a silent zero.
ConicMatrix bifocalConicOf(
  Vec2 f1,
  Vec2 f2,
  Vec2 p, {
  required bool difference,
}) {
  final d = f2 - f1;
  final centre = (f1 + f2) / 2;
  final cSquared = d.normSquared / 4;
  final r1 = p.distanceTo(f1);
  final r2 = p.distanceTo(f2);
  final semiAxis = (difference ? (r1 - r2).abs() : r1 + r2) / 2;
  final aSquared = semiAxis * semiAxis;
  final s = aSquared - cSquared;

  // (X−O)·D and (X−O)·D^⊥ as affine forms `(ux·x + uy·y + uw)`; the conic
  // is `s·U² + a²·V² + K`, so every entry is the same combination of the
  // two forms' coefficient products.
  final ux = d.x;
  final uy = d.y;
  final uw = -(centre.x * d.x + centre.y * d.y);
  final vx = -d.y;
  final vy = d.x;
  final vw = centre.x * d.y - centre.y * d.x;

  return ConicMatrix.coefficients(
    s * ux * ux + aSquared * vx * vx,
    2 * (s * ux * uy + aSquared * vx * vy),
    s * uy * uy + aSquared * vy * vy,
    2 * (s * ux * uw + aSquared * vx * vw),
    2 * (s * uy * uw + aSquared * vy * vw),
    s * uw * uw + aSquared * vw * vw - 4 * cSquared * aSquared * s,
  );
}
