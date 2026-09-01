import '../../math/circle_eq.dart';
import '../../math/rational.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The circle around [center] whose radius is a *stated* exact rational
/// — the constants stack's fixed-radius tie (PLAN §"The constants
/// stack"). A point on it satisfies `lconst(p, center; radius)` by
/// construction, which is what `hypotheses()` emits and what separates
/// this kind from [FixedRadiusCircle]: that one's float parameter draws
/// the same curve but cannot honestly *state* the value a proof would
/// cite, so it stays in the "contributes nothing" list.
///
/// Euclidean-only, like the prover vocabulary it exists to feed: a
/// stated length is a chart quantity (the vocabulary's one
/// non-scale-invariant statement), so a proper absolute leaves the
/// circle undefined — the `SegmentRatioPoint` arrangement — rather than
/// reinterpreting the number in another measure.
class StatedRadiusCircle extends GeoCircle {
  /// Throws [ArgumentError] on a non-positive radius, the
  /// `FixedRadiusCircle` contract with exactness added.
  StatedRadiusCircle({
    required super.id,
    required this.center,
    required this.radius,
    super.attributes,
  }) {
    if (radius.isZero || radius.isNegative) {
      throw ArgumentError.value(radius, 'radius', 'must be positive');
    }
    recompute();
  }

  final GeoPoint center;

  /// Radius in world units, exact and fixed for the object's lifetime.
  final Rational radius;

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
    final c = absolute.isEuclidean ? center.projPoint : null;
    if (c == null) {
      _conic = null;
      _circle = null;
      return;
    }
    final r = radius.toDouble();
    final k = circleWithRadius(c, r);
    _conic = k.isZero ? null : k;
    final projected = _conic == null ? null : c.toVec2();
    _circle = projected == null ? null : CircleEq(projected, r);
  }
}
