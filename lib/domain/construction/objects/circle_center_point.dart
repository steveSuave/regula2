import '../../math/circle_eq.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The circle with a given center, passing through another point.
///
/// Defined whenever both parents are defined — coincident parents give a
/// zero-radius circle ([CircleEq] allows that) so the object survives a
/// drag through the degeneracy without flickering undefined.
///
/// Migrated (Phase 109): stores [circleThrough] of the parents'
/// projective views; [circle] is its projection. A rim at infinity now
/// yields the degenerate double line at infinity ([conic] non-null,
/// [circle] null — an "infinite radius" carrier); a center at infinity
/// has no circle at all ([conic] null).
class CircleCenterPoint extends GeoCircle {
  CircleCenterPoint({
    required super.id,
    required this.center,
    required this.onCircle,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint center;
  final GeoPoint onCircle;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [center, onCircle];

  @override
  void recompute() {
    final c = center.projPoint;
    final p = onCircle.projPoint;
    if (c == null || p == null) {
      _conic = null;
      _circle = null;
      return;
    }
    final k = circleThrough(c, p);
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
  }
}
