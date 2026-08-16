import 'geo_object.dart';
import 'objects/angle_bisector_line.dart';
import 'objects/arc.dart';
import 'objects/circle_center_point.dart';
import 'objects/five_point_conic.dart';
import 'objects/intersection_point.dart';
import 'objects/line_through_two_points.dart';
import 'objects/midpoint.dart';
import 'objects/perpendicular_bisector_line.dart';
import 'objects/point_on_object.dart';
import 'objects/ray.dart';
import 'objects/relative_line.dart';
import 'objects/sector.dart';
import 'objects/segment.dart';
import 'objects/tangent_line.dart';
import 'objects/three_point_circle.dart';
import 'objects/two_line_bisector_line.dart';

/// Whether [point] lies on [curve] **by construction** — parent ties and
/// construction theorems only, never an epsilon test on current
/// positions. A point that merely coincides with the curve in the
/// current figure is deliberately not incident: incidence must survive
/// any drag.
///
/// Sources:
///
/// - a [PointOnObject] hosted on [curve];
/// - an [IntersectionPoint] with [curve] as either parent;
/// - a defining point of [curve] that sits on its carrier
///   ([onCarrierDefiningPoints]);
/// - the derived theorems of [_derivedIncident] (Phase 44b).
///
/// Shared by line clipping (`lineClipSpan` mode 2) and the intersection
/// tool's duplicate check (a point incident on both curves *is* their
/// intersection).
bool structurallyIncident(GeoObject curve, GeoPoint point) {
  if (point case PointOnObject(curve: final host)
      when identical(host, curve)) {
    return true;
  }
  if (point case IntersectionPoint(:final curve1, :final curve2)
      when identical(curve1, curve) || identical(curve2, curve)) {
    return true;
  }
  if (onCarrierDefiningPoints(curve).any((p) => identical(p, point))) {
    return true;
  }
  return _derivedIncident(curve, point);
}

/// The defining points of [curve] that lie on its carrier by
/// construction. Kinds whose defining geometry is elsewhere — the
/// perpendicular bisector's endpoints, a compass circle's radius pair, a
/// [Sector]'s direction-only `end` — and unknown future kinds contribute
/// none.
List<GeoPoint> onCarrierDefiningPoints(GeoObject curve) => switch (curve) {
      LineThroughTwoPoints() => [curve.point1, curve.point2],
      Segment() => [curve.point1, curve.point2],
      Ray() => [curve.origin, curve.through],
      // Perpendicular and parallel lines pass through their point.
      RelativeLine() => [curve.through],
      AngleBisectorLine() => [curve.vertex],
      // Both tangent branches pass through the external point.
      TangentLine() => [curve.point],
      CircleCenterPoint() => [curve.onCircle],
      ThreePointCircle() => [curve.point1, curve.point2, curve.point3],
      // Five points determine the conic, so all five are on it.
      FivePointConic() => curve.points,
      Arc() => [curve.start, curve.via, curve.end],
      // A sector's start pins its radius; its end fixes an angle only.
      Sector() => [curve.start],
      _ => const [],
    };

/// Derived structural incidences (Phase 44b): points provably on [curve]
/// by a construction theorem over parent ties — still zero epsilon.
///
/// - Every branch of a `TwoLineBisectorLine` passes through the crossing
///   of its two parent lines, so any point incident on *both* parents is
///   on it: distinct lines cross at most once (coincident parents leave
///   the bisector undefined), so such a point *is* the crossing. Covers
///   the `IntersectionPoint` of the pair and a defining point the
///   parents share — two segments hanging off one vertex.
/// - A `PerpendicularBisectorLine` passes through the midpoint of its
///   two parent points, so the `Midpoint` of exactly those points
///   (either order) is on it.
bool _derivedIncident(GeoObject curve, GeoPoint point) =>
    switch ((curve, point)) {
      (final TwoLineBisectorLine b, _) =>
        structurallyIncident(b.line1, point) &&
            structurallyIncident(b.line2, point),
      (final PerpendicularBisectorLine b, final Midpoint m) =>
        _samePair(m.point1, m.point2, b.point1, b.point2),
      _ => false,
    };

/// Whether {[a1], [a2]} and {[b1], [b2]} are the same instance pair,
/// order-blind.
bool _samePair(GeoObject a1, GeoObject a2, GeoObject b1, GeoObject b2) =>
    (identical(a1, b1) && identical(a2, b2)) ||
    (identical(a1, b2) && identical(a2, b1));
