import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/metric.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The midpoint of two points.
///
/// Defined whenever both parents are defined — coincident parents just
/// give the shared position.
///
/// Migrated (Phase 107): [midpointOf] on the parents' projective views.
/// A parent at infinity yields that point at infinity (the affine limit),
/// marked as such: [projPoint] real, [position] null.
class Midpoint extends GeoPoint {
  Midpoint({
    required super.id,
    required this.point1,
    required this.point2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p1 = point1.projPoint;
    final p2 = point2.projPoint;
    if (p1 == null || p2 == null) {
      _point = null;
      return;
    }
    final m = midpointOf(p1, p2, absolute);
    _point = m.isZero ? null : m.wPositive;
  }
}
