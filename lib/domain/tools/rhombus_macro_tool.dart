import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/point_on_object.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import 'multi_point_tool.dart';
import 'tool.dart';

/// Three taps make a rhombus: the first two are adjacent corners A, B
/// (one side); the third is *position-only* and picks the adjacent
/// side's direction — corner C is the tap projected onto the hidden
/// compass circle around B with radius |AB|, so |BC| = |AB| rides the
/// construction. D closes the shape via the parallelogram trick (the
/// single-branch intersection of the parallels to AB through C and to
/// BC through A), making all four sides equal under every drag.
///
/// Like the trapezium's fourth tap, the third input projects an existing
/// point's location but never consumes the object — C must stay
/// constrained to the circle. C is a `PointOnObject` on a circle, whose
/// polar-angle parameter follows the center around (no analytic-drift
/// caveat here, unlike the line case).
///
/// Coincident A, B collapse the circle to its center: the shape is
/// degenerate but every parent stays defined, and separating the corners
/// restores it.
class RhombusMacroTool extends MultiPointTool {
  RhombusMacroTool({required super.newId});

  /// The tapped corner points; the position-only third input is not a
  /// collected vertex.
  @override
  int get pointCount => 2;

  /// The third tap, alive only inside the commit turn.
  Vec2? _cTarget;

  @override
  ToolResult onInput(ToolInput input) {
    if (collectedVertices.length < pointCount) {
      return collectVertex(input) == null
          ? const ToolIgnored()
          : const ToolAccepted();
    }
    _cTarget = input.position;
    final result = commitCollected();
    _cTarget = null;
    return result;
  }

  @override
  void reset() {
    _cTarget = null;
    super.reset();
  }

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    const hidden = ObjectAttributes(visible: false);

    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final circleAroundB = CompassCircle(
      id: newId(),
      radiusPoint1: a,
      radiusPoint2: b,
      center: b,
      attributes: hidden,
    );
    // A zero-radius circle (A ≡ B) is still a defined curve, but the tap
    // may sit exactly on its center where `near` has no angle to pick —
    // fall back like the trapezium does on an undefined carrier.
    final circle = circleAroundB.circle;
    final degenerate = circle == null || _cTarget == circle.center;
    final cornerC = degenerate
        ? PointOnObject(id: newId(), curve: circleAroundB, parameter: 0)
        : PointOnObject.near(
            id: newId(),
            curve: circleAroundB,
            position: _cTarget!,
          );
    final sideBC = Segment(id: newId(), point1: b, point2: cornerC);
    final parallelThroughC = ParallelLine(
      id: newId(),
      through: cornerC,
      reference: sideAB,
      attributes: hidden,
    );
    final parallelThroughA = ParallelLine(
      id: newId(),
      through: a,
      reference: sideBC,
      attributes: hidden,
    );
    final cornerD = IntersectionPoint(
      id: newId(),
      curve1: parallelThroughC,
      curve2: parallelThroughA,
      branchIndex: 0,
      absolute: absolute,
    );

    return [
      sideAB,
      circleAroundB,
      cornerC,
      sideBC,
      parallelThroughC,
      parallelThroughA,
      cornerD,
      Segment(id: newId(), point1: cornerC, point2: cornerD),
      Segment(id: newId(), point1: cornerD, point2: a),
    ];
  }
}
