import 'dart:math' as math;

import '../../math/vec2.dart';
import '../../projective/complex.dart';
import '../../projective/conic_intersection.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_point.dart';
import '../../projective/tolerances.dart';
import '../geo_object.dart';

/// One intersection point of two curves (lines and/or circles).
///
/// Migrated (Phase 110): candidates come from the projective kernel
/// ([intersectionCandidates]) and are *total* — line ∩ conic always has
/// two, conic ∩ conic four with the circular points I, J filtered out,
/// line ∩ line one. A candidate can be complex or at infinity;
/// [branchIndex] picks one by its place in the canonical order, and
/// [position] is its projection — null exactly while the tracked
/// candidate is not real and finite, which is when this object reads
/// undefined. Through a real miss both branches go complex (conjugate
/// mates) and each returns on its own side when the curves touch again.
///
/// [branchIndex] (0 or 1) addresses the canonical order, which agrees
/// with the old deterministic orderings on real transverse cases (PLAN
/// §Migration):
///
/// - line ∩ line: one point, the index clamps to it.
/// - line ∩ circle: ordered along the line's direction. The line parent's
///   role is fixed by *type*, not argument order, so the branch is stable
///   however the user picked the two curves.
/// - circle ∩ circle: branch 0 is left of the directed center line
///   `curve1 → curve2`; here parent order matters and is preserved.
///
/// At tangency the double root repeats the point, so both branch objects
/// sit on the tangency and separate again as the root pair does — V1's
/// index clamp falls out of the representation. Note V1's *epsilon band*
/// around tangency (a world-unit distance test) is gone, like every band
/// the migration removes: candidates classify real or complex by the
/// relative realness predicate alone.
///
/// Canonical ordering is still re-derived every recompute, so a branch
/// can swap sides through a degeneracy mid-drag — branch identity held by
/// continuation arrives with tracing (Phases 113–116).
///
/// Segments intersect via their infinite carrier line for now — clipping
/// to the segment's extent is a later refinement (tracked in PLAN).
class IntersectionPoint extends GeoPoint {
  IntersectionPoint({
    required this.curve1,
    required this.curve2,
    required this.branchIndex,
    required super.id,
    super.attributes,
  }) {
    if (branchIndex < 0 || branchIndex > 1) {
      throw ArgumentError.value(branchIndex, 'branchIndex', 'must be 0 or 1');
    }
    if ((curve1 is! GeoLine && curve1 is! GeoCircle) ||
        (curve2 is! GeoLine && curve2 is! GeoCircle)) {
      throw ArgumentError('IntersectionPoint parents must be curves');
    }
    if (identical(curve1, curve2)) {
      throw ArgumentError('Cannot intersect a curve with itself');
    }
    recompute();
  }

  /// Each a [GeoLine] or [GeoCircle] (enforced in the constructor).
  final GeoObject curve1;
  final GeoObject curve2;

  /// Which intersection branch this point tracks (see class doc).
  ///
  /// Mutable under the same contract as `PointOnObject.parameter` during
  /// a locus sweep only: `Locus.recompute`'s linkage continuation flips
  /// it while tracing through a tangency and always restores it before
  /// returning, so no listener, command or save ever observes a flipped
  /// value. Everything else must treat it as fixed at creation.
  int branchIndex;

  ProjPoint? _point;
  int _candidateCount = 0;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  /// How many *distinct* real finite intersection points the parent curves
  /// currently have (0, 1 or 2), as of the last [recompute] — a double
  /// root's coincident copies count once (`closeTo` within
  /// `doubleRootEpsilon`). Two candidates collapsing to one and then none
  /// is a tangency — the signal the locus sweep's linkage continuation
  /// branches on (the walker contract, until Phase 117 rewrites it on
  /// tracing).
  int get candidateCount => _candidateCount;

  @override
  List<GeoObject> get parents => [curve1, curve2];

  @override
  void recompute() {
    final candidates = intersectionCandidates(curve1, curve2);
    _candidateCount = _distinctRealCount(candidates);
    _point = candidates.isEmpty
        ? null
        : candidates[math.min(branchIndex, candidates.length - 1)];
  }

