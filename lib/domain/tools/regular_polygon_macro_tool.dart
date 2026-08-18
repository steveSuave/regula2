import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/objects/rotated_point.dart';
import '../construction/objects/segment.dart';
import 'multi_point_tool.dart';

/// Two taps make a regular polygon of [sideCount] sides, and **what the
/// two taps mean depends on the document's geometry** (Phase 128, PLAN
/// §"A shape is not an angle"):
///
/// - **Euclidean**: A and B are adjacent vertices, and the remaining
///   [sideCount] − 2 chain as `RotatedPoint`s — each vertex is the
///   previous-but-one turned about the previous by 2π/n − π, so the
///   polygon lies to the *left* of A→B, every derived vertex is
///   single-valued and continuous, and there is no hidden scaffolding.
/// - **Proper absolute**: A is the polygon's *centre* and B is one
///   vertex; the rest are B turned about A by 2πk/n. Every side is then
///   an isometric image of every other by construction, in any geometry.
///
/// The split is not a preference. A Cayley–Klein plane has no similar
/// figures, so a regular n-gon of side `s` turns by θ where
/// `cos(π/n) = σ(s/2)·sin(θ/2)` — σ = cosh hyperbolic, cos elliptic,
/// ≡ 1 Euclidean — and that turn moves with `s` while
/// [RotatedPoint.angle] is fixed for the object's lifetime. Chaining a
/// constant leaves the ring open: a hyperbolic octagon at a chart side of
/// 0.6 closes with a segment 3.8× the length of its others. `2πk/n`
/// survives because it is an angle at the **centre of the symmetry that
/// generates the figure** rather than an angle of the figure — the cyclic
/// group of order n fixing A acts transitively on a regular n-gon's
/// vertices under any absolute.
///
/// The cost is that the same gesture reads differently in the two cases,
/// which is preferred to refusing the tool in a non-Euclidean document.
/// A geometry switch does not rebuild an existing figure either way.
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
    // Each derived vertex dedups independently ([dedupedDerivedPoint]) so
    // re-stamping over an existing polygon reuses the whole ring; the
    // chain continues from whichever instance survived.
    final created = <GeoPoint>[];
    final vertices = absolute.isEuclidean
        ? _chained(points, created)
        : _orbit(points, created);
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

  /// Two adjacent vertices, each new one the previous-but-one turned
  /// about the previous by the Euclidean interior angle.
  List<GeoPoint> _chained(List<GeoPoint> points, List<GeoPoint> created) {
    final vertices = <GeoPoint>[points[0], points[1]];
    final turn = 2 * math.pi / sideCount - math.pi;
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
    return vertices;
  }

  /// A centre and one vertex; the rest are that vertex's orbit under the
  /// cyclic rotation group of order [sideCount] fixing the centre.
  List<GeoPoint> _orbit(List<GeoPoint> points, List<GeoPoint> created) {
    final centre = points[0];
    final vertices = <GeoPoint>[points[1]];
    for (var k = 1; k < sideCount; k++) {
      final candidate = RotatedPoint(
        id: newId(),
        point: points[1],
        center: centre,
        angle: 2 * math.pi * k / sideCount,
      );
      final vertex = dedupedDerivedPoint(candidate);
      if (identical(vertex, candidate)) {
        created.add(candidate);
      }
      vertices.add(vertex);
    }
    return vertices;
  }
}
