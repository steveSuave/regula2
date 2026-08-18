import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/perpendicular_line.dart';
import '../construction/objects/segment.dart';
import '../projective/absolute.dart';
import 'multi_point_tool.dart';

/// Three taps make a right trapezium: the tapped points are the base
/// corners A, B (the right angles sit at A) and the far top corner C.
/// The last corner D is *derived* — the (single-branch, line∩line)
/// intersection of the perpendicular to AB through A with the parallel
/// to AB through C — so ∠A = ∠D = 90° and DC ∥ AB by construction, and
/// dragging any tapped corner keeps the shape a right trapezium.
///
/// Coincident A, B (or C on the line AB) leave the scaffolding without a
/// crossing, so D and the sides through it stay undefined until the
/// degeneracy passes. Tap order matters: C belongs above B's end of the
/// base — a C past A's side folds the quad over itself, like the other
/// macros' odd tap orders.
class RightTrapeziumMacroTool extends MultiPointTool {
  RightTrapeziumMacroTool({required super.newId});

  /// **Euclidean only** (Phase 129), for the trapezium's reason: it too
  /// stands on *the* parallel through a point, which no Cayley–Klein
  /// plane has.
  @override
  bool availableUnder(Absolute absolute) => absolute.isEuclidean;

  @override
  int get pointCount => 3;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    final c = points[2];
    const hidden = ObjectAttributes(visible: false);

    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final sideBC = Segment(id: newId(), point1: b, point2: c);
    final perpendicularA = PerpendicularLine(
      id: newId(),
      through: a,
      reference: sideAB,
      attributes: hidden,
    );
    final parallelThroughC = ParallelLine(
      id: newId(),
      through: c,
      reference: sideAB,
      attributes: hidden,
    );
    final cornerD = IntersectionPoint(
      id: newId(),
      curve1: perpendicularA,
      curve2: parallelThroughC,
      branchIndex: 0,
      absolute: absolute,
    );
    final corner = dedupedDerivedPoint(cornerD);

    return [
      sideAB,
      sideBC,
      if (identical(corner, cornerD)) ...[
        perpendicularA,
        parallelThroughC,
        cornerD,
      ],
      Segment(id: newId(), point1: c, point2: corner),
      Segment(id: newId(), point1: corner, point2: a),
    ];
  }
}
