import 'dart:math' as math;
import 'dart:typed_data';

import '../complex.dart';
import '../proj_point.dart';

/// The tracing slot on an intersection-bearing object: the tracked root's
/// homogeneous coordinates, carried between the substeps of a
/// `Construction.recomputeAlongPath` pass.
///
/// While [isActive], the owner's `recompute` calls [follow] to pick the
/// intersection candidate *nearest the stored root* instead of addressing
/// the canonical order by `branchIndex` — that is the whole tracing idea:
/// branch identity is held by continuity of the root, not by per-frame
/// re-sorting. Outside a tracing pass the slot is inactive and the
/// owner's static behaviour is untouched.
///
/// Besides the root, the slot keeps the two quantities the Phase 114 step
/// controller reads: [motion] (how far the root moved at the last
/// [follow]) and [separation] (how close the candidates were to each
/// other). A trial step is accepted only if every root's motion stayed
/// under half the separation recorded at the previous accepted step — the
/// Cinderella rule — which is exactly the condition under which
/// nearest-root matching provably cannot swap two branches (two roots
/// each moving less than half their mutual distance cannot reach a common
/// candidate). [checkpoint]/[restore] let the controller roll a refused
/// trial back.
///
/// Storage is a parallel-scalar `Float64List` (re/im per coordinate), the
/// struct-of-arrays shape the Phase 101 benchmark pinned for the tracing
/// hot loop; the boxed [root] accessors are the API face until Phase 122
/// moves the inner loop fully onto the buffers.
class TracedBranch {
  /// `[x.re, x.im, y.re, y.im, w.re, w.im]` of the tracked root.
  final Float64List _root = Float64List(6);

  double _balanceCx = 0;
  double _balanceCy = 0;
  double _balanceInvScale = 1;
  bool _balanced = false;

  bool _active = false;
  double _separation = double.infinity;
  double _motion = 0;
  int _matchedIndex = -1;
  bool _hasCandidates = false;

  /// Whether a tracing pass currently owns this slot.
  bool get isActive => _active;

  /// Whether the owner's candidate computation may accept *complex*
  /// carriers (Phase 115). Statically, intersecting a complex carrier
  /// would fabricate geometry, so `intersectionCandidates` refuses them —
  /// but while a complex detour walks the drag parameter off the real
  /// axis, every affected carrier is legitimately complex and the
  /// candidates are its analytic continuation. Set (and cleared) by the
  /// pass strictly around the detour arc, never checkpointed: a refused
  /// arc trial stays on the arc. Meaningless while not [isActive];
  /// [seed] and [clear] reset it.
  bool allowComplexCarriers = false;

  /// The tracked root as stored by the last [seed] or [follow].
  /// Meaningless while not [isActive].
  ProjPoint get root => ProjPoint(
        Complex(_root[0], _root[1]),
        Complex(_root[2], _root[3]),
        Complex(_root[4], _root[5]),
      );

  /// The minimum pairwise chordal distance among the candidates seen at
  /// the last [seed] or [follow] — the sqrt of the same scale-invariant
  /// measure [nearestIndexAmong] minimizes. Infinity with fewer than two
  /// candidates (a single root has nothing to swap with) and after
  /// [coast] (matching restarts unconstrained when candidates return).
  double get separation => _separation;

  /// The chordal distance the tracked root moved at the last [follow];
  /// zero after [seed] and [coast].
  double get motion => _motion;

  /// The candidate index matched at the last [follow]; −1 after [seed]
  /// and [coast] (no match happened). The step controller compares it
  /// across branches on the same curve pair to refuse collisions.
  int get matchedIndex => _matchedIndex;

  /// Whether the owner's candidate set was non-empty at the last [seed]
  /// or [follow] — false after [coast] (and after seeding on an empty
  /// set). The step controller reads it to refuse a *match→coast
  /// transition* on a wide trial (Phase 116b): candidates vanishing
  /// under a large step means the trial absorbed an unchecked crossing
  /// of a carrier degeneracy, and the retained root would go stale by
  /// the whole span — refusal forces refinement, so a coast is always
  /// entered with a fresh root.
  bool get hasCandidates => _hasCandidates;

