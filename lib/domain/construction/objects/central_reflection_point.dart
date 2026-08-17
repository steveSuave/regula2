import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_point.dart';
import '../../projective/proj_transform.dart';
import '../geo_object.dart';

/// The reflection of [point] about [center] (a half-turn: the center is
/// the midpoint of the point and its image).
///
/// Defined whenever both parents are — a point coinciding with the center
/// reflects to itself.
///
/// Migrated (Phase 108): [ProjTransform.pointReflection] on the parents'
/// projective views. A half-turn fixes every point at infinity, so a
/// parent at infinity is its own image, marked as such: [projPoint] real,
/// [position] null.
class CentralReflectionPoint extends GeoPoint {
  CentralReflectionPoint({
    required super.id,
    required this.point,
    required this.center,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point;
  final GeoPoint center;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point, center];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p = point.projPoint;
    final c = center.projPoint;
    if (p == null || c == null) {
      _point = null;
      return;
    }
    final image = ProjTransform.pointReflection(c).apply(p);
    _point = image.isZero ? null : image;
  }
}
