import 'dart:math' as math;

import '../commands/command.dart';
import '../commands/move_free_point_command.dart';
import '../commands/move_text_anchor_command.dart';
import '../commands/set_point_on_object_parameter_command.dart';
import '../commands/translate_objects_command.dart';
import '../construction/construction.dart';
import '../construction/free_point_ancestors.dart';
import '../construction/geo_object.dart';
import '../construction/locus_refresh.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/expression_text.dart';
import '../construction/objects/free_point.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/point_on_object.dart';
import '../math/circle_eq.dart';
import '../math/grid_snap.dart';
import '../math/vec2.dart';
import '../projective/conic_shape.dart';
import '../projective/proj_point.dart';
import '../projective/tracing/drag_path.dart';
import '../projective/tracing/trace_diagnostics.dart';
import '../projective/tracing/tracing_flags.dart';

/// One in-progress drag gesture in move/select mode.
///
/// [update] previews each frame by mutating the construction directly —
/// the one sanctioned mutation outside a command (see CLAUDE.md). The
/// gesture must finish with [end], which rolls the preview back and
/// returns the single command capturing start → end (commands apply
/// against the pre-drag state, so the preview cannot be left in place),
/// or with [cancel], which only rolls back. A session is dead after
/// either; drop it.
///
/// What drags:
/// - a [FreePoint] moves itself → [MoveFreePointCommand] — with
///   `TracingFlags.dragTracing` on (the default since Phase 116), each
///   preview frame resolves through `Construction.recomputeAlongPath`
///   so intersection branches follow their roots, with a static bail on
///   any failure; each frame's pass adopts the branch it followed into
///   `IntersectionPoint.branchIndex`, and the gesture's command carries
///   the net adoptions so commit, undo and redo replay traced identity
///   exactly (see [end]);
/// - a [PointOnObject] slides along its host curve — the pointer is
///   projected onto the curve each frame and the point's analytic
///   parameter re-set → [SetPointOnObjectParameterCommand]; with tracing
///   on, each frame resolves through
///   `Construction.recomputeAlongParameterPath` with the same branch
///   adoption, command capture and static bail as a free point
///   (Phase 116b);
/// - any *other* derived point does not drag ([start] returns null): its
///   position is its constraint's business — an intersection lives where
///   its parents cross;
/// - a [CompassCircle] drags by translating only its *center's* free
///   ancestors: the radius is a measurement of two other points, not part
///   of the rigid body, so those points stay put;
/// - an [ExpressionText] moves its own world anchor →
///   [MoveTextAnchorCommand]: its free-point ancestors are the geometry
///   its expressions *reference*, which must stay put;
/// - any other object drags as a rigid translation of its free-point
///   ancestors → [TranslateObjectsCommand]: grab a circle's rim and the
///   whole circle moves because its defining points do.
/// One traced preview frame's step-controller counts, plus whether the
/// frame fell back to the static solve — the Phase 116 debug-overlay
/// feed (`Construction.recomputeAlongPath` returns the counts; the drag
/// session records them per frame).
typedef TraceFrameStats = ({
  int accepted,
  int rejected,
  int detours,
  bool bailed,
});

abstract class DragSession {
  /// Starts dragging [target], grabbed at [grabStart] (world coordinates).
  /// Null when the target cannot drag (a derived point other than a
  /// [PointOnObject], nothing free upstream, or a constrained point whose
  /// curve is undefined).
  ///
  /// [gridSnapStep] > 0 quantizes a *single free point's* drag to the
  /// grid (Phase 45): the preview lands on crossings every frame and the
  /// one command commits the snapped end position. Rigid translations
  /// deliberately ignore it — quantizing every free ancestor
  /// independently would distort shapes — and constrained slides can't
  /// use it (the point lives on its curve, not on the grid).
  static DragSession? start(
    Construction construction,
    GeoObject target,
    Vec2 grabStart, {
    double gridSnapStep = 0,
  }) {
    if (target is PointOnObject) {
      return _SlideDragSession.start(construction, target, grabStart);
    }
    if (target is GeoPoint && target is! FreePoint) {
      return null;
    }
    // A text's free-point ancestors are the objects its expressions
    // *reference* — rigidly translating it would move the measured
    // geometry. Instead the text moves its own anchor, freely.
    if (target is ExpressionText) {
      return _TextAnchorDragSession(construction, target, grabStart);
    }
    if (target is GeoText) {
      return null;
    }
    final points = target is CompassCircle
        ? freePointAncestors(target.center)
        : freePointAncestors(target);
    if (points.isEmpty) {
      return null;
    }
    return _TranslateDragSession(
      construction,
      target is FreePoint,
      grabStart,
      [...points],
      gridSnapStep: target is FreePoint ? gridSnapStep : 0,
    );
  }

