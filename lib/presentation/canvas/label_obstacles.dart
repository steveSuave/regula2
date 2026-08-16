import 'dart:math' as math;
import 'dart:ui';

import '../../domain/construction/construction.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/line_clip.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/ray.dart';
import '../../domain/construction/objects/sector.dart';
import '../../domain/construction/objects/segment.dart';
import '../../domain/math/vec2.dart';
import '../../domain/projective/conic_shape.dart';
import 'canvas_viewport.dart';
import 'label_declutter.dart';
import 'label_layout.dart';

/// Sampling flatness (screen px) of a conic obstacle chain. Coarser than
/// the painter's, because a label only needs the ink's *shape*, not its
/// antialiasing — the same reason a circle obstacle is a 12–48-gon.
const double _conicObstacleFlatness = 3;

/// Everything the declutter solver needs to see, in screen space.
typedef DeclutterScene = ({
  List<LabelBox> labels,
  List<RectObstacle> rects,
  List<Capsule> capsules,
});

/// Converts the construction's visible ink and labels into the solver's
/// screen-space scene, mirroring the painter's per-kind geometry
/// (`GeometryPainter._drawObject`): curves become chord runs, strokes
/// become capsules at `strokeWidth / 2 + 1` px half-width, point dots
/// become rects. Fills are deliberately not obstacles — a label on a
/// translucent interior stays legible. Hidden and undefined objects
/// contribute nothing, like they paint nothing. Label rects come from
/// [labelScreenRect] — the same measurement the painter and the drag
/// hit test use — so the solver can never disagree with the screen.
DeclutterScene buildDeclutterScene(
  Construction construction,
  CanvasViewport viewport,
  Size canvasSize,
) {
  final labels = <LabelBox>[];
  final rects = <RectObstacle>[];
  final capsules = <Capsule>[];

  for (final object in construction.objects) {
    if (!object.attributes.visible || !object.isDefined) {
      continue;
    }
    final halfWidth = object.attributes.strokeWidth / 2 + 1;
    void capsule(Offset a, Offset b) =>
        capsules.add(Capsule(a, b, halfWidth, ownerId: object.id));
    void chords(List<Offset> points) {
      for (var i = 0; i + 1 < points.length; i++) {
        capsule(points[i], points[i + 1]);
      }
    }

    switch (object) {
      case GeoPoint():
        rects.add(
          RectObstacle(
            Rect.fromCircle(
              center: viewport.worldToScreen(object.position!),
              radius: object.attributes.pointSize + 1,
            ),
            ownerId: object.id,
          ),
        );
      case Segment():
        capsule(
          viewport.worldToScreen(object.start!),
          viewport.worldToScreen(object.end!),
        );
      case Ray():
        final span = _clipSpan(construction, viewport, object);
        if (span != null) {
          capsule(span.$1, span.$2);
        } else {
          // The painter's reach: far enough to cross the whole canvas.
          final start = viewport.worldToScreen(object.start!);
          final along =
              viewport.worldToScreen(object.throughPosition!) - start;
          if (along.distance > 0) {
            final direction = along / along.distance;
            final reach =
                start.distance + canvasSize.width + canvasSize.height;
            capsule(start, start + direction * reach);
          }
        }
      case GeoLine():
        final span = _clipSpan(construction, viewport, object);
        if (span != null) {
          capsule(span.$1, span.$2);
        } else {
          final line = object.line!;
          final anchor = viewport.worldToScreen(line.pointOnLine);
          final along =
              viewport.worldToScreen(line.pointOnLine + line.direction) -
                  anchor;
          if (along.distance > 0) {
            final direction = along / along.distance;
            final reach =
                anchor.distance + canvasSize.width + canvasSize.height;
            capsule(anchor - direction * reach, anchor + direction * reach);
          }
        }
      case Arc():
        chords(
          _branchPoints(viewport, object, object.startAngle!, object.sweep!),
        );
      case Sector():
        final points = _branchPoints(
          viewport,
          object,
          object.startAngle!,
          object.sweep!,
        );
        chords(points);
        final center = viewport.worldToScreen(object.circle!.center);
        capsule(center, points.first);
        capsule(center, points.last);
      case GeoCircle():
        final circle = object.circle;
        if (circle == null) {
          // A conic with no centre and radius: its own visible arcs are
          // the obstacle, at the sampling density the box asks for — a
          // hyperbola's two arms give two chains, not one.
          final box = viewport.visibleWorldBox(canvasSize);
          final strokes = ConicShape.of(object.conic!).polylines(
            min: box.min,
            max: box.max,
            flatness: viewport.screenToWorldLength(_conicObstacleFlatness),
          );
          for (final stroke in strokes) {
            chords([
              for (final point in stroke.points)
                viewport.worldToScreen(point),
              if (stroke.closed && stroke.points.isNotEmpty)
                viewport.worldToScreen(stroke.points.first),
            ]);
          }
          break;
        }
        final center = viewport.worldToScreen(circle.center);
        final radius = viewport.worldToScreenLength(circle.radius);
        final n = (2 * math.pi * radius / 12).ceil().clamp(12, 48);
        chords([
          for (var i = 0; i <= n; i++)
            center +
                Offset(
                  radius * math.cos(2 * math.pi * i / n),
                  radius * math.sin(2 * math.pi * i / n),
                ),
        ]);
      case GeoAngle():
        _addAngleMarker(viewport, object, chords);
      case GeoPolygon():
        final points = [
          for (final vertex in object.polygonVertices!)
            viewport.worldToScreen(vertex),
        ];
        chords([...points, points.first]);
      case GeoMeasurement() || GeoText():
        // Pure text — the label pass below is the whole object.
        break;
      case GeoLocus():
        _addLocusRuns(viewport, object, chords);
    }

    final rect = labelScreenRect(object, viewport);
    if (rect != null) {
      final offset = Offset(
        object.attributes.labelDx,
        object.attributes.labelDy,
      );
      labels.add(
        LabelBox(
          id: object.id,
          // Recover the offset origin from the rect the label actually
          // occupies — for angles that's the bisector base, not the
          // anchor (labelBaseTopLeft needs the text size, which only
          // the rect knows here).
          anchor: rect.topLeft - offset,
          size: rect.size,
          offset: offset,
        ),
      );
    }
  }

  return (labels: labels, rects: rects, capsules: capsules);
}

