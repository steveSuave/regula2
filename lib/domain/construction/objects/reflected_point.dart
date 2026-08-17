import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_point.dart';
import '../../projective/proj_transform.dart';
import '../geo_object.dart';

/// The mirror image of [point] across the [mirror] line.
///
/// Undefined while either parent is (e.g. the mirror's defining points
/// coincide); a point lying on the mirror reflects to itself, which is
/// not degenerate. Segments and rays mirror across their infinite
/// carrier, matching `IntersectionPoint`'s carrier semantics.
///
/// Migrated (Phase 108): [ProjTransform.reflection] of the mirror's
/// projective carrier, applied to the parent's projective view. A parent
/// at infinity reflects to the mirrored direction at infinity, marked as
/// such: [projPoint] real, [position] null.
class ReflectedPoint extends GeoPoint {
  ReflectedPoint({
    required super.id,
    required this.point,
    required this.mirror,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point;
  final GeoLine mirror;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point, mirror];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p = point.projPoint;
    final axis = mirror.projLine;
    if (p == null || axis == null) {
      _point = null;
      return;
    }
    final image = ProjTransform.reflection(axis, absolute).apply(p);
    _point = image.isZero ? null : image;
  }
}
