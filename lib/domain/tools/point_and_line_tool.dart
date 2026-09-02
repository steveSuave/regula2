import '../commands/add_object_command.dart';
import '../commands/macro_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/free_point.dart';
import '../math/vec2.dart';
import 'tool.dart';

/// Builds the derived object from the collected point and line. Named
/// parameters match the `RelativeLine` constructors, so
/// `PerpendicularLine.new` / `ParallelLine.new` tear-offs slot in
/// directly (the extra optional `attributes` parameter doesn't hurt
/// assignability).
typedef PointAndLineBuilder = GeoObject Function({
  required String id,
  required GeoPoint through,
  required GeoLine reference,
});

/// Collects one point and one line — in either order — then builds one
/// object on them (perpendicular line, parallel line).
///
/// A tap on an existing point fills the point slot; empty canvas creates
/// a new free point there, like `PointTool`. A tap on a line fills the
/// line slot. Input for an already-filled slot is ignored, as are
/// circles. As in `MultiPointTool`, a new free point is held privately
/// until commit and grouped with the built object in one `MacroCommand`,
/// so the step is a single undo unit.
class PointAndLineTool implements ToolInputPreview {
  PointAndLineTool({required this.newId, required this.build});

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  final PointAndLineBuilder build;

  GeoPoint? _point;
  bool _pointIsNew = false;
  GeoLine? _line;

  /// Only a *new* free point gets a marker (it isn't in the construction
  /// yet); a consumed existing point or line is haloed instead.
  @override
  bool get hasPartialInput => _point != null || _line != null;

  @override
  List<Vec2> get previewPositions => [if (_pointIsNew) ?_point?.position];

  @override
  List<String> get previewObjectIds => [
    if (!_pointIsNew) ?_point?.id,
    ?_line?.id,
  ];

  @override
  ToolResult onInput(ToolInput input) {
    switch (input.hit) {
      case final GeoPoint hit:
        if (_point != null) return const ToolIgnored();
        _point = hit;
        _pointIsNew = false;
      case final GeoLine hit:
        if (_line != null) return const ToolIgnored();
        _line = hit;
      case GeoCircle() ||
          GeoAngle() ||
          GeoPolygon() ||
          GeoMeasurement() ||
          GeoLocus() ||
          GeoText():
        return const ToolIgnored();
      case null:
        if (_point != null) return const ToolIgnored();
        _point = FreePoint(id: newId(), position: input.position);
        _pointIsNew = true;
    }

    final point = _point;
    final line = _line;
    if (point == null || line == null) {
      return const ToolAccepted();
    }

    final pointIsNew = _pointIsNew;
    reset();
    final derived = build(id: newId(), through: point, reference: line);
    return ToolCommitted(
      pointIsNew
          ? MacroCommand([AddObjectCommand(point), AddObjectCommand(derived)])
          : AddObjectCommand(derived),
    );
  }

  @override
  void reset() {
    _point = null;
    _pointIsNew = false;
    _line = null;
  }
}