  /// Previews the gesture at [pointer] (world coordinates).
  void update(Vec2 pointer);

  /// The most recent preview frame's tracing counts — null before the
  /// first frame and for sessions that never trace (rigid translations,
  /// slides, text anchors, or the flag off).
  TraceFrameStats? get traceStats => null;

  /// Rolls the preview back and returns the gesture's one command, or
  /// null when the gesture ended where it started (nothing to undo).
  Command? end();

  /// Rolls the preview back (Esc, tool switch, undo mid-drag).
  void cancel();
}

/// The drag-session side of branch adoption (Phases 116/116b): the
/// pre-drag [IntersectionPoint.branchIndex] of everything downstream of
/// a traced drag's mutable object. Traced preview frames adopt indices
/// in place, so [restore] puts them back before a rollback's recompute
/// and [diff] turns the net adoptions into the gesture command's
/// [BranchChange]s. Objects that vanished under the session (an undo
/// mid-drag) are skipped everywhere.
/// The trial budget one gesture on [pointId] derives from its graph.
///
/// The quota is divided by what one trial of *this* construction costs,
/// which `Construction.tracedWorkPerTrial` answers off the same
/// partition the walk uses — loci excluded, since Phase 117b settles
/// those once per pass rather than once per trial.
///
/// Taken at session start rather than per frame because the graph is
/// what it divides and a drag cannot change the graph. The *pin*
/// ([TracingFlags.dragStepBudget]) is read per frame instead — it is a
/// debug override, and a caller that sets it mid-gesture means it to
/// take effect now.
int _derivedStepBudget(Construction construction, String pointId) =>
    TracingFlags.dragStepBudgetFor(construction.tracedWorkPerTrial(pointId));

class _BranchSnapshot {
  _BranchSnapshot(this._construction, String pointId) {
    for (final id in _construction.transitiveDependentsOf(pointId)) {
      final object = _construction.byId(id);
      if (object is IntersectionPoint) {
        _start[id] = object.branchIndex;
      }
    }
  }

  /// For untraced sessions: nothing snapshotted, [restore] and [diff]
  /// are no-ops.
  _BranchSnapshot.empty(this._construction);

  final Construction _construction;
  final Map<String, int> _start = {};

  void restore() {
    for (final entry in _start.entries) {
      final object = _construction.byId(entry.key);
      if (object is IntersectionPoint) {
        object.branchIndex = entry.value;
      }
    }
  }

  List<BranchChange> diff() => [
    for (final entry in _start.entries)
      if (_construction.byId(entry.key) case final IntersectionPoint point
          when point.branchIndex != entry.value)
        (id: entry.key, from: entry.value, to: point.branchIndex),
  ];
}

/// How a [PointOnObject]'s circle-kind host is currently parameterized —
/// the dispatch `PointOnObject.recompute` runs, held from frame to frame
/// so a change of frame is an *event* the session can act on.
sealed class _HostFrame {
  const _HostFrame();
}

/// The host projects to a `CircleEq`: the parameter is its polar angle,
/// which has no discrete frame choice and never switches by itself.
class _PolarFrame extends _HostFrame {
  const _PolarFrame();
}

/// The host is a general conic: the parameter is [shape]'s pencil angle,
/// whose canonical frame carries the discrete choices of Phase 132d.
class _PencilFrame extends _HostFrame {
  const _PencilFrame(this.shape);

  final ConicShape shape;
}