  /// Conjugates every measure this slot computes (matching, [motion],
  /// [separation]) by the affine chart map `(x, y) ↦ ((x − cx)/scale,
  /// (y − cy)/scale)` — homogeneously `[x : y : w] ↦ [(x − cx·w)/scale
  /// : (y − cy·w)/scale : w]`, linear, so complex and infinite points
  /// transform soundly.
  ///
  /// The raw chordal measure on `[x, y, 1]` lifts is the angle metric at
  /// the *world origin*: two points far from the origin in a similar
  /// direction are chordally close no matter how far apart they sit in
  /// world terms, which degrades nearest matching and the Cinderella
  /// bound for configurations living far out — exactly where a locus's
  /// projective line sweeps go (the Phase 117 fixture had a branch
  /// silently swap onto a candidate 300 world units away because both
  /// sat ~700 from the origin). Balancing re-centers the metric on the
  /// figure. Identity by default — drag tracing, whose geometry lives
  /// on screen, is bitwise unaffected until a caller opts in. Reset by
  /// [clear], so balance never leaks across passes; set it before
  /// [seed] so the seed separation is measured under it.
  void setBalance({required double cx, required double cy, required double scale}) {
    if (!(scale > 0) || !scale.isFinite || !cx.isFinite || !cy.isFinite) {
      throw ArgumentError('Balance needs finite cx/cy and a positive scale');
    }
    _balanceCx = cx;
    _balanceCy = cy;
    _balanceInvScale = 1 / scale;
    _balanced = cx != 0 || cy != 0 || scale != 1;
  }

  ProjPoint _balance(ProjPoint p) {
    if (!_balanced) {
      return p;
    }
    final k = _balanceInvScale;
    return ProjPoint(
      (p.x - p.w.scale(_balanceCx)).scale(k),
      (p.y - p.w.scale(_balanceCy)).scale(k),
      p.w,
    );
  }

  /// The balanced chordal distance from the stored root to [p] — the
  /// instance counterpart of [chordalDistance] under this slot's
  /// balance.
  double distanceFrom(ProjPoint p) =>
      chordalDistance(_balance(root), _balance(p));

  /// Activates the slot on [p] — the tracked identity at the start of a
  /// tracing pass (typically the owner's current root, however it was
  /// selected). [candidates] should be the owner's candidate set at the
  /// same state, so [separation] constrains the pass's first trial like
  /// every later one; omitting it leaves the first trial unconstrained.
  /// Throws on the zero triple: it is no point, and nearest matching
  /// against it is meaningless.
  void seed(ProjPoint p, {List<ProjPoint> candidates = const []}) {
    if (p.isZero) {
      throw ArgumentError('Cannot seed a traced branch on the zero triple');
    }
    _store(p);
    _separation = _pairwiseSeparation(candidates);
    _motion = 0;
    _matchedIndex = -1;
    _hasCandidates = candidates.isNotEmpty;
    allowComplexCarriers = false;
    _active = true;
  }

  /// Matches the stored root against [candidates], stores the nearest one
  /// as the new root, and records [motion], [separation] and
  /// [matchedIndex] for the step controller. Returns the matched
  /// candidate. [candidates] must be non-empty and zero-triple-free, as
  /// `intersectionCandidates` guarantees.
  ProjPoint follow(List<ProjPoint> candidates) {
    final (index, measure) = _nearest(candidates);
    final matched = candidates[index];
    _motion = math.sqrt(measure);
    _matchedIndex = index;
    _hasCandidates = true;
    _store(matched);
    _separation = _pairwiseSeparation(candidates);
    return matched;
  }

  /// Records a candidate-free substep (a parent momentarily undefined or
  /// coincident): the root is kept for matching to resume from, motion is
  /// nothing, and [separation] resets to infinity so the re-acquisition
  /// step, whose motion no continuous history can bound, is not refused.
  void coast() {
    _motion = 0;
    _matchedIndex = -1;
    _hasCandidates = false;
    _separation = double.infinity;
  }

