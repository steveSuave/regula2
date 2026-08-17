import 'dart:math' as math;

import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
import '../../projective/conic_intersection.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_point.dart';
import '../../projective/tolerances.dart';
import '../../projective/tracing/traced_branch.dart';
import '../geo_object.dart';
import '../object_attributes.dart';

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
/// [branchIndex] (`0..maxBranchCount − 1`) addresses the canonical order,
/// which agrees with the old deterministic orderings on real transverse
/// cases (PLAN §Migration):
///
/// - line ∩ line: one point, the index clamps to it.
/// - line ∩ circle: ordered along the line's direction. The line parent's
///   role is fixed by *type*, not argument order, so the branch is stable
///   however the user picked the two curves.
/// - circle ∩ circle: branch 0 is left of the directed center line
///   `curve1 → curve2`; here parent order matters and is preserved.
/// - conic ∩ conic: up to **four** branches, in the pencil solver's
///   canonical order with the circular points I and J filtered out
///   (Phase 105/110). See [maxBranchCount].
///
/// At tangency the double root repeats the point, so both branch objects
/// sit on the tangency and separate again as the root pair does — V1's
/// index clamp falls out of the representation. Note V1's *epsilon band*
/// around tangency (a world-unit distance test) is gone, like every band
/// the migration removes: candidates classify real or complex by the
/// relative realness predicate alone.
///
/// Canonical ordering is still re-derived every recompute, so a branch
/// can swap sides through a degeneracy mid-drag; while [tracedBranch] is
/// active (inside a `Construction.recomputeAlongPath` pass only), branch
/// identity is instead held by continuity — [recompute] follows the
/// candidate nearest the tracked root, and the pass's step controller
/// reads the slot's motion/separation bookkeeping to keep that matching
/// unambiguous (Phase 114; complex detours around degeneracies are 115).
///
/// The parent pair is stored in **canonical order** ([canonicalPairOrder]),
/// whichever way round the caller named it. `branchIndex` addresses the
/// canonical order of `intersectionCandidates(curve1, curve2)`, and the
/// reversed pair is a *different* order — so a construction holding points
/// on both orderings of the same two curves holds two incompatible address
/// spaces for one set of crossings, and nothing that compares indices
/// (creation's duplicate refusal, a tracing pass's branch adoption, the
/// codec's repair) can see across them. Two points then drift onto the
/// same crossing under a drag and one crossing is left vacant — the
/// accumulation reported in Phase 120c, whose last root cause this was.
/// Normalizing at the constructor puts every point on a pair into one
/// numbering, which is what makes those guards total.
///
/// Segments intersect via their infinite carrier line for now — clipping
/// to the segment's extent is a later refinement (tracked in PLAN).
class IntersectionPoint extends GeoPoint {
  /// Builds the point that is branch [branchIndex] of
  /// `intersectionCandidates(curve1, curve2)` — the caller's order, which
  /// is how the tool and the codec both name a crossing.
  ///
  /// The pair is then **stored canonically** (see [canonicalPairOrder]),
  /// remapping the index onto the canonical order's numbering when the
  /// caller named the curves the other way round. The crossing the caller
  /// asked for is the crossing the object tracks; only its *address*
  /// changes.
  ///
  /// [absolute] is the document's geometry (Phase 126), and it is here for
  /// the remapping alone: both orders' candidate lists are filtered
  /// against the absolute, so a remap computed under the wrong one
  /// translates between two numberings that neither the caller nor the
  /// construction is using. It does *not* need to reach [recompute] — the
  /// value settles when `Construction.add` recomputes under the document's
  /// absolute — but the address, once stored, is never recomputed.
  factory IntersectionPoint({
    required GeoObject curve1,
    required GeoObject curve2,
    required int branchIndex,
    required String id,
    ObjectAttributes? attributes,
    Absolute absolute = Absolute.euclidean,
  }) {
    if (branchIndex < 0 || branchIndex >= maxBranchCount) {
      throw ArgumentError.value(
        branchIndex,
        'branchIndex',
        'must be 0..${maxBranchCount - 1}',
      );
    }
    if ((curve1 is! GeoLine && curve1 is! GeoCircle) ||
        (curve2 is! GeoLine && curve2 is! GeoCircle)) {
      throw ArgumentError('IntersectionPoint parents must be curves');
    }
    if (identical(curve1, curve2)) {
      throw ArgumentError('Cannot intersect a curve with itself');
    }
    if (canonicalPairOrder(curve1, curve2)) {
      return IntersectionPoint.canonical(
        curve1: curve1,
        curve2: curve2,
        branchIndex: branchIndex,
        id: id,
        attributes: attributes,
      );
    }
    return IntersectionPoint.canonical(
      curve1: curve2,
      curve2: curve1,
      branchIndex: _readdress(curve1, curve2, branchIndex, absolute),
      id: id,
      attributes: attributes,
    );
  }

