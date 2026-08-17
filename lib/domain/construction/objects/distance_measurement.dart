import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/ck_measure.dart';
import '../geo_object.dart';

/// The live distance between two points, displayed as canvas text at
/// their midpoint. Undefined while either point is (point–line distance
/// is deferred, per PLAN).
///
/// Reads the parents' projective views; where the value comes from then
/// depends on the geometry (Phase 124). Euclidean distance is *parabolic*
/// — the absolute degenerates and the cross-ratio that would define it is
/// identically 1 — so it is computed in the chart, which is the only
/// place it exists, not as an optimization. Hyperbolic and elliptic
/// distance are genuine projective invariants and come from
/// [distanceBetween]. A parent that is complex or at infinity leaves the
/// measurement undefined either way; the anchor stays a chart quantity,
/// because it is where the label is drawn rather than something measured.
class DistanceMeasurement extends GeoMeasurement {
  DistanceMeasurement({
    required super.id,
    required this.point1,
    required this.point2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  double? _value;
  Vec2? _anchor;

  @override
  double? get value => _value;

  @override
  Vec2? get anchor => _anchor;

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p1 = point1.projPoint?.toVec2();
    final p2 = point2.projPoint?.toVec2();
    if (p1 == null || p2 == null) {
      _value = null;
      _anchor = null;
      return;
    }
    // Euclidean distance is parabolic — not a cross-ratio, so the chart
    // is not a shortcut here but the only place it exists (PLAN §"Angle
    // unifies, distance does not"). A proper absolute measures
    // projectively instead, off the same parents' homogeneous values.
    _value = distanceKindOf(absolute) == MeasureKind.parabolic
        ? p1.distanceTo(p2)
        : distanceBetween(absolute, point1.projPoint!, point2.projPoint!);
    _anchor = p1.lerp(p2, 0.5);
  }
}
