import '../construction/geo_object.dart';
import 'multi_point_tool.dart';

/// Builds the derived object from three collected points, in tap order.
/// Positional parameters because the meaning differs per object (angle
/// bisector: arm, vertex, arm; three-point circle: any order).
typedef ThreePointBuilder = GeoObject Function(
  String id,
  GeoPoint first,
  GeoPoint second,
  GeoPoint third,
);

/// Collects three distinct points, then builds one object on them —
/// the three-point sibling of `TwoPointTool` (angle bisector, and later
/// the three-point circle and arc). All collection behaviour, preview
/// markers and the single-undo-unit commit come from `MultiPointTool`.
class ThreePointTool extends MultiPointTool {
  ThreePointTool({
    required super.newId,
    required this.build,
    super.allowCurveTaps,
  });

  final ThreePointBuilder build;

  @override
  int get pointCount => 3;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    build(newId(), points[0], points[1], points[2]),
  ];
}