/// A clipped line/ray's drawn stretch as screen endpoints, or null for
/// the full carrier (mirrors `GeometryPainter._clipSpan`).
(Offset, Offset)? _clipSpan(
  Construction construction,
  CanvasViewport viewport,
  GeoLine object,
) {
  if (object.attributes.lineClip == 0) {
    return null;
  }
  final span = lineClipSpan(construction.objects, object);
  if (span == null) {
    return null;
  }
  return (
    viewport.worldToScreen(span.start),
    viewport.worldToScreen(span.end),
  );
}

/// Screen points along a circle branch from [startAngle] through
/// [sweep], chord-sampled like the painted arc (world angles negate on
/// screen — here via the explicit y flip).
List<Offset> _branchPoints(
  CanvasViewport viewport,
  GeoCircle object,
  double startAngle,
  double sweep,
) {
  final circle = object.circle!;
  final center = viewport.worldToScreen(circle.center);
  final radius = viewport.worldToScreenLength(circle.radius);
  final n = (radius * sweep.abs() / 12).ceil().clamp(4, 48);
  return [
    for (var i = 0; i <= n; i++)
      center +
          Offset(
            radius * math.cos(startAngle + sweep * i / n),
            -radius * math.sin(startAngle + sweep * i / n),
          ),
  ];
}

/// The angle marker as capsules: the right-angle square's four edges, or
/// the wedge as spokes at ≤ 30° steps plus rim chords between the tips.
/// Spokes cover the wedge interior cheaply, and outside the sweep there
/// is no obstacle — so the reflex side of the vertex stays available,
/// exactly where an angle value reads best. Geometry mirrors
/// `GeometryPainter._drawAngleMarker` / `_rightAngleSquarePath`.
void _addAngleMarker(
  CanvasViewport viewport,
  GeoAngle object,
  void Function(List<Offset>) chords,
) {
  final angle = object.angle!;
  final vertex = viewport.worldToScreen(angle.vertex);
  final radius = object.attributes.angleMarkerRadius;
  if ((angle.sweep - math.pi / 2).abs() <= defaultEpsilon) {
    final side = 0.7 * radius;
    final d1 = angle.startDirection;
    final d2 = d1.rotated(angle.sweep);
    // World directions are y-up; the screen flips y.
    Offset corner(Vec2 d) => vertex + Offset(d.x, -d.y) * side;
    chords([vertex, corner(d1), corner(d1 + d2), corner(d2), vertex]);
    return;
  }
  final start = angle.startDirection.angle;
  final steps = math.max(2, (angle.sweep / (math.pi / 6)).ceil());
  final tips = [
    for (var i = 0; i <= steps; i++)
      vertex +
          Offset(
            radius * math.cos(start + angle.sweep * i / steps),
            -radius * math.sin(start + angle.sweep * i / steps),
          ),
  ];
  for (final tip in tips) {
    chords([vertex, tip]);
  }
  chords(tips);
}

/// A locus's non-null sample runs as chord polylines, decimated so a
/// long trace stays a few dozen capsules.
void _addLocusRuns(
  CanvasViewport viewport,
  GeoLocus object,
  void Function(List<Offset>) chords,
) {
  final run = <Offset>[];
  void endRun() {
    if (run.length > 1) {
      final stride = math.max(1, run.length ~/ 64);
      chords([
        for (var i = 0; i < run.length; i += stride) run[i],
        if ((run.length - 1) % stride != 0) run.last,
      ]);
    }
    run.clear();
  }

  for (final sample in object.samples!) {
    if (sample == null) {
      endRun();
    } else {
      run.add(viewport.worldToScreen(sample));
    }
  }
  endRun();
}