  /// Deactivates the slot; the owner reverts to static branch selection.
  /// The stored coordinates are kept but mean nothing until re-seeded.
  /// The balance resets to identity — it never outlives its pass.
  void clear() {
    _active = false;
    allowComplexCarriers = false;
    _balanceCx = 0;
    _balanceCy = 0;
    _balanceInvScale = 1;
    _balanced = false;
  }

  /// The slot's state, for the step controller to [restore] when it
  /// refuses a trial step.
  TracedBranchCheckpoint checkpoint() => TracedBranchCheckpoint._(
        Float64List.fromList(_root),
        _separation,
        _motion,
        _matchedIndex,
        _hasCandidates,
      );

  /// Rolls the slot back to [state] (see [checkpoint]).
  void restore(TracedBranchCheckpoint state) {
    _root.setAll(0, state._root);
    _separation = state._separation;
    _motion = state._motion;
    _matchedIndex = state._matchedIndex;
    _hasCandidates = state._hasCandidates;
  }

  /// The index of the candidate projectively nearest the stored root, by
  /// the scale-invariant chordal measure `|p × c|² / (|p|²·|c|²)` — the
  /// same residual `ProjPoint.closeTo` bounds, usable on complex
  /// candidates. Ties break to the lower index (deterministic; breaking
  /// them *well* is Phase 115's detour). [candidates] must be non-empty
  /// and zero-triple-free, as `intersectionCandidates` guarantees.
  int nearestIndexAmong(List<ProjPoint> candidates) =>
      _nearest(candidates).$1;

  (int, double) _nearest(List<ProjPoint> candidates) {
    final p = _balance(root);
    final pNorm2 = p.norm2;
    var best = 0;
    var bestMeasure = double.infinity;
    for (var i = 0; i < candidates.length; i++) {
      final c = _balance(candidates[i]);
      final measure = p.join(c).norm2 / (pNorm2 * c.norm2);
      if (measure < bestMeasure) {
        bestMeasure = measure;
        best = i;
      }
    }
    return (best, bestMeasure);
  }

  double _pairwiseSeparation(List<ProjPoint> candidates) {
    if (!_balanced) {
      return _minPairwiseSeparation(candidates);
    }
    return _minPairwiseSeparation(
      [for (final c in candidates) _balance(c)],
    );
  }

  /// The chordal distance between two points — the sqrt of the
  /// scale-invariant measure `|p × q|² / (|p|²·|q|²)` that all tracing
  /// comparisons ([nearestIndexAmong], [motion], [separation]) are built
  /// on. Zero exactly on projectively equal points, usable on complex and
  /// infinite ones, invariant under rescaling either argument.
  static double chordalDistance(ProjPoint p, ProjPoint q) =>
      math.sqrt(p.join(q).norm2 / (p.norm2 * q.norm2));

  static double _minPairwiseSeparation(List<ProjPoint> candidates) {
    var min = double.infinity;
    for (var i = 0; i < candidates.length; i++) {
      for (var j = i + 1; j < candidates.length; j++) {
        final d = chordalDistance(candidates[i], candidates[j]);
        if (d < min) min = d;
      }
    }
    return min;
  }

  void _store(ProjPoint p) {
    _root[0] = p.x.re;
    _root[1] = p.x.im;
    _root[2] = p.y.re;
    _root[3] = p.y.im;
    _root[4] = p.w.re;
    _root[5] = p.w.im;
  }
}

/// A [TracedBranch]'s state at an accepted step — taken by
/// [TracedBranch.checkpoint], rolled back by [TracedBranch.restore] when
/// the step controller refuses a trial.
class TracedBranchCheckpoint {
  TracedBranchCheckpoint._(
    this._root,
    this._separation,
    this._motion,
    this._matchedIndex,
    this._hasCandidates,
  );

  final Float64List _root;
  final double _separation;
  final double _motion;
  final int _matchedIndex;
  final bool _hasCandidates;

  /// The candidate separation at the checkpointed step — half of it is
  /// the motion the Cinderella rule allows the next trial.
  double get separation => _separation;

  /// [TracedBranch.hasCandidates] at the checkpointed step — the "was
  /// matching" side of the match→coast transition refusal.
  bool get hasCandidates => _hasCandidates;
}
