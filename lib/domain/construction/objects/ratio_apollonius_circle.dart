import '../../math/circle_eq.dart';
import '../../math/rational.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/complex.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The Apollonius circle over [point1] (A) and [point2] (B) with a
/// *stated* rational distance ratio: the locus of points P with
/// `|PA| / |PB| = ratio` — the constants stack's two-anchor scaled tie
/// (PLAN §"The constants stack"). A point `p` on it satisfies
/// `rconst(p, point1, p, point2; ratio)` by construction, which is what
/// `hypotheses()` emits; [ApolloniusCircle] draws the same family with
/// the ratio supplied by a third point, which states `eqratio`, not a
/// constant.
///
/// The ratio is strictly not 1: at 1 the locus is the perpendicular
/// bisector, a line and a different kind — producers build
/// `PerpendicularBisectorLine` there, whose `cong` is the plainer
/// statement (the `_respelled` precedence). Refusing 1 up front is what
/// keeps this a circle *by construction*, so `hypotheses()` may treat
/// it as one unconditionally.
///
/// Euclidean-only, the [ApolloniusCircle] restriction for the same
/// reason (a ratio of CK distances is not a conic); undefined while a
/// parent is undefined or at infinity, or the anchors coincide — no
/// point has two distances to one place in a stated ratio ≠ 1.
class RatioApolloniusCircle extends GeoCircle {
  /// Throws [ArgumentError] on a non-positive ratio or on exactly 1.
  RatioApolloniusCircle({
    required super.id,
    required this.point1,
    required this.point2,
    required this.ratio,
    super.attributes,
  }) {
    if (ratio.isZero || ratio.isNegative) {
      throw ArgumentError.value(ratio, 'ratio', 'must be positive');
    }
    if (ratio == Rational.one) {
      throw ArgumentError.value(
        ratio,
        'ratio',
        'at 1 the locus is the perpendicular bisector — build that kind',
      );
    }
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  /// The stated distance ratio `|PA| / |PB|`, exact and fixed for the
  /// object's lifetime.
  final Rational ratio;

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
    final a = absolute.isEuclidean ? point1.projPoint?.toVec2() : null;
    final b = point2.projPoint?.toVec2();
    if (a == null || b == null || a == b) {
      _conic = null;
      _circle = null;
      return;
    }
    // |PA| = k·|PB| squares to the circle with centre
    // (a − k²·b) / (1 − k²) and radius k·|ab| / |1 − k²| — the classic
    // form, real for every k ≠ 1.
    final k2 = ratio.toDouble() * ratio.toDouble();
    final w = 1 / (1 - k2);
    final centre = (a - b * k2) * w;
    final r = ratio.toDouble() * a.distanceTo(b) * w.abs();
    final k = circleWithRadius(
      ProjPoint(Complex(centre.x), Complex(centre.y), Complex.one),
      r,
    );
    _conic = k.isZero ? null : k;
    _circle = _conic == null ? null : CircleEq(centre, r);
  }
}
