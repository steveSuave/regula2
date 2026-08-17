import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/metric.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The point dividing the directed span from [point1] to [point2] at a
/// fixed [ratio]: `position = point1 + ratio · (point2 − point1)`.
///
/// `ratio` 0 is [point1], 1 is [point2], 0.5 the midpoint; values outside
/// [0, 1] extrapolate beyond the endpoints, which is deliberate (the
/// classic "extend AB by its own length" construction is `ratio` 2).
/// Defined whenever both parents are — coincident parents just give the
/// shared position.
///
/// Migrated (Phase 108): [lerpOf] on the parents' projective views. A
/// parent at infinity yields that point at infinity (the affine limit)
/// whenever its interpolation weight is nonzero, marked as such:
/// [projPoint] real, [position] null.
class SegmentRatioPoint extends GeoPoint {
  SegmentRatioPoint({
    required super.id,
    required this.point1,
    required this.point2,
    required this.ratio,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  /// Interpolation parameter along point1 → point2. Fixed for the
  /// object's lifetime, like `PointOnObject.parameter`.
  final double ratio;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Euclidean only (Phase 125). A ratio along a segment is affine — it divides in the ratio the
    // affine chart reads. The CK analogue divides a *distance*, which is a
    // logarithm of a cross-ratio, so the point is not an interpolation.
    if (!absolute.isEuclidean) {
      _point = null;
      return;
    }
    final p1 = point1.projPoint;
    final p2 = point2.projPoint;
    if (p1 == null || p2 == null) {
      _point = null;
      return;
    }
    final r = lerpOf(p1, p2, ratio);
    _point = r.isZero ? null : r;
  }
}
