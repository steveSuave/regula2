import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/objects/rotated_point.dart';

/// [regularPolygonOrbit]'s result: the vertices in ring order, and the
/// subset of them this call actually created (the rest deduplicated onto
/// points already in the construction). Append `created` to a macro's
/// build list before the segments over `vertices`.
typedef PolygonOrbit = ({List<GeoPoint> created, List<GeoPoint> vertices});

/// The regular [sideCount]-gon with centre [centre] and one vertex
/// [vertex]: that vertex's orbit under the cyclic rotation group of order
/// [sideCount] fixing the centre.
///
/// **This is the construction that survives a change of absolute** (Phase
/// 128, PLAN §"A shape is not an angle"). `2πk/n` is an angle at the
/// centre of the *symmetry that generates the figure*, not an angle of
/// the figure, so it is a genuine constant in every geometry — the cyclic
/// group of order n fixing the centre acts transitively on a regular
/// n-gon's vertices under any absolute, which makes every side an
/// isometric image of every other by construction. An angle *of* the
/// figure is a function of its side length and cannot be baked into a
/// `RotatedPoint`, whose angle is fixed for the object's lifetime.
///
/// Each derived vertex goes through [dedupe] independently, so
/// re-stamping over an existing ring reuses the whole of it.
PolygonOrbit regularPolygonOrbit({
  required GeoPoint centre,
  required GeoPoint vertex,
  required int sideCount,
  required String Function() newId,
  required GeoPoint Function(GeoPoint candidate) dedupe,
}) {
  final created = <GeoPoint>[];
  final vertices = <GeoPoint>[vertex];
  for (var k = 1; k < sideCount; k++) {
    final candidate = RotatedPoint(
      id: newId(),
      point: vertex,
      center: centre,
      angle: 2 * math.pi * k / sideCount,
    );
    final corner = dedupe(candidate);
    if (identical(corner, candidate)) {
      created.add(candidate);
    }
    vertices.add(corner);
  }
  return (created: created, vertices: vertices);
}
