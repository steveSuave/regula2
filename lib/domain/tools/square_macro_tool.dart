import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/perpendicular_line.dart';
import '../construction/objects/segment.dart';
import 'multi_point_tool.dart';

/// Two taps make a square: the tapped points are adjacent corners A and
/// B, the other two corners are *derived*, so dragging A or B keeps the
/// shape a square.
///
/// The corners are a scripted compass-and-straightedge composition of
/// existing primitives (no new object kind, so codec / painter / hit
/// tester are untouched): C is the branch-1 intersection of the
/// perpendicular to AB at B with the circle around B of radius |AB|, and
/// D likewise at A. The side segment AB doubles as the perpendiculars'
/// carrier reference; the perpendiculars and circles are added invisible.
///
/// Branch 1 of line∩circle is the candidate *along* the perpendicular's
/// direction, which is the AB carrier's normal — the counterclockwise
/// rotation of the A→B direction. Both corners use the same normal, so
/// the square always lies to the left of A→B: tap order picks the side,
/// and the side follows the points continuously under dragging (the
/// carrier direction comes from parent order, it is never re-canonicalized).
///
/// Coincident corner positions leave every derived object undefined until
/// the points separate again, like any other degenerate construction.
///
/// Each derived corner runs through [dedupedDerivedPoint]: a visible
/// existing point identically coincident with it (stamping the square
/// over the same two corners again) is reused, and that corner's hidden
/// scaffolding is not added.
class SquareMacroTool extends MultiPointTool {
  SquareMacroTool({required super.newId});

  @override
  int get pointCount => 2;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    const hidden = ObjectAttributes(visible: false);

    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final perpB = PerpendicularLine(
      id: newId(),
      through: b,
      reference: sideAB,
      attributes: hidden,
    );
    final circleB = CompassCircle(
      id: newId(),
      radiusPoint1: a,
      radiusPoint2: b,
      center: b,
      attributes: hidden,
    );
    final cornerC = IntersectionPoint(
      id: newId(),
      curve1: perpB,
      curve2: circleB,
      branchIndex: 1,
      absolute: absolute,
    );
    final perpA = PerpendicularLine(
      id: newId(),
      through: a,
      reference: sideAB,
      attributes: hidden,
    );
    final circleA = CompassCircle(
      id: newId(),
      radiusPoint1: a,
      radiusPoint2: b,
      center: a,
      attributes: hidden,
    );
    final cornerD = IntersectionPoint(
      id: newId(),
      curve1: perpA,
      curve2: circleA,
      branchIndex: 1,
      absolute: absolute,
    );
    final c = dedupedDerivedPoint(cornerC);
    final d = dedupedDerivedPoint(cornerD);

    return [
      sideAB,
      if (identical(c, cornerC)) ...[perpB, circleB, cornerC],
      if (identical(d, cornerD)) ...[perpA, circleA, cornerD],
      Segment(id: newId(), point1: b, point2: c),
      Segment(id: newId(), point1: c, point2: d),
      Segment(id: newId(), point1: d, point2: a),
    ];
  }
}
