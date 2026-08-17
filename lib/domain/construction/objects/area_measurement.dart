import 'dart:math' as math;

import '../../math/polygon_math.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../geo_object.dart';
import 'arc.dart';
import 'sector.dart';

/// The live area of a polygon, circle, sector or arc, displayed as canvas
/// text at the subject's center of mass — the vertex average, the
/// circle's center, or the wedge / circular-segment centroid. A sector
/// measures its wedge (½r²θ), an arc the circular segment its chord cuts
/// off (½r²(θ − sin θ)) — never the whole parent circle, whose area only
/// a full-circle subject reports. Undefined while the subject is.
///
/// One kind serves both subjects, so [subject] is a plain [GeoObject]
/// with the allowed kinds enforced in the constructor (the
/// `PointOnObject.curve` precedent — an ill-typed save normalizes to
/// `FormatException` through the codec's ArgumentError handler). A
/// polygon's area is the absolute shoelace value, so a self-intersecting
/// loop reports its alternating region sum's magnitude (documented at
/// [polygonSignedArea]).
///
/// Migrated (Phase 112): circle subjects are read through their conic and
/// projected to center-and-radius form here — area is a chart quantity
/// (the metric boundary). A carrier that is not a real circle (degenerate
/// line pair, complex) leaves the measurement undefined; extents stay
/// affine metadata. Polygon subjects read [GeoPolygon.polygonVertices],
/// which is itself the vertex projection a migrated `Polygon` computes.
class AreaMeasurement extends GeoMeasurement {
  AreaMeasurement({
    required super.id,
    required this.subject,
    super.attributes,
  }) {
    if (subject is! GeoPolygon && subject is! GeoCircle) {
      throw ArgumentError(
        'AreaMeasurement requires a polygon or circle parent',
      );
    }
    recompute();
  }

  /// A [GeoPolygon] or [GeoCircle] (enforced in the constructor).
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
    // Euclidean-only (Phase 124). Area is an integral too, and diverges further: a
    // hyperbolic triangle's area is its angular *defect*, π minus the
    // angle sum, which shares no algebra with the shoelace formula.
    // Under a proper absolute this is undefined rather than wrong: a
    // number computed in the chart would silently be the Euclidean
    // answer to a question the document is not asking.
    if (!absolute.isEuclidean) {
      _value = null;
      _anchor = null;
      return;
    }
    _value = null;
    _anchor = null;
    switch (subject) {
      case GeoPolygon(:final polygonVertices?):
        _value = polygonSignedArea(polygonVertices).abs();
        _anchor =
            polygonVertices.reduce((sum, vertex) => sum + vertex) /
            polygonVertices.length.toDouble();
      // Sector and Arc are GeoCircles, so they must match before the
      // full-circle case. Both centroids sit on the extent's bisector at
      // a fraction of the radius; the guards are the θ → 0 limits of the
      // exact formulas, where numerator and denominator both vanish.
      case Sector(:final conic?, :final startAngle?, :final sweep?):
        final circle = conic.toCircleEq();
        if (circle == null) return;
        final r = circle.radius;
        _value = r * r * sweep / 2;
        // Wedge centroid: (4r/(3θ))·sin(θ/2) from the center; → 2r/3.
        final t = sweep < 1e-6 ? 2 / 3 : 4 * math.sin(sweep / 2) / (3 * sweep);
        _anchor = circle.center.lerp(circle.pointAt(startAngle + sweep / 2), t);
      case Arc(:final conic?, :final startAngle?, :final sweep?):
        final circle = conic.toCircleEq();
        if (circle == null) return;
        final r = circle.radius;
        final theta = sweep.abs();
        _value = r * r * (theta - math.sin(theta)) / 2;
        // Segment centroid: 4r·sin³(θ/2) / (3(θ − sin θ)) from the
        // center; → r (the rim) as the segment thins out.
        final lens = theta - math.sin(theta);
        final half = math.sin(theta / 2);
        final t = lens < 1e-9 ? 1.0 : 4 * half * half * half / (3 * lens);
        _anchor = circle.center.lerp(circle.pointAt(startAngle + sweep / 2), t);
      case GeoCircle(:final conic?):
        final circle = conic.toCircleEq();
        if (circle == null) return;
        _value = math.pi * circle.radius * circle.radius;
        _anchor = circle.center;
      default:
        break;
    }
  }
}
