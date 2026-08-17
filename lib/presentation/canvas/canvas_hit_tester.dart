import 'dart:math' as math;

import '../../domain/construction/geo_object.dart';
import '../../domain/construction/line_clip.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/ray.dart';
import '../../domain/construction/objects/sector.dart';
import '../../domain/construction/objects/segment.dart';
import '../../domain/math/angle_geometry.dart';
import '../../domain/math/circle_eq.dart';
import '../../domain/math/vec2.dart';
import '../../domain/projective/conic_matrix.dart';
import '../../domain/projective/conic_shape.dart';

/// Finds the object under a tap.
///
/// Works entirely in world coordinates: the caller converts the screen
/// threshold (8 px by convention) to world units via
/// `CanvasViewport.screenToWorldLength` — so the tester itself needs no
/// viewport and no Flutter types. The one screen-sized target, an angle's
/// marker wedge, rides the optional [hitTestAll] `worldPerPx` hint
/// (`screenToWorldLength(1)`) instead of a viewport.
///
/// Selection order is (priority, distance), lexicographically: any point
/// within the threshold beats any circle, which beats any line — small,
/// precise targets must not be shadowed by the big shapes drawn through
/// them (PLAN: points > arcs/circles > segments/rays/lines/loci >
/// angles > measurements > polygons). Ties go to the object added
/// latest, i.e. the one drawn on top.
///
/// Undefined and invisible objects are never hit — unless the caller
/// passes `includeHidden` (the Show/Hide tool, which renders hidden
/// objects dimmed and must let taps reach them).
///
/// Named `CanvasHitTester` because `flutter_test` exports a `HitTester`
/// of its own, which every widget test would collide with.
class CanvasHitTester {
  const CanvasHitTester();

  /// The best object within [threshold] world units of [point], or null.
  ///
  /// [objects] must come in insertion (drawing) order — that is what makes
  /// "latest wins ties" mean "topmost wins".
  GeoObject? hitTest(
    Iterable<GeoObject> objects,
    Vec2 point,
    double threshold, {
    double worldPerPx = 0,
    bool includeHidden = false,
  }) => hitTestAll(
    objects,
    point,
    threshold,
    worldPerPx: worldPerPx,
    includeHidden: includeHidden,
  ).firstOrNull;

  /// Every visible, defined object within [threshold] world units of
  /// [point], best first — the same (priority, distance) order as
  /// [hitTest], with ties going to the object added latest (topmost).
  /// Point resolution reads the runners-up to spot curve crossings.
  ///
  /// [worldPerPx] (`screenToWorldLength(1)`) sizes the angle markers,
  /// which are drawn at a fixed *screen* radius: with it, an angle is
  /// picked anywhere on its wedge; without it (0), the marker degenerates
  /// to its vertex — the pre-22b behavior callers without a viewport get.
  List<GeoObject> hitTestAll(
    Iterable<GeoObject> objects,
    Vec2 point,
    double threshold, {
    double worldPerPx = 0,
    bool includeHidden = false,
  }) {
    final candidates = <(GeoObject, int, double, int)>[];
    var index = 0;
    for (final object in objects) {
      index++;
      if ((!object.attributes.visible && !includeHidden) || !object.isDefined) {
        continue;
      }
      final distance = _distanceTo(objects, object, point, worldPerPx);
      if (distance > threshold) {
        continue;
      }
      final priority = switch (object) {
        GeoPoint() => 0,
        // A conic is picked like the circle it generalizes.
        GeoCircle() => 1,
        GeoLine() => 2,
        GeoLocus() => 2, // a locus is picked like the line it draws as
        GeoAngle() => 3,
        GeoMeasurement() || GeoText() => 4,
        // Lowest: a polygon's interior hits at distance 0, so anything
        // drawn inside it must still win the tap.
        GeoPolygon() => 5,
      };
      candidates.add((object, priority, distance, index));
    }
    candidates.sort((a, b) {
      if (a.$2 != b.$2) {
        return a.$2.compareTo(b.$2);
      }
      if (a.$3 != b.$3) {
        return a.$3.compareTo(b.$3);
      }
      return b.$4.compareTo(a.$4); // exact tie: latest inserted first
    });
    return [for (final c in candidates) c.$1];
  }

