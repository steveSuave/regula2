import 'dart:math' as math;

import '../../domain/construction/geo_object.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/ray.dart';
import '../../domain/construction/objects/sector.dart';
import '../../domain/construction/objects/segment.dart';
import '../../domain/math/vec2.dart';
import '../../domain/projective/conic_shape.dart';

/// World position a label hangs from. The painter converts it to screen
/// space and nudges it by a fixed pixel offset, so this only decides
/// *where on the object* the label belongs:
///
/// - points and angles: the point / vertex itself;
/// - segments: the midpoint; rays: the origin;
/// - infinite lines: the anchor closest to the world origin (the only
///   stable point an unbounded carrier has);
/// - circles: the top of the rim; other conics: a deterministic point of
///   the curve; arcs and sectors: the middle of the drawn branch;
/// - polygons: the vertex average (inside for convex regions, stable
///   under drags either way);
/// - measurements: their anchor — the label *is* the object;
/// - loci: the first recorded sample (the world origin stands in for an
///   all-gap locus, which draws no ink to hang a label from).
///
/// Only call on defined objects — the force-unwraps mirror the painter's,
/// which skips undefined objects before asking for an anchor.
Vec2 labelAnchor(GeoObject object) => switch (object) {
      GeoPoint() => object.position!,
      Segment() => object.start!.lerp(object.end!, 0.5),
      Ray() => object.start!,
      GeoLine() => object.line!.pointOnLine,
      Arc() => object.circle!.pointAt(object.startAngle! + object.sweep! / 2),
      Sector() =>
        object.circle!.pointAt(object.startAngle! + object.sweep! / 2),
      GeoCircle() => switch (object.circle) {
        final circle? => circle.pointAt(math.pi / 2),
        // A conic with no centre and radius has no "top of the rim"; the
        // shape's own scan point stands in. `isDefined` for such a kind
        // is `ConicShape.isDrawable`, which guarantees ink but not that
        // the scan finds a *finite* point of it, so the origin is the
        // last resort — the same fallback an all-gap locus takes.
        null => ConicShape.of(object.conic!).anchorPoint ?? Vec2.zero,
      },
      GeoAngle() => object.angle!.vertex,
      GeoPolygon() => object.polygonVertices!
              .reduce((sum, vertex) => sum + vertex) /
          object.polygonVertices!.length.toDouble(),
      GeoMeasurement() => object.anchor!,
      GeoText() => object.anchor,
      // Core samples, not the full trace: a diverging line-host arm
      // reaches astronomically far out — an anchor there is never
      // on-screen. All-gap core (defined ink only far out) falls back
      // to the world origin, like the all-gap defined locus always has.
      GeoLocus() => object.coreSamples!.firstOrNull ?? Vec2.zero,
    };
