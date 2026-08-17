import '../construction/geo_object.dart';
import '../construction/objects/apollonius_circle.dart';
import '../construction/objects/arc.dart';
import '../construction/objects/bifocal_conic.dart';
import '../construction/objects/central_reflection_point.dart';
import '../construction/objects/circle_center_point.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/diameter_circle.dart';
import '../construction/objects/five_point_conic.dart';
import '../construction/objects/homothetic_point.dart';
import '../construction/objects/inscribed_circle.dart';
import '../construction/objects/line_through_two_points.dart';
import '../construction/objects/nine_point_circle.dart';
import '../construction/objects/ray.dart';
import '../construction/objects/reflected_point.dart';
import '../construction/objects/rotated_point.dart';
import '../construction/objects/sector.dart';
import '../construction/objects/segment.dart';
import '../construction/objects/three_point_circle.dart';
import '../construction/objects/translated_point.dart';
import '../construction/objects/vertex_angle.dart';

/// The first object in [objects] equivalent to [candidate], or null.
///
/// Equivalence is *structural identity*: same concrete kind, identical
/// parent **instances** slot-by-slot, equal params (`RotatedPoint.angle`
/// and `HomotheticPoint.ratio` compared exactly — the same dialog value,
/// no epsilon). A numerically coincident object built from different
/// parents deliberately does not match: it moves differently under drags.
///
/// Covers exactly what `TransformObjectTool` can emit — the five
/// transform-point kinds and the twelve rebuildable curve kinds; any
/// other candidate finds nothing.
GeoObject? equivalentExisting(
  Iterable<GeoObject> objects,
  GeoObject candidate,
) {
  if (!_covered(candidate)) {
    return null;
  }
  for (final existing in objects) {
    if (_equivalent(existing, candidate)) {
      return existing;
    }
  }
  return null;
}

bool _covered(GeoObject object) => switch (object) {
  ReflectedPoint() ||
  CentralReflectionPoint() ||
  RotatedPoint() ||
  TranslatedPoint() ||
  HomotheticPoint() ||
  Segment() ||
  Ray() ||
  LineThroughTwoPoints() ||
  CircleCenterPoint() ||
  DiameterCircle() ||
  CompassCircle() ||
  ThreePointCircle() ||
  NinePointCircle() ||
  InscribedCircle() ||
  ApolloniusCircle() ||
  FivePointConic() ||
  BifocalConic() ||
  Arc() ||
  Sector() ||
  VertexAngle() => true,
  _ => false,
};

bool _equivalent(GeoObject existing, GeoObject candidate) {
  if (existing.runtimeType != candidate.runtimeType) {
    return false;
  }
  final existingParents = existing.parents;
  final candidateParents = candidate.parents;
  if (existingParents.length != candidateParents.length) {
    return false;
  }
  for (var i = 0; i < existingParents.length; i++) {
    if (!identical(existingParents[i], candidateParents[i])) {
      return false;
    }
  }
  return switch ((existing, candidate)) {
    (final RotatedPoint a, final RotatedPoint b) => a.angle == b.angle,
    (final HomotheticPoint a, final HomotheticPoint b) => a.ratio == b.ratio,
    _ => true,
  };
}
