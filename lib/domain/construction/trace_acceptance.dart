/// The shared trial-acceptance rules of the tracing walk (Phases 114–117).
///
/// Extracted from `Construction`'s drag walk in Phase 117 so the locus
/// sweep (`Locus.recompute`, which traces its private chain outside any
/// `Construction` pass) applies the *identical* acceptance semantics —
/// the Cinderella rule, the absolute motion cap, collision refusal and
/// coast-entry refusal — instead of re-deriving them. Behaviour is
/// pinned by the Phase 114–116b engine tests; these helpers are the same
/// code under public names.
library;

import '../projective/tolerances.dart';
import '../projective/tracing/singularity.dart';
import '../projective/tracing/traced_branch.dart';
import 'objects/intersection_point.dart';

/// The largest chordal motion any accepted step may carry, regardless
/// of separation (sin of ~14.5° on the root's projective line). The
/// separation-relative bound alone is unsound at large steps: the
/// chordal metric is the geometry of RP¹, where two chart-distant
/// roots can be *close through the point at infinity* — a glados
/// counterexample had a quarter-turn step match each root to the other
/// branch with motions just under sep/2 (a silent swap the collision
/// check cannot see either, since the swapped match is a bijection).
/// Capping the accepted motion forces refinement long before that
/// ambiguity: within small steps, continuity decides correctly.
/// Legitimate through-infinity motion (a line∩line meet under a
/// parallel sweep) is not forbidden — it just refines into more steps.
const double maxAcceptedMotion = 0.25;

/// The widest trial span (in path-parameter units) that may *enter* a
/// coast: a match→coast transition on a wider trial is refused (see
/// [trialAccepted]). Matches [detourTriggerStep]'s scale — by the
/// time refinement is this fine, the carrier degeneracy is localized
/// and the root retained on coast entry is fresh to within one
/// tiny step's motion.
const double maxCoastEntrySpan = 1e-5;

/// The tightest candidate separation across the seeded slots at the
/// current state — the collapse-law sample singularity estimation
/// reads (infinite when every slot is unconstrained, e.g. single-root
/// line∩line branches, which keeps estimation quiet).
double minSeparation(List<IntersectionPoint> seeded) {
  var min = double.infinity;
  for (final o in seeded) {
    final s = o.tracedBranch.separation;
    if (s < min) min = s;
  }
  return min;
}

/// The Cinderella acceptance rule over one trial's matches: every
/// followed root must have moved less than half its candidates'
/// separation at the previous accepted step ([checkpoints]), and less
/// than [maxAcceptedMotion] outright. A branch coasting this trial
/// (no candidates) imposes nothing — *unless* it was matching at the
/// previous accepted step and [span] exceeds [maxCoastEntrySpan]: a
/// wide trial whose endpoint kills the candidates has absorbed an
/// unchecked crossing of a carrier degeneracy (the Phase 116b
/// Cinderella demo starved on exactly this — a half-path trial landing
/// bitwise on the circles' coincidence froze the slot on a stale
/// root), so it is refused and refinement localizes the degeneracy
/// first. Coast→coast and seeded-while-undefined branches stay
/// permissive, as does re-acquisition. Written so a NaN motion —
/// degenerate norms upstream — refuses the trial rather than
/// accepting it.
bool trialAccepted(
  List<IntersectionPoint> seeded,
  List<TracedBranchCheckpoint?> checkpoints,
  double span,
) {
  for (var i = 0; i < seeded.length; i++) {
    final branch = seeded[i].tracedBranch;
    if (branch.matchedIndex < 0) {
      if (!branch.hasCandidates &&
          checkpoints[i]!.hasCandidates &&
          span > maxCoastEntrySpan) {
        return false;
      }
      continue;
    }
    final allowed = checkpoints[i]!.separation / 2;
    final cap = allowed < maxAcceptedMotion ? allowed : maxAcceptedMotion;
    if (!(branch.motion < cap)) {
      return false;
    }
  }
  return true;
}

/// Collision refusal over the distinct-seeded [pairs] on a shared curve
/// pair: refuse the trial when both grabbed the same candidate while
/// the candidate set held a genuinely distinct alternative. When the
/// candidates coincide anyway ([TracedBranch.separation] within
/// `doubleRootEpsilon` — a double root), riding the touch point
/// together is correct and halving could not separate the matches, so
/// the grab is benign. (Separation is the set's minimum pairwise
/// distance — for today's two-candidate sets that *is* the distance to
/// the alternative; once conic∩conic carriers expose four real
/// candidates (Phases 119–120) it is a conservative proxy.)
bool collisionFree(List<(TracedBranch, TracedBranch)> pairs) {
  for (final (a, b) in pairs) {
    if (a.matchedIndex >= 0 &&
        a.matchedIndex == b.matchedIndex &&
        a.separation > doubleRootEpsilon) {
      return false;
    }
  }
  return true;
}

/// The distinct-seeded pairs on shared ordered curve pairs — the input
/// [collisionFree] checks every trial. Pairs whose seeds already
/// coincide (within `doubleRootEpsilon`) are exempt: they legitimately
/// travel together (duplicate branch objects, a pass starting on a
/// tangency) and no step size could ever separate their matches.
List<(TracedBranch, TracedBranch)> collisionCheckPairs(
  List<IntersectionPoint> seeded,
) {
  final pairs = <(TracedBranch, TracedBranch)>[];
  final byPair = <(Object, Object), List<IntersectionPoint>>{};
  for (final o in seeded) {
    byPair.putIfAbsent((o.curve1, o.curve2), () => []).add(o);
  }
  for (final group in byPair.values) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final a = group[i].tracedBranch;
        final b = group[j].tracedBranch;
        if (TracedBranch.chordalDistance(a.root, b.root) > doubleRootEpsilon) {
          pairs.add((a, b));
        }
      }
    }
  }
  return pairs;
}