  /// The visible, defined objects wholly inside the axis-aligned world
  /// rect spanned by [corner1] and [corner2] — rubber-band selection.
  ///
  /// "Wholly inside" is the rule: a band that merely crosses an object
  /// does not take it. Infinite carriers (lines, rays) can never be
  /// contained; arcs and sectors are measured by their drawn branch, not
  /// the full carrier circle; an angle by its vertex (its marker is
  /// screen-sized, invisible to a world-space tester — cf. [hitTest]).
  List<GeoObject> objectsInRect(
    Iterable<GeoObject> objects,
    Vec2 corner1,
    Vec2 corner2,
  ) {
    final minX = math.min(corner1.x, corner2.x);
    final maxX = math.max(corner1.x, corner2.x);
    final minY = math.min(corner1.y, corner2.y);
    final maxY = math.max(corner1.y, corner2.y);
    return objectsContainedIn(
      objects,
      (p) => p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY,
    );
  }

  /// The visible, defined objects wholly inside the rectangular region
  /// given by [within] — the general band-selection predicate.
  ///
  /// [within] takes world points; the region must be a rectangle in
  /// *some* frame, and [cardinalAngle] is the world polar angle of that
  /// frame's +x direction. Under view rotation (Phase 43) the canvas
  /// passes the screen-space band — `Rect.contains ∘ worldToScreen`,
  /// which in world space is a rotated quad — with `−rotation` as the
  /// frame angle: circle and arc containment tests the branch extremes
  /// along the *band's* axes, where the true touching points lie.
  List<GeoObject> objectsContainedIn(
    Iterable<GeoObject> objects,
    bool Function(Vec2) within, {
    double cardinalAngle = 0,
  }) => [
    for (final object in objects)
      if (object.attributes.visible &&
          object.isDefined &&
          _containedIn(object, within, cardinalAngle))
        object,
  ];

  bool _containedIn(
    GeoObject object,
    bool Function(Vec2) within,
    double cardinalAngle,
  ) => switch (object) {
    GeoPoint() => within(object.position!),
    Segment() => within(object.start!) && within(object.end!),
    Arc() => _branchExtremes(object.circle!, object.containsAngle, [
      object.startPosition!,
      object.endPosition!,
    ], cardinalAngle).every(within),
    Sector() => _branchExtremes(object.circle!, object.containsAngle, [
      object.circle!.center,
      object.startRim!,
      object.endRim!,
    ], cardinalAngle).every(within),
    GeoCircle() =>
      object.circle == null
          ? _conicContained(object.conic!, within, cardinalAngle)
          : _branchExtremes(
              object.circle!,
              (_) => true,
              const [],
              cardinalAngle,
            ).every(within),
    GeoLine() => false, // infinite (rays included): never contained
    GeoAngle() => within(object.angle!.vertex),
    GeoPolygon() => object.polygonVertices!.every(within),
    // A measurement is its text, which is screen-sized like an angle
    // marker; the anchor stands in for it (cf. GeoAngle above).
    GeoMeasurement() => within(object.anchor!),
    GeoText() => within(object.anchor),
    // Every recorded sample must be inside; an all-gap locus (no
    // drawn ink) can never be band-selected.
    GeoLocus() => _locusContained(object, within),
  };

  /// Whether a conic without a centre and radius is wholly inside the
  /// region. Only an ellipse can be: every other drawable class runs off
  /// to infinity, and a band that merely crosses an object does not take
  /// it. The ellipse's extremes along the band frame's two axes are its
  /// exact bounding box in that frame — the conic analogue of
  /// [_branchExtremes], computed projectively rather than by sampling.
  bool _conicContained(
    ConicMatrix conic,
    bool Function(Vec2) within,
    double cardinalAngle,
  ) {
    final shape = ConicShape.of(conic);
    if (shape.kind != ConicClass.ellipse) {
      return false;
    }
    for (var k = 0; k < 2; k++) {
      final extremes = shape.extremesAlong(cardinalAngle + k * math.pi / 2);
      if (extremes.length < 2 || !extremes.every(within)) {
        return false;
      }
    }
    return true;
  }

