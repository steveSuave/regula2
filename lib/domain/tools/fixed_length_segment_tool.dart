import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/fixed_radius_circle.dart';
import '../construction/objects/point_on_object.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import 'multi_point_tool.dart';
import 'tool.dart';

/// Two taps make a segment of a fixed [length]: the first resolves to
/// endpoint A via the shared point ladder; the second is *position-only*
/// and picks the direction — B is a `PointOnObject` projected from the
/// tap onto a hidden `FixedRadiusCircle(A, length)`, so |AB| ≡ [length]
/// by construction and B stays draggable around A through the Phase 14
/// slide-drag. The length comes from a dialog before the tool activates.
///
/// Like the trapezium's fourth tap, the direction input projects an
/// existing point's location but never consumes the object — B must stay
/// constrained to the circle. B inherits `PointOnObject`'s
/// analytic-parameter caveat (see that class). A direction tap exactly
/// on A projects to angle 0 (the circle's `angleAt` convention); a tap
/// while A is undefined falls back to parameter 0 and recovers with the
/// rest of the construction.
class FixedLengthSegmentTool extends MultiPointTool {
  FixedLengthSegmentTool({required super.newId, required this.length})
    : assert(
        length.isFinite && length > 0,
        'the dialog admits only finite positive lengths',
      );

  /// Segment length in world units, fixed for the tool's lifetime.
  final double length;

  /// The tapped endpoint; the position-only direction input is not a
  /// collected vertex.
  @override
  int get pointCount => 1;

  /// The direction tap, alive only inside the commit turn.
  Vec2? _directionTarget;

  @override
  ToolResult onInput(ToolInput input) {
    if (collectedVertices.length < pointCount) {
      return collectVertex(input) == null
          ? const ToolIgnored()
          : const ToolAccepted();
    }
    _directionTarget = input.position;
    final result = commitCollected();
    _directionTarget = null;
    return result;
  }

  @override
  void reset() {
    _directionTarget = null;
    super.reset();
  }

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final circle = FixedRadiusCircle(
      id: newId(),
      center: a,
      radius: length,
      attributes: const ObjectAttributes(visible: false),
    );
    final b = circle.circle == null
        ? PointOnObject(id: newId(), curve: circle, parameter: 0)
        : PointOnObject.near(
            id: newId(),
            curve: circle,
            position: _directionTarget!,
          );
    return [circle, b, Segment(id: newId(), point1: a, point2: b)];
  }
}
