import 'dart:math' as math;

import '../commands/command.dart';
import '../commands/move_free_point_command.dart';
import '../commands/move_text_anchor_command.dart';
import '../commands/set_point_on_object_parameter_command.dart';
import '../commands/translate_objects_command.dart';
import '../construction/construction.dart';
import '../construction/free_point_ancestors.dart';
import '../construction/geo_object.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/expression_text.dart';
import '../construction/objects/free_point.dart';
import '../construction/objects/point_on_object.dart';
import '../math/grid_snap.dart';
import '../math/vec2.dart';
import '../projective/tracing/drag_path.dart';
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
///   `TracingFlags.dragTracing` on, each preview frame resolves through
///   `Construction.recomputeAlongPath` so intersection branches follow
///   their roots (Phase 113; static bail on any failure, and the
///   committed command still applies statically until Phase 116);
/// - a [PointOnObject] slides along its host curve — the pointer is
///   projected onto the curve each frame and the point's analytic
///   parameter re-set → [SetPointOnObjectParameterCommand];
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

  /// Rolls the preview back and returns the gesture's one command, or
  /// null when the gesture ended where it started (nothing to undo).
  Command? end();

  /// Rolls the preview back (Esc, tool switch, undo mid-drag).
  void cancel();
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
  })  : _gridSnapStep = gridSnapStep,
        _pointIds = [for (final point in points) point.id],
        _startPositions = {
          for (final point in points) point.id: point.position,
        };

  final Construction _construction;
  final bool _isFreePoint;
  final Vec2 _grabStart;
  final List<String> _pointIds;
  final Map<String, Vec2> _startPositions;

  /// Non-zero only for a single free point (see [DragSession.start]).
  final double _gridSnapStep;

  /// Whether previews resolve through `recomputeAlongPath` (Phase 113).
  /// Captured from [TracingFlags.dragTracing] at session start so one
  /// gesture never mixes resolution modes. Single free points only —
  /// rigid translations move several roots at once, which the naive
  /// single-path walk cannot continue yet.
  final bool _traceDrags = TracingFlags.dragTracing;

  /// The previous traced preview's end — where the next preview path
  /// starts, so branch matching is continuous across pointer events.
  /// Null until the first traced update (the gesture starts from the
  /// point's start position).
  Vec2? _lastPreview;

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
    _delta = pointer - _grabStart;
    if (_isFreePoint) {
      if (_traceDrags) {
        _tracedUpdate(_freePointPosition);
      } else {
        _construction.moveFreePoint(_pointIds.single, _freePointPosition);
      }
      return;
    }
    for (final id in _pointIds) {
      _construction.moveFreePoint(id, _startPositions[id]! + _delta);
    }
  }

  /// One traced preview frame: continue branches along the path from the
  /// previous preview position to [target]. The static-solve bail (PLAN
  /// §Risks) stands in every phase: whatever goes wrong inside the
  /// tracing engine, the frame falls back to the canonical static solve
  /// and the gesture carries on.
  void _tracedUpdate(Vec2 target) {
    final id = _pointIds.single;
    final from = _lastPreview ?? _startPositions[id]!;
    _lastPreview = target;
    try {
      _construction.recomputeAlongPath(
        id,
        DragPath(from, target),
        steps: TracingFlags.dragSteps,
      );
    } catch (_) {
      _construction.moveFreePoint(id, target);
    }
  }

  @override
  Command? end() {
    final delta = _delta;
    if (_isFreePoint) {
      final id = _pointIds.single;
      final from = _startPositions[id]!;
      final to = _freePointPosition;
      _rollback();
      // A snapped drag can quantize back onto its start — nothing to undo.
      if (delta == Vec2.zero || to == from) {
        return null;
      }
      return MoveFreePointCommand(pointId: id, from: from, to: to);
    }
    _rollback();
    if (delta == Vec2.zero) {
      return null;
    }
    return TranslateObjectsCommand(pointIds: _pointIds, delta: delta);
  }

  @override
  void cancel() => _rollback();

  /// Restores every dragged point's start position verbatim (float-exact,
  /// like the commands). Points that vanished under the session — an
  /// undo mid-drag can remove them — are skipped rather than thrown on.
  void _rollback() {
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
  _TextAnchorDragSession(this._construction, ExpressionText text, this._grabStart)
      : _textId = text.id,
        _startAnchor = text.anchor;

  final Construction _construction;
  final String _textId;
  final Vec2 _startAnchor;
  final Vec2 _grabStart;

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
  ) : _parameter = _startParameter;

  /// Null when the host curve is undefined — nothing to slide on (the hit
  /// tester skips undefined objects, so this is belt and braces).
  static _SlideDragSession? start(
    Construction construction,
    PointOnObject target,
    Vec2 grabStart,
  ) {
    final curve = target.curve;
    final project = switch (curve) {
      GeoLine(:final line?) => line.parameterAt,
      GeoCircle(:final circle?) => circle.angleAt,
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
    if (curve is GeoCircle) {
      // Angular parameters are periodic: near atan2's ±π cut the raw
      // offset can come out ~2π even though the grab sits on the point.
      // Normalize to (−π, π] so the stored parameter never jumps a turn.
      grabOffset -= 2 * math.pi * (grabOffset / (2 * math.pi)).roundToDouble();
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

  double _parameter;

  @override
  void update(Vec2 pointer) {
    _parameter = _clamp(_project(pointer) + _grabOffset);
    _construction.setPointOnObjectParameter(_pointId, _parameter);
  }

  @override
  Command? end() {
    final parameter = _parameter;
    _rollback();
    if (parameter == _startParameter) {
      return null;
    }
    return SetPointOnObjectParameterCommand(
      pointId: _pointId,
      from: _startParameter,
      to: parameter,
    );
  }

  @override
  void cancel() => _rollback();

  /// Restores the start parameter verbatim (float-exact, like the
  /// command). Skipped if the point vanished under the session.
  void _rollback() {
    if (_construction.contains(_pointId)) {
      _construction.setPointOnObjectParameter(_pointId, _startParameter);
    }
  }
}
