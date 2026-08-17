/// Cayley–Klein measurement: distance and angle against an [Absolute]
/// (PLAN §"Angle unifies, distance does not").
///
/// Measurement is the whole of what a change of geometry changes, so this
/// is where M-CK actually lands. The classical formulas are cross-ratio
/// logarithms — for two points `P`, `Q`, the line `PQ` meets the absolute
/// at `M`, `N` and `d = c·log CR(P,Q;M,N)`; dually for two lines through a
/// vertex and the tangents to the absolute from it. Both are implemented
/// here through the **bilinear forms** those cross-ratios reduce to, which
/// need no root-finding, no branch choice and no complex logarithm.
///
/// The asymmetry between the two is the important part, and it is not an
/// implementation detail — it is the Cayley–Klein classification showing
/// up as a constraint on the code. Each of distance and angle is
/// independently *elliptic*, *parabolic* or *hyperbolic* according to how
/// the absolute meets the line (or pencil) being measured along:
///
/// | geometry   | distance   | angle    |
/// |------------|------------|----------|
/// | Euclidean  | parabolic  | elliptic |
/// | hyperbolic | hyperbolic | elliptic |
/// | elliptic   | elliptic   | elliptic |
///
/// So **angle substitutes and distance dispatches**. Every geometry here
/// has elliptic angle measure, and one formula covers all three. Distance
/// does not: under the Euclidean absolute a line meets the *doubled* line
/// at infinity in one point twice, a cross-ratio with a repeated point is
/// identically 1, and its logarithm is identically 0 — for every pair of
/// points, at every constant. Euclidean distance is not a cross-ratio, and
/// no amount of care recovers it from one; it needs the constant to
/// diverge exactly as the absolute degenerates. That is the same fact as
/// "Euclidean geometry has similar triangles": there is no absolute unit
/// of length, so length cannot be projective.
library;

import 'dart:math' as math;

import 'absolute.dart';
import 'complex.dart';
import 'proj_line.dart';
import 'proj_point.dart';
import 'tolerances.dart';

/// How an absolute meets the line or pencil a measurement runs along, and
/// so which formula that measurement takes.
enum MeasureKind {
  /// Two real meets: the measure is a real logarithm, unbounded, and the
  /// absolute is a genuine boundary you cannot reach. Hyperbolic distance.
  hyperbolic,

  /// One doubled meet: the measure degenerates and is not projective at
  /// all. Euclidean distance, and nothing else here.
  parabolic,

  /// A conjugate pair of meets: the measure is periodic and bounded.
  /// Every geometry's angle, and elliptic distance.
  elliptic,
}

/// The measure kind [absolute] gives to *distance*.
MeasureKind distanceKindOf(Absolute absolute) => switch (absolute.metric) {
  FundamentalConic.euclidean => MeasureKind.parabolic,
  FundamentalConic.hyperbolic => MeasureKind.hyperbolic,
  FundamentalConic.elliptic => MeasureKind.elliptic,
};

/// The measure kind [absolute] gives to *angle* — [MeasureKind.elliptic]
/// for all three, which is why [angleBetweenLines] needs no dispatch.
///
/// A function rather than a constant because it is a claim about the
/// absolute, and a fourth geometry would have to answer it.
MeasureKind angleKindOf(Absolute absolute) => MeasureKind.elliptic;

/// The Cayley–Klein angle between the lines [l] and [m], in `[0, π/2]`,
/// or null where the measure is undefined (a zero triple, or a line
/// tangent to the absolute — an isotropic line has no angle to anything).
///
/// ```
/// cos θ = |⟨ℓ, m⟩*| / √(⟨ℓ, ℓ⟩* · ⟨m, m⟩*)
/// ```
///
/// against the *dual* absolute — Laguerre's cross-ratio formula with the
/// logarithms cleared. This is one formula for all three geometries, and
/// under the Euclidean absolute `⟨ℓ,m⟩*` is `a₁a₂ + b₁b₂`, so it *is* the
/// textbook angle between two lines, not a limit of it.
///
/// Unsigned and unoriented: lines have no direction, so the answer is the
/// acute angle. Kinds that need a signed or obtuse wedge get it from the
/// chart, where orientation lives (`AngleGeometry`).
double? angleBetweenLines(Absolute absolute, ProjLine l, ProjLine m) {
  final ll = absolute.evaluateLine(l);
  final mm = absolute.evaluateLine(m);
  final lm = absolute.pairLines(l, m);
  return _ratioToAngle(lm, ll, mm);
}

/// The Cayley–Klein distance between the points [p] and [q], or null where
/// it is undefined — including **every** call under a Euclidean absolute,
/// whose distance is parabolic and lives in the chart instead.
///
/// ```
/// cosh d = |⟨P, Q⟩| / √(⟨P, P⟩ · ⟨Q, Q⟩)     (hyperbolic)
///  cos d = |⟨P, Q⟩| / √(⟨P, P⟩ · ⟨Q, Q⟩)     (elliptic)
/// ```
///
/// against the point conic. Null for a point *on* the absolute (which is
/// infinitely far from everything), for one outside it in the hyperbolic
/// case (no such point is in the plane), and for a non-real pairing.
///
/// Callers must handle the null under [MeasureKind.parabolic] rather than
/// treating it as an error: it is the honest answer, and the reason
/// `DistanceMeasurement` still reads the chart in Euclidean documents.
double? distanceBetween(Absolute absolute, ProjPoint p, ProjPoint q) {
  final kind = distanceKindOf(absolute);
  if (kind == MeasureKind.parabolic) {
    // Not an unimplemented case — an impossible one. See the library doc.
    return null;
  }
  final pp = absolute.pairPoints(p, p);
  final qq = absolute.pairPoints(q, q);
  final pq = absolute.pairPoints(p, q);
  final ratio = _realRatio(pq, pp, qq);
  if (ratio == null) {
    return null;
  }
  if (kind == MeasureKind.elliptic) {
    return math.acos(math.min(ratio, 1));
  }
  // Hyperbolic: the interior of the absolute is the plane, and the ratio
  // is ≥ 1 there. Below 1 the pair is not both-interior — an ultra-ideal
  // point, which this measure has no value for.
  return ratio < 1 ? null : _acosh(ratio);
}

/// `|⟨a,b⟩| / √(⟨a,a⟩·⟨b,b⟩)` as a real number, or null when the forms are
/// not real, either self-pairing vanishes (the argument is *on* the
/// absolute), or the product under the root is negative.
double? _realRatio(Complex ab, Complex aa, Complex bb) {
  const eps = projectiveEpsilon;
  if (ab.im.abs() > eps * (ab.abs2 + 1) ||
      aa.im.abs() > eps * (aa.abs2 + 1) ||
      bb.im.abs() > eps * (bb.abs2 + 1)) {
    return null;
  }
  final product = aa.re * bb.re;
  if (product <= 0) {
    return null;
  }
  return ab.re.abs() / math.sqrt(product);
}

/// The acute angle whose cosine is `|ab| / √(aa·bb)`, clamped into the
/// arccos domain — the ratio can exceed 1 by rounding on a near-parallel
/// pair, and an angle of exactly 0 is the right answer there.
double? _ratioToAngle(Complex ab, Complex aa, Complex bb) {
  final ratio = _realRatio(ab, aa, bb);
  if (ratio == null) {
    return null;
  }
  return math.acos(math.min(ratio, 1));
}

double _acosh(double x) => math.log(x + math.sqrt(x * x - 1));