/// The drag-session side of pencil-angle re-anchoring (Phase 132d) — the
/// same settlement branch adoption chose, applied to the other stored
/// address a drag can strand.
///
/// A conic-glued [PointOnObject]'s parameter names a point of the curve
/// only through `ConicShape`'s canonical frame, and that frame's discrete
/// choices switch as the host moves — a stored angle then names a
/// different point (up to 2.7 world units on the measured rig, PLAN
/// §Parameterization). Statics stay canonical: `recompute` remains a pure
/// function of (parents, params, ambient), a save carries a canonical
/// angle, a load re-derives everything — the alternative, re-anchoring
/// inside `recompute` itself, was rejected because a history-dependent
/// recompute breaks every exactness contract at once (the locus sweep's
/// restore, the point-coincidence probe's perturb-and-restore, bitwise
/// undo). Instead **identity across a switch is held by the gesture**:
/// after each preview frame this tracker compares every affected host's
/// frame with the previous frame's, and where it switched, re-expresses
/// the stored angle so the point stays put
/// ([ConicShape.carryParameterFrom] — exact at the switch; a class
/// change, where no frame continues, falls back to re-expressing from
/// the point's own previous position). [restore] puts the start
/// parameters back for a rollback, and [diff] turns the net
/// re-expressions into the gesture command's [GlueChange]s, so commit,
/// undo and redo replay them exactly — the [_BranchSnapshot] shape,
/// deliberately.
class _GlueTracker {
  _GlueTracker(this._construction, List<String> draggedIds) {
    final affected = <String>{};
    for (final id in draggedIds) {
      affected.addAll(_construction.transitiveDependentsOf(id));
    }
    for (final id in affected) {
      final object = _construction.byId(id);
      if (object is! PointOnObject) continue;
      final host = object.curve;
      if (host is! GeoCircle) continue;
      (_byHost[host.id] ??= []).add(id);
      _start[id] = object.parameter;
      _lastPosition[id] = object.position;
    }
    for (final hostId in _byHost.keys) {
      final frame = _frameOf(hostId);
      if (frame != null) _frames[hostId] = frame;
    }
  }

  final Construction _construction;

  /// Tracked glued points per affected circle-kind host.
  final Map<String, List<String>> _byHost = {};

  /// Pre-drag parameters of every tracked point.
  final Map<String, double> _start = {};

  /// Each point's chart position as of the last frame's end, after any
  /// re-expression — what a fallback re-expression anchors on when no
  /// frame continues. Only overwritten while defined, so a host that
  /// degenerates mid-gesture and comes back re-anchors on the last state
  /// that had a position at all.
  final Map<String, Vec2?> _lastPosition = {};

  /// Each host's parameterization frame as of the last frame's end. A
  /// host with no live frame (undefined, or an unparameterized conic)
  /// keeps its previous entry: the switch is detected against the last
  /// frame that meant anything.
  final Map<String, _HostFrame> _frames = {};

  _HostFrame? _frameOf(String hostId) {
    final host = _construction.byId(hostId);
    if (host is! GeoCircle) return null;
    // Mirrors PointOnObject.recompute's dispatch: a CircleEq projection
    // wins, and only a general conic takes the pencil angle.
    if (host.circle != null) return const _PolarFrame();
    final conic = host.conic;
    if (conic == null) return null;
    final shape = ConicShape.of(conic);
    return shape.isParameterized ? _PencilFrame(shape) : null;
  }

  /// Re-anchors every tracked point whose host's frame switched since the
  /// last call. Call once per preview frame, after the frame's move.
  void reanchor() {
    _byHost.forEach((hostId, pointIds) {
      final current = _frameOf(hostId);
      if (current == null) return;
      final previous = _frames[hostId];
      _frames[hostId] = current;
      for (final id in pointIds) {
        final object = _construction.byId(id);
        if (object is! PointOnObject) continue;
        final carried = _carry(object, previous, current);
        if (carried != null && carried != object.parameter) {
          _construction.setPointOnObjectParameter(id, carried);
        }
        final position = object.position;
        if (position != null) _lastPosition[id] = position;
      }
    });
  }

  /// The parameter [object] should hold under [current], or null when
  /// nothing needs saying (no previous frame, or nothing to anchor on).
  double? _carry(
    PointOnObject object,
    _HostFrame? previous,
    _HostFrame current,
  ) {
    switch ((previous, current)) {
      case (null, _) || (_PolarFrame(), _PolarFrame()):
        // No previous frame to have switched from; and a polar angle has
        // no frame choice — it moves the point continuously by itself.
        return null;
      case (final _PencilFrame p, final _PencilFrame c):
        final carried = c.shape.carryParameterFrom(p.shape, object.parameter);
        if (carried != null) return carried;
        // The class changed under the point — no frame continues, so
        // anchor on the point's own previous position, the Phase 133
        // move.
        return _fromPosition(object, current);
      case (_PolarFrame(), _PencilFrame()) || (_PencilFrame(), _PolarFrame()):
        // The parameter's *meaning* flipped (polar angle ↔ pencil angle,
        // the host crossing the CircleEq projection boundary): only the
        // position carries across.
        return _fromPosition(object, current);
    }
  }

