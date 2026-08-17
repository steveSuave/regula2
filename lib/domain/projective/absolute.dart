/// The fundamental conic — *the absolute* — a document's measurement is
/// founded on (PLAN §"M-CK — Cayley–Klein").
///
/// Incidence is projective and needs none of this. Distance and angle are
/// cross-ratio logarithms against the absolute, and perpendicularity is
/// conjugacy with respect to it, so *the absolute is where the geometry
/// lives*: substituting it is what turns Euclidean constructions into
/// hyperbolic or elliptic ones, without any incidence code moving.
///
/// **The dual is primary, and both matrices are given explicitly.** For a
/// nondegenerate absolute the dual is the adjugate and either determines
/// the other; for the Euclidean one it does not, and Euclidean is the
/// default every existing document is in — see [euclidean].
library;

import 'complex.dart';
import 'conic_matrix.dart';
import 'proj_line.dart';
import 'proj_point.dart';
import 'tolerances.dart';

/// The geometry a document is drawn in, named.
///
/// Kept as an enum rather than free-form text because the save format has
/// to *reserve* the two unimplemented names: a build that silently read a
/// hyperbolic document as Euclidean would draw the wrong geometry rather
/// than refuse the file, which is what the v2 version stamp exists to
/// prevent (PLAN §"The version field is a requirement").
enum FundamentalConic {
  /// The degenerate absolute: the doubled line at infinity as a point
  /// conic, the circular points {I, J} as its dual.
  euclidean('euclidean'),

  /// The unit circle: Beltrami–Klein hyperbolic geometry.
  hyperbolic('hyperbolic'),

  /// The imaginary unit conic: elliptic geometry.
  elliptic('elliptic');

  const FundamentalConic(this.name);

  /// The token written to and read from the save format. Kept separate
  /// from the Dart identifier so renaming the latter cannot silently
  /// change the file format.
  final String name;

  static FundamentalConic? byName(String name) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }
}

/// A fundamental conic as the pair of matrices measurement reads: the
/// point conic and its dual.
///
/// Both are stored, and that is the design rather than an optimization.
/// The dual of a conic is its adjugate, which is fine for the two proper
/// absolutes but **identically zero for the Euclidean one**: its point
/// conic is the *doubled* line at infinity, rank 1, and the adjugate of a
/// rank-1 matrix vanishes. The dual — the point pair {I, J}, `diag(1,1,0)`
/// — cannot be recovered from it and has to be written down. Since the
/// Euclidean absolute is the one every document written so far is in,
/// deriving is not an option and each instance supplies both.
///
/// The dual is also the half the code actually reads. Three places in the
/// kernel arrived at `diag(1,1,0)` independently before this type existed:
/// `normalDirectionOf` (the perpendicular direction is [poleOf] the line),
/// `focalConicOf`'s single Euclidean coefficient `a² + b²` (which is
/// [evaluateLine]), and `ProjTransform.reflection`'s `m22`.
///
/// Every operation is polynomial in the arguments' homogeneous
/// coordinates — holomorphic, division-free, total on degenerate input —
/// per the layer convention in [ConicMatrix].
class Absolute {
  const Absolute({
    required this.metric,
    required this.pointConic,
    required this.dualConic,
  });

  /// Euclidean geometry: the point conic is the doubled line at infinity
  /// `w² = 0`, and its dual is the circular point pair {I, J}.
  ///
  /// This is the degenerate member of the family, and every degeneracy the
  /// Euclidean plane has as a *metric* space traces back to it: parallels
  /// exist because the absolute lies on one line, so two lines can meet
  /// on it; similar triangles exist because the absolute has no scale.
  /// [dualConic] is `diag(1,1,0)`, which is why [poleOf] reduces to
  /// `[a : b : 0]` — the familiar perpendicular direction — and
  /// [evaluateLine] to `a² + b²`.
  static const Absolute euclidean = Absolute(
    metric: FundamentalConic.euclidean,
    // w² = 0, the line at infinity doubled.
    pointConic: ConicMatrix(
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.one,
    ),
    // diag(1, 1, 0) — the lines through I or J, i.e. the isotropic ones.
    dualConic: ConicMatrix(
      Complex.one,
      Complex.zero,
      Complex.one,
      Complex.zero,
      Complex.zero,
      Complex.zero,
    ),
  );

  /// Hyperbolic geometry in the Beltrami–Klein model: the absolute is the
  /// unit circle `x² + y² − w² = 0`, and the plane is its interior.
  ///
  /// Self-dual up to scale — the adjugate of `diag(1,1,−1)` is
  /// `diag(−1,−1,1)`, stored here as the adjugate itself so that the
  /// relation `dual = adj(point)` holds literally wherever it holds at all.
  static const Absolute hyperbolic = Absolute(
    metric: FundamentalConic.hyperbolic,
    pointConic: ConicMatrix(
      Complex.one,
      Complex.zero,
      Complex.one,
      Complex.zero,
      Complex.zero,
      Complex(-1),
    ),
    dualConic: ConicMatrix(
      Complex(-1),
      Complex.zero,
      Complex(-1),
      Complex.zero,
      Complex.zero,
      Complex.one,
    ),
  );

  /// Elliptic geometry: the absolute is the imaginary unit conic
  /// `x² + y² + w² = 0`, which no real point lies on — so there are no
  /// parallels and no ideal boundary to draw.
  ///
  /// Self-dual: the adjugate of the identity is the identity.
  static const Absolute elliptic = Absolute(
    metric: FundamentalConic.elliptic,
    pointConic: ConicMatrix(
      Complex.one,
      Complex.zero,
      Complex.one,
      Complex.zero,
      Complex.zero,
      Complex.one,
    ),
    dualConic: ConicMatrix(
      Complex.one,
      Complex.zero,
      Complex.one,
      Complex.zero,
      Complex.zero,
      Complex.one,
    ),
  );

