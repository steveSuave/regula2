import '../commands/add_object_command.dart';
import '../commands/macro_command.dart';
import '../construction/geo_object.dart';
import '../construction/incidence.dart';
import '../construction/objects/tangent_line.dart';
import '../math/vec2.dart';
import 'point_resolution.dart';
import 'tool.dart';

/// Collects one point and one circle — in either order — then emits
/// **both** tangent lines from the point to the circle in a single
/// `MacroCommand` (the GeoGebra convention: the pair is the natural undo
/// unit, and deleting one afterwards is trivial) — or **one**, when the
/// point is on the circle by construction and the two branches would be
/// the same line (Phase 164).
///
/// The `PointAndLineTool` pattern with a circle slot: a tap on an
/// existing point fills the point slot, and the topmost in-threshold
/// circle (consulted from `hit`/`extraHits` *before* the point ladder,
/// the `TransformObjectTool` slot precedent) fills the circle slot — so
/// a tap on the target circle never glues a `PointOnObject` to it. Any
/// other tap resolves the point slot through the shared Phase 20 ladder
/// (existing point / crossing / glue to a line / free point). Input for
/// an already-filled slot is ignored.
class TangentTool implements ToolInputPreview {
  TangentTool({required this.newId});

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  GeoPoint? _point;
  bool _pointIsNew = false;
  GeoCircle? _circle;

  /// Only a *new* point (free, glued, intersection) gets a marker (it
  /// isn't in the construction yet); a consumed existing point or circle
  /// is haloed instead.
  @override
  bool get hasPartialInput => _point != null || _circle != null;

  @override
  List<Vec2> get previewPositions => [if (_pointIsNew) ?_point?.position];

  @override
  List<String> get previewObjectIds => [
    if (!_pointIsNew) ?_point?.id,
    ?_circle?.id,
  ];

  @override
  ToolResult onInput(ToolInput input) {
    final circleHit = input.hits.whereType<GeoCircle>().firstOrNull;
    if (input.hit is! GeoPoint && circleHit != null) {
      if (_circle != null) return const ToolIgnored();
      _circle = circleHit;
    } else {
      if (_point != null) return const ToolIgnored();
      // The circle-slot branch above consumed every circle-flavored tap,
      // so the ladder can only reuse a point, glue to a line, or drop a
      // free point here.
      final resolved = resolvePoint(input, newId);
      _point = resolved.point;
      _pointIsNew = resolved.isNew;
    }

    final point = _point;
    final circle = _circle;
    if (point == null || circle == null) {
      return const ToolAccepted();
    }

    final pointIsNew = _pointIsNew;
    reset();
    return ToolCommitted(
      MacroCommand([
        if (pointIsNew) AddObjectCommand(point),
        // From a point on the circle both branches are the tangent at
        // that point, so emitting both would add one line twice (Phase
        // 164). Branch 0 is the survivor for no reason beyond being first.
        for (final branch in structurallyIncident(circle, point) ? [0] : [0, 1])
          AddObjectCommand(
            TangentLine(
              id: newId(),
              point: point,
              circle: circle,
              branch: branch,
            ),
          ),
      ]),
    );
  }

  @override
  void reset() {
    _point = null;
    _pointIsNew = false;
    _circle = null;
  }
}