  double? _fromPosition(PointOnObject object, _HostFrame current) {
    final position = _lastPosition[object.id];
    if (position == null) return null;
    switch (current) {
      case _PencilFrame(:final shape):
        return shape.parameterOf(ProjPoint.lift(position));
      case _PolarFrame():
        final host = object.curve;
        if (host is! GeoCircle) return null;
        final circle = host.circle;
        if (circle == null) return null;
        return host.clampAngle(circle.angleAt(position));
    }
  }

  /// Puts the pre-drag parameters back — raw writes, like
  /// [_BranchSnapshot.restore]: the rollback's own moves recompute.
  void restore() {
    for (final entry in _start.entries) {
      if (_construction.byId(entry.key) case final PointOnObject point) {
        point.parameter = entry.value;
      }
    }
  }

  List<GlueChange> diff() => [
    for (final entry in _start.entries)
      if (_construction.byId(entry.key) case final PointOnObject point
          when point.parameter != entry.value)
        (id: entry.key, from: entry.value, to: point.parameter),
  ];
}

/// A free point moving itself, or a derived non-point rigidly translating
/// its free-point ancestors.
class _TranslateDragSession implements DragSession {
  _TranslateDragSession(
    this._construction,
    this._isFreePoint,
    this._grabStart,
    List<FreePoint> points, {
    double gridSnapStep = 0,
  }) : _gridSnapStep = gridSnapStep,
       _pointIds = [for (final point in points) point.id],
       _startPositions = {
         for (final point in points) point.id: point.position,
       } {
    // Traced previews adopt branch identity per frame (each pass leaves
    // `branchIndex` re-derived under the tracked root — Phase 116), so
    // the session snapshots the start indices of every intersection the
    // drag can touch: rollback restores them like the positions, and
    // [end] diffs them into the command's branch changes.
    _branches = _isFreePoint && _traceDrags
        ? _BranchSnapshot(_construction, _pointIds.single)
        : _BranchSnapshot.empty(_construction);
    _derivedBudget = _isFreePoint && _traceDrags
        ? _derivedStepBudget(_construction, _pointIds.single)
        : 0;
    // Conic-glued points re-anchor per frame, whatever moves their host —
    // a single dragged point and a rigid translation both carry a host
    // across a parameterization-frame switch (an argmax tie crosses under
    // pure translation).
    _glue = _GlueTracker(_construction, _pointIds);
  }

  final Construction _construction;
  final bool _isFreePoint;
  final Vec2 _grabStart;
  final List<String> _pointIds;
  final Map<String, Vec2> _startPositions;

  /// Pre-drag branch indices — populated only for traced
  /// single-free-point drags (see the constructor).
  late final _BranchSnapshot _branches;

  /// Pencil-angle re-anchoring state for conic-glued points downstream of
  /// the drag (Phase 132d; see [_GlueTracker]).
  late final _GlueTracker _glue;

  /// Non-zero only for a single free point (see [DragSession.start]).
  final double _gridSnapStep;

  /// Whether previews resolve through `recomputeAlongPath` (Phase 113).
  /// Captured from [TracingFlags.dragTracing] at session start so one
  /// gesture never mixes resolution modes. Single free points only —
  /// rigid translations move several roots at once, which the naive
  /// single-path walk cannot continue yet.
  final bool _traceDrags = TracingFlags.dragTracing;

  /// Trials this gesture's traced frames may spend before bailing,
  /// derived from the graph once at session start (Phase 139; see
  /// [_derivedStepBudget]). Zero for untraced sessions, which never read
  /// it.
  late final int _derivedBudget;

  /// What a frame actually spends: the pin if one is set, else the
  /// derivation. See [_derivedStepBudget] for why only one of the two is
  /// captured.
  int get _stepBudget => TracingFlags.dragStepBudget ?? _derivedBudget;

