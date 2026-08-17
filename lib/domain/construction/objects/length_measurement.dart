import 'dart:math' as math;

import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../geo_object.dart';
import 'sector.dart';

/// The live length of a circular curve, displayed as canvas text on its
/// rim. What "length" means follows the subject's shape: a full circle is
/// a closed curve, so its circumference (2πr, anchored at the top); an
/// arc is an open curve, so its arc length (r·sweep, anchored at the
/// arc's midpoint); a sector is a closed region, so its full perimeter
/// (2r + r·sweep — both radii included; anchored at the rim midpoint).
/// Undefined while the subject is.
///
/// [subject] is a plain [GeoObject] with the allowed kind enforced in the
/// constructor — the `AreaMeasurement.subject` precedent, so an ill-typed
/// save normalizes to `FormatException` through the codec's ArgumentError
/// handler.
///
/// Migrated (Phase 112): reads the subject's conic and projects it to
/// center-and-radius form itself — circumference and arc length are chart
/// quantities (the metric boundary). A carrier that is not a real circle
/// (degenerate line pair, complex) leaves the measurement undefined; the
/// angular extent stays affine metadata per PLAN §Parameterization.
class LengthMeasurement extends GeoMeasurement {
  LengthMeasurement({
    required super.id,
    required this.subject,
    super.attributes,
  }) {
    if (subject is! GeoCircle) {
      throw ArgumentError(
        'LengthMeasurement requires a circle, arc or sector parent',
      );
    }
    recompute();
  }

  /// A [GeoCircle] — full circle, `Arc` or `Sector` (enforced in the
  /// constructor).
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
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Euclidean-only (Phase 124). Arc length is an *integral* of distance, not a substitution:
    // a hyperbolic circle of radius r has circumference 2π·sinh r, and no
    // re-founding of the endpoint formula produces that.
    // Under a proper absolute this is undefined rather than wrong: a
    // number computed in the chart would silently be the Euclidean
    // answer to a question the document is not asking.
    if (!absolute.isEuclidean) {
      _value = null;
      _anchor = null;
      return;
    }
    final curve = subject as GeoCircle;
    final circle = curve.conic?.toCircleEq();
    if (circle == null) {
      _value = null;
      _anchor = null;
      return;
    }
    final extent = curve.angularExtent;
    if (extent == null) {
      _value = 2 * math.pi * circle.radius;
      _anchor = circle.pointAt(math.pi / 2);
      return;
    }
    final (start, sweep) = extent;
    final arcLength = circle.radius * sweep;
    _value = subject is Sector ? 2 * circle.radius + arcLength : arcLength;
    _anchor = circle.pointAt(start + sweep / 2);
  }
}
