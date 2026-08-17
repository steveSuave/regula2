import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_point.dart';
import '../../projective/proj_transform.dart';
import '../geo_object.dart';

/// [point] rotated around [center] by a fixed [angle].
///
/// Defined whenever both parents are — a point coinciding with the center
/// rotates to itself. The angle is world-space (counter-clockwise for
/// positive values, like every angle in the math layer) and fixed for the
/// object's lifetime, same as `SegmentRatioPoint.ratio`.
///
/// Migrated (Phase 108): [ProjTransform.rotation] on the parents'
/// projective views. A point at infinity rotates to the turned direction
/// at infinity, marked as such: [projPoint] real, [position] null.
class RotatedPoint extends GeoPoint {
  RotatedPoint({
    required super.id,
    required this.point,
    required this.center,
    required this.angle,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point;
  final GeoPoint center;

  /// Rotation angle in radians, counter-clockwise.
  final double angle;

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
    final image = ProjTransform.rotation(c, angle).apply(p);
    _point = image.isZero ? null : image;
  }
}
