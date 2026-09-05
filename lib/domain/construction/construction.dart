import 'dart:collection';
import 'dart:math' as math;

import '../math/vec2.dart';
import '../projective/complex.dart';
import '../projective/conic_shape.dart';
import '../projective/proj_point.dart';
import '../projective/tolerances.dart';
import '../projective/tracing/drag_path.dart';
import '../projective/tracing/singularity.dart';
import '../projective/tracing/trace_diagnostics.dart';
import '../projective/tracing/trace_step_budget_exception.dart';
import '../projective/tracing/traced_branch.dart';
import 'document_kernel.dart';
import 'geo_object.dart';
import 'geometry_change.dart';
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
  Construction({this._kernel = const DocumentKernel()});

  /// The geometry this document is drawn in — the absolute every metric
  /// recompute is founded on (PLAN §"M-CK — Cayley–Klein").
  ///
  /// **Read-only, and there is no setter — deliberately.** Through Phase
  /// 125 this was a `final` field, on the reasoning that a settable one is
  /// exactly how the re-addressing would get skipped. Phase 126 has to
  /// make it changeable and keeps the guarantee by changing the *shape* of
  /// the mutation rather than trusting the caller: the only way to alter
  /// it is [switchKernel], which cannot switch without re-pointing, and
  /// which hands back the report of what it did. The candidate list an
  /// `IntersectionPoint`'s `branchIndex` addresses is itself a function of
  /// the absolute (the circular-point filter, and canonical order's
  /// centre), so a switch that merely assigned would leave every stored
  /// address naming whatever crossing now sits at that index — PLAN
  /// §"The audit".
  DocumentKernel get kernel => _kernel;
  DocumentKernel _kernel;

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
    object.recompute(kernel.absolute);
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
  /// through [detourHalfPlane]'s half-plane of the path's own
  /// parameter — a **constant**, so a round trip closes a loop around the
  /// branch point and honestly trades the two roots (Phase 120c; see
  /// `singularity.dart` for why the constant, and for the
  /// reversal-identity convention it replaced). On the
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
  /// **A pass keeps what it carried across (Phase 189).** Exhausting the
  /// budget *after* a completed detour is not a failure: the identity
  /// the detour exists to carry has already crossed the singularity,
  /// and what is left is the exit's climb back to path scale — ~15
  /// trials on a tangency, ~40 on a transversal crossing, against an
  /// approach that already cost 47–93. So once `detours > 0` the pass
  /// does not throw at the budget; it stops at its last accepted real
  /// parameter, drives the construction there, adopts branches from that
  /// state exactly as a complete pass adopts them at the end, and
  /// reports `reached < 1`. The caller anchors its next path there and
  /// the exit finishes on a fresh budget. A pass with no detour behind
  /// it still throws: it has carried nothing a static solve would lose,
  /// and a path ending on a singularity would otherwise lag for ever.
  /// See PLAN §"A pass keeps what it carried across".
  ///
  /// Excluded from seeding: intersection points inside a [Locus.chain] —
  /// the sweep-and-restore recompute would drag their roots along the
  /// sweep (Phase 117 rewrites loci on tracing). Points whose candidate
  /// set is empty at the start stay static too: there is no identity to
  /// continue. When nothing seeds, the pass collapses to a single static
  /// solve at the path's end (reported as one accepted step).
  ///
  /// The pass drives to `path.start` and recomputes before it seeds, so
  /// matching continuity is anchored on the path's own start rather than
  /// on wherever the caller left the point (Phase 134 — the frame after
  /// a bail starts behind the construction).
  ///
  /// [startStep] is the fraction of the path the step controller opens
  /// with. It exists because a pass restarts the collapse law from
  /// nothing, so its first trial is otherwise unbounded and a crossing
  /// strictly inside the path is glided over — see the returned
  /// `closing`, which is what a caller sets this from.
  ///
  /// Returns the accepted and rejected trial counts, the number of
  /// completed detours, and `closing`: how far the tightest candidate
  /// pair closed over the pass, as a ratio of end separation to start.
  /// Zero means they met — an end state no later pass can seed identity
  /// from, so a caller must not anchor its next path there.
  ///
  /// [onStep] fires after each *accepted* step's
  /// recompute at a real parameter — the arc's interior steps are
  /// complex and silent; a completed detour fires once, at its exit —
  /// the observation hook for the toy harness and the Phase 116 debug
  /// overlay. Notifies once, like [moveFreePoint]. Throws
  /// [ArgumentError] when [id] is not a [FreePoint] or [stepBudget] < 1.
  ({
    int acceptedSteps,
    int rejectedSteps,
    int detours,
    double closing,
    double reached,
  })
  recomputeAlongPath(
    String id,
    DragPath path, {
    int stepBudget = 128,
    double startStep = 1.0,
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
      stepBudget: stepBudget,
      startStep: startStep,
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
  /// [recomputeAlongPath]'s, verbatim; the pass likewise drives to
  /// [from] and recomputes before it seeds. Throws
  /// [ArgumentError] when [id] is not a [PointOnObject] or [stepBudget]
  /// < 1.
  ({
    int acceptedSteps,
    int rejectedSteps,
    int detours,
    double closing,
    double reached,
  })
  recomputeAlongParameterPath(
    String id,
    double from,
    double to, {
    int stepBudget = 128,
    double startStep = 1.0,
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
        object.recompute(kernel.absolute);
      },
      driveComplex: (t) {
        final s = Complex.one - t;
        object.tracedPosition = evaluate(s.scale(from) + t.scale(to));
      },
      stepBudget: stepBudget,
      startStep: startStep,
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
      // A general conic (Phase 132): the pencil evaluation, continued.
      // `ConicShape.pointAt` is already polynomial in homogeneous
      // coordinates, so its complex form is the same expression and a
      // real parameter reproduces the real evaluation bitwise, exactly
      // as the two arms above do. Built once per gesture, like them —
      // the host does not move while a constrained point slides on it.
      //
      // `chartLiftAt` rather than `pointAtComplex` because the two arms
      // above answer `w` exactly one and this one has to as well: the
      // pencil form is homogeneous, so its `w` is whatever the algebra
      // leaves — arbitrary in scale and *sign* — and `tracedPosition`
      // hands that straight to consumers that read the chart back
      // without dividing (Phase 132c).
      case GeoCircle(conic: final matrix?)
          when ConicShape.of(matrix).isParameterized:
        final shape = ConicShape.of(matrix);
        return shape.chartLiftAt;
      default:
        return (_) => throw StateError(
          'No chart to continue: the carrier of ${object.id} is undefined',
        );
    }
  }

  /// The shared tracing walk (Phases 114–116) behind [recomputeAlongPath]
  /// and [recomputeAlongParameterPath]: [driveReal] puts the dragged
  /// object at real path parameter `t` (including its own recompute, if
  /// it needs one), [driveComplex] at a complex `t` during a detour arc.
  /// Detours take the constant [detourHalfPlane]. See
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
  /// The dragged point's dependents, split into what a traced pass
  /// recomputes on every *trial* and the loci it settles once per pass.
  ///
  /// Loci are DAG leaves (nothing may take one as a parent: both
  /// [IntersectionPoint] and [PointOnObject] reject them), so no
  /// acceptance decision can read one. Recomputing a locus is a whole
  /// traced sweep of its own — orders of magnitude more work than the
  /// rest of the graph — so the walk holds them back and settles them
  /// once, at whatever state the pass ends on. Before Phase 117b a
  /// single starving frame paid `stepBudget` full sweeps (~130) before
  /// bailing, which is what froze the app on documents carrying both a
  /// locus and a degenerate intersection.
  ({Set<String> affected, Set<String> affectedCore, List<Locus> affectedLoci})
  _tracedPartition(String id) {
    final affected = transitiveDependentsOf(id);
    final affectedLoci = [
      for (final o in _objects.values)
        if (o is Locus && affected.contains(o.id)) o,
    ];
    final affectedCore = {...affected}
      ..removeAll([for (final l in affectedLoci) l.id]);
    return (
      affected: affected,
      affectedCore: affectedCore,
      affectedLoci: affectedLoci,
    );
  }

  /// How many objects a traced pass over [id] recomputes on every trial
  /// — the size of [_tracedPartition]'s core.
  ///
  /// This is what a trial *costs*, and Phase 139 divides a fixed work
  /// quota by it to get the pass's step budget
  /// ([TracingFlags.dragStepBudgetFor]). It reads off the same partition
  /// the walk itself uses, so the two cannot drift: a kind that starts
  /// or stops being held back changes both together.
  int tracedWorkPerTrial(String id) => _tracedPartition(id).affectedCore.length;

  ({
    int acceptedSteps,
    int rejectedSteps,
    int detours,
    double closing,
    double reached,
  })
  _traceAlong({
    required String id,
    required void Function(double t) driveReal,
    required void Function(Complex t) driveComplex,
    required int stepBudget,
    double startStep = 1.0,
    Map<String, ProjPoint>? seedMemory,
    void Function(double t)? onStep,
  }) {
    if (stepBudget < 1) {
      throw ArgumentError.value(stepBudget, 'stepBudget', 'must be at least 1');
    }
    TraceDiagnostics.count(TraceCounter.dragPasses);
    final (:affected, :affectedCore, :affectedLoci) = _tracedPartition(id);
    // Locus-chain intersection points do not trace (Phase 113), and the
    // reason has changed twice. The original one — that a locus
    // recompute mid-walk would sweep its driver and drag the tracked
    // root along — expired in Phase 117b, which holds loci out of the
    // walk entirely. What kept it after that was **branch adoption**: a
    // traced pass writes `branchIndex` back, so a pass that crosses a
    // coalescence and cannot get back across leaves the stored index
    // naming the wrong root *for good*, where an untraced point's index
    // never moves and the canonical flip is symmetric — wrong, but
    // self-healing.
    //
    // Phase 134 tried the obvious separation — trace these slots and
    // suppress only the write-back — and **it buys nothing**: without
    // adoption the carried identity dies at the gesture's end, when the
    // command applies and the point resolves canonically again. Measured
    // on `no-locus.rgl`: byte-identical to not tracing at all. With
    // adoption back on it crosses the collapse at A and strands 7 of 12
    // randomized gesture sequences on the transversal at B — at every
    // budget from 128 to 2048, so it is not the budget. Against 0 of 12
    // stuck with the exclusion in place. The order therefore still
    // stands: make *every* crossing on the shape crossable first.
    final excluded = <GeoObject>{};
    for (final o in _objects.values) {
      if (o is Locus) {
        excluded.addAll(o.chain);
      }
    }
    // Seed at the path's *start* state, not at whatever state the
    // construction happens to be in (Phase 134). Every pass used to
    // assume its caller had left the point on `path.start`, which holds
    // for a gesture whose frames all succeed and fails for the frame
    // after a bail: a bailed frame ends on a static solve at the
    // pointer, and the drag sessions keep their path anchor at the last
    // parameter identity was actually carried through — so the
    // construction sits *ahead* of the path the next pass walks. One
    // recompute makes the precondition true instead of assumed, and on
    // the frames that do satisfy it already the drive is a no-op that
    // recomputes the same values.
    driveReal(0);
    _recomputeAffected(affectedCore);
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
          final candidates = intersectionCandidates(
            o.curve1,
            o.curve2,
            absolute: kernel.absolute,
          );
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
        return (
          acceptedSteps: 1,
          rejectedSteps: 0,
          detours: 0,
          closing: 1.0,
          reached: 1.0,
        );
      }
      final checkpoints = List<TracedBranchCheckpoint?>.filled(
        seeded.length,
        null,
      );
      void snapshot() {
        for (var i = 0; i < seeded.length; i++) {
          checkpoints[i] = seeded[i].tracedBranch.checkpoint();
        }
      }

      snapshot();
      var t = 0.0;
      var step = startStep;
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
      // Where the roots stood when the pass began — the denominator of
      // the `closing` ratio it reports back (Phase 134).
      final sepStart = sepCurr;
      // The widest span the next accepted step may cover before an
      // extrapolated root collision could hide inside it (Phase 117b).
      var stepLimit = double.infinity;

      void restoreAll() {
        for (var i = 0; i < seeded.length; i++) {
          seeded[i].tracedBranch.restore(checkpoints[i]!);
        }
      }

      // Where the pass ends: 1 for a complete walk, the last accepted
      // real parameter for one that ran out of budget past a crossing.
      var reached = 1.0;
      // Whether this pass has made a crossing it can *vouch for* — the
      // only kind the budget rule below keeps. A detour vouches for
      // itself in one of two ways: its collision was measured
      // (`SeparationMinimum.isCollision`: the separation profile ahead
      // went below the double-root floor, so the arc encloses a real
      // singularity — the transversal shape), or a tracked root changed
      // realness across it (complex conjugates at the entry, real at the
      // exit, or the reverse: a real branch point lies under the arc's
      // diameter — the tangency shape, whose collision sits inside the
      // measurement's first probe and is never bracketed). An arc that
      // is neither is a bet on the extrapolated estimate — an
      // ultra-tight near-miss plans short arcs that wind around nothing
      // — and a bet that ran the budget out is bailed on as before.
      var carried = false;

      /// Walks [arc] from θ = π (its entry — where the pass already
      /// sits) down to θ = 0 (its real exit past the singularity) with
      /// the identical acceptance machinery, complex carriers allowed
      /// for the duration. Trials share the pass budget; exhaustion
      /// mid-arc restores the real entry state and throws — unless a
      /// detour is already behind this pass, in which case it answers
      /// false with the entry state restored, and the pass ends there
      /// (Phase 189).
      bool traceArc(DetourArc arc) {
        for (final o in seeded) {
          o.tracedBranch.allowComplexCarriers = true;
        }
        try {
          var theta = math.pi;
          var dTheta = maxDetourArcStep;
          while (theta > 0) {
            TraceDiagnostics.checkpoint(
              'drag detour arc',
              detail: () =>
                  'theta=${theta.toStringAsFixed(6)} '
                  'dTheta=${dTheta.toStringAsExponential(2)} '
                  'trials=${accepted + rejected}/$stepBudget',
            );
            if (accepted + rejected >= stepBudget) {
              for (final o in seeded) {
                o.tracedBranch.allowComplexCarriers = false;
              }
              driveReal(arc.entry);
              _recomputeAffected(affectedCore);
              if (carried) {
                return false;
              }
              throw TraceStepBudgetException(
                tReached: arc.entry,
                trials: accepted + rejected,
              );
            }
            final trialTheta = theta - dTheta > 0 ? theta - dTheta : 0.0;
            if (trialTheta == theta) {
              // Refinement bottomed out on the floating-point grid: no
              // representable step advances the arc, so no budget can
              // walk it — stop here rather than spend the frame's whole
              // allowance refusing one trial over and over. The locus
              // walk's `_traceArc` carries the identical floor. The
              // pass bails to the static solve, which is what it would
              // have done at the budget anyway, only sooner.
              for (final o in seeded) {
                o.tracedBranch.allowComplexCarriers = false;
              }
              driveReal(arc.entry);
              _recomputeAffected(affectedCore);
              if (carried) {
                return false;
              }
              throw TraceStepBudgetException(
                tReached: arc.entry,
                trials: accepted + rejected,
              );
            }
            driveComplex(arc.tAt(trialTheta));
            _recomputeAffected(affectedCore);
            TraceDiagnostics.count(TraceCounter.dragArcTrials);
            if (trialAccepted(
                  seeded,
                  checkpoints,
                  (theta - trialTheta) * arc.radius,
                ) &&
                collisionFree(checkPairs)) {
              accepted++;
              TraceDiagnostics.count(TraceCounter.dragAccepted);
              theta = trialTheta;
              dTheta = math.min(
                dTheta * 2 < theta ? dTheta * 2 : theta,
                maxDetourArcStep,
              );
              snapshot();
            } else {
              rejected++;
              TraceDiagnostics.count(TraceCounter.dragRejected);
              restoreAll();
              dTheta /= 2;
            }
          }
          return true;
        } finally {
          for (final o in seeded) {
            o.tracedBranch.allowComplexCarriers = false;
          }
        }
      }

      while (t < 1) {
        TraceDiagnostics.checkpoint(
          'drag walk',
          detail: () =>
              't=${t.toStringAsFixed(9)} '
              'step=${step.toStringAsExponential(2)} '
              'sep=${sepCurr.toStringAsExponential(2)} '
              'trials=${accepted + rejected}/$stepBudget',
        );
        if (accepted + rejected >= stepBudget) {
          if (carried) {
            // Past a measured crossing: keep it. The construction sits
            // at the last *trial* (a refused one, past `t`, or short of
            // it when the step limit refused it unevaluated) with the
            // slots restored to the accepted state, so drive back to
            // `t` and recompute: the slots re-match their own roots
            // there and adoption below reads the state a static solve
            // at `t` reproduces.
            reached = t;
            driveReal(t);
            _recomputeAffected(affectedCore);
            break;
          }
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
          accept =
              trialAccepted(seeded, checkpoints, trialT - t) &&
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
            final certified =
                measured != null && measured.isCollision && measured.t > t;
            final tStar = measured == null
                ? estimateSingularParameter(
                    t1: tPrev,
                    s1: sepPrev,
                    t2: tCurr,
                    s2: sepCurr,
                  )
                : (certified ? measured.t : null);
            final arc = tStar == null
                ? null
                : DetourArc.plan(
                    entry: t,
                    tStar: tStar,
                    orientation: detourHalfPlane,
                  );
            if (arc != null) {
              final realAtEntry = [
                for (final o in seeded) o.tracedBranch.root.isReal(),
              ];
              if (!traceArc(arc)) {
                // Out of budget inside a later arc: the entry state is
                // restored and `t` is the entry, so end there.
                reached = t;
                break;
              }
              detours++;
              var flipped = false;
              for (var i = 0; i < seeded.length; i++) {
                if (seeded[i].tracedBranch.root.isReal() != realAtEntry[i]) {
                  flipped = true;
                }
              }
              if (certified || flipped) {
                carried = true;
              }
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
      // t = 1 on real carriers (or at `reached`, for a pass that kept
      // a crossing — Phase 189), so each slot's matchedIndex is the
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
      //
      // **Adoption is atomic per curve pair** (Phase 120c). The guards
      // above are *per point*, so a pass can adopt for some points on a
      // pair and not others — a coasting slot keeps a stale index while
      // its neighbours take new ones — and a stale index can collide
      // with a freshly adopted one. Two points on the same ordered pair
      // sharing a `branchIndex` are the *same intersection* by
      // construction: they resolve to the same candidate for ever after,
      // no later pass can separate them, and the user sees two points
      // stacked on one crossing with another crossing empty. Collision
      // refusal makes that unreachable *within* a pass, so this is the
      // belt to its braces — but the failure is permanent and silent, so
      // it is worth paying for. A pair that would end up with a
      // duplicate keeps every one of its pre-pass indices instead;
      // identity then rests on canonical addressing, which is exactly
      // where a pass that adopts nothing leaves it.
      final proposed = <IntersectionPoint, int>{};
      for (final o in seeded) {
        final branch = o.tracedBranch;
        if (branch.matchedIndex >= 0 &&
            branch.matchedIndex < IntersectionPoint.maxBranchCount &&
            branch.separation > doubleRootEpsilon) {
          proposed[o] = branch.matchedIndex;
        }
        // Refresh the gesture's seed memory with the root the completed
        // pass leaves behind — a coasting slot retains its last followed
        // root, which is exactly what the next pass must resume from
        // when the intersection is undefined at its start.
        seedMemory?[o.id] = branch.root;
      }
      final byPair = <String, List<IntersectionPoint>>{};
      for (final o in seeded) {
        byPair
            .putIfAbsent('${o.curve1.id}\u0000${o.curve2.id}', () => [])
            .add(o);
      }
      for (final group in byPair.values) {
        final after = {for (final o in group) proposed[o] ?? o.branchIndex};
        if (after.length != group.length) {
          TraceDiagnostics.count(TraceCounter.dragRejected);
          continue;
        }
        for (final o in group) {
          final index = proposed[o];
          if (index != null) o.branchIndex = index;
        }
      }
      return (
        acceptedSteps: accepted,
        rejectedSteps: rejected,
        detours: detours,
        // How far the tightest pair closed over this pass. A frame that
        // ends with the roots much nearer than it started is a frame the
        // *next* one must approach carefully, and this is the only
        // warning available: a crossing strictly inside a path cannot be
        // seen from that path's two ends, because the two roots exchange
        // there and every endpoint statistic is invariant under the
        // exchange (Phase 134). Ratio rather than a threshold, so it
        // carries no world scale of its own.
        //
        // A pass that ends *coasting* reports 0 outright. Coasting sets
        // the separation to infinity — the candidates went away, so
        // there is no pair left to measure — and that reads as a ratio
        // saying "nothing to fear" where in fact the carrier itself has
        // collapsed, which is the loudest warning the walk can give.
        //
        // Exactly zero is its own statement: the roots have closed all
        // the way, so no pass can seed identity from this state — the
        // caller must not anchor its next path here.
        closing:
            seeded.any((o) => o.tracedBranch.matchedIndex < 0) ||
                sepCurr <= doubleRootEpsilon
            ? 0.0
            : sepStart.isFinite && sepStart > 0
            ? (sepCurr / sepStart).clamp(0.0, 1.0)
            : 1.0,
        reached: reached,
      );
    } finally {
      for (final o in seeded) {
        o.tracedBranch.clear();
      }
      // The held-back leaves, settled once at the state the pass ends
      // on — the accepted end, or the last trial of a bail. Slots are
      // cleared first: a locus sweep seeds its own chain.
      for (final locus in affectedLoci) {
        locus.recompute(kernel.absolute);
      }
      _notify();
    }
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
            intersectionCandidates(
              o.curve1,
              o.curve2,
              absolute: kernel.absolute,
            ),
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
      throw ArgumentError(
        '$id is not an IntersectionPoint in this construction',
      );
    }
    if (branchIndex < 0 || branchIndex >= IntersectionPoint.maxBranchCount) {
      throw ArgumentError.value(
        branchIndex,
        'branchIndex',
        'must be 0..${IntersectionPoint.maxBranchCount - 1}',
      );
    }
    object.branchIndex = branchIndex;
    object.recompute(kernel.absolute);
    _recomputeDependentsOf(id);
    _notify();
  }

  /// Changes the document's geometry, re-points every intersection point
  /// at the crossing it was actually on, and reports what moved.
  ///
  /// **The only way to change [kernel]**, and it is a method rather than a
  /// setter because the two halves cannot be separated: `branchIndex`
  /// addresses the candidate list *as filtered and ordered against the
  /// absolute*, so assigning a new geometry without re-pointing leaves
  /// every stored address naming whatever crossing now happens to sit at
  /// that index. Points then land on each other's crossings while others
  /// sit vacant — the Phase 120c defect, reached from a third direction
  /// (PLAN §"The audit").
  ///
  /// Matching is by chordal distance from where the point was, the same
  /// primitive as the constructor's canonical remap and a tracing pass's
  /// branch adoption, and for the same reason: the two orderings are not
  /// related by a fixed permutation, so only the geometry can say which
  /// crossing is which. It is defined on complex candidates too, so a
  /// point whose crossing is currently imaginary is still matched.
  ///
  /// One pass in insertion (= topological) order, re-pointing each
  /// intersection as soon as its carriers have settled, so everything
  /// downstream is computed against the address the point will keep.
  /// Notifies once, at the end.
  ///
  /// See [GeometryChange] for what the report holds — in particular why
  /// an undo must restore the old addresses verbatim rather than re-match.
  GeometryChange switchKernel(DocumentKernel kernel) {
    final from = _kernel;
    if (kernel == from) {
      return GeometryChange(from: from, to: kernel);
    }
    // Where each intersection point sits *now*, in the old geometry. Read
    // before anything is touched: this is the only evidence of which
    // crossing the user meant, and the switch destroys it.
    final was = <String, ProjPoint>{};
    // And which objects were drawable at all, for the same reason: an
    // affine ratio and a unique parallel have no value in a Cayley–Klein
    // plane, so a figure standing on either stops here, and only the
    // reading taken *before* the switch can tell that from a degeneracy
    // the document already had (Phase 129).
    final drawable = <String>{};
    for (final object in _objects.values) {
      if (object.isDefined) {
        drawable.add(object.id);
      }
      if (object is IntersectionPoint) {
        final p = object.projPoint;
        if (p != null && !p.isZero) {
          was[object.id] = p;
        }
      }
    }

    _kernel = kernel;
    final readdressed = <Readdressing>[];
    final unmatched = <String>[];
    for (final object in _objects.values) {
      object.recompute(kernel.absolute);
      if (object is! IntersectionPoint) {
        continue;
      }
      final target = was[object.id];
      if (target == null) {
        unmatched.add(object.id);
        continue;
      }
      final candidates = intersectionCandidates(
        object.curve1,
        object.curve2,
        absolute: kernel.absolute,
      );
      if (candidates.isEmpty) {
        unmatched.add(object.id);
        continue;
      }
      var best = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < candidates.length; i++) {
        final d = TracedBranch.chordalDistance(target, candidates[i]);
        if (d < bestDistance) {
          bestDistance = d;
          best = i;
        }
      }
      if (best != object.branchIndex) {
        readdressed.add((id: object.id, from: object.branchIndex, to: best));
        object.branchIndex = best;
        object.recompute(kernel.absolute);
      }
    }
    // After the whole pass, not inside it: a re-addressed point recomputes
    // a second time, and this is a question about where the document
    // settled.
    final undefined = [
      for (final object in _objects.values)
        if (drawable.contains(object.id) && !object.isDefined) object.id,
    ];
    _notify();
    return GeometryChange(
      from: from,
      to: kernel,
      readdressed: readdressed,
      unmatched: unmatched,
      undefined: undefined,
    );
  }

  /// Replays a geometry switch that [switchKernel] already decided —
  /// **undo and redo only** (`SetGeometryCommand`).
  ///
  /// Takes the addresses instead of deriving them, which is the whole
  /// point: re-matching is not invertible. The match is nearest-position,
  /// and a point that had no position at the switch was never matched in
  /// the first place, so a round trip through two matches is not the
  /// identity. A command that performed the switch holds both address
  /// maps and can restore either exactly.
  void replayKernel(DocumentKernel kernel, Map<String, int> addresses) {
    _kernel = kernel;
    for (final object in _objects.values) {
      if (object is IntersectionPoint) {
        final address = addresses[object.id];
        if (address != null) {
          object.branchIndex = address;
        }
      }
      object.recompute(kernel.absolute);
    }
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
    object.recompute(kernel.absolute);
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
      object.recompute(kernel.absolute);
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

  void removeListener(void Function() listener) => _listeners.remove(listener);

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
        object.recompute(kernel.absolute);
      }
    }
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