  /// The last position a traced preview actually carried identity to —
  /// where the next preview path starts, so branch matching is
  /// continuous across pointer events. Null until the first *successful*
  /// traced update (the gesture starts from the point's start position).
  ///
  /// A bailed frame does not advance it (Phase 134). The bail's fallback
  /// is a static solve, which resolves canonically and so is precisely
  /// the state whose branch identity the gesture has no reason to trust;
  /// anchoring the next path there hands that relabelling to the walk as
  /// a fact. Held back, the next path spans the anchor to the new
  /// pointer instead — which is also what puts a degeneracy the pointer
  /// landed exactly on into the path's *interior*, where a detour arc
  /// has somewhere to land, rather than at an endpoint where it has not.
  Vec2? _lastPreview;

  /// Consecutive bailed frames since the anchor last advanced.
  int _stale = 0;

  /// The smallest fraction of a path a cautious frame starts at. Below
  /// this the approach costs more trials than a frame's budget buys, and
  /// measurement finds nothing left to win: every floor from 1/64 to 1/2
  /// crosses the same degeneracies.
  static const double _minStartStep = 1 / 64;

  /// Consecutive bailed frames the path anchor is held for. One: a
  /// second failure says the gesture has genuinely lost the thread, and
  /// widening the path every frame from then on only spends budget.
  /// Measured — holding without limit buys two more crossings on the
  /// reported document and costs five times the bails on the four-point
  /// ellipse rig, which is the wrong side of that trade.
  static const int _anchorHoldFrames = 1;

  /// Where the next traced pass starts its step controller — 1 for a
  /// frame with nothing to fear, and the fraction by which the previous
  /// frame's roots closed when they were converging.
  ///
  /// A pass restarts its collapse-law samples from nothing, so its first
  /// trial is unbounded and spans the whole frame; a crossing strictly
  /// inside that span is glided over and the nearest match silently
  /// takes the wrong root, because the two roots exchange at a crossing
  /// and no statistic read from the path's two ends can tell the
  /// exchange from a small motion (Phase 134). The previous frame's
  /// `closing` ratio is the one warning that does carry across, so the
  /// next frame starts at that fraction of its path and lets the walk
  /// find the collapse by refining into it. A bail reports no ratio at
  /// all, and takes the floor.
  double _startStep = 1.0;

  /// Gesture-scoped continuation memory: each traced pass writes back
  /// the roots it followed, so a later pass can re-seed an intersection
  /// that is undefined at its start (the previous frame ended exactly on
  /// a carrier degeneracy). Cleared on a bail — after a static solve the
  /// remembered identity no longer describes the construction — and dies
  /// with the session, so no continuation state outlives the gesture.
  final Map<String, ProjPoint> _seedMemory = {};

  TraceFrameStats? _traceStats;

  @override
  TraceFrameStats? get traceStats => _traceStats;

  Vec2 _delta = Vec2.zero;

  /// Where the free point sits for the current [_delta] — the one place
  /// deciding both the per-frame preview and the committed end position,
  /// so they can't drift. [snapToGrid] passes positions through untouched
  /// while the step is 0.
  Vec2 get _freePointPosition {
    final id = _pointIds.single;
    return snapToGrid(_startPositions[id]! + _delta, _gridSnapStep);
  }

  /// Every dragged point sits at its start position plus the pointer's
  /// total delta, so a rigid shape stays rigid regardless of frame timing.
  @override
  void update(Vec2 pointer) {
    TraceDiagnostics.frameBegin(_diagnosticLabel);
    try {
      // A preview frame, so loci may lag the pointer rather than pace it
      // (Phase 117d). The gesture's *command* runs outside this scope,
      // so what gets committed is never stale.
      LocusRefresh.preview(() {
        _delta = pointer - _grabStart;
        if (_isFreePoint) {
          if (_traceDrags) {
            _tracedUpdate(_freePointPosition);
          } else {
            _construction.moveFreePoint(_pointIds.single, _freePointPosition);
          }
        } else {
          for (final id in _pointIds) {
            _construction.moveFreePoint(id, _startPositions[id]! + _delta);
          }
        }
        // After the frame's move: carry conic-glued points across any
        // host frame switch the move crossed (Phase 132d).
        _glue.reanchor();
      });
    } finally {
      TraceDiagnostics.frameEnd();
    }
  }

  /// What the diagnostics recorder calls this gesture.
  late final String _diagnosticLabel = _pointIds.length == 1
      ? 'drag ${_construction.nameOf(_pointIds.single)}'
      : 'translate ${_pointIds.length} points';

