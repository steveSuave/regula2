import '../construction/geo_object.dart';
import 'multi_point_tool.dart';

/// Builds a two-point object. Constructor parameter names differ across
/// the two-point objects (`point1`/`point2`, `center`/`onCircle`), so
/// this takes them positionally — adapt with a small lambda:
///
/// ```dart
/// TwoPointTool(
///   newId: newObjectId,
///   build: (id, a, b) => CircleCenterPoint(id: id, center: a, onCircle: b),
/// )
/// ```
typedef TwoPointBuilder =
    GeoObject Function(String id, GeoPoint first, GeoPoint second);

/// Collects two points, then emits one two-point object — line, segment,
/// circle (center + rim point), midpoint. Tap order is [TwoPointBuilder]
/// argument order, so for a circle the first tap is the center. Input
/// handling (existing points vs new free points, single undo unit,
/// preview markers) is [MultiPointTool]'s.
class TwoPointTool extends MultiPointTool {
  TwoPointTool({required super.newId, required this.build});

  final TwoPointBuilder build;

  @override
  int get pointCount => 2;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    build(newId(), points[0], points[1]),
  ];
}
