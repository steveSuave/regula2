import 'dart:collection';
import 'dart:math' as math;

import '../math/vec2.dart';
import '../projective/tolerances.dart';
import '../projective/tracing/drag_path.dart';
import '../projective/tracing/singularity.dart';
import '../projective/tracing/trace_step_budget_exception.dart';
import '../projective/tracing/traced_branch.dart';
import 'geo_object.dart';
import 'object_attributes.dart';
import 'objects/expression_text.dart';
import 'objects/free_point.dart';
import 'objects/intersection_point.dart';
import 'objects/locus.dart';
import 'objects/point_on_object.dart';

/// The construction graph — the single source of truth for the app.
///
/// Owns every [GeoObject] in insertion order. Because an object's parents
/// must already be in the construction when it is added (and parents never
/// change), insertion order *is* a topological order: recomputing affected
/// objects in insertion order always sees up-to-date parents.
///
/// Mutations happen only through commands (see `domain/commands/`); the
/// methods here are the primitive operations those commands compose.
///
/// Notifies listeners after every mutation. This is a hand-rolled,
/// pure-Dart equivalent of `ChangeNotifier` — the domain layer must not
/// import Flutter (see CLAUDE.md); the application layer bridges this to
/// Riverpod.
class Construction {
  final LinkedHashMap<String, GeoObject> _objects =
      LinkedHashMap<String, GeoObject>();

  /// Direct dependents (children) by parent id. Maintained by [add] /
  /// [removeWithDependents]; powers dirty propagation and cascade delete.
  final Map<String, Set<String>> _dependents = {};

  final List<void Function()> _listeners = [];

  /// All objects, in insertion (= topological) order.
  Iterable<GeoObject> get objects => _objects.values;

  int get length => _objects.length;

  bool get isEmpty => _objects.isEmpty;

  GeoObject? byId(String id) => _objects[id];

  bool contains(String id) => _objects.containsKey(id);

  /// Adds [object] to the construction.
  ///
  /// Its parents must already be present (the *same instances* — the graph
  /// is wired by object reference, ids alone are not enough), and its id
  /// must be unused. Recomputes the object on entry so it is consistent
  /// with its parents' current state.
  void add(GeoObject object) {
    if (_objects.containsKey(object.id)) {
      throw ArgumentError('Duplicate object id: ${object.id}');
    }
    for (final parent in object.parents) {
      if (!identical(_objects[parent.id], parent)) {
        throw ArgumentError(
          'Parent ${parent.id} of ${object.id} is not in the construction',
        );
      }
    }
    _objects[object.id] = object;
    for (final parent in object.parents) {
      _dependents.putIfAbsent(parent.id, () => {}).add(object.id);
    }
    object.recompute();
    _notify();
  }

  /// Moves the free point [id] to [position] and recomputes its transitive
  /// dependents (in topological order).
  ///
  /// The only mutation of geometry the graph allows — everything else is
  /// derived. Throws [ArgumentError] when [id] is not a [FreePoint].
  void moveFreePoint(String id, Vec2 position) {
    final object = _objects[id];
    if (object is! FreePoint) {
      throw ArgumentError('$id is not a FreePoint in this construction');
    }
    object.position = position;
    _recomputeDependentsOf(id);
    _notify();
  }

