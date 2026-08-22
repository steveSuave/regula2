import '../construction/geo_object.dart';
import '../construction/incidence.dart';
import '../construction/objects/angle_bisector_line.dart';
import '../construction/objects/bifocal_conic.dart';
import '../construction/objects/central_reflection_point.dart';
import '../construction/objects/circle_center.dart';
import '../construction/objects/circle_center_point.dart';
import '../construction/objects/circumcenter.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/diameter_circle.dart';
import '../construction/objects/five_point_conic.dart';
import '../construction/objects/fixed_radius_circle.dart';
import '../construction/objects/focal_conic.dart';
import '../construction/objects/harmonic_conjugate_point.dart';
import '../construction/objects/homothetic_point.dart';
import '../construction/objects/incenter.dart';
import '../construction/objects/midpoint.dart';
import '../construction/objects/orthocenter.dart';
import '../construction/objects/parallel_line.dart';
import '../construction/objects/perpendicular_bisector_line.dart';
import '../construction/objects/perpendicular_line.dart';
import '../construction/objects/projection_point.dart';
import '../construction/objects/reflected_point.dart';
import '../construction/objects/rotated_point.dart';
import '../construction/objects/sector.dart';
import '../construction/objects/segment_ratio_point.dart';
import '../construction/objects/tangent_line.dart';
import '../construction/objects/translated_point.dart';
import '../construction/objects/two_line_bisector_line.dart';
import '../projective/absolute.dart';
import 'predicate.dart';

