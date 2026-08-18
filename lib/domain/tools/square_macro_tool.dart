import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/perpendicular_line.dart';
import '../construction/objects/segment.dart';
import 'multi_point_tool.dart';
import 'regular_polygon_orbit.dart';

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
///
/// **Under a proper absolute that composition builds a Saccheri
/// quadrilateral rather than a square** (Phase 129, PLAN §"The macro
/// triage"). Every step of it generalizes — the perpendicular and the
/// compass circle are both metric — and the figure still comes out with
/// three equal sides and two right base angles, which in a Cayley–Klein
/// plane is a *different quadrilateral*: its summit measures longer than
/// its base in the hyperbolic plane and shorter in the elliptic one, and
/// its summit angles are not right, because no such plane has a
/// quadrilateral with four of them.
///
/// A square is the regular 4-gon, so the CK route is
/// [regularPolygonOrbit] with n = 4 — the same construction
/// `RegularPolygonMacroTool` takes, and the taps mean what they mean
/// there: the first is the *centre* and the second one corner.
class SquareMacroTool extends MultiPointTool {
  SquareMacroTool({required super.newId});

  @override
  int get pointCount => 2;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    if (!absolute.isEuclidean) {
      final orbit = regularPolygonOrbit(
        centre: points[0],
        vertex: points[1],
        sideCount: 4,
        newId: newId,
        dedupe: dedupedDerivedPoint,
      );
      return [
        ...orbit.created,
        for (var k = 0; k < 4; k++)
          Segment(
            id: newId(),
            point1: orbit.vertices[k],
            point2: orbit.vertices[(k + 1) % 4],
          ),
      ];
    }
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
