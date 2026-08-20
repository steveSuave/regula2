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
///
/// **Generalized (Phase 127)**: under a proper absolute this is
/// [ProjTransform.ckRotation], the exponential of `Ω*·[C]ₓ`, of which the
/// Euclidean matrix is the special case — kept as the Euclidean route
/// because it is exact and cheaper, per the Phase 122/124 rule.
///
/// Undefined when the *centre* is not inside the absolute, which is the
/// classical trichotomy rather than a shortcoming: an isometry fixing a
/// point on the absolute is parabolic and one fixing a point outside it
/// is a boost along that point's polar, so neither has an angle for
/// [angle] to be. In elliptic geometry the absolute has no real points
/// and every real centre rotates. See [ProjTransform.ckRotation].
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
    // Phase 125 deferred this on the grounds that the pencil through a
    // general centre is not uniformly circular. That is true, and it is
    // true of centres *outside* the absolute: the pencil through an
    // interior point misses the dual conic entirely, so its angle measure
    // is elliptic and a rotation there is as circular as a Euclidean one.
    // `ckRotation` answers the zero map for the other two cases, which
    // lands in the same guard a degenerate Euclidean rotation does.
    final transform = absolute.isEuclidean
        ? ProjTransform.rotation(c, angle)
        : ProjTransform.ckRotation(c, angle, absolute);
    final image = transform.apply(p);
    _point = image.isZero ? null : image.wPositive;
  }
}
