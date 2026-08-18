import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/objects/rotated_point.dart';
import '../construction/objects/segment.dart';
import 'multi_point_tool.dart';

/// Two taps make a regular polygon: the tapped points A, B are adjacent
/// vertices, and the remaining [sideCount] − 2 chain as `RotatedPoint`s —
/// each vertex is the previous-but-one turned about the previous by
/// 2π/n − π, so the polygon lies to the *left* of A→B, every derived
/// vertex is single-valued and continuous, and there is no hidden
/// scaffolding. The side count comes from a dialog before the tool
/// activates.
///
/// **This is a Euclidean construction, and under a proper absolute the
/// ring does not close** (Phase 128, measured in
/// `test/domain/tools/ck_macro_tools_test.dart`). Every chained vertex is
/// an isometric image of the previous-but-one, so the figure is
/// equilateral as far as it goes; but the fixed turn is the Euclidean
/// interior angle, the last vertex does not land adjacent to the first,
/// and the closing segment draws a side that is not one. The error
/// accumulates with the vertex count as well as the side: a hyperbolic
/// octagon at a chart side of 0.6 closes with a segment 3.8× the length
/// of its others.
///
/// A regular n-gon of Cayley–Klein side `s` turns by θ where
/// `cos(π/n) = σ(s/2)·sin(θ/2)`, with `σ = cosh` in the hyperbolic plane,
/// `cos` in the elliptic one and `σ ≡ 1` in the Euclidean — which is the
/// whole of why a constant works here and nowhere else. That turn moves
/// with `s`, and [RotatedPoint]'s angle is fixed for the object's
/// lifetime, so baking a better constant would only be correct until the
/// first drag.
///
/// A dedicated class for the same reason as `RotatedPointTool`: the
/// toolbar's Macros highlight keys on tool identity, which a closure
/// capturing the count would defeat.
class RegularPolygonMacroTool extends MultiPointTool {
  RegularPolygonMacroTool({required super.newId, required this.sideCount})
    : assert(sideCount >= 3, 'a polygon needs at least 3 sides');

  /// Number of vertices (= sides), fixed for the tool's lifetime.
  final int sideCount;

  @override
  int get pointCount => 2;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final vertices = <GeoPoint>[points[0], points[1]];
    final turn = 2 * math.pi / sideCount - math.pi;
    // Each derived vertex dedups independently ([dedupedDerivedPoint]) so
    // re-stamping over an existing polygon's two vertices reuses the whole
    // ring; the chain continues from whichever instance survived.
    final created = <GeoPoint>[];
    for (var k = 2; k < sideCount; k++) {
      final candidate = RotatedPoint(
        id: newId(),
        point: vertices[k - 2],
        center: vertices[k - 1],
        angle: turn,
      );
      final vertex = dedupedDerivedPoint(candidate);
      if (identical(vertex, candidate)) {
        created.add(candidate);
      }
      vertices.add(vertex);
    }
    return [
      ...created,
      for (var k = 0; k < sideCount; k++)
        Segment(
          id: newId(),
          point1: vertices[k],
          point2: vertices[(k + 1) % sideCount],
        ),
    ];
  }
}
