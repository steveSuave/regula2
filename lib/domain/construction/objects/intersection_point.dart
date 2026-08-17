import 'dart:math' as math;

import '../../math/vec2.dart';
import '../../projective/complex.dart';
import '../../projective/conic_intersection.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_point.dart';
import '../../projective/tolerances.dart';
import '../../projective/tracing/traced_branch.dart';
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
/// [branchIndex] (`0..maxBranchCount − 1`) addresses the canonical order,
/// which agrees with the old deterministic orderings on real transverse
/// cases (PLAN §Migration). **Every bound on it belongs to
/// [maxBranchCount]**: the constructor's, `Construction`'s adoption
/// step and `Construction.setIntersectionBranch`. Three separate `0..1`
/// literals survived into the conic era and each broke something
/// different — the constructor threw on the third crossing (120b),
/// adoption silently collapsed branches onto one index, and the commit
/// primitive threw out of the drag's command (both 120c).
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
    recompute();
  }

  /// The most branches any carrier pair can have: **four**, from
  /// conic ∩ conic via the pencil (Phase 105). Line ∩ line has one and
  /// the line ∩ conic and circle ∩ circle pairs two.
  ///
  /// The bound was `0 or 1` until Phase 120b. That was right for as long
  /// as every `GeoCircle` was a circle — and it survived Phase 110's
  /// four-candidate conic ∩ conic solver only because no kind could yet
  /// *produce* a general conic. The first `FivePointConic` tapped against
  /// another conic made the tool throw on the third crossing, and would
  /// have made the codec refuse to reload any document containing one.
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

  /// The half-plane (`+1` upper, `−1` lower) of the last detour arc walked
  /// around a root collision this point took part in, or null if it has
  /// never detoured. Read and written only by `Construction._traceAlong`.
  ///
  /// **This is what makes a there-and-back drag an identity** (Phase
  /// 120c). Reversing a path conjugates its parameter's imaginary axis —
  /// the return leg's `Im s > 0` is the outward leg's `Im t < 0` — so the
  /// two legs trace the *same* bump, and cancel, exactly when they detour
  /// on opposite sides *in their own parameters*. Each detour therefore
  /// takes the negation of what this records.
  ///
  /// The alternation generalizes past a single clean out-and-back: between
  /// two consecutive crossings of one singularity the path must leave its
  /// neighbourhood and come back, crossing every *other* singularity an
  /// even number of times on the way, so a per-point counter still
  /// alternates on that point's own crossings and the windings telescope
  /// to zero.
  ///
  /// It is deliberately **not** gesture-scoped: a there-and-back done as
  /// two separate drags is the common case, and any state that resets at
  /// mouse-up would hand the return leg the same half-plane as the
  /// outward one. It is not persisted either — a freshly loaded document
  /// has no history to be consistent with.
  double? lastDetourOrientation;

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
    final candidates = intersectionCandidates(
      curve1,
      curve2,
      complexCarriers:
          tracedBranch.isActive && tracedBranch.allowComplexCarriers,
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
      return _lineConicCandidates(a, b, complexCarriers);
    case (final GeoCircle a, final GeoLine b):
      return _lineConicCandidates(b, a, complexCarriers);
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

List<ProjPoint> _lineConicCandidates(
  GeoLine line,
  GeoCircle circle,
  bool complexCarriers,
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
      if (!p.isZero && !isCircularPoint(p)) _realSnapped(p),
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