  /// Moves the free point [id] along [path] with adaptive substeps,
  /// recomputing its transitive dependents at every accepted step — the
  /// tracing sibling of [moveFreePoint] (Phase 114; complex detours
  /// around degeneracies since Phase 115).
  ///
  /// Before stepping, every affected [IntersectionPoint] whose tracked
  /// candidate exists is seeded ([TracedBranch.seed], with its candidate
  /// set at the path start); during the pass their `recompute` follows
  /// the candidate nearest the tracked root, so branch identity is held
  /// by continuity instead of canonical re-selection. Slots are cleared
  /// before returning — [branchIndex] stays untouched, so the *next
  /// static recompute* re-selects canonically (the endpoint's tracked
  /// value persists only until then; commands and save keep static
  /// semantics until Phase 116). Identity chains across consecutive calls
  /// because each seeds from the value the previous pass left behind.
  ///
  /// **Step control (the Cinderella rule).** The first trial attempts the
  /// whole path. A trial is accepted only if every traced root moved less
  /// than *half its candidates' minimum pairwise separation at the
  /// previous accepted step* — the condition under which nearest-root
  /// matching cannot silently merge two branches — and less than an
  /// absolute cap ([_maxAcceptedMotion], which closes the rule's
  /// through-infinity loophole), and no two distinct-seeded branches on
  /// the same curve pair grabbed the same candidate (collision refusal;
  /// see [_collisionFree]). A refused trial is rolled back
  /// ([TracedBranch.restore]) and retried at half the step;
  /// an accepted step doubles it again (capped at the path end, which is
  /// reached bitwise-exactly).
  ///
  /// **Complex detour (Phase 115).** Near a degeneracy *on* the path the
  /// separation — and with it the allowed motion — collapses, so the
  /// controller starves. When the trial step has shrunk under
  /// [detourTriggerStep] while the tightest separation sits under
  /// [detourTriggerSeparation], the singular parameter is extrapolated
  /// from the last two accepted steps' separations
  /// ([estimateSingularParameter]) and the pass walks a [DetourArc]: the
  /// same interpolation continued holomorphically around the singularity
  /// through the *upper half-plane* of the path's own parameter — the
  /// fixed orientation that makes the crossing deterministic and a
  /// there-and-back drag an identity (see `singularity.dart`). On the
  /// arc the affected [IntersectionPoint]s accept complex carriers
  /// ([TracedBranch.allowComplexCarriers], arc-scoped) and the identical
  /// acceptance machinery walks it: away from the singularity the roots
  /// stay separated, so the arc resolves in bounded trials, lands
  /// exactly real, and real stepping resumes past the degeneracy —
  /// through-tangency drags cross with no jump and no swap. When no
  /// valid detour exists (the samples don't extrapolate, the singularity
  /// sits at or past the path's end, or the arc itself exhausts the
  /// budget) the pass throws [TraceStepBudgetException] once accepted
  /// plus refused trials reach [stepBudget], leaving the point real (at
  /// the last trial position, or back at the arc entry after a failed
  /// arc) with slots cleared; callers bail to a static solve (the drag
  /// session does — PLAN §Risks). Returns the accepted/rejected trial
  /// counts and the number of completed detours (the Phase 116
  /// debug-overlay feed).
  ///
  /// Excluded from seeding: intersection points inside a [Locus.chain] —
  /// the sweep-and-restore recompute would drag their roots along the
  /// sweep (Phase 117 rewrites loci on tracing). Points whose candidate
  /// set is empty at the start stay static too: there is no identity to
  /// continue. When nothing seeds, the pass collapses to a single static
  /// solve at the path's end (reported as one accepted step).
  ///
  /// Matching continuity assumes `path.start` is where the point
  /// currently sits (drag sessions anchor each preview path at the
  /// previous one's end). [onStep] fires after each *accepted* step's
  /// recompute at a real parameter — the arc's interior steps are
  /// complex and silent; a completed detour fires once, at its exit —
  /// the observation hook for the toy harness and the Phase 116 debug
  /// overlay. Notifies once, like [moveFreePoint]. Throws
  /// [ArgumentError] when [id] is not a [FreePoint] or [stepBudget] < 1.
  ({int acceptedSteps, int rejectedSteps, int detours}) recomputeAlongPath(
    String id,
    DragPath path, {
    int stepBudget = 128,
    void Function(double t)? onStep,
  }) {
    final object = _objects[id];
    if (object is! FreePoint) {
      throw ArgumentError('$id is not a FreePoint in this construction');
    }
    if (stepBudget < 1) {
      throw ArgumentError.value(stepBudget, 'stepBudget', 'must be at least 1');
    }
    final affected = transitiveDependentsOf(id);
    final excluded = <GeoObject>{};
    for (final o in _objects.values) {
      if (o is Locus) {
        excluded.addAll(o.chain);
      }
    }
    final seeded = <IntersectionPoint>[];
    for (final o in _objects.values) {
      if (o is IntersectionPoint &&
          affected.contains(o.id) &&
          !excluded.contains(o)) {
        final p = o.projPoint;
        if (p != null && !p.isZero) {
          o.tracedBranch.seed(
            p,
            candidates: intersectionCandidates(o.curve1, o.curve2),
          );
          seeded.add(o);
        }
      }
    }
    // Collision refusal (Phase 114): two branches on the same ordered
    // curve pair must never silently grab the same candidate — that is
    // nearest matching gone ambiguous (a tie the Cinderella bound cannot
    // see after a coast lifted it). Pairs whose seeds already coincide
    // are exempt: they legitimately travel together (duplicate branch
    // objects, a pass starting on a tangency) and no step size could
    // ever separate their matches.
    final checkPairs = <(TracedBranch, TracedBranch)>[];
    {
      final byPair = <(GeoObject, GeoObject), List<IntersectionPoint>>{};
      for (final o in seeded) {
        byPair.putIfAbsent((o.curve1, o.curve2), () => []).add(o);
      }
      for (final group in byPair.values) {
        for (var i = 0; i < group.length; i++) {
          for (var j = i + 1; j < group.length; j++) {
            final a = group[i].tracedBranch;
            final b = group[j].tracedBranch;
            if (TracedBranch.chordalDistance(a.root, b.root) >
                doubleRootEpsilon) {
              checkPairs.add((a, b));
            }
          }
        }
      }
    }
    try {
      if (seeded.isEmpty) {
        object.position = path.at(1);
        _recomputeAffected(affected);
        onStep?.call(1);
        return (acceptedSteps: 1, rejectedSteps: 0, detours: 0);
      }
      final checkpoints =
          List<TracedBranchCheckpoint?>.filled(seeded.length, null);
      void snapshot() {
        for (var i = 0; i < seeded.length; i++) {
          checkpoints[i] = seeded[i].tracedBranch.checkpoint();
        }
      }

      snapshot();
      var t = 0.0;
      var step = 1.0;
      var accepted = 0;
      var rejected = 0;
      var detours = 0;
      // Separation samples at the last two accepted steps — the
      // collapse-law data singularity estimation extrapolates. The
      // infinite "previous" sample keeps estimation quiet until two
      // genuine samples exist (after a detour they are reset the same
      // way: the law restarts on the far side of the singularity).
      var tPrev = 0.0;
      var sepPrev = double.infinity;
      var tCurr = 0.0;
      var sepCurr = _minSeparation(seeded);
      // One orientation per pass (the path has one direction): the odd
      // rule that makes a there-and-back drag an identity.
      final orientation = detourOrientation(path.start, path.end);

      void restoreAll() {
        for (var i = 0; i < seeded.length; i++) {
          seeded[i].tracedBranch.restore(checkpoints[i]!);
        }
      }

      /// Walks [arc] from θ = π (its entry — where the pass already
      /// sits) down to θ = 0 (its real exit past the singularity) with
      /// the identical acceptance machinery, complex carriers allowed
      /// for the duration. Trials share the pass budget; exhaustion
      /// mid-arc restores the real entry state and throws.
      void traceArc(DetourArc arc) {
        for (final o in seeded) {
          o.tracedBranch.allowComplexCarriers = true;
        }
        try {
          var theta = math.pi;
          var dTheta = math.pi;
          while (theta > 0) {
            if (accepted + rejected >= stepBudget) {
              for (final o in seeded) {
                o.tracedBranch.allowComplexCarriers = false;
              }
              object.position = path.at(arc.entry);
              _recomputeAffected(affected);
              throw TraceStepBudgetException(
                tReached: arc.entry,
                trials: accepted + rejected,
              );
            }
            final trialTheta = theta - dTheta > 0 ? theta - dTheta : 0.0;
            object.tracedPosition = path.evaluate(arc.tAt(trialTheta));
            _recomputeAffected(affected);
            if (_trialAccepted(seeded, checkpoints) &&
                _collisionFree(checkPairs)) {
              accepted++;
              theta = trialTheta;
              dTheta = dTheta * 2 < theta ? dTheta * 2 : theta;
              snapshot();
            } else {
              rejected++;
              restoreAll();
              dTheta /= 2;
            }
          }
        } finally {
          for (final o in seeded) {
            o.tracedBranch.allowComplexCarriers = false;
          }
        }
      }

      while (t < 1) {
        if (accepted + rejected >= stepBudget) {
          throw TraceStepBudgetException(
            tReached: t,
            trials: accepted + rejected,
          );
        }
        final trialT = t + step < 1 ? t + step : 1.0;
        object.position = path.at(trialT);
        _recomputeAffected(affected);
        if (_trialAccepted(seeded, checkpoints) && _collisionFree(checkPairs)) {
          accepted++;
          t = trialT;
          step = step * 2 < 1 ? step * 2 : 1.0;
          snapshot();
          tPrev = tCurr;
          sepPrev = sepCurr;
          tCurr = t;
          sepCurr = _minSeparation(seeded);
          onStep?.call(trialT);
        } else {
          rejected++;
          restoreAll();
          step /= 2;
          // Starvation ⇒ detour attempt: the step has collapsed while
          // the tightest separation did — a root collision ahead on the
          // real axis (a large separation would instead point at the
          // absolute motion cap refining a legitimate sweep).
          if (step < detourTriggerStep && sepCurr < detourTriggerSeparation) {
            final tStar = estimateSingularParameter(
              t1: tPrev,
              s1: sepPrev,
              t2: tCurr,
              s2: sepCurr,
            );
            final arc = tStar == null
                ? null
                : DetourArc.plan(
                    entry: t,
                    tStar: tStar,
                    orientation: orientation,
                  );
            if (arc != null) {
              traceArc(arc);
              detours++;
              t = arc.exit;
              // Resume at the arc's own scale: the roots just crossed a
              // near-degeneracy, so accepted steps grow from there by
              // doubling — restarting from the whole remaining path
              // would burn ~30 refusals halving back down.
              step = arc.radius;
              tPrev = t;
              sepPrev = double.infinity;
              tCurr = t;
              sepCurr = _minSeparation(seeded);
              onStep?.call(t);
            }
          }
        }
      }
      return (acceptedSteps: accepted, rejectedSteps: rejected, detours: detours);
    } finally {
      for (final o in seeded) {
        o.tracedBranch.clear();
      }
      _notify();
    }
  }

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
  static const double _maxAcceptedMotion = 0.25;