  /// The generative constructor, for callers that already hold the pair in
  /// [canonicalPairOrder] — subclasses (which cannot redirect through a
  /// factory) and the factory itself. Prefer the unnamed constructor:
  /// it accepts either order and renumbers.
  IntersectionPoint.canonical({
    required this.curve1,
    required this.curve2,
    required this.branchIndex,
    required super.id,
    super.attributes,
  }) : assert(
         canonicalPairOrder(curve1, curve2),
         'IntersectionPoint stores its pair in canonical order',
       ) {
    recompute();
  }

  /// The same branch, renumbered from `(a, b)`'s canonical order into
  /// `(b, a)`'s.
  ///
  /// The two orders are *not* related by a fixed permutation: the ordering
  /// key is the directed centre line `a → b`, which reverses the
  /// real-finite tier while leaving the points at infinity and the
  /// non-real ones where they are — so the permutation depends on how many
  /// candidates are currently real, which changes as the parents move.
  /// Matching by chordal distance is therefore the only sound translation,
  /// and it is defined on complex candidates too, so it still speaks while
  /// the crossing is imaginary. With no candidates to match against
  /// (an undefined parent) the index passes through unchanged.
  static int _readdress(
    GeoObject a,
    GeoObject b,
    int index,
    Absolute absolute,
  ) {
    final from = intersectionCandidates(a, b, absolute: absolute);
    final to = intersectionCandidates(b, a, absolute: absolute);
    if (index >= from.length || to.isEmpty) return index;
    final target = from[index];
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < to.length; i++) {
      final d = TracedBranch.chordalDistance(target, to[i]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// The most branches any carrier pair can have: **four**, from
  /// conic ∩ conic via the pencil (Phase 105). Line ∩ line has one and
  /// the line ∩ conic and circle ∩ circle pairs two.
  ///
  /// **Every bound on [branchIndex] must derive from this constant** —
  /// the constructor's, `Construction`'s pass-end adoption step, and
  /// `Construction.setIntersectionBranch`. Three separate hand-written
  /// `0..1` literals survived into the conic era and each broke something
  /// different: the constructor threw on the third crossing (120b);
  /// adoption silently collapsed branches onto one index, because capping
  /// it makes adoption *asymmetric* rather than merely partial; and the
  /// commit primitive threw out of the drag's own command, which is why
  /// the crossings went on merging in the app after the engine had
  /// stopped merging them (both 120c). The bound is on the *addressing
  /// space*, never on the current candidate count — that varies as the
  /// parents move, and [recompute] clamps to it.
  static const int maxBranchCount = 4;

  /// Each a [GeoLine] or [GeoCircle] (enforced in the constructor).
  final GeoObject curve1;
  final GeoObject curve2;

  /// Which intersection branch this point tracks (see class doc).
  ///
  /// Mutable in exactly two places. During a locus sweep,
  /// `Locus.recompute`'s linkage continuation flips it while tracing
  /// through a tangency and always restores it before returning, so no
  /// listener, command or save observes a flipped value. And a tracing
  /// pass (`Construction.recomputeAlongPath`) ends by *adopting* the
  /// branch it followed — re-deriving the index as the canonical-order
  /// position of the tracked root (Phase 116) — which is how traced
  /// identity survives static recomputes, commits and saves; the drag
  /// session captures adoptions in its one command
  /// (`MoveFreePointCommand.branchChanges`), so undo/redo replay them
  /// exactly. Everything else must treat it as fixed at creation.
  int branchIndex;

  /// Tracing slot (Phase 113). Seeded, stepped and cleared exclusively by
  /// `Construction.recomputeAlongPath`; inactive at all other times, so
  /// nothing outside a tracing pass ever observes non-canonical branch
  /// selection. Objects inside a `Locus` chain are never seeded — the
  /// sweep-and-restore recompute would drag the root along the sweep
  /// (that machinery dissolves when Phase 117 rewrites loci on tracing).
  final TracedBranch tracedBranch = TracedBranch();

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
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final candidates = intersectionCandidates(
      curve1,
      curve2,
      complexCarriers:
          tracedBranch.isActive && tracedBranch.allowComplexCarriers,
      absolute: absolute,
    );
    _candidateCount = _distinctRealCount(candidates);
    if (candidates.isEmpty) {
      // The slot coasts through a momentarily candidate-free step
      // (coincident carriers, an undefined parent): the root is kept and
      // matching resumes from it when candidates return.
      if (tracedBranch.isActive) {
        tracedBranch.coast();
      }
      _point = null;
      return;
    }
    if (tracedBranch.isActive) {
      _point = tracedBranch.follow(candidates);
      return;
    }
    _point = candidates[math.min(branchIndex, candidates.length - 1)];
  }

  static int _distinctRealCount(List<ProjPoint> candidates) {
    var count = 0;
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i].toVec2() == null) continue;
      var repeated = false;
      for (var j = 0; j < i && !repeated; j++) {
        repeated =
            candidates[j].toVec2() != null &&
            candidates[i].closeTo(candidates[j], doubleRootEpsilon);
      }
      if (!repeated) count++;
    }
    return count;
  }
}

