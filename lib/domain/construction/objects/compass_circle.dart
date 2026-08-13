import '../../math/circle_eq.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The compass construction: a circle around [center] whose radius is
/// the distance between two other points.
///
/// Defined whenever all parents are — coincident radius points give a
/// zero-radius circle ([CircleEq] allows that), matching
/// `CircleCenterPoint`'s behaviour through degeneracy.
///
/// Migrated (Phase 109): stores [compassCircleOf] of the parents'
/// projective views; [circle] is its projection. A radius point at
/// infinity now yields the degenerate double line at infinity ([conic]
/// non-null, [circle] null); a center at infinity has no circle-shaped
/// projection either.
class CompassCircle extends GeoCircle {
  CompassCircle({
    required super.id,
    required this.radiusPoint1,
    required this.radiusPoint2,
    required this.center,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint radiusPoint1;
  final GeoPoint radiusPoint2;
  final GeoPoint center;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [radiusPoint1, radiusPoint2, center];

  @override
  void recompute() {
    final r1 = radiusPoint1.projPoint;
    final r2 = radiusPoint2.projPoint;
    final c = center.projPoint;
    if (r1 == null || r2 == null || c == null) {
      _conic = null;
      _circle = null;
      return;
    }
    final k = compassCircleOf(c, r1, r2);
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
  }
}