  /// The absolute [metric] names.
  static Absolute of(FundamentalConic metric) => switch (metric) {
    FundamentalConic.euclidean => euclidean,
    FundamentalConic.hyperbolic => hyperbolic,
    FundamentalConic.elliptic => elliptic,
  };

  /// Which of the three geometries this is.
  final FundamentalConic metric;

  /// The absolute as a point conic: the locus `pᵀΩp = 0`. Rank 1 for
  /// [euclidean] (the doubled line at infinity), rank 3 for the others.
  final ConicMatrix pointConic;

  /// The absolute as a dual conic: the lines tangent to it, `ℓᵀΩ*ℓ = 0`.
  /// Rank 2 for [euclidean] (the point pair {I, J}), rank 3 for the
  /// others. See the class doc for why this is stored rather than derived.
  final ConicMatrix dualConic;

  /// Whether this is the geometry every pre-M-CK document is in.
  bool get isEuclidean => metric == FundamentalConic.euclidean;

  /// The pole of [l] with respect to the absolute — `Ω*·ℓ`.
  ///
  /// This is the metric's single most-used operation. Under [euclidean] it
  /// is `[a : b : 0]`, the point at infinity of the directions
  /// perpendicular to [l] — so `perpendicularThrough(p, l)` is the join of
  /// `p` with this point in *every* geometry, and `euclidean.dart`'s
  /// `normalDirectionOf` is this function with the absolute inlined.
  ProjPoint poleOf(ProjLine l) => dualConic.applyToLine(l);

  /// The polar of [p] with respect to the absolute — `Ω·p`.
  ///
  /// Under [euclidean] this is the line at infinity for every finite [p]
  /// (and the zero triple for a point already at infinity), which is why
  /// the Euclidean half-turn about a point reads as an affine homothety of
  /// ratio −1: the harmonic homology `(p, polarOf(p))` has ℓ∞ as its axis.
  ProjLine polarOf(ProjPoint p) => pointConic.polarLine(p);

  /// `ℓᵀΩ*ℓ`, zero exactly when [l] is tangent to the absolute.
  ///
  /// Under [euclidean] this is `a² + b²`, vanishing on the isotropic lines
  /// — those through I or J, including ℓ∞ itself. It is the whole of the
  /// Euclidean structure in `focalConicOf` (PLAN §"The conic
  /// constructors"), so it is the single substitution that re-founds it.
  Complex evaluateLine(ProjLine l) =>
      dualConic.xx * l.a * l.a +
      dualConic.yy * l.b * l.b +
      dualConic.ww * l.c * l.c +
      (dualConic.xy * l.a * l.b +
              dualConic.xw * l.a * l.c +
              dualConic.yw * l.b * l.c)
          .scale(2);

  /// `ℓᵀΩ*m` — the bilinear form [evaluateLine] is the quadratic form of.
  ///
  /// This is what angle measurement reads (`ck_measure.dart`). Under
  /// [euclidean] it is `a₁a₂ + b₁b₂`, the dot product of the two lines'
  /// normals, which is why the Cayley–Klein angle and the textbook
  /// Euclidean one are the same expression rather than a limit of it.
  Complex pairLines(ProjLine l, ProjLine m) =>
      dualConic.xx * l.a * m.a +
      dualConic.yy * l.b * m.b +
      dualConic.ww * l.c * m.c +
      dualConic.xy * (l.a * m.b + l.b * m.a) +
      dualConic.xw * (l.a * m.c + l.c * m.a) +
      dualConic.yw * (l.b * m.c + l.c * m.b);

  /// `pᵀΩq` — the bilinear form [evaluatePoint] is the quadratic form of.
  ///
  /// What distance measurement reads on a *proper* absolute. Under
  /// [euclidean] it is `w₁w₂`, which carries no information about where
  /// the points are — the algebraic statement that Euclidean distance is
  /// not a cross-ratio (`ck_measure.dart`).
  Complex pairPoints(ProjPoint p, ProjPoint q) =>
      pointConic.xx * p.x * q.x +
      pointConic.yy * p.y * q.y +
      pointConic.ww * p.w * q.w +
      pointConic.xy * (p.x * q.y + p.y * q.x) +
      pointConic.xw * (p.x * q.w + p.w * q.x) +
      pointConic.yw * (p.y * q.w + p.w * q.y);

  /// `pᵀΩp`, zero exactly when [p] lies on the absolute.
  ///
  /// Under [euclidean] this is `w²`: every finite point is off the
  /// absolute and every point at infinity is on it, which is the sense in
  /// which "at infinity" is a Euclidean rather than a projective notion.
  Complex evaluatePoint(ProjPoint p) => pointConic.evaluate(p);

  /// Whether [l] is tangent to the absolute (isotropic), relatively:
  /// `|ℓᵀΩ*ℓ| ≤ eps·‖Ω*‖·|ℓ|²`. False when either side is zero.
  bool isIsotropic(ProjLine l, [double eps = projectiveEpsilon]) {
    final scale2 = dualConic.norm2 * l.norm2 * l.norm2;
    if (scale2 == 0) return false;
    return evaluateLine(l).abs2 <= eps * eps * scale2;
  }

  @override
  bool operator ==(Object other) => other is Absolute && other.metric == metric;

  @override
  int get hashCode => metric.hashCode;

  @override
  String toString() => 'Absolute(${metric.name})';
}
