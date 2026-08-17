import '../../math/circle_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/ck_circles.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/metric.dart';
import '../geo_object.dart';

/// The circle with the span from [point1] to [point2] as a diameter:
/// centered at their midpoint, radius half their distance — the Thales
/// circle over the two points.
///
/// Defined whenever both parents are defined — coincident parents give a
/// zero-radius circle ([CircleEq] allows that) so the object survives a
/// drag through the degeneracy without flickering undefined.
///
/// Migrated (Phase 109): stores [diameterCircleOf] of the parents'
/// projective views; [circle] is its projection. An endpoint at infinity
/// now yields the degenerate line pair of the perpendicular through the
/// finite endpoint with the line at infinity — the Thales limit shape
/// ([conic] non-null, [circle] null).
class DiameterCircle extends GeoCircle {
  DiameterCircle({
    required super.id,
    required this.point1,
    required this.point2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final a = point1.projPoint;
    final b = point2.projPoint;
    if (a == null || b == null) {
      _conic = null;
      _circle = null;
      return;
    }
    // Centre at the midpoint, through an end — which is what the
    // Euclidean bilinear form computes too, and which generalizes because
    // both halves already do.
    final k = absolute.isEuclidean
        ? diameterCircleOf(a, b)
        : ckCircleThrough(absolute, midpointOf(a, b, absolute), a);
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
  }
}