  /// One traced preview frame: continue branches along the path from the
  /// previous preview position to [target]. The static-solve bail (PLAN
  /// §Risks) stands in every phase: whatever goes wrong inside the
  /// tracing engine — including the step controller starving against a
  /// degeneracy and throwing `TraceStepBudgetException` (Phase 114) —
  /// the frame falls back to the canonical static solve and the gesture
  /// carries on.
  void _tracedUpdate(Vec2 target) {
    final id = _pointIds.single;
    final from = _lastPreview ?? _startPositions[id]!;
    try {
      final result = _construction.recomputeAlongPath(
        id,
        DragPath(from, target),
        stepBudget: _stepBudget,
        startStep: _startStep,
        seedMemory: _seedMemory,
      );
      // Zero says the roots closed all the way, so this end state is
      // one no pass can seed from: hold the anchor, exactly as a bail
      // does. The anchor advances only to states identity can be picked
      // up again at.
      if (result.closing > 0) {
        _lastPreview = target;
        _stale = 0;
      }
      _startStep = result.closing.clamp(_minStartStep, 1.0);
      _traceStats = (
        accepted: result.acceptedSteps,
        rejected: result.rejectedSteps,
        detours: result.detours,
        bailed: false,
      );
    } catch (_) {
      _traceStats = (accepted: 0, rejected: 0, detours: 0, bailed: true);
      TraceDiagnostics.count(TraceCounter.dragBails);
      _seedMemory.clear();
      _startStep = _minStartStep;
      if (++_stale > _anchorHoldFrames) {
        _lastPreview = target;
        _stale = 0;
      }
      _construction.moveFreePoint(id, target);
    }
  }

  @override
  Command? end() {
    final delta = _delta;
    // Diff the adoptions the previews left behind — branch indices and
    // re-expressed glue parameters — before rollback restores the start
    // values.
    final glueChanges = _glue.diff();
    if (_isFreePoint) {
      final id = _pointIds.single;
      final from = _startPositions[id]!;
      final to = _freePointPosition;
      final branchChanges = _branches.diff();
      _rollback();
      // A snapped drag can quantize back onto its start — nothing to
      // undo, unless the loop crossed degeneracies with a net branch
      // change or a net re-anchoring, which is a real re-pointing to
      // commit.
      if ((delta == Vec2.zero || to == from) &&
          branchChanges.isEmpty &&
          glueChanges.isEmpty) {
        return null;
      }
      return MoveFreePointCommand(
        pointId: id,
        from: from,
        to: to,
        branchChanges: branchChanges,
        glueChanges: glueChanges,
      );
    }
    _rollback();
    if (delta == Vec2.zero && glueChanges.isEmpty) {
      return null;
    }
    return TranslateObjectsCommand(
      pointIds: _pointIds,
      delta: delta,
      glueChanges: glueChanges,
    );
  }

  @override
  void cancel() => _rollback();

  /// Restores every dragged point's start position verbatim (float-exact,
  /// like the commands), the pre-drag branch indices any traced previews
  /// adopted away, and the pre-drag glue parameters any frame switch
  /// re-expressed — stored state first, so the moves' recompute
  /// re-selects the original branches and re-evaluates the original
  /// angles. Objects that vanished under the session — an undo mid-drag
  /// can remove them — are skipped rather than thrown on.
  void _rollback() {
    _branches.restore();
    _glue.restore();
    for (final id in _pointIds) {
      if (_construction.contains(id)) {
        _construction.moveFreePoint(id, _startPositions[id]!);
      }
    }
  }
}

/// An [ExpressionText] moving its own world anchor — free placement, no
/// radial clamp (the clamp belongs to *captions* riding another object's
/// anchor; a text's body is the object). Grid snap is deliberately not
/// consulted: a text is annotation beside the figure, not geometry on it.
class _TextAnchorDragSession implements DragSession {
  _TextAnchorDragSession(
    this._construction,
    ExpressionText text,
    this._grabStart,
  ) : _textId = text.id,
      _startAnchor = text.anchor;

  final Construction _construction;
  final String _textId;
  final Vec2 _startAnchor;
  final Vec2 _grabStart;

  @override
  TraceFrameStats? get traceStats => null;

  Vec2 _delta = Vec2.zero;

  @override
  void update(Vec2 pointer) {
    // Total-delta form like the rigid translate: the anchor rides the
    // pointer's motion regardless of frame timing, and the grab point
    // within the text stays under the finger.
    _delta = pointer - _grabStart;
    _construction.moveTextAnchor(_textId, _startAnchor + _delta);
  }

