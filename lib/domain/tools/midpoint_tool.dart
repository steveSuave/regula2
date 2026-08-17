import '../commands/add_object_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/circle_center.dart';
import '../construction/objects/midpoint.dart';
import 'point_coincidence.dart';
import 'tool.dart';
import 'two_point_tool.dart';

/// GeoGebra's "Midpoint or Center": two point taps build a [Midpoint];
/// a tap whose topmost hit is a circle-valued object (circle, arc,
/// sector) instead emits its [CircleCenter] in one step.
///
/// The circle shortcut only fires while nothing is collected — after a
/// first point, a circle tap resolves through the normal point ladder
/// (gluing the second midpoint parent onto the curve), so the two-point
/// flow is unchanged. A point sitting on the circle still wins the tap:
/// only a circle-topmost hit is taken as "the circle itself".
///
/// Both products dedup against the construction: a midpoint that already
/// exists identically (same pair either way round, or a differently
/// defined point that provably sits there — a diagonals' crossing) and a
/// center already present as a visible point (the circle was drawn *on*
/// its center point) refuse the completing tap instead of stacking a
/// duplicate ([dedupedDerivedPoint] / [coincidentExistingPoint]).
class MidpointTool extends TwoPointTool {
  MidpointTool({required super.newId}) : super(build: _buildMidpoint);

  static GeoObject _buildMidpoint(String id, GeoPoint a, GeoPoint b) =>
      Midpoint(id: id, point1: a, point2: b);

  @override
  ToolResult onInput(ToolInput input) {
    final hit = input.hit;
    if (collectedVertices.isEmpty && hit is GeoCircle) {
      final center = CircleCenter(id: newId(), circle: hit);
      if (coincidentExistingPoint(
            input.objects,
            center,
            absolute: input.absolute,
          ) !=
          null) {
        return const ToolIgnored();
      }
      return ToolCommitted(AddObjectCommand(center));
    }
    return super.onInput(input);
  }

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final midpoint = Midpoint(
      id: newId(),
      point1: points[0],
      point2: points[1],
    );
    return [if (identical(dedupedDerivedPoint(midpoint), midpoint)) midpoint];
  }
}
