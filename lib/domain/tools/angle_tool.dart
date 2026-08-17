import '../construction/geo_object.dart';
import '../construction/objects/line_angle.dart';
import '../construction/objects/vertex_angle.dart';
import '../math/vec2.dart';
import 'two_line_or_three_point_tool.dart';

/// The angle tool, two modes decided by the first tap (Phase 46, merging
/// the former vertex-angle and line-angle tools).
///
/// A first tap on a line enters two-line mode: the second line commits a
/// [LineAngle] marking the tapped wedge (Phase 31). A first tap on a
/// point or on empty canvas enters point mode, the arm–vertex–arm
/// [VertexAngle] flow. See [TwoLineOrThreePointTool] for the mode
/// mechanics.
class AngleTool extends TwoLineOrThreePointTool {
  AngleTool({required super.newId});

  @override
  GeoObject buildFromLines(
    String id,
    GeoLine line1,
    GeoLine line2,
    Vec2 tap1,
    Vec2 tap2,
  ) => LineAngle.near(
    id: id,
    line1: line1,
    line2: line2,
    tap1: tap1,
    tap2: tap2,
  );

  @override
  GeoObject buildFromPoints(
    String id,
    GeoPoint arm1,
    GeoPoint vertex,
    GeoPoint arm2,
  ) => VertexAngle(id: id, arm1: arm1, vertex: vertex, arm2: arm2);
}
