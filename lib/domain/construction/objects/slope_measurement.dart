import '../../math/vec2.dart';
import '../geo_object.dart';

/// The live slope of a line-valued object — the carrier's rise over run
/// (`direction.y / direction.x`), GeoGebra's Slope — displayed as canvas
/// text on the subject: a segment's midpoint, a ray's origin, or the
/// carrier point closest to the world origin for infinite lines (the
/// `labelAnchor` conventions, derived here from [GeoLine.parameterExtent]
/// so the domain stays presentation-free). Slope is direction-sign
/// invariant, so the carrier's canonical orientation never shows.
/// Undefined for vertical lines (run is zero) and while the subject is.
/// Chiefly a quick parallelism check: equal slopes, parallel lines.
///
/// [subject] is a plain [GeoObject] with the allowed kind enforced in the
/// constructor — the `AreaMeasurement.subject` precedent, so an ill-typed
/// save normalizes to `FormatException` through the codec's ArgumentError
/// handler.
class SlopeMeasurement extends GeoMeasurement {
  SlopeMeasurement({
    required super.id,
    required this.subject,
    super.attributes,
  }) {
    if (subject is! GeoLine) {
      throw ArgumentError(
        'SlopeMeasurement requires a line, segment or ray parent',
      );
    }
    recompute();
  }

  /// A [GeoLine] — infinite line, `Segment`, `Ray` or any derived line
  /// (enforced in the constructor).
  final GeoObject subject;

  double? _value;
  Vec2? _anchor;

  @override
  double? get value => _value;

  @override
  Vec2? get anchor => _anchor;

  @override
  List<GeoObject> get parents => [subject];

  @override
  void recompute() {
    final carrier = subject as GeoLine;
    final line = carrier.line;
    if (line == null || line.direction.x == 0) {
      _value = null;
      _anchor = null;
      return;
    }
    _value = line.direction.y / line.direction.x;
    _anchor = switch (carrier.parameterExtent) {
      (final double min, final double max) => line.pointAt((min + max) / 2),
      (final double min, null) => line.pointAt(min),
      (null, final double max) => line.pointAt(max),
      _ => line.pointOnLine,
    };
  }
}
