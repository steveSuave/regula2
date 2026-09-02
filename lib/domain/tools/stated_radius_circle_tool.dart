import '../construction/geo_object.dart';
import '../construction/objects/stated_radius_circle.dart';
import '../math/rational.dart';
import '../projective/absolute.dart';
import 'multi_point_tool.dart';

/// One tap makes a `StatedRadiusCircle`: the tap resolves to the centre
/// via the shared point ladder, and the exact [radius] comes from a
/// dialog before the tool activates (Phase 184, the app-facing half of
/// PLAN §"The constants stack").
///
/// The twin of `FixedRadiusCircleTool` with the value made exact: that
/// tool's circle draws the same curve from a float and states nothing a
/// proof could cite, this one's emits `lconst` for every named point on
/// it. Two tools rather than one with a flag because the two kinds are
/// different objects with different contracts, and the user is choosing
/// between "a circle this big" and "a circle whose radius *is* 5/2".
///
/// A dedicated class for the reason `FixedRadiusCircleTool` gives: the
/// toolbar keys its highlights and availability rows on tool identity.
class StatedRadiusCircleTool extends MultiPointTool {
  /// Throws [ArgumentError] on a non-positive radius — the object's own
  /// contract, checked when the tool is picked rather than on the tap.
  StatedRadiusCircleTool({required super.newId, required this.radius}) {
    if (radius.isZero || radius.isNegative) {
      throw ArgumentError.value(radius, 'radius', 'must be positive');
    }
  }

  /// Radius in world units, exact and fixed for the tool's lifetime.
  final Rational radius;

  @override
  int get pointCount => 1;

  /// Euclidean-only, like the circle: a stated length is a chart
  /// quantity, so a Cayley–Klein document refuses every input.
  @override
  bool availableUnder(Absolute absolute) => absolute.isEuclidean;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    StatedRadiusCircle(id: newId(), center: points[0], radius: radius),
  ];
}