  @override
  Command? end() {
    final delta = _delta;
    _rollback();
    if (delta == Vec2.zero) {
      return null;
    }
    return MoveTextAnchorCommand(
      textId: _textId,
      from: _startAnchor,
      to: _startAnchor + delta,
    );
  }

  @override
  void cancel() => _rollback();

  /// Restores the start anchor verbatim (float-exact, like the command).
  /// Skipped if the text vanished under the session.
  void _rollback() {
    if (_construction.contains(_textId)) {
      _construction.moveTextAnchor(_textId, _startAnchor);
    }
  }
}

/// A [PointOnObject] sliding along its host curve.
///
/// The curve's analytic form is captured once at grab time — it cannot
/// change mid-gesture, since the drag only re-sets the point's parameter
/// and never touches the curve's parents. Each frame projects the pointer
/// onto that form, offset so the point rides the pointer's motion instead
/// of jumping under the cursor (the grab may be up to a hit-threshold away
/// from the point itself). On a bounded host — `Arc`/`Sector`
/// (`angularExtent`) or `Segment`/`Ray` (`parameterExtent`) — every
/// frame's parameter is clamped into the drawn extent, so the point stops
/// at the curve's ends instead of continuing along the carrier — and
/// reverses the moment the pointer does.
class _SlideDragSession implements DragSession {
  _SlideDragSession._(
    this._construction,
    this._pointId,
    this._startParameter,
    this._grabOffset,
    this._project,
    this._clamp,
  ) : _parameter = _startParameter {
    _branches = _traceDrags
        ? _BranchSnapshot(_construction, _pointId)
        : _BranchSnapshot.empty(_construction);
    _derivedBudget = _traceDrags
        ? _derivedStepBudget(_construction, _pointId)
        : 0;
  }

  /// Null when the host curve is undefined — nothing to slide on (the hit
  /// tester skips undefined objects, so this is belt and braces).
  static _SlideDragSession? start(
    Construction construction,
    PointOnObject target,
    Vec2 grabStart,
  ) {
    final curve = target.curve;
    // A general conic slides by its pencil angle, the same map a tap uses
    // (Phase 132). The shape is built once per gesture rather than per
    // frame: a slide moves the point along its host, never the host.
    final shape = switch (curve) {
      GeoCircle(circle: null, :final conic?) => ConicShape.of(conic),
      _ => null,
    };
    final project = switch (curve) {
      GeoLine(:final line?) => line.parameterAt,
      GeoCircle(:final circle?) => circle.angleAt,
      GeoCircle() when shape != null && shape.isParameterized =>
        (Vec2 p) => shape.parameterNear(p) ?? target.parameter,
      _ => null,
    };
    if (project == null) {
      return null;
    }
    final clamp = switch (curve) {
      final GeoCircle host => host.clampAngle,
      final GeoLine host => host.clampParameter,
      _ => _identityParameter,
    };
    // The offset is taken from the *effective* (clamped) parameter: after
    // a host shrank past the stored parameter the point renders on the
    // extent's end, and that is where the user grabbed it.
    var grabOffset = clamp(target.parameter) - project(grabStart);
    // Angular parameters are periodic: near the wrap the raw offset can
    // come out a whole period even though the grab sits on the point.
    // Normalize to half a period either side so the stored parameter
    // never jumps a turn. A circle's polar angle has period 2π; a
    // conic's pencil angle is exactly π-periodic (`ConicShape.pointAt`).
    final period = switch (curve) {
      GeoCircle(circle: final CircleEq _) => 2 * math.pi,
      GeoCircle() => math.pi,
      _ => null,
    };
    if (period != null) {
      grabOffset -= period * (grabOffset / period).roundToDouble();
    }
    return _SlideDragSession._(
      construction,
      target.id,
      target.parameter,
      grabOffset,
      project,
      clamp,
    );
  }

  static double _identityParameter(double parameter) => parameter;

  final Construction _construction;
  final String _pointId;
  final double _startParameter;
  final double _grabOffset;
  final double Function(Vec2) _project;
  final double Function(double) _clamp;

  /// Whether previews resolve through `recomputeAlongParameterPath`
  /// (Phase 116b) — the parameter-drive sibling of the free-point
  /// session's tracing. Captured once per gesture, like there.
  final bool _traceDrags = TracingFlags.dragTracing;

