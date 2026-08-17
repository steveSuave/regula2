import '../construction/geo_object.dart';
import '../construction/objects/angle_bisector_line.dart';
import '../construction/objects/two_line_bisector_line.dart';
import '../math/vec2.dart';
import 'two_line_or_three_point_tool.dart';

/// The angle bisector tool, two modes decided by the first tap (Phase
/// 29b; the mode machine lives in [TwoLineOrThreePointTool] since Phase
/// 46).
///
/// Two-line mode commits a [TwoLineBisectorLine] bisecting the tapped
/// wedge; point mode is the classic arm–vertex–arm [AngleBisectorLine]
/// flow.
class AngleBisectorTool extends TwoLineOrThreePointTool {
  AngleBisectorTool({required super.newId});

  @override
  GeoObject buildFromLines(
    String id,
    GeoLine line1,
    GeoLine line2,
    Vec2 tap1,
    Vec2 tap2,
  ) => TwoLineBisectorLine.near(
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
  ) => AngleBisectorLine(id: id, arm1: arm1, vertex: vertex, arm2: arm2);
}
