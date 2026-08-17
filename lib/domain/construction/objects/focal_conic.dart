import '../../math/circle_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/conic_shape.dart';
import '../../projective/conics.dart';
import '../geo_object.dart';

/// The conic of points whose distance to a [focus] is [eccentricity] times
/// their distance to a [directrix] — a **parabola** at `e = 1`, an ellipse
/// below it, a hyperbola above.
///
/// One kind covers all three, because one formula does ([focalConicOf]):
/// the eccentricity is a stored parameter, not a change of construction,
/// so the parabola tool is this kind at `e = 1` and there is no separate
/// parabola kind to keep in step. The object-tree label reads the stored
/// value back, so a parabola still calls itself one.
///
/// Metric, but polynomial (PLAN §"The conic constructors, and where the
/// metric enters"): the whole Euclidean content is the single coefficient
/// `a² + b²`, so this kind reads its parents' projective accessors and
/// never touches the chart.
///
/// [isDefined] is [ConicShape.isDrawable] — a degenerate result is still
/// defined when it draws (the isotropic-directrix line pair), undefined
/// when it does not (`e = 0`, which is the focus as an isolated point:
/// real, but no curve). Undefined parents, or a zero result, are
/// undefined; every other degeneracy is total and unbanded, per the
/// standing Phase 110 rule.
class FocalConic extends GeoCircle {
  FocalConic({
    required super.id,
    required this.focus,
    required this.directrix,
    required this.eccentricity,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint focus;
  final GeoLine directrix;

  /// The ratio `|XF| / d(X, ℓ)` the conic holds — `1` for a parabola.
  ///
  /// Negative values are the same conic as their absolute value (only
  /// `e²` enters the formula); the tools never produce one.
  final double eccentricity;

  ConicMatrix? _conic;
  CircleEq? _circle;
  bool _drawable = false;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  bool get isDefined => _drawable;

  @override
  List<GeoObject> get parents => [focus, directrix];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final f = focus.projPoint;
    final l = directrix.projLine;
    if (f == null || l == null) {
      _conic = null;
      _circle = null;
      _drawable = false;
      return;
    }
    final k = focalConicOf(f, l, Complex(eccentricity));
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
    _drawable = _conic != null && ConicShape.of(_conic!).isDrawable;
  }
}
