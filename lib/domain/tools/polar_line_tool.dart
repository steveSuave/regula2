import '../commands/add_object_command.dart';
import '../commands/macro_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/polar_line.dart';
import '../math/vec2.dart';
import 'point_resolution.dart';
import 'tool.dart';

/// Collects one point (the pole) and one circle — in either order — then
/// creates the pole's [PolarLine] with respect to the circle.
///
/// `TangentTool`'s slot collection verbatim: a tap on an existing point
/// fills the point slot, the topmost in-threshold circle (consulted from
/// `hit`/`extraHits` *before* the point ladder) fills the circle slot,
/// any other tap resolves the point slot through the shared Phase 20
/// ladder, and input for an already-filled slot is ignored. Unlike the
/// tangent pair the polar is a single line, so the commit is one object
/// (plus the new point when the ladder built one). An existing polar
/// over the same point and circle instances refuses the completing tap
/// instead of stacking a duplicate — `RadicalAxisTool`'s structural
/// dedupe; a ladder-built point is new by construction, so only reused
/// points are checked.
class PolarLineTool implements ToolInputPreview {
  PolarLineTool({required this.newId});

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
      final point = _point;
      if (point != null &&
          !_pointIsNew &&
          _existingPolar(input.objects, point, circleHit)) {
        return const ToolIgnored();
      }
      _circle = circleHit;
    } else {
      if (_point != null) return const ToolIgnored();
      // The circle-slot branch above consumed every circle-flavored tap,
      // so the ladder can only reuse a point, glue to a line, or drop a
      // free point here.
      final resolved = resolvePoint(input, newId);
      final circle = _circle;
      if (!resolved.isNew &&
          circle != null &&
          _existingPolar(input.objects, resolved.point, circle)) {
        return const ToolIgnored();
      }
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
    final polar = PolarLine(id: newId(), point: point, circle: circle);
    return ToolCommitted(
      pointIsNew
          ? MacroCommand([AddObjectCommand(point), AddObjectCommand(polar)])
          : AddObjectCommand(polar),
    );
  }

  static bool _existingPolar(
    Iterable<GeoObject> objects,
    GeoPoint point,
    GeoCircle circle,
  ) => objects.any(
    (object) =>
        object is PolarLine &&
        identical(object.point, point) &&
        identical(object.circle, circle),
  );

  @override
  void reset() {
    _point = null;
    _pointIsNew = false;
    _circle = null;
  }
}
