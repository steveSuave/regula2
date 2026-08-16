import '../../math/circle_eq.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/conic_shape.dart';
import '../../projective/conics.dart';
import '../geo_object.dart';

/// The conic with foci [focus1] and [focus2] through [point] — the
/// **ellipse** `|XF₁| + |XF₂| = |PF₁| + |PF₂|` when [difference] is false,
/// the **hyperbola** `‖XF₁| − |XF₂‖ = ‖PF₁| − |PF₂‖` when it is true.
///
/// One kind, one formula ([bifocalConicOf]), one branch flag — the same
/// shape as `TangentLine.branch` and `TwoLineBisectorLine.branch`. The
/// flag chooses a *definition* rather than a case in the algebra: the sum
/// branch always has `a ≥ c` and the difference branch `a ≤ c`, both by
/// the triangle inequality, so each always produces its own class.
///
/// **This kind reads the chart**, and is the only conic kind that does.
/// `|PF₁| ± |PF₂|` is a sum of square roots of distances with no
/// polynomial form in the homogeneous data, so the parents are projected
/// here and the metric is taken in the affine view — the sanctioned Phase
/// 112 metric boundary, and where M-CK re-founds this constructor (PLAN
/// §"The conic constructors, and where the metric enters"). A parent that
/// is complex or at infinity has no chart point and leaves the conic
/// undefined, exactly as it does for the measurement kinds.
///
/// [isDefined] is [ConicShape.isDrawable]. Degenerate results are total
/// and unbanded, and both are honest limits of the definition: [point] on
/// the segment `F₁F₂` (sum branch) doubles the major axis, and [point]
/// equidistant from the foci (difference branch) doubles the perpendicular
/// bisector — which *is* the set `|XF₁| = |XF₂|`. Both still draw, so both
/// stay defined. **Coincident foci** are the one guard (within
/// `projectiveEpsilon`, the `carrierThrough` convention): the branch has
/// no meaning there, and the circle through [point] is
/// `CircleCenterPoint`'s job rather than a limit for this kind to invent.
class BifocalConic extends GeoCircle {
  BifocalConic({
    required super.id,
    required this.focus1,
    required this.focus2,
    required this.point,
    required this.difference,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint focus1;
  final GeoPoint focus2;

  /// The point the conic is required to pass through, which fixes the
  /// semi-axis.
  final GeoPoint point;

  /// False for the ellipse (constant *sum* of focal distances), true for
  /// the hyperbola (constant *difference*).
  final bool difference;

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
  List<GeoObject> get parents => [focus1, focus2, point];

  @override
  void recompute() {
    final f1 = focus1.projPoint;
    final f2 = focus2.projPoint;
    final p = point.projPoint;
    if (f1 == null || f2 == null || p == null || f1.closeTo(f2)) {
      _conic = null;
      _circle = null;
      _drawable = false;
      return;
    }
    // The metric boundary: the semi-axis is a sum of square roots of
    // distances, so the parents are projected and measured in the chart.
    final a = f1.toVec2();
    final b = f2.toVec2();
    final through = p.toVec2();
    if (a == null || b == null || through == null) {
      _conic = null;
      _circle = null;
      _drawable = false;
      return;
    }
    final k = bifocalConicOf(a, b, through, difference: difference);
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
    _drawable = _conic != null && ConicShape.of(_conic!).isDrawable;
  }
}
