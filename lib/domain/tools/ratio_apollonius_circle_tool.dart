import '../construction/geo_object.dart';
import '../construction/objects/perpendicular_bisector_line.dart';
import '../construction/objects/ratio_apollonius_circle.dart';
import '../math/rational.dart';
import '../projective/absolute.dart';
import 'multi_point_tool.dart';

/// Two taps, A then B, make the `RatioApolloniusCircle` of points P with
/// `|PA| / |PB|` equal to the stated [ratio] (Phase 184, the app-facing
/// half of PLAN §"The constants stack"). The ratio comes from a dialog
/// before the tool activates; the three-point Apollonius tool stays the
/// way to state the ratio with a point instead of a number.
///
/// At ratio 1 the locus is the perpendicular bisector of AB, a line and
/// a different kind, so the tool builds `PerpendicularBisectorLine`
/// there — the circle kind refuses 1 outright, and the bisector's `cong`
/// is the plainer statement (the `_respelled` precedence the corpus
/// translator applies at the same value).
///
/// A dedicated class for the reason `FixedRadiusCircleTool` gives: the
/// toolbar keys its highlights and availability rows on tool identity.
class RatioApolloniusCircleTool extends MultiPointTool {
  /// Throws [ArgumentError] on a non-positive ratio — the object's own
  /// contract, checked when the tool is picked rather than on the tap.
  RatioApolloniusCircleTool({required super.newId, required this.ratio}) {
    if (ratio.isZero || ratio.isNegative) {
      throw ArgumentError.value(ratio, 'ratio', 'must be positive');
    }
  }

  /// The stated distance ratio `|PA| / |PB|`, exact and fixed for the
  /// tool's lifetime.
  final Rational ratio;

  @override
  int get pointCount => 2;

  /// Euclidean-only, like the circle it builds (a ratio of Cayley–Klein
  /// distances is not a conic).
  @override
  bool availableUnder(Absolute absolute) => absolute.isEuclidean;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    if (ratio == Rational.one)
      PerpendicularBisectorLine(
        id: newId(),
        point1: points[0],
        point2: points[1],
      )
    else
      RatioApolloniusCircle(
        id: newId(),
        point1: points[0],
        point2: points[1],
        ratio: ratio,
      ),
  ];
}
