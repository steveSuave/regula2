import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// Base for point objects derived from the three vertices of a triangle
/// (`Centroid`, `Orthocenter`, `Incenter`, `Circumcenter`).
///
/// Migrated (Phase 107): stores the homogeneous center from
/// [computeCenter]. Degenerate configurations that V1 flagged undefined
/// now mostly land at infinity (collinear vertices) or on the zero triple
/// (coincident vertices); either way [position] — the chart projection —
/// goes null there, so `isDefined` keeps its V1 answers while [projPoint]
/// carries the at-infinity value for projective consumers.
abstract class TriangleCenterPoint extends GeoPoint {
  TriangleCenterPoint({
    required super.id,
    required this.vertex1,
    required this.vertex2,
    required this.vertex3,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint vertex1;
  final GeoPoint vertex2;
  final GeoPoint vertex3;

  ProjPoint? _center;

  @override
  ProjPoint? get projPoint => _center;

  @override
  Vec2? get position => _center?.toVec2();

  @override
  List<GeoObject> get parents => [vertex1, vertex2, vertex3];

  /// The homogeneous center of triangle `abc`. May be the zero triple, or
  /// null for degeneracies the subclass computes affinely (`Incenter`);
  /// both leave the object undefined.
  ProjPoint? computeCenter(
    ProjPoint a,
    ProjPoint b,
    ProjPoint c,
    Absolute absolute,
  );

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final a = vertex1.projPoint;
    final b = vertex2.projPoint;
    final c = vertex3.projPoint;
    if (a == null || b == null || c == null) {
      _center = null;
      return;
    }
    final center = computeCenter(a, b, c, absolute);
    _center = (center == null || center.isZero) ? null : center;
  }
}