/// Whether `(curve1, curve2)` is the canonical order for an
/// [IntersectionPoint]'s parent pair — object id ascending, which is
/// stable across a save/load round trip and independent of which curve the
/// user happened to tap first.
///
/// A pair's *ordering* is load-bearing (`intersectionCandidates` orders
/// real crossings along the directed centre line `curve1 → curve2`), so
/// every point on the same two curves has to agree on one. Which order
/// that is carries no meaning; that they share it is the whole point.
bool canonicalPairOrder(GeoObject curve1, GeoObject curve2) =>
    curve1.id.compareTo(curve2.id) <= 0;

/// Whether [p] is a point every circle of [absolute]'s geometry shares,
/// and so carries no branch information.
///
/// Euclidean circles all pass through I and J, which is why they are
/// filtered out of solver output — two circles meet in four points and
/// two of them are always those. **That is a fact about the Euclidean
/// absolute, not about circles.** Under a proper absolute a circle is
/// bitangent to it, and two such circles share no point at all: their
/// pencil's degenerate member is a genuine line pair, so all four
/// intersections carry information and none may be dropped.
///
/// This matters beyond tidiness because `branchIndex` addresses the
/// *filtered* order, so every caller has to filter identically or two
/// points on one curve pair end up in different address spaces — the
/// Phase 120c failure, arrived at from a new direction.
bool _sharedWithAbsolute(ProjPoint p, Absolute absolute) =>
    absolute.isEuclidean && isCircularPoint(p);

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
/// A *non-real* parent carrier yields no candidates at all — unless
/// [complexCarriers] is set. Statically, a complex carrier (an undefined
/// intersection's conjugate branch, the bisector over it) still passes
/// through real points — its own vertex, say — and intersecting it would
/// fabricate real geometry V1 rightly left undefined; static candidates
/// exist only between real carriers, while points at infinity and
/// degenerate real conics are real and take part. A tracing pass's
/// complex detour (Phase 115) is the one context where complex carriers
/// are legitimate: the dragged point sits at a complex path parameter, so
/// every affected carrier is the analytic continuation of a real one and
/// its candidates continue the traced roots. The kernel functions are
/// holomorphic throughout, so [complexCarriers] only skips the realness
/// gates — nothing else changes (canonical *order* is meaningless on
/// complex carriers, but a detour matches by continuity, never by order).
///
/// Consumed by [IntersectionPoint] and the snap-to-intersection ladder.
List<ProjPoint> intersectionCandidates(
  GeoObject curve1,
  GeoObject curve2, {
  bool complexCarriers = false,
  Absolute absolute = Absolute.euclidean,
}) {
  switch ((curve1, curve2)) {
    case (final GeoLine a, final GeoLine b):
      final l1 = a.projLine;
      final l2 = b.projLine;
      if (l1 == null || l2 == null) {
        return const [];
      }
      if (!complexCarriers && (!l1.isReal() || !l2.isReal())) {
        return const [];
      }
      if (l1.closeTo(l2)) {
        return const [];
      }
      final p = l1.meet(l2);
      return p.isZero ? const [] : [p];
    case (final GeoLine a, final GeoCircle b):
      return _lineConicCandidates(a, b, complexCarriers, absolute);
    case (final GeoCircle a, final GeoLine b):
      return _lineConicCandidates(b, a, complexCarriers, absolute);
    case (final GeoCircle a, final GeoCircle b):
      final c1 = a.conic;
      final c2 = b.conic;
      if (c1 == null || c2 == null) {
        return const [];
      }
      if (!complexCarriers && (!c1.isReal() || !c2.isReal())) {
        return const [];
      }
      return [
        for (final p in intersectConicConic(c1, c2))
          if (!p.isZero && !_sharedWithAbsolute(p, absolute)) _realSnapped(p),
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

List<ProjPoint> _lineConicCandidates(
  GeoLine line,
  GeoCircle circle,
  bool complexCarriers,
  Absolute absolute,
) {
  final l = line.projLine;
  final c = circle.conic;
  if (l == null || c == null) {
    return const [];
  }
  if (!complexCarriers && (!l.isReal() || !c.isReal())) {
    return const [];
  }
  final candidates = [
    for (final p in intersectLineConic(l, c))
      if (!p.isZero && !_sharedWithAbsolute(p, absolute)) _realSnapped(p),
  ];
  // `intersectLineConic` orders along the *representative's* direction,
  // but no kind contract pins the stored carrier's sign — a join through
  // a chart-normalized parent can flip it. V1 defined the branch order
  // along the line's oriented affine direction, so re-anchor the pair to
  // it, exactly as `orientedAlong` re-anchors the projection. (Reversing
  // also flips the conjugate-pair order — consistent: V1 order was a
  // property of the direction, and flipping the direction flips both.)
  final affine = line.line;
  if (candidates.length == 2 && affine != null) {
    final d = affine.direction;
    // The representative direction, by the kernel's own rule (real parts,
    // falling back to imaginary parts for complex-phase representatives).
    final reNorm = l.a.re * l.a.re + l.b.re * l.b.re;
    final imNorm = l.a.im * l.a.im + l.b.im * l.b.im;
    final along = reNorm >= imNorm
        ? d.x * l.b.re - d.y * l.a.re
        : d.x * l.b.im - d.y * l.a.im;
    if (along < 0) {
      return [candidates[1], candidates[0]];
    }
  }
  return candidates;
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
