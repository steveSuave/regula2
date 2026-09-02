import '../construction/geo_object.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/scaled_compass_circle.dart';
import '../math/rational.dart';
import '../projective/absolute.dart';
import 'multi_point_tool.dart';

/// The compass tool with a stated scale: two span points, then the
/// centre — the compass tool's own order — and a `ScaledCompassCircle`
/// whose radius is [factor] times the span (Phase 184, the app-facing
/// half of PLAN §"The constants stack"). The factor comes from a dialog
/// before the tool activates.
///
/// At factor 1 the tool builds the plain `CompassCircle` instead: the
/// same curve, and its `cong` is the plainer statement, with rule
/// consumers a `rconst` of 1 does not have — the `_respelled`
/// precedence the corpus translator applies at the same value.
///
/// A dedicated class for the reason `FixedRadiusCircleTool` gives: the
/// toolbar keys its highlights and availability rows on tool identity.
class ScaledCompassCircleTool extends MultiPointTool {
  /// Throws [ArgumentError] on a non-positive factor — the object's own
  /// contract, checked when the tool is picked rather than on the tap.
  ScaledCompassCircleTool({required super.newId, required this.factor}) {
    if (factor.isZero || factor.isNegative) {
      throw ArgumentError.value(factor, 'factor', 'must be positive');
    }
  }

  /// The stated scale on the compassed distance, exact and fixed for the
  /// tool's lifetime.
  final Rational factor;

  @override
  int get pointCount => 3;

  /// Euclidean-only, like the circle it builds (the vocabulary's ratio
  /// facts are chart statements).
  @override
  bool availableUnder(Absolute absolute) => absolute.isEuclidean;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    if (factor == Rational.one)
      CompassCircle(
        id: newId(),
        radiusPoint1: points[0],
        radiusPoint2: points[1],
        center: points[2],
      )
    else
      ScaledCompassCircle(
        id: newId(),
        center: points[2],
        radiusPoint1: points[0],
        radiusPoint2: points[1],
        factor: factor,
      ),
  ];
}