/// Reads the DD hypotheses off a construction (PLAN §M-P2b): every
/// predicate the construction *guarantees* by its parent ties, never by
/// the current positions — the same discipline as `incidence.dart`, which
/// is what the incidence-shaped hypotheses are read through. A statement
/// that merely happens to be true in the figure is the `DiagramFilter`'s
/// business to reject as an accident, not this function's to assert.
///
/// The vocabulary is point-tuples, so a fact about a *line* needs point
/// witnesses: `para` between a `ParallelLine` and its reference is
/// expressible only through pairs of points structurally on each carrier,
/// and a carrier with fewer than two known points contributes nothing —
/// honest, since DD could do nothing with an unnamed line anyway. Where
/// several witness pairs exist, every combination is emitted: the DD core
/// has no coll-propagation rules to reconstruct a missing spelling, and
/// the fact database's canonical keying collapses the redundancy at
/// insert. The counts are combinatorial in points-per-carrier, which is
/// small in real documents.
///
/// **Euclidean only, refused rather than approximated** — the
/// `DiagramFilter` argument verbatim, one boundary earlier: under a
/// proper absolute a `PerpendicularLine` is CK-perpendicular, and
/// emitting the chart's `perp` about it would assert a falsehood every
/// deduction downstream inherits. A CK prover re-founds the vocabulary;
/// until then a non-Euclidean [absolute] throws.
///
/// Emissions are deterministic in the objects' iteration order, so a run
/// — and the proof it prints — is reproducible. Degenerate instances
/// (a reflection with its point on the mirror, an orthocenter on a
/// vertex) are emitted anyway and left to the filter: degeneracy is a
/// property of the *configuration*, which is exactly what the filter
/// samples and this function must not read.
///
/// Kinds with no pointwise statement contribute nothing, deliberately:
/// `Centroid` (its medians need the side midpoints, which the diagram may
/// not name), `FixedRadiusCircle`'s numeric radius, `HomotheticPoint` and
/// `SegmentRatioPoint` beyond collinearity (their ratios are params, not
/// points — except the exact-half `SegmentRatioPoint`, which is `midp`),
/// the conic-valued kinds (`FivePointConic`, `BifocalConic`,
/// `FocalConic` — `cyclic` is about circles), and every measurement.
///
/// Two silences are conditional rather than per-kind, and are worth
/// separating from that list: a `TangentLine` whose touch point the
/// figure has not named says nothing (there is no point to be
/// perpendicular *at* — naming one is Phase 153's search, not this
/// function's guess), and a tangent to a conic that is not a circle by
/// construction says nothing at any time, because the radius theorem is
/// about circles.
List<Predicate> hypotheses(
  Iterable<GeoObject> objects, {
  Absolute absolute = Absolute.euclidean,
}) {
  if (!absolute.isEuclidean) {
    throw ArgumentError.value(
      absolute,
      'absolute',
      'the predicate vocabulary is Euclidean; a proper absolute needs '
          'the CK re-founding, not this extraction',
    );
  }
  final all = List.of(objects);
  final points = [
    for (final object in all)
      if (object is GeoPoint) object,
  ];
  final out = <Predicate>[];
  void emit(PredicateKind kind, List<GeoPoint> args) =>
      out.add(Predicate(kind, args));

  // The points the construction puts on a carrier, in insertion order.
  List<GeoPoint> onCurve(GeoObject curve) => [
    for (final point in points)
      if (structurallyIncident(curve, point)) point,
  ];
  List<List<GeoPoint>> pairsOn(GeoObject curve) => _choose(onCurve(curve), 2);

  // The circle's centre as a *named* point: the one its kind stores, or
  // a `CircleCenter` the user drew on it. Tangency is a statement about
  // the radius, so without a name for the centre there is nothing to
  // say — a `ThreePointCircle` has no structural centre and is exactly
  // the case this second half exists for.
  GeoPoint? centreOf(GeoCircle circle) {
    final structural = _structuralCenter(circle);
    if (structural != null) return structural;
    for (final object in all) {
      if (object is CircleCenter && identical(object.circle, circle)) {
        return object;
      }
    }
    return null;
  }

  for (final object in all) {
    // Incidence-shaped statements, for every carrier at once: points a
    // line kind puts on one line are collinear, points a circle kind
    // puts on one circle are concyclic. Per-kind statements follow.
    switch (object) {
      case GeoLine():
        for (final triple in _choose(onCurve(object), 3)) {
          emit(PredicateKind.coll, triple);
        }
      case GeoCircle() when _isCircleByConstruction(object):
        for (final quad in _choose(onCurve(object), 4)) {
          emit(PredicateKind.cyclic, quad);
        }
        final center = _structuralCenter(object);
        if (center != null) {
          for (final pair in pairsOn(object)) {
            emit(PredicateKind.cong, [center, pair[0], center, pair[1]]);
          }
        }
      default:
        break;
    }
    switch (object) {
      case final Midpoint m:
        emit(PredicateKind.midp, [m, m.point1, m.point2]);
      case final SegmentRatioPoint r:
        emit(PredicateKind.coll, [r, r.point1, r.point2]);
        if (r.ratio == 0.5) {
          emit(PredicateKind.midp, [r, r.point1, r.point2]);
        }
      case final HomotheticPoint h:
        emit(PredicateKind.coll, [h, h.center, h.point]);
      case final HarmonicConjugatePoint d:
        emit(PredicateKind.coll, [d, d.point1, d.point2]);
        // (A,B;C,D) = −1: |AC|/|CB| = |AD|/|DB|, unsigned.
        emit(PredicateKind.eqratio, [
          d.point1, d.point3, d.point3, d.point2, // |AC| / |CB|
          d.point1, d, d, d.point2, // |AD| / |DB|
        ]);
      case final CentralReflectionPoint r:
        emit(PredicateKind.midp, [r.center, r.point, r]);
      case final RotatedPoint r:
        emit(PredicateKind.cong, [r.center, r.point, r.center, r]);
      case final TranslatedPoint t:
        emit(PredicateKind.cong, [t.point, t, t.vectorFrom, t.vectorTo]);
        emit(PredicateKind.para, [t.point, t, t.vectorFrom, t.vectorTo]);
      case final ReflectedPoint r:
        for (final q in onCurve(r.mirror)) {
          emit(PredicateKind.cong, [q, r.point, q, r]);
        }
        for (final pair in pairsOn(r.mirror)) {
          emit(PredicateKind.perp, [r.point, r, ...pair]);
        }
      case final ProjectionPoint f:
        for (final pair in pairsOn(f.line)) {
          emit(PredicateKind.coll, [f, ...pair]);
          emit(PredicateKind.perp, [f.point, f, ...pair]);
        }
      case final Circumcenter o:
        emit(PredicateKind.cong, [o, o.vertex1, o, o.vertex2]);
        emit(PredicateKind.cong, [o, o.vertex1, o, o.vertex3]);
      case final Orthocenter h:
        emit(PredicateKind.perp, [h, h.vertex1, h.vertex2, h.vertex3]);
        emit(PredicateKind.perp, [h, h.vertex2, h.vertex1, h.vertex3]);
        emit(PredicateKind.perp, [h, h.vertex3, h.vertex1, h.vertex2]);
      case final Incenter i:
        emit(PredicateKind.eqangle, [
          i.vertex1, i.vertex2, i.vertex1, i, // ∠(AB, AI)
          i.vertex1, i, i.vertex1, i.vertex3, // ∠(AI, AC)
        ]);
        emit(PredicateKind.eqangle, [
          i.vertex2,
          i.vertex1,
          i.vertex2,
          i,
          i.vertex2,
          i,
          i.vertex2,
          i.vertex3,
        ]);
        emit(PredicateKind.eqangle, [
          i.vertex3,
          i.vertex1,
          i.vertex3,
          i,
          i.vertex3,
          i,
          i.vertex3,
          i.vertex2,
        ]);
      case final CircleCenter o when _isCircleByConstruction(o.circle):
        for (final pair in pairsOn(o.circle)) {
          emit(PredicateKind.cong, [o, pair[0], o, pair[1]]);
        }
      case final ParallelLine l:
        for (final ownPair in pairsOn(l)) {
          for (final referencePair in pairsOn(l.reference)) {
            emit(PredicateKind.para, [...ownPair, ...referencePair]);
          }
        }
      case final PerpendicularLine l:
        for (final ownPair in pairsOn(l)) {
          for (final referencePair in pairsOn(l.reference)) {
            emit(PredicateKind.perp, [...ownPair, ...referencePair]);
          }
        }
      case final PerpendicularBisectorLine b:
        for (final point in onCurve(b)) {
          emit(PredicateKind.cong, [point, b.point1, point, b.point2]);
        }
        for (final pair in pairsOn(b)) {
          emit(PredicateKind.perp, [...pair, b.point1, b.point2]);
        }
      case final AngleBisectorLine b:
        for (final point in onCurve(b)) {
          if (identical(point, b.vertex)) continue;
          emit(PredicateKind.eqangle, [
            b.vertex,
            b.arm1,
            b.vertex,
            point,
            b.vertex,
            point,
            b.vertex,
            b.arm2,
          ]);
        }
      case final TwoLineBisectorLine b:
        // ∠(line1, bisector) = ∠(bisector, line2) holds for *both*
        // branches mod π — the external bisector shifts both sides by
        // π/2 — so the emission needs no branch flag.
        for (final ownPair in pairsOn(b)) {
          for (final pair1 in pairsOn(b.line1)) {
            for (final pair2 in pairsOn(b.line2)) {
              emit(PredicateKind.eqangle, [
                ...pair1,
                ...ownPair,
                ...ownPair,
                ...pair2,
              ]);
            }
          }
        }
      case final DiameterCircle c:
        // Thales, by construction: the angle in the semicircle.
        for (final point in onCurve(c)) {
          if (identical(point, c.point1) || identical(point, c.point2)) {
            continue;
          }
          emit(PredicateKind.perp, [point, c.point1, point, c.point2]);
        }
      case final CompassCircle c:
        for (final point in onCurve(c)) {
          emit(PredicateKind.cong, [
            c.center,
            point,
            c.radiusPoint1,
            c.radiusPoint2,
          ]);
        }
      // Tangency, when the figure has named the touch point (Phase 155).
      // The kind computes its touch point inside `recompute` and does not
      // publish it as a `GeoPoint`, so there is nothing here to point at
      // — but a point the construction puts on *both* the tangent and its
      // circle is the touch point, because a tangent meets its circle
      // exactly once. Drawing the intersection is the natural way to get
      // one, and JGEX's *Tangent* asks for the same thing.
      //
      // No new predicate: the tangent at `t` is perpendicular to the
      // radius `centre→t`, which is `perp(O, T, T, P)` for every other
      // named `P` on the line, and the radii `cong` the theorem also
      // wants is already emitted by the circle case above. When no touch
      // point is named there is nothing to say, and inventing one is
      // Phase 153's problem rather than this one's.
      //
      // Guarded on the parent being a circle by construction for the
      // same reason `cyclic` is: the tangent to a general conic at `t`
      // is *not* perpendicular to the join of `t` with the conic's
      // centre, so the statement would be false about a `FivePointConic`
      // that happens to look round.
      case final TangentLine t when _isCircleByConstruction(t.circle):
        final centre = centreOf(t.circle);
        if (centre == null) break;
        final onTangent = onCurve(t);
        for (final touch in onTangent) {
          if (!structurallyIncident(t.circle, touch)) continue;
          for (final other in onTangent) {
            if (identical(other, touch)) continue;
            emit(PredicateKind.perp, [centre, touch, touch, other]);
          }
        }
      default:
        break;
    }
  }
  return out;
}

