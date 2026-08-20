import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_point.dart';
import '../../projective/proj_transform.dart';
import '../geo_object.dart';

/// [point] scaled about [center] by a fixed [ratio] — the homothety
/// (dilation) image `center + ratio · (point − center)`.
///
/// Defined whenever both parents are — a point coinciding with the center
/// maps to itself. The ratio is fixed for the object's lifetime, like
/// `RotatedPoint.angle`: negative lands on the far side of the center, 1
/// is the identity. Not an isometry, so it stays out of the whole-object
/// transform machinery (`TransformKind`) v1.
///
/// Migrated (Phase 108): [ProjTransform.homothety] on the parents'
/// projective views. Homotheties fix every point at infinity, so a parent
/// at infinity is its own image, marked as such: [projPoint] real,
/// [position] null.
class HomotheticPoint extends GeoPoint {
  HomotheticPoint({
    required super.id,
    required this.point,
    required this.center,
    required this.ratio,
    super.attributes,
  }) {
    if (!ratio.isFinite) {
      throw ArgumentError.value(ratio, 'ratio', 'must be finite');
    }
    recompute();
  }

  final GeoPoint point;
  final GeoPoint center;

  /// Scale factor of the dilation about [center].
  final double ratio;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point, center];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Euclidean only (Phase 125). A homothety of ratio other than +-1 is a *similarity*, and
    // Cayley-Klein geometries have none: similar-but-not-congruent
    // triangles exist exactly when the parallel postulate holds (Wallis).
    // So there is no transformation here to apply.
    if (!absolute.isEuclidean) {
      _point = null;
      return;
    }
    final p = point.projPoint;
    final c = center.projPoint;
    if (p == null || c == null) {
      _point = null;
      return;
    }
    final image = ProjTransform.homothety(c, ratio).apply(p);
    _point = image.isZero ? null : image.wPositive;
  }
}
