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