  /// The tightest candidate separation across the seeded slots at the
  /// current state — the collapse-law sample singularity estimation
  /// reads (infinite when every slot is unconstrained, e.g. single-root
  /// line∩line branches, which keeps estimation quiet).
  static double _minSeparation(List<IntersectionPoint> seeded) {
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
  /// than [_maxAcceptedMotion] outright. Coasting branches (no
  /// candidates this trial) impose nothing. Written so a NaN motion —
  /// degenerate norms upstream — refuses the trial rather than
  /// accepting it.
  static bool _trialAccepted(
    List<IntersectionPoint> seeded,
    List<TracedBranchCheckpoint?> checkpoints,
  ) {
    for (var i = 0; i < seeded.length; i++) {
      final branch = seeded[i].tracedBranch;
      if (branch.matchedIndex < 0) continue;
      final allowed = checkpoints[i]!.separation / 2;
      final cap = allowed < _maxAcceptedMotion ? allowed : _maxAcceptedMotion;
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
  static bool _collisionFree(List<(TracedBranch, TracedBranch)> pairs) {
    for (final (a, b) in pairs) {
      if (a.matchedIndex >= 0 &&
          a.matchedIndex == b.matchedIndex &&
          a.separation > doubleRootEpsilon) {
        return false;
      }
    }
    return true;
  }

  /// Moves the text [id]'s world anchor to [anchor] and notifies.
  ///
  /// The text sibling of [moveFreePoint] — the anchor is pure placement,
  /// so nothing recomputes: a text's rendered value reads its *parents*,
  /// never its own position, and texts are not referenceable, so they
  /// have no dependents. Throws [ArgumentError] when [id] is not an
  /// [ExpressionText].
  void moveTextAnchor(String id, Vec2 anchor) {
    final object = _objects[id];
    if (object is! ExpressionText) {
      throw ArgumentError('$id is not an ExpressionText in this construction');
    }
    object.anchor = anchor;
    _notify();
  }

  /// Re-parameterizes the constrained point [id] to [parameter] and
  /// recomputes it and its transitive dependents (in topological order).
  ///
  /// The constrained-point sibling of [moveFreePoint] — the parameter is
  /// the one mutable input a [PointOnObject] has, everything downstream is
  /// derived. Throws [ArgumentError] when [id] is not a [PointOnObject].
  void setPointOnObjectParameter(String id, double parameter) {
    final object = _objects[id];
    if (object is! PointOnObject) {
      throw ArgumentError('$id is not a PointOnObject in this construction');
    }
    object.parameter = parameter;
    object.recompute();
    _recomputeDependentsOf(id);
    _notify();
  }

  /// Replaces the attributes of object [id].
  ///
  /// Attributes are display-only — no geometry depends on them — so
  /// dependents never recompute, but listeners are notified (the painter
  /// must redraw). Texts are the one carve-out (Phase 72): their
  /// `renderedText` bakes `valueDecimals` inside `recompute()`, so the
  /// object itself re-renders — parents are untouched, dependents can't
  /// exist (nothing derives from a text). Throws [ArgumentError] for an
  /// unknown id.
  void setAttributes(String id, ObjectAttributes attributes) {
    final object = _objects[id];
    if (object == null) {
      throw ArgumentError('Unknown object id: $id');
    }
    object.attributes = attributes;
    if (object is GeoText) {
      object.recompute();
    }
    _notify();
  }

  /// The ids of every object that (transitively) depends on [id],
  /// excluding [id] itself.
  Set<String> transitiveDependentsOf(String id) {
    final result = <String>{};
    var frontier = <String>{id};
    while (frontier.isNotEmpty) {
      final next = <String>{};
      for (final fid in frontier) {
        for (final child in _dependents[fid] ?? const <String>{}) {
          if (result.add(child)) {
            next.add(child);
          }
        }
      }
      frontier = next;
    }
    return result;
  }

  /// Removes the object [id] and everything that depends on it.
  ///
  /// Returns the removed objects in insertion order — parents before
  /// children — so a delete command can hold them and [restore] can re-add
  /// them on undo. Throws [ArgumentError] for an unknown id.
  List<GeoObject> removeWithDependents(String id) {
    if (!_objects.containsKey(id)) {
      throw ArgumentError('Unknown object id: $id');
    }
    final doomed = transitiveDependentsOf(id)..add(id);
    final removed = [
      for (final object in _objects.values)
        if (doomed.contains(object.id)) object,
    ];
    for (final object in removed) {
      _objects.remove(object.id);
      _dependents.remove(object.id);
      for (final parent in object.parents) {
        _dependents[parent.id]?.remove(object.id);
      }
    }
    _notify();
    return removed;
  }

  /// Re-adds objects previously returned by [removeWithDependents], in the
  /// same order (parents before children).
  ///
  /// Restored objects are appended, so z-order within the construction may
  /// differ from before the delete — acceptable until rendering order
  /// becomes user-visible state.
  void restore(List<GeoObject> objects) {
    for (final object in objects) {
      add(object);
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  void _recomputeDependentsOf(String id) {
    final affected = transitiveDependentsOf(id);
    if (affected.isEmpty) {
      return;
    }
    _recomputeAffected(affected);
  }

  /// Recomputes the objects in [affected], in insertion (= topological)
  /// order.
  void _recomputeAffected(Set<String> affected) {
    for (final object in _objects.values) {
      if (affected.contains(object.id)) {
        object.recompute();
      }
    }
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
