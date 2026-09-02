import '../construction/geo_object.dart';
import '../construction/objects/triangle_circle.dart';
import 'multi_point_tool.dart';

/// Signature shared by the triangle-circle constructors — pass a tear-off
/// (`NinePointCircle.new`, `InscribedCircle.new`) to [TriangleCircleTool].
typedef TriangleCircleBuilder = TriangleCircle Function({
  required String id,
  required GeoPoint vertex1,
  required GeoPoint vertex2,
  required GeoPoint vertex3,
});

/// Collects three vertices, then emits one triangle circle. Input
/// handling (existing points vs new free points, single undo unit,
/// preview markers) is [MultiPointTool]'s.
///
/// A circle that already exists over the same triangle refuses the
/// completing tap instead of stacking a duplicate — the
/// `TriangleCenterTool` convention, but checked *structurally* (same
/// concrete kind, identical parent instances in any vertex order — the
/// circles are symmetric in their vertices): the numeric
/// [dedupedDerivedPoint] probe only covers points, not circles.
class TriangleCircleTool extends MultiPointTool {
  TriangleCircleTool({required super.newId, required this.buildCircle});

  /// Builds the concrete circle from the three collected vertices.
  final TriangleCircleBuilder buildCircle;

  @override
  int get pointCount => 3;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final circle = buildCircle(
      id: newId(),
      vertex1: points[0],
      vertex2: points[1],
      vertex3: points[2],
    );
    final alreadyExists = constructionObjects.any(
      (object) =>
          object.runtimeType == circle.runtimeType &&
          object is TriangleCircle &&
          points.every(
            (p) =>
                identical(p, object.vertex1) ||
                identical(p, object.vertex2) ||
                identical(p, object.vertex3),
          ),
    );
    return [if (!alreadyExists) circle];
  }
}
