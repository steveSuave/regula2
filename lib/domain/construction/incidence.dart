import 'geo_object.dart';
import 'objects/angle_bisector_line.dart';
import 'objects/arc.dart';
import 'objects/bifocal_conic.dart';
import 'objects/circle_center_point.dart';
import 'objects/diameter_circle.dart';
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
  if (point case PointOnObject(curve: final host) when identical(host, curve)) {
    return true;
  }
  if (point case IntersectionPoint(
    :final curve1,
    :final curve2,
  ) when identical(curve1, curve) || identical(curve2, curve)) {
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
  // Both ends of the diameter are on the circle it spans — the same
  // fact as `ThreePointCircle`'s, and missing from this switch until
  // Phase 136b's box was worked. A compass circle's radius pair is not
  // here for the opposite reason: it fixes a length somewhere else.
  DiameterCircle() => [curve.point1, curve.point2],
  ThreePointCircle() => [curve.point1, curve.point2, curve.point3],
  // Five points determine the conic, so all five are on it.
  FivePointConic() => curve.points,
  // A bifocal conic passes through the point that fixed its semi-axis
  // — but not through its foci, which are off the curve entirely.
  BifocalConic() => [curve.point],
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
      (final PerpendicularBisectorLine b, final Midpoint m) => _samePair(
        m.point1,
        m.point2,
        b.point1,
        b.point2,
      ),
      _ => false,
    };

/// Whether [a] and [b] are one line **by construction** — the same
/// carrier under two objects, decided from parent ties alone and never
/// from current positions, for the reason [structurallyIncident] gives:
/// the answer must survive any drag.
///
/// Where it is true:
///
/// - the same object;
/// - two-point kinds ([LineThroughTwoPoints], [Segment], [Ray]) over the
///   same two points in either order — a segment, the line through its
///   ends and a ray along it all draw one carrier;
/// - two [TangentLine]s from one point to one circle on the same
///   branch, or on either branch when the point is *on* the circle,
///   where both branches collapse to the tangent at that point (Phase
///   164 — `tangent-chord.rgl` holds exactly that pair);
/// - two [RelativeLine]s of one kind through one point whose references
///   coincide;
/// - two [AngleBisectorLine]s of one vertex over the same pair of arms.
///
/// Any other pair is not known to coincide, which is the safe answer: a
/// line that merely lies on another in the current figure is not it.
///
/// This is what lets the prover's readers treat which *object* names a
/// line as their business rather than the click's: a point the
/// construction puts on `d` is on `c` when `c` and `d` are one line.
bool coincidentCarriers(GeoLine a, GeoLine b) {
  if (identical(a, b)) return true;
  final ends = (_twoPointEnds(a), _twoPointEnds(b));
  if (ends case ((final p1, final p2)?, (final q1, final q2)?)) {
    return _samePair(p1, p2, q1, q2);
  }
  return switch ((a, b)) {
    (final TangentLine x, final TangentLine y) =>
      identical(x.point, y.point) &&
          identical(x.circle, y.circle) &&
          (x.branch == y.branch || structurallyIncident(x.circle, x.point)),
    (final RelativeLine x, final RelativeLine y) =>
      x.runtimeType == y.runtimeType &&
          identical(x.through, y.through) &&
          coincidentCarriers(x.reference, y.reference),
    (final AngleBisectorLine x, final AngleBisectorLine y) =>
      identical(x.vertex, y.vertex) &&
          _samePair(x.arm1, x.arm2, y.arm1, y.arm2),
    _ => false,
  };
}

/// The points the construction puts on [carrier] — on it directly
/// ([structurallyIncident]) or on any line in [objects] that
/// [coincidentCarriers] says is the same line — in [objects]' order.
///
/// The prover's readers go through this rather than
/// [structurallyIncident] alone so that a figure holding one line twice
/// reads the same whichever copy is named (Phase 164).
List<GeoPoint> pointsOnCarrier(Iterable<GeoObject> objects, GeoObject carrier) {
  final all = objects is List<GeoObject> ? objects : objects.toList();
  final twins = [
    if (carrier is GeoLine)
      for (final object in all)
        if (object is GeoLine &&
            !identical(object, carrier) &&
            coincidentCarriers(object, carrier))
          object,
  ];
  return [
    for (final object in all)
      if (object is GeoPoint &&
          (structurallyIncident(carrier, object) ||
              twins.any((twin) => structurallyIncident(twin, object))))
        object,
  ];
}

/// The two points a two-point line kind is drawn through, or null for
/// any other kind.
(GeoPoint, GeoPoint)? _twoPointEnds(GeoLine line) => switch (line) {
  LineThroughTwoPoints() => (line.point1, line.point2),
  Segment() => (line.point1, line.point2),
  Ray() => (line.origin, line.through),
  _ => null,
};

/// Whether {[a1], [a2]} and {[b1], [b2]} are the same instance pair,
/// order-blind.
bool _samePair(GeoObject a1, GeoObject a2, GeoObject b1, GeoObject b2) =>
    (identical(a1, b1) && identical(a2, b2)) ||
    (identical(a1, b2) && identical(a2, b1));

/// The points the construction puts on **both** [curve1] and [curve2] —
/// the crossings that are known before any arithmetic is done (Phase
/// 135).
///
/// This is what makes deflation possible. `IntersectionPoint` addresses
/// its roots by their place in a *geometric* canonical order, and a
/// geometric order exchanges two roots wherever they coincide — so a
/// point holding "the second crossing" silently becomes a point holding
/// the first one as soon as the figure moves through a tangency. A
/// crossing named here is immune to that: it is the same crossing at
/// every parameter value, by construction, so the roots left over after
/// it is divided out are too.
///
/// The order is deterministic and depends only on the construction —
/// [curve1]'s defining points in their declared order, then [curve2]'s
/// that were not already named — which is what lets a caller address one
/// of these by position and keep meaning the same crossing across
/// recomputes, loads and drags. Deduplicated by identity.
///
/// Only *defining* points are considered, so a shared crossing that
/// neither curve was built from — an `IntersectionPoint` of exactly this
/// pair, say — is not found. That is a missed optimization, never a
/// wrong answer.
List<GeoPoint> sharedIncidentPoints(GeoObject curve1, GeoObject curve2) {
  final shared = <GeoPoint>[];
  void consider(GeoObject curve, GeoObject other) {
    for (final point in onCarrierDefiningPoints(curve)) {
      if (!structurallyIncident(other, point)) continue;
      if (shared.any((q) => identical(q, point))) continue;
      shared.add(point);
    }
  }

  consider(curve1, curve2);
  consider(curve2, curve1);
  return shared;
}
