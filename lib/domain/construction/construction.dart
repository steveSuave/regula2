import 'dart:collection';
import 'dart:math' as math;

import '../math/vec2.dart';
import '../projective/complex.dart';
import '../projective/proj_point.dart';
import '../projective/tolerances.dart';
import '../projective/tracing/drag_path.dart';
import '../projective/tracing/singularity.dart';
import '../projective/tracing/trace_diagnostics.dart';
import '../projective/tracing/trace_step_budget_exception.dart';
import '../projective/tracing/traced_branch.dart';
import 'geo_object.dart';
import 'object_attributes.dart';
import 'objects/expression_text.dart';
import 'objects/free_point.dart';
import 'objects/intersection_point.dart';
import 'objects/locus.dart';
import 'objects/point_on_object.dart';
import 'trace_acceptance.dart';

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

  /// A short human label for [id] — its name if it has one, otherwise
  /// its kind and a truncated id. For diagnostics and log lines only;
  /// never parsed, never shown as a name in the UI.
  String nameOf(String id) {
    final object = _objects[id];
    if (object == null) {
      return '<$id gone>';
    }
    final name = object.attributes.name;
    if (name.isNotEmpty) {
      return name;
    }
    return '${object.runtimeType}#${id.length > 6 ? id.substring(0, 6) : id}';
  }

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
  /// by continuity instead of canonical re-selection. When the pass
  /// completes, each seeded point *adopts* the branch the trace followed
  /// (Phase 116): `branchIndex` is re-derived as the canonical-order
  /// index its final step matched ([TracedBranch.matchedIndex] — the
  /// index into the end state's canonically ordered candidates), except
  /// on a double root, where canonical order carries no information and
  /// the seeded index is kept. Slots are then cleared, so every later
  /// *static* recompute re-selects the adopted — traced — branch:
  /// identity survives commits, saves and the drag session's static
  /// bail. Identity also chains across consecutive calls because each
  /// seeds from the value the previous pass left behind. A pass that
  /// throws adopts nothing (the state it leaves is its entry state or a
  /// mid-path real position; the caller's static solve re-selects by the
  /// last adopted index).
  ///
  /// **Step control (the Cinderella rule).** The first trial attempts the
  /// whole path. A trial is accepted only if every traced root moved less
  /// than *half its candidates' minimum pairwise separation at the
  /// previous accepted step* — the condition under which nearest-root
  /// matching cannot silently merge two branches — and less than an
  /// absolute cap ([maxAcceptedMotion], which closes the rule's
  /// through-infinity loophole), and no two distinct-seeded branches on
  /// the same curve pair grabbed the same candidate (collision refusal;
  /// see `trace_acceptance.dart`). A refused trial is rolled back
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
  /// through one half-plane of the path's own parameter. Which one
  /// *alternates per colliding point* — the negation of the half-plane
  /// that point last detoured in — which is what makes a there-and-back
  /// drag an identity, and it replaces reading the half-plane off the
  /// drag direction, whose seam lay on the horizontal axis (Phase 120c;
  /// see [_alternatingOrientation], which still opens on the direction
  /// rule for a collision with no history). On the
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
    Map<String, ProjPoint>? seedMemory,
    void Function(double t)? onStep,
  }) {
    final object = _objects[id];
    if (object is! FreePoint) {
      throw ArgumentError('$id is not a FreePoint in this construction');
    }
    return _traceAlong(
      id: id,
      driveReal: (t) => object.position = path.at(t),
      driveComplex: (t) => object.tracedPosition = path.evaluate(t),
      orientation: detourOrientation(path.start, path.end),
      stepBudget: stepBudget,
      seedMemory: seedMemory,
      onStep: onStep,
    );
  }

  /// Moves the constrained point [id] along its host curve from
  /// parameter [from] to [to] with the same adaptive tracing walk as
  /// [recomputeAlongPath] — the parameter-drag drive (Phase 116b).
  ///
  /// Real steps set the (real) interpolated parameter and re-enter the
  /// point's own `recompute`, so host extent clamping behaves exactly as
  /// in [setPointOnObjectParameter] — and a clamped stretch cannot
  /// starve the controller, since the position is constant there. A
  /// complex detour instead evaluates the carrier's chart form at the
  /// complex interpolated parameter (`PointOnObject.tracedPosition`,
  /// pass-internal; the stored parameter stays real throughout — PLAN
  /// §Parameterization). The carrier itself never moves during a
  /// parameter drag, so its chart form is captured once per pass.
  ///
  /// Everything else — seeding, acceptance, collision refusal, detour
  /// planning, branch adoption at pass end, bail semantics — is
  /// [recomputeAlongPath]'s, verbatim; matching continuity likewise
  /// assumes [from] is where the point currently sits. Throws
  /// [ArgumentError] when [id] is not a [PointOnObject] or [stepBudget]
  /// < 1.
  ({int acceptedSteps, int rejectedSteps, int detours})
      recomputeAlongParameterPath(
    String id,
    double from,
    double to, {
    int stepBudget = 128,
    Map<String, ProjPoint>? seedMemory,
    void Function(double t)? onStep,
  }) {
    final object = _objects[id];
    if (object is! PointOnObject) {
      throw ArgumentError('$id is not a PointOnObject in this construction');
    }
    final evaluate = _chartEvaluator(object);
    return _traceAlong(
      id: id,
      driveReal: (t) {
        // The two-product lerp form, like DragPath.at: bitwise-exact
        // endpoints, so the commit's static solve lands identically.
        object.parameter = from * (1 - t) + to * t;
        object.recompute();
      },
      driveComplex: (t) {
        final s = Complex.one - t;
        object.tracedPosition = evaluate(s.scale(from) + t.scale(to));
      },
      orientation: detourOrientation1D(from, to),
      stepBudget: stepBudget,
      seedMemory: seedMemory,
      onStep: onStep,
    );
  }

  /// The holomorphic continuation of [object]'s carrier chart form —
  /// mirrors `LineEq.pointAt` / `CircleEq.pointAt` operation for
  /// operation, so a real-valued complex parameter reproduces the real
  /// evaluation exactly (zero imaginary parts; a detour rejoins the real
  /// axis bitwise). Extent clamping is deliberately absent: a complex
  /// parameter cannot be clamped, and every real step re-enters the
  /// clamping `recompute`. With a chartless carrier the evaluator
  /// throws, but is unreachable: an undefined carrier leaves every
  /// dependent candidate-free, nothing seeds, and the pass collapses to
  /// the static solve without ever detouring.
  static ProjPoint Function(Complex) _chartEvaluator(PointOnObject object) {
    switch (object.curve) {
      case GeoLine(line: final form?):
        final anchor = form.pointOnLine;
        final direction = form.direction;
        return (p) => ProjPoint(
              Complex(anchor.x) + p.scale(direction.x),
              Complex(anchor.y) + p.scale(direction.y),
              Complex.one,
            );
      case GeoCircle(circle: final form?):
        final center = form.center;
        final radius = form.radius;
        return (p) => ProjPoint(
              Complex(center.x) + p.cos.scale(radius),
              Complex(center.y) + p.sin.scale(radius),
              Complex.one,
            );
      default:
        return (_) => throw StateError(
              'No chart to continue: the carrier of ${object.id} is undefined',
            );
    }
  }

  /// The shared tracing walk (Phases 114–116) behind [recomputeAlongPath]
  /// and [recomputeAlongParameterPath]: [driveReal] puts the dragged
  /// object at real path parameter `t` (including its own recompute, if
  /// it needs one), [driveComplex] at a complex `t` during a detour arc;
  /// [orientation] is the drive's odd detour orientation. See
  /// [recomputeAlongPath] for the full contract.
  /// [seedMemory], when provided, is *gesture-scoped* continuation state
  /// (Phase 116b): a pass whose start state leaves an intersection
  /// undefined — the previous preview frame ended exactly on a carrier
  /// degeneracy, coincident circles say — has no live root to seed from,
  /// and without help identity would reset to the canonical solve when
  /// the point re-emerges. Seeding falls back to the memory's root (the
  /// value the *previous pass in the same gesture* left there — a
  /// completed pass writes every seeded slot's final root back), so
  /// matching resumes across the undefined stretch exactly as a coast
  /// resumes within one pass. The caller owns the map's lifetime and
  /// must not let it outlive its drag gesture (the drag session clears
  /// it on bail and drops it at gesture end) — continuation state never
  /// survives a commit, save or bail, per the Phase 115 architecture
  /// notes.
  ({int acceptedSteps, int rejectedSteps, int detours}) _traceAlong({
    required String id,
    required void Function(double t) driveReal,
    required void Function(Complex t) driveComplex,
    required double orientation,
    required int stepBudget,
    Map<String, ProjPoint>? seedMemory,
    void Function(double t)? onStep,
  }) {
    if (stepBudget < 1) {
      throw ArgumentError.value(stepBudget, 'stepBudget', 'must be at least 1');
    }
    TraceDiagnostics.count(TraceCounter.dragPasses);
    final affected = transitiveDependentsOf(id);
    // Loci are DAG leaves (nothing may take one as a parent: both
    // `IntersectionPoint` and `PointOnObject` reject them), so no
    // acceptance decision can read one. Recomputing a locus is a whole
    // traced sweep of its own — orders of magnitude more work than the
    // rest of the graph — so the walk holds them back and settles them
    // once, in the `finally` below, at whatever state the pass ends on.
    // Before Phase 117b a single starving frame paid `stepBudget` full
    // sweeps (~130) before bailing, which is what froze the app on
    // documents that carry both a locus and a degenerate intersection.
    final affectedLoci = [
      for (final o in _objects.values)
        if (o is Locus && affected.contains(o.id)) o,
    ];
    final affectedCore = {
      ...affected,
    }..removeAll([for (final l in affectedLoci) l.id]);
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
        // A live root wins; an undefined intersection falls back to the
        // gesture's seed memory so identity bridges a degenerate frame
        // boundary (the candidate list is empty there, leaving the seed
        // separation infinite — the first trial is unconstrained, like
        // a coast re-acquisition).
        final p = o.projPoint ?? seedMemory?[o.id];
        if (p != null && !p.isZero) {
          final candidates = intersectionCandidates(o.curve1, o.curve2);
          // Structural double roots never seed (Phase 117b). A point
          // built as `TangentLine ∩ the circle it touches` has its two
          // candidates coincident *by construction*, at every position
          // of every parent — there is no second branch to hold
          // identity against, and no step size could separate the
          // matches. Seeding one made the Cinderella bound
          // (motion < separation/2, with separation ~1e-16) refuse
          // every trial, so the controller halved to nothing and the
          // whole pass starved and bailed — on every frame of every
          // drag. Left unseeded, the slot simply resolves canonically,
          // which is exact when the candidates coincide, and the pass's
          // other slots keep tracing.
          if (TracedBranch.candidateSeparation(candidates) >
              doubleRootEpsilon) {
            o.tracedBranch.seed(p, candidates: candidates);
            seeded.add(o);
          }
        }
      }
    }
    // Collision refusal (Phase 114): two branches on the same ordered
    // curve pair must never silently grab the same candidate — that is
    // nearest matching gone ambiguous (a tie the Cinderella bound cannot
    // see after a coast lifted it). See `trace_acceptance.dart`.
    final checkPairs = collisionCheckPairs(seeded);
    try {
      if (seeded.isEmpty) {
        driveReal(1);
        _recomputeAffected(affectedCore);
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
      var sepCurr = minSeparation(seeded);
      // The widest span the next accepted step may cover before an
      // extrapolated root collision could hide inside it (Phase 117b).
      var stepLimit = double.infinity;

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
          var dTheta = maxDetourArcStep;
          while (theta > 0) {
            TraceDiagnostics.checkpoint(
              'drag detour arc',
              detail: () => 'theta=${theta.toStringAsFixed(6)} '
                  'dTheta=${dTheta.toStringAsExponential(2)} '
                  'trials=${accepted + rejected}/$stepBudget',
            );
            if (accepted + rejected >= stepBudget) {
              for (final o in seeded) {
                o.tracedBranch.allowComplexCarriers = false;
              }
              driveReal(arc.entry);
              _recomputeAffected(affectedCore);
              throw TraceStepBudgetException(
                tReached: arc.entry,
                trials: accepted + rejected,
              );
            }
            final trialTheta = theta - dTheta > 0 ? theta - dTheta : 0.0;
            driveComplex(arc.tAt(trialTheta));
            _recomputeAffected(affectedCore);
            if (trialAccepted(
                  seeded,
                  checkpoints,
                  (theta - trialTheta) * arc.radius,
                ) &&
                collisionFree(checkPairs)) {
              accepted++;
              TraceDiagnostics.count(TraceCounter.dragAccepted);
              theta = trialTheta;
              dTheta = math.min(dTheta * 2 < theta ? dTheta * 2 : theta, maxDetourArcStep);
              snapshot();
            } else {
              rejected++;
              TraceDiagnostics.count(TraceCounter.dragRejected);
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
        TraceDiagnostics.checkpoint(
          'drag walk',
          detail: () => 't=${t.toStringAsFixed(9)} '
              'step=${step.toStringAsExponential(2)} '
              'sep=${sepCurr.toStringAsExponential(2)} '
              'trials=${accepted + rejected}/$stepBudget',
        );
        if (accepted + rejected >= stepBudget) {
          throw TraceStepBudgetException(
            tReached: t,
            trials: accepted + rejected,
          );
        }
        final trialT = t + step < 1 ? t + step : 1.0;
        // A root collision extrapolated to lie inside this trial refuses
        // it unevaluated: refine instead, so the collision is localized
        // at a step *end* where the fold/crossing machinery can classify
        // it, never glided over (Phase 117b — see [collisionStepLimit]).
        // Refusal falls through to the shared starvation path below, so
        // the throttle converges into a detour rather than the budget.
        final overStepLimit = trialT - t > stepLimit;
        var accept = false;
        if (!overStepLimit) {
          driveReal(trialT);
          _recomputeAffected(affectedCore);
          accept = trialAccepted(seeded, checkpoints, trialT - t) &&
              collisionFree(checkPairs);
        }
        if (accept) {
          accepted++;
          TraceDiagnostics.count(TraceCounter.dragAccepted);
          t = trialT;
          step = step * 2 < 1 ? step * 2 : 1.0;
          snapshot();
          tPrev = tCurr;
          sepPrev = sepCurr;
          tCurr = t;
          sepCurr = minSeparation(seeded);
          stepLimit = collisionStepLimit(
            t1: tPrev,
            s1: sepPrev,
            t2: tCurr,
            s2: sepCurr,
          );
          onStep?.call(trialT);
        } else {
          rejected++;
          TraceDiagnostics.count(TraceCounter.dragRejected);
          if (!overStepLimit) {
            restoreAll();
          }
          step /= 2;
          // Starvation ⇒ detour attempt: the step has collapsed while
          // the tightest separation did — a root collision ahead on the
          // real axis (a large separation would instead point at the
          // absolute motion cap refining a legitimate sweep).
          if (step < detourTriggerStep && sepCurr < detourTriggerSeparation) {
            // Prefer the *measured* collision to the extrapolated one
            // (Phase 117b — see [locateSeparationMinimum]): the collapse
            // law is exact only on the √ law of a transverse tangency
            // and undershoots persistently on the linear law of a
            // transversal crossing, which centres the arc on the
            // collision's near shoulder instead of the collision. A
            // measured *near-miss* decides the question outright —
            // the roots never meet ahead, so no arc is planned at all
            // and the pass refines through or bails honestly.
            final culprits = [
              for (final o in seeded)
                if (o.tracedBranch.separation < detourTriggerSeparation) o,
            ];
            final measured = _measureCollision(
              culprits,
              driveReal,
              affectedCore,
              restoreAll,
              t,
            );
            final tStar = measured == null
                ? estimateSingularParameter(
                    t1: tPrev,
                    s1: sepPrev,
                    t2: tCurr,
                    s2: sepCurr,
                  )
                : (measured.isCollision && measured.t > t ? measured.t : null);
            // The half-plane alternates per culprit rather than being
            // read off the drag direction (Phase 120c — see
            // [IntersectionPoint.lastDetourOrientation]). [orientation]
            // is only the opening move, for a collision none of these
            // points has crossed before.
            final arcOrientation = _alternatingOrientation(
              culprits,
              orientation,
            );
            final arc = tStar == null
                ? null
                : DetourArc.plan(
                    entry: t,
                    tStar: tStar,
                    orientation: arcOrientation,
                  );
            if (arc != null) {
              traceArc(arc);
              // Only the culprits wound around anything: the arc encloses
              // *their* branch point, and every other slot's value is
              // analytic there, so winding around it is the identity for
              // them however the arc was oriented.
              for (final o in culprits) {
                o.lastDetourOrientation = arcOrientation;
              }
              detours++;
              TraceDiagnostics.count(TraceCounter.dragDetours);
              t = arc.exit;
              // Resume at the arc's own scale: the roots just crossed a
              // near-degeneracy, so accepted steps grow from there by
              // doubling — restarting from the whole remaining path
              // would burn ~30 refusals halving back down.
              step = arc.radius;
              tPrev = t;
              sepPrev = double.infinity;
              tCurr = t;
              sepCurr = minSeparation(seeded);
              stepLimit = double.infinity;
              onStep?.call(t);
            }
          }
        }
      }
      // Branch adoption (Phase 116): the final accepted step ran at
      // t = 1 on real carriers, so each slot's matchedIndex is the
      // index of the tracked root in the end state's canonically
      // ordered candidate list — exactly the re-derived branchIndex.
      // No adoption when the step coasted (matchedIndex −1: nothing
      // was matched), on a double root (separation within
      // doubleRootEpsilon: the tie broke arbitrarily and canonical
      // order says nothing), or outside the range branchIndex
      // addresses.
      //
      // That range is [maxBranchCount], and it must stay in step with
      // it: capping adoption below what `branchIndex` can hold makes
      // adoption *asymmetric*, which is worse than not adopting at
      // all. A root landing at an addressable index writes back while
      // one landing past the cap silently does not, so two branches
      // converge onto the same stored index and the next static
      // recompute puts both points on the same root. The cap sat at 1
      // from Phase 116, when two candidates was the most any carrier
      // pair could produce; Phase 120's conics made four reachable and
      // four intersection points collapsed to one within two drag
      // frames (Phase 120c).
      for (final o in seeded) {
        final branch = o.tracedBranch;
        if (branch.matchedIndex >= 0 &&
            branch.matchedIndex < IntersectionPoint.maxBranchCount &&
            branch.separation > doubleRootEpsilon) {
          o.branchIndex = branch.matchedIndex;
        }
        // Refresh the gesture's seed memory with the root the completed
        // pass leaves behind — a coasting slot retains its last followed
        // root, which is exactly what the next pass must resume from
        // when the intersection is undefined at its start.
        seedMemory?[o.id] = branch.root;
      }
      return (acceptedSteps: accepted, rejectedSteps: rejected, detours: detours);
    } finally {
      for (final o in seeded) {
        o.tracedBranch.clear();
      }
      // The held-back leaves, settled once at the state the pass ends
      // on — the accepted end, or the last trial of a bail. Slots are
      // cleared first: a locus sweep seeds its own chain.
      for (final locus in affectedLoci) {
        locus.recompute();
      }
      _notify();
    }
  }

  /// The half-plane the next detour around [culprits]' collision must be
  /// walked in: the negation of what they last used, or [fallback] when
  /// none of them has detoured before.
  ///
  /// Alternation is what makes a there-and-back drag an identity, and it
  /// replaces reading the half-plane off the drag direction — which was
  /// odd in the direction, as it must be, but took the direction's sign
  /// from `dy` and only fell back to `dx` when `dy` was *exactly* zero.
  /// The seam of that rule therefore sat on the horizontal axis, which is
  /// where "drag the two circles onto each other" lives, so `dy` was pure
  /// pointer noise and each frame's half-plane was chosen by the sign of
  /// the jitter. Measured on two equal-radius circles dragged past
  /// tangency and back: exactly horizontal returned correctly 60 times out
  /// of 60, and ±0.05 px of y-jitter sent the point back on the far side
  /// of the circle in about a third of runs (Phase 120c). Any ±1 rule on
  /// directions has such a seam somewhere; alternation has none because it
  /// never looks at the direction.
  ///
  /// **The trade is that this carries state and so is not
  /// self-correcting.** A memoryless rule recovers on the next frame; if a
  /// crossing detours on the way out but the way back bails
  /// ([TraceStepBudgetException]) instead of detouring, the parity is
  /// wrong from then on. Detours were measured firing symmetrically on all
  /// 60 randomized frame subdivisions of the rig above, so this is the
  /// rare path — but it is a real one.
  ///
  /// Histories that disagree fall back rather than picking a winner: the
  /// culprits of one collision are its two branches and normally share a
  /// history exactly, so disagreement means the premise does not hold.
  double _alternatingOrientation(
    List<IntersectionPoint> culprits,
    double fallback,
  ) {
    double? required;
    for (final o in culprits) {
      final last = o.lastDetourOrientation;
      if (last == null) continue;
      if (required == null) {
        required = -last;
      } else if (required != -last) {
        return fallback;
      }
    }
    return required ?? fallback;
  }

  /// The measured minimum of [culprits]' candidate separation ahead of
  /// [t] on the unit path (Phase 117b) — where the roots come closest,
  /// and how close — or null when the profile offers no bracket before
  /// the path's end, the one case that still falls back to the
  /// extrapolated estimate.
  ///
  /// Probing drives the path and recomputes, which follows the tracked
  /// roots, so the slots are restored afterwards exactly as
  /// [_probeIsReal]-style probes do. The construction is left at the
  /// last probe; the next trial re-drives it.
  SeparationMinimum? _measureCollision(
    List<IntersectionPoint> culprits,
    void Function(double) driveReal,
    Set<String> affectedCore,
    void Function() restoreAll,
    double t,
  ) {
    if (culprits.isEmpty) {
      return null;
    }
    final minimum = locateSeparationMinimum(
      from: t,
      end: 1,
      firstStep: detourTriggerStep,
      separationAt: (probe) {
        TraceDiagnostics.count(TraceCounter.collisionProbes);
        driveReal(probe);
        _recomputeAffected(affectedCore);
        var min = double.infinity;
        for (final o in culprits) {
          final sep = TracedBranch.candidateSeparation(
            intersectionCandidates(o.curve1, o.curve2),
          );
          if (sep < min) min = sep;
        }
        return min;
      },
    );
    restoreAll();
    return minimum;
  }

  /// Re-points the intersection point [id] at [branchIndex] and
  /// recomputes it and its transitive dependents (in topological order).
  ///
  /// The commit primitive of branch adoption (Phase 116): a traced drag
  /// can end with an intersection on the other canonical branch than it
  /// started (a crossed degeneracy flips the ordering under the tracked
  /// root), and the gesture's one command must replay that re-pointing
  /// in both directions for undo/redo to be exact. Throws
  /// [ArgumentError] when [id] is not an [IntersectionPoint] or
  /// [branchIndex] is outside `0..maxBranchCount − 1` — the same range
  /// the constructor accepts, and it must stay that way: this is the one
  /// path a *committed* re-pointing takes, so a narrower bound here
  /// rejects adoptions the trace legitimately made and throws out of the
  /// gesture's command (Phase 120c — it was `> 1` while conic∩conic
  /// carriers were producing 2 and 3, which is what made the four
  /// crossings of two ellipses keep merging after the engine itself
  /// stopped merging them).
  void setIntersectionBranch(String id, int branchIndex) {
    final object = _objects[id];
    if (object is! IntersectionPoint) {
      throw ArgumentError('$id is not an IntersectionPoint in this construction');
    }
    if (branchIndex < 0 ||
        branchIndex >= IntersectionPoint.maxBranchCount) {
      throw ArgumentError.value(
        branchIndex,
        'branchIndex',
        'must be 0..${IntersectionPoint.maxBranchCount - 1}',
      );
    }
    object.branchIndex = branchIndex;
    object.recompute();
    _recomputeDependentsOf(id);
    _notify();
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
    TraceDiagnostics.count(TraceCounter.chainSolves);
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
