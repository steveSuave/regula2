import '../../math/circle_eq.dart';
import '../../math/rational.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The compass construction with a *stated* rational scale: the circle
/// around [center] whose radius is [factor] times the distance from
/// [radiusPoint1] to [radiusPoint2] — the constants stack's scaled tie
/// (PLAN §"The constants stack"). A point `p` on it satisfies
/// `rconst(p, center, radiusPoint1, radiusPoint2; factor)` by
/// construction, which is what `hypotheses()` emits. At factor 1 the
/// curve is [CompassCircle]'s, whose `cong` is the plainer statement —
/// producers should build that kind instead, the `_respelled`
/// precedence one level up; this class does not forbid 1 because the
/// curve is still honest there.
///
/// Euclidean-only, like the prover vocabulary it exists to feed
/// (the `SegmentRatioPoint` arrangement); undefined too while a parent
/// is, or a radius point sits at infinity — a scaled distance to an
/// ideal point is no length. Coincident radius points give the
/// zero-radius circle, matching [CompassCircle].
class ScaledCompassCircle extends GeoCircle {
  /// Throws [ArgumentError] on a non-positive factor: a stated ratio is
  /// positive, the `Predicate` contract.
  ScaledCompassCircle({
    required super.id,
    required this.center,
    required this.radiusPoint1,
    required this.radiusPoint2,
    required this.factor,
    super.attributes,
  }) {
    if (factor.isZero || factor.isNegative) {
      throw ArgumentError.value(factor, 'factor', 'must be positive');
    }
    recompute();
  }

  final GeoPoint center;
  final GeoPoint radiusPoint1;
  final GeoPoint radiusPoint2;

  /// The stated scale on the compassed distance, exact and fixed for
  /// the object's lifetime.
  final Rational factor;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [center, radiusPoint1, radiusPoint2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final c = absolute.isEuclidean ? center.projPoint : null;
    final p = radiusPoint1.projPoint?.toVec2();
    final q = radiusPoint2.projPoint?.toVec2();
    if (c == null || p == null || q == null) {
      _conic = null;
      _circle = null;
      return;
    }
    final r = factor.toDouble() * p.distanceTo(q);
    final k = circleWithRadius(c, r);
    _conic = k.isZero ? null : k;
    final projected = _conic == null ? null : c.toVec2();
    _circle = projected == null ? null : CircleEq(projected, r);
  }
}