  /// The free-point session's twins: the budget derived from the graph
  /// once at session start, and what a frame spends (Phase 139).
  late final int _derivedBudget;

  int get _stepBudget => TracingFlags.dragStepBudget ?? _derivedBudget;

  /// Pre-drag branch indices — populated only when tracing (see the
  /// constructor).
  late final _BranchSnapshot _branches;

  /// Gesture-scoped continuation memory, exactly as in
  /// [_TranslateDragSession]: bridges frames whose boundary state leaves
  /// an intersection undefined; cleared on bail, dies with the session.
  final Map<String, ProjPoint> _seedMemory = {};

  /// The last parameter a traced preview actually carried identity to —
  /// the start of the next preview path, and the slide session's twin of
  /// [_TranslateDragSession._lastPreview]. A bailed frame does not
  /// advance it; see that field for why.
  late double _anchor = _startParameter;

  /// Consecutive bailed frames since [_anchor] last advanced.
  int _stale = 0;

  /// The slide session's twins of [_TranslateDragSession._minStartStep]
  /// and [_TranslateDragSession._anchorHoldFrames].
  static const double _minStartStep = 1 / 64;
  static const int _anchorHoldFrames = 1;

  /// The slide session's twin of [_TranslateDragSession._startStep].
  double _startStep = 1.0;

  TraceFrameStats? _traceStats;

  @override
  TraceFrameStats? get traceStats => _traceStats;

  double _parameter;

  /// What the diagnostics recorder calls this gesture.
  late final String _diagnosticLabel =
      'slide ${_construction.nameOf(_pointId)}';

  @override
  void update(Vec2 pointer) {
    TraceDiagnostics.frameBegin(_diagnosticLabel);
    try {
      // See the free-point session: a preview frame, so loci may lag.
      LocusRefresh.preview(() => _update(pointer));
    } finally {
      TraceDiagnostics.frameEnd();
    }
  }

  void _update(Vec2 pointer) {
    _parameter = _clamp(_project(pointer) + _grabOffset);
    if (!_traceDrags) {
      _construction.setPointOnObjectParameter(_pointId, _parameter);
      return;
    }
    final from = _anchor;
    // One traced preview frame, anchored at the last parameter a pass
    // carried identity to, so branch matching is continuous across
    // pointer events.
    // The static bail stands, exactly as for free-point drags: whatever
    // goes wrong inside the engine, the frame falls back to the static
    // solve and the gesture carries on.
    try {
      final result = _construction.recomputeAlongParameterPath(
        _pointId,
        from,
        _parameter,
        stepBudget: _stepBudget,
        startStep: _startStep,
        seedMemory: _seedMemory,
      );
      // See the free-point session: a fully-closed end is not an anchor.
      if (result.closing > 0) {
        _anchor = _parameter;
        _stale = 0;
      }
      _startStep = result.closing.clamp(_minStartStep, 1.0);
      _traceStats = (
        accepted: result.acceptedSteps,
        rejected: result.rejectedSteps,
        detours: result.detours,
        bailed: false,
      );
    } catch (_) {
      _traceStats = (accepted: 0, rejected: 0, detours: 0, bailed: true);
      TraceDiagnostics.count(TraceCounter.dragBails);
      _seedMemory.clear();
      _startStep = _minStartStep;
      if (++_stale > _anchorHoldFrames) {
        _anchor = _parameter;
        _stale = 0;
      }
      _construction.setPointOnObjectParameter(_pointId, _parameter);
    }
  }

  @override
  Command? end() {
    final parameter = _parameter;
    // Diff the branch adoptions before rollback restores the indices.
    final branchChanges = _branches.diff();
    _rollback();
    if (parameter == _startParameter && branchChanges.isEmpty) {
      return null;
    }
    return SetPointOnObjectParameterCommand(
      pointId: _pointId,
      from: _startParameter,
      to: parameter,
      branchChanges: branchChanges,
    );
  }

  @override
  void cancel() => _rollback();

  /// Restores the start parameter verbatim (float-exact, like the
  /// command), and the pre-drag branch indices any traced previews
  /// adopted away — indices first, so the recompute re-selects the
  /// original branches. Skipped if the point vanished under the session.
  void _rollback() {
    _branches.restore();
    if (_construction.contains(_pointId)) {
      _construction.setPointOnObjectParameter(_pointId, _startParameter);
    }
  }
}
