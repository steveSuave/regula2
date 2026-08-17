import '../commands/add_object_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/distance_measurement.dart';
import '../construction/objects/length_measurement.dart';
import 'tool.dart';
import 'two_point_tool.dart';

/// The distance / length tool. Two point taps measure the distance
/// between them — the plain [TwoPointTool] flow, resolving each tap
/// through the point ladder. But a *first* tap whose topmost hit is a
/// circle, arc or sector instead commits a [LengthMeasurement] of that
/// curve (circumference, arc length, or sector perimeter) in one command.
///
/// Topmost-only keeps the rest of the ladder intact: an in-threshold
/// point outranks the curve and starts a point-to-point measurement, and
/// a tap near a line-circle crossing with the line on top still snaps an
/// intersection point. With one point already collected, curve taps glue
/// a `PointOnObject` as before, so point-to-curve-point distances remain
/// constructible.
class DistanceTool extends TwoPointTool {
  DistanceTool({required super.newId}) : super(build: _distance);

  static GeoObject _distance(String id, GeoPoint a, GeoPoint b) =>
      DistanceMeasurement(id: id, point1: a, point2: b);

  @override
  ToolResult onInput(ToolInput input) {
    if (input.hit case final GeoCircle subject when collectedVertices.isEmpty) {
      return ToolCommitted(
        AddObjectCommand(LengthMeasurement(id: newId(), subject: subject)),
      );
    }
    return super.onInput(input);
  }
}
