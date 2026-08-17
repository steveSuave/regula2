import '../../math/circle_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/ck_circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The circle around [center] with a fixed numeric [radius].
///
/// The radius is given up front (dialog input) rather than by a point, and
/// is fixed for the object's lifetime like `RotatedPoint.angle` — so this
/// serves the circle-by-radius tool directly and doubles as the hidden
/// circle behind the segment-by-length macro. Defined iff the center
/// projects to a real finite point.
///
/// Migrated (Phase 109): stores [circleWithRadius] of the center's
/// projective view. [circle] pairs the projected center with the *stored*
/// [radius] rather than re-deriving it from the conic — recovering `r²`
/// from the entries costs an ulp against an arbitrary center, and the
/// radius is this object's own exact parameter.
class FixedRadiusCircle extends GeoCircle {
  FixedRadiusCircle({
    required super.id,
    required this.center,
    required this.radius,
    super.attributes,
  }) {
    if (radius.isNaN || radius.isInfinite || radius <= 0) {
      throw ArgumentError.value(
        radius,
        'radius',
        'must be a finite positive number',
      );
    }
    recompute();
  }

  final GeoPoint center;

  /// Radius in world units, fixed for the object's lifetime.
  final double radius;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [center];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final c = center.projPoint;
    if (c == null) {
      _conic = null;
      _circle = null;
      return;
    }
    // The stored radius is a *metric* quantity, so it changes meaning
    // with the geometry: the same number names a Euclidean radius, a
    // hyperbolic one (Klein radius tanh r) or an elliptic one. The
    // parameter is not reinterpreted on a geometry switch — that is part
    // of what Phase 126's re-addressing has to decide.
    final k = absolute.isEuclidean
        ? circleWithRadius(c, radius)
        : ckCircleWithRadius(absolute, c, radius);
    _conic = k.isZero ? null : k;
    final projected = _conic == null ? null : c.toVec2();
    _circle = projected == null ? null : CircleEq(projected, radius);
  }
}