  bool _locusContained(GeoLocus locus, bool Function(Vec2) within) {
    final points = locus.samples!.whereType<Vec2>();
    return points.isNotEmpty && points.every(within);
  }

  /// The points bounding a carrier-circle branch: the [seeds] (endpoints,
  /// and for a sector its center) plus each extreme of the carrier along
  /// the region frame's cardinal directions — [cardinalAngle] + k·π/2 —
  /// that lies on the branch. Their combined bounding box *in that frame*
  /// is the branch's exact bounding box.
  Iterable<Vec2> _branchExtremes(
    CircleEq circle,
    bool Function(double) containsAngle,
    List<Vec2> seeds,
    double cardinalAngle,
  ) sync* {
    yield* seeds;
    for (var k = 0; k < 4; k++) {
      final angle = cardinalAngle + k * math.pi / 2;
      if (containsAngle(angle)) {
        yield circle.center +
            Vec2(math.cos(angle), math.sin(angle)) * circle.radius;
      }
    }
  }

  /// Distance from [point] to the object's visible geometry. Only called
  /// on defined objects, so the force-unwraps are safe. [objects] feeds
  /// the `lineClipSpan` scan for clipped lines and rays — the hit target
  /// follows the drawn stretch, so a tap on the invisible part of a
  /// clipped carrier misses.
  double _distanceTo(
    Iterable<GeoObject> objects,
    GeoObject object,
    Vec2 point,
    double worldPerPx,
  ) => switch (object) {
    GeoPoint() => object.position!.distanceTo(point),
    // An arc measures to its branch of the carrier: on the far branch
    // the nearest visible geometry is an endpoint (cf. segment/ray).
    Arc() => _arcDistance(object, point),
    // A sector's visible geometry is its wedge outline: the arc branch
    // plus the two straight radius edges.
    Sector() => _sectorDistance(object, point),
    // A conic with no centre and radius measures to its curve — the
    // closest-point search in `ConicShape` (see there for why it is a
    // bracketed search and not a Newton step).
    GeoCircle() =>
      object.circle?.distanceTo(point) ??
          ConicShape.of(object.conic!).distanceTo(point),
    // Segments and rays measure to their extent, not the infinite
    // carrier: t clamps to [0, 1] and [0, ∞) respectively.
    Segment() => _clampedDistance(object.start!, object.end!, point, 1),
    Ray() => _lineClippedDistance(
      objects,
      object,
      point,
      orElse: () => _clampedDistance(
        object.start!,
        object.throughPosition!,
        point,
        double.infinity,
      ),
    ),
    GeoLine() => _lineClippedDistance(
      objects,
      object,
      point,
      orElse: () => object.line!.distanceTo(point),
    ),
    // An angle is picked on its marker wedge (see _angleDistance) —
    // low priority, so anything else there wins.
    GeoAngle() => _angleDistance(object, point, worldPerPx),
    // A polygon's interior hits at distance 0 (but lowest priority —
    // an empty interior tap selects the region, anything drawn inside
    // still wins); outside, the nearest edge decides.
    GeoPolygon() => _polygonDistance(object, point),
    // A measurement's geometry is its text anchor; the canvas tap
    // handler additionally checks the text's labelScreenRect first,
    // so text dragged far from the anchor stays tappable.
    GeoMeasurement() => object.anchor!.distanceTo(point),
    GeoText() => object.anchor.distanceTo(point),
    // A locus is its drawn polyline: the nearest of the consecutive
    // sample segments (gaps break the chain; isolated samples and an
    // all-gap locus are unreachable, matching the painter's ink).
    GeoLocus() => _locusDistance(object, point),
  };

  double _locusDistance(GeoLocus locus, Vec2 p) {
    final samples = locus.samples!;
    var best = double.infinity;
    for (var i = 0; i + 1 < samples.length; i++) {
      final a = samples[i];
      final b = samples[i + 1];
      if (a == null || b == null) {
        continue;
      }
      best = math.min(best, _clampedDistance(a, b, p, 1));
    }
    return best;
  }