  static int _distinctRealCount(List<ProjPoint> candidates) {
    var count = 0;
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i].toVec2() == null) continue;
      var repeated = false;
      for (var j = 0; j < i && !repeated; j++) {
        repeated = candidates[j].toVec2() != null &&
            candidates[i].closeTo(candidates[j], doubleRootEpsilon);
      }
      if (!repeated) count++;
    }
    return count;
  }
}

/// The intersection candidates of two curve objects (each a [GeoLine] or
/// [GeoCircle]), in canonical order, zero triples dropped and the circular
/// points I, J filtered out ([isCircularPoint]). Empty while a parent's
/// projective view is null.
///
/// - Line ∩ line: the single meet — empty when the carriers projectively
///   coincide (no discrete intersection, matching [intersectConicConic]'s
///   coincident-input convention).
/// - Line ∩ conic: always two ([intersectLineConic]), whichever argument
///   is the line.
/// - Conic ∩ conic: the four pencil points ([intersectConicConic]); for
///   two real circles I and J are always two of them, leaving the two
///   branch-carrying candidates in V1 order.
///
/// Candidates real within `doubleRootEpsilon` but not within the predicate
/// default are snapped exactly real: a *constructed* tangency's double
/// root splits into a conjugate pair whose imaginary part is the square
/// root of the construction's rounding error — far above the realness
/// predicate, pure noise all the same. A genuine near-miss stays complex,
/// its imaginary measure growing as sqrt(|miss|). (This replaces V1's
/// world-unit epsilon band around tangency with a relative,
/// root-noise-sized one.)
///
/// Consumed by [IntersectionPoint] and the snap-to-intersection ladder.
List<ProjPoint> intersectionCandidates(GeoObject curve1, GeoObject curve2) {
  switch ((curve1, curve2)) {
    case (final GeoLine a, final GeoLine b):
      final l1 = a.projLine;
      final l2 = b.projLine;
      if (l1 == null || l2 == null || l1.closeTo(l2)) {
        return const [];
      }
      final p = l1.meet(l2);
      return p.isZero ? const [] : [p];
    case (final GeoLine a, final GeoCircle b):
      return _lineConicCandidates(a, b);
    case (final GeoCircle a, final GeoLine b):
      return _lineConicCandidates(b, a);
    case (final GeoCircle a, final GeoCircle b):
      final c1 = a.conic;
      final c2 = b.conic;
      if (c1 == null || c2 == null) {
        return const [];
      }
      return [
        for (final p in intersectConicConic(c1, c2))
          if (!p.isZero && !isCircularPoint(p)) _realSnapped(p),
      ];
    // Unreachable from IntersectionPoint: its constructor rejects
    // non-curve parents.
    case ((GeoPoint(), _) || (_, GeoPoint())):
    case ((GeoAngle(), _) || (_, GeoAngle())):
    case ((GeoPolygon(), _) || (_, GeoPolygon())):
    case ((GeoMeasurement(), _) || (_, GeoMeasurement())):
    case ((GeoLocus(), _) || (_, GeoLocus())):
    case ((GeoText(), _) || (_, GeoText())):
      throw ArgumentError('intersection candidates need two curves');
  }
}

List<ProjPoint> _lineConicCandidates(GeoLine line, GeoCircle circle) {
  final l = line.projLine;
  final c = circle.conic;
  if (l == null || c == null) {
    return const [];
  }
  return [
    for (final p in intersectLineConic(l, c))
      if (!p.isZero && !isCircularPoint(p)) _realSnapped(p),
  ];
}

/// [p] with its imaginary noise stripped when it is real within
/// `doubleRootEpsilon` but not within the predicate default (see
/// [intersectionCandidates]); [p] itself otherwise. Snapping normalizes
/// first (chart normalization removes complex phase), so the result is
/// exactly real and projectively within `doubleRootEpsilon` of the input.
ProjPoint _realSnapped(ProjPoint p) {
  if (p.isReal() || !p.isReal(doubleRootEpsilon)) {
    return p;
  }
  final n = p.normalized;
  return ProjPoint(Complex(n.x.re), Complex(n.y.re), Complex(n.w.re));
}