/// Whether [circle]'s carrier is a circle *by construction* — the
/// conic-valued kinds under `GeoCircle` (Phase 119's parking decision)
/// are conics whose being a circle would be an accident of position, and
/// `cyclic`/radius-`cong` must not be asserted about them.
bool _isCircleByConstruction(GeoCircle circle) => switch (circle) {
  FivePointConic() || BifocalConic() || FocalConic() => false,
  _ => true,
};

/// The point the kind stores as its own center, when it has one.
GeoPoint? _structuralCenter(GeoCircle circle) => switch (circle) {
  CircleCenterPoint() => circle.center,
  CompassCircle() => circle.center,
  FixedRadiusCircle() => circle.center,
  Sector() => circle.center,
  _ => null,
};

/// The k-element subsets of [items], in lexicographic index order.
List<List<GeoPoint>> _choose(List<GeoPoint> items, int k) {
  final out = <List<GeoPoint>>[];
  final indices = List.generate(k, (i) => i);
  if (items.length < k) return out;
  while (true) {
    out.add([for (final i in indices) items[i]]);
    var position = k - 1;
    while (position >= 0 && indices[position] == items.length - k + position) {
      position--;
    }
    if (position < 0) return out;
    indices[position]++;
    for (var i = position + 1; i < k; i++) {
      indices[i] = indices[i - 1] + 1;
    }
  }
}