  /// Distance to an angle's marker wedge: the arc at the marker radius
  /// clamped to the sweep, plus the two straight edges — the
  /// marker-radius analogue of [_sectorDistance]. The marker is drawn at
  /// a fixed *screen* radius; [worldPerPx] converts it to world units,
  /// and without it (0) the wedge degenerates to the vertex. The Phase 22
  /// right-angle square is approximated by its arc — at most ~0.3 × the
  /// marker radius off, well inside any usable threshold.
  double _angleDistance(GeoAngle object, Vec2 p, double worldPerPx) {
    final angle = object.angle!;
    final radius = object.attributes.angleMarkerRadius * worldPerPx;
    if (radius <= 0) {
      return angle.vertex.distanceTo(p);
    }
    final rel = p - angle.vertex;
    final d1 = angle.startDirection;
    final arc = ccwSweep(d1.angle, rel.angle) <= angle.sweep
        ? (rel.norm - radius).abs()
        : double.infinity;
    final d2 = d1.rotated(angle.sweep);
    final edge1 = _clampedDistance(
      angle.vertex,
      angle.vertex + d1 * radius,
      p,
      1,
    );
    final edge2 = _clampedDistance(
      angle.vertex,
      angle.vertex + d2 * radius,
      p,
      1,
    );
    return math.min(arc, math.min(edge1, edge2));
  }

  double _polygonDistance(GeoPolygon object, Vec2 p) {
    final vertices = object.polygonVertices!;
    if (_pointInPolygon(vertices, p)) {
      return 0;
    }
    var best = double.infinity;
    for (var i = 0; i < vertices.length; i++) {
      best = math.min(
        best,
        _clampedDistance(
          vertices[i],
          vertices[(i + 1) % vertices.length],
          p,
          1,
        ),
      );
    }
    return best;
  }

  /// Even-odd ray cast: [p] is inside when a ray towards +x crosses the
  /// loop's edges an odd number of times. Matches the painter's default
  /// even-odd fill, self-intersecting loops included.
  bool _pointInPolygon(List<Vec2> vertices, Vec2 p) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final a = vertices[i];
      final b = vertices[j];
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  double _arcDistance(Arc arc, Vec2 p) {
    final circle = arc.circle!;
    if (arc.containsAngle(circle.angleAt(p))) {
      return circle.distanceTo(p);
    }
    final toStart = p.distanceTo(arc.startPosition!);
    final toEnd = p.distanceTo(arc.endPosition!);
    return toStart < toEnd ? toStart : toEnd;
  }

  double _sectorDistance(Sector sector, Vec2 p) {
    final circle = sector.circle!;
    final arc = sector.containsAngle(circle.angleAt(p))
        ? circle.distanceTo(p)
        : double.infinity;
    final edge1 = _clampedDistance(circle.center, sector.startRim!, p, 1);
    final edge2 = _clampedDistance(circle.center, sector.endRim!, p, 1);
    return math.min(arc, math.min(edge1, edge2));
  }

  /// Distance to a line/ray's *drawn* stretch under its `lineClip` mode:
  /// clamped to the `lineClipSpan` endpoints when a clip applies,
  /// [orElse] (the kind's unclipped rule) otherwise. The `lineClip == 0`
  /// guard skips the helper's whole-construction scan for the common
  /// unclipped case.
  double _lineClippedDistance(
    Iterable<GeoObject> objects,
    GeoLine line,
    Vec2 p, {
    required double Function() orElse,
  }) {
    if (line.attributes.lineClip == 0) {
      return orElse();
    }
    final span = lineClipSpan(objects, line);
    if (span == null) {
      return orElse();
    }
    return _clampedDistance(span.start, span.end, p, 1);
  }

  double _clampedDistance(Vec2 a, Vec2 b, Vec2 p, double tMax) {
    final ab = b - a;
    if (ab.normSquared == 0) {
      return p.distanceTo(a);
    }
    final t = ((p - a).dot(ab) / ab.normSquared).clamp(0.0, tMax);
    return p.distanceTo(a.lerp(b, t));
  }
}
