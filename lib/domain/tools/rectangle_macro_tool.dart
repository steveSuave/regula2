import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/perpendicular_line.dart';
import '../construction/objects/point_on_object.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import 'multi_point_tool.dart';
import 'tool.dart';

/// Three taps make a rectangle: the first two are adjacent corners A, B
/// (one side); the third is *position-only* and sets the height — corner
/// C is the tap projected onto the hidden perpendicular to AB through B,
/// and D closes the shape as the (single-branch, line∩line) intersection
/// of the perpendicular through A with the parallel to AB through C.
/// Right angles at A and B and DC ∥ AB hold by construction, so dragging
/// any tapped corner keeps the shape a rectangle.
///
/// Like the trapezium's fourth tap, the third input projects an existing
/// point's location but never consumes the object — C must stay
/// constrained to the perpendicular. C is a `PointOnObject` and inherits
/// its analytic-parameter caveat (translating the perpendicular along
/// itself leaves C in place; see that class).
///
/// While A and B coincide the perpendicular has no geometry to project
/// onto — C falls back to parameter 0 and the shape recovers when the
/// corners separate.
class RectangleMacroTool extends MultiPointTool {
  RectangleMacroTool({required super.newId});

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
    final perpendicularB = PerpendicularLine(
      id: newId(),
      through: b,
      reference: sideAB,
      attributes: hidden,
    );
    final cornerC = perpendicularB.line == null
        ? PointOnObject(id: newId(), curve: perpendicularB, parameter: 0)
        : PointOnObject.near(
            id: newId(),
            curve: perpendicularB,
            position: _cTarget!,
          );
    final parallelThroughC = ParallelLine(
      id: newId(),
      through: cornerC,
      reference: sideAB,
      attributes: hidden,
    );
    final perpendicularA = PerpendicularLine(
      id: newId(),
      through: a,
      reference: sideAB,
      attributes: hidden,
    );
    final cornerD = IntersectionPoint(
      id: newId(),
      curve1: parallelThroughC,
      curve2: perpendicularA,
      branchIndex: 0,
      absolute: absolute,
    );

    return [
      sideAB,
      perpendicularB,
      cornerC,
      Segment(id: newId(), point1: b, point2: cornerC),
      parallelThroughC,
      perpendicularA,
      cornerD,
      Segment(id: newId(), point1: cornerC, point2: cornerD),
      Segment(id: newId(), point1: cornerD, point2: a),
    ];
  }
}
