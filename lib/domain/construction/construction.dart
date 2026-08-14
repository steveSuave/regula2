import 'dart:collection';

import '../math/vec2.dart';
import '../projective/tracing/drag_path.dart';
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
  /// around degeneracies arrive in Phase 115).
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
  /// matching provably cannot swap two branches. A refused trial is
  /// rolled back ([TracedBranch.restore]) and retried at half the step;
  /// an accepted step doubles it again (capped at the path end, which is
  /// reached bitwise-exactly). Near a degeneracy the separation — and
  /// with it the allowed motion — collapses, so the controller *starves*:
  /// when accepted plus refused trials reach [stepBudget], the pass
  /// throws [TraceStepBudgetException], leaving the point at the last
  /// trial position with slots cleared; callers bail to a static solve
  /// (the drag session does — PLAN §Risks). Returns the accepted/rejected
  /// trial counts (the Phase 116 debug-overlay feed).
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
  /// recompute — the observation hook for the toy harness and the Phase
  /// 116 debug overlay. Notifies once, like [moveFreePoint]. Throws
  /// [ArgumentError] when [id] is not a [FreePoint] or [stepBudget] < 1.
  ({int acceptedSteps, int rejectedSteps}) recomputeAlongPath(
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
    try {
      if (seeded.isEmpty) {
        object.position = path.at(1);
        _recomputeAffected(affected);
        onStep?.call(1);
        return (acceptedSteps: 1, rejectedSteps: 0);
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
        if (_trialAccepted(seeded, checkpoints)) {
          accepted++;
          t = trialT;
          step = step * 2 < 1 ? step * 2 : 1.0;
          snapshot();
          onStep?.call(trialT);
        } else {
          rejected++;
          for (var i = 0; i < seeded.length; i++) {
            seeded[i].tracedBranch.restore(checkpoints[i]!);
          }
          step /= 2;
        }
      }
      return (acceptedSteps: accepted, rejectedSteps: rejected);
    } finally {
      for (final o in seeded) {
        o.tracedBranch.clear();
      }
      _notify();
    }
  }

  /// The Cinderella acceptance rule over one trial's matches: every
  /// followed root must have moved less than half its candidates'
  /// separation at the previous accepted step ([checkpoints]). Coasting
  /// branches (no candidates this trial) impose nothing. Written so a
  /// NaN motion — degenerate norms upstream — refuses the trial rather
  /// than accepting it.
  static bool _trialAccepted(
    List<IntersectionPoint> seeded,
    List<TracedBranchCheckpoint?> checkpoints,
  ) {
    for (var i = 0; i < seeded.length; i++) {
      final branch = seeded[i].tracedBranch;
      if (branch.matchedIndex < 0) continue;
      if (!(branch.motion < checkpoints[i]!.separation / 2)) {
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
