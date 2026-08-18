import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/construction/construction.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/line_clip.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/locus.dart';
import '../../domain/construction/objects/ray.dart';
import '../../domain/construction/objects/sector.dart';
import '../../domain/construction/objects/segment.dart';
import '../../domain/math/circle_eq.dart';
import '../../domain/math/vec2.dart';
import '../../domain/projective/absolute.dart';
import '../../domain/projective/conic_matrix.dart';
import '../../domain/projective/conic_shape.dart';
import 'canvas_viewport.dart';
import 'dash_path.dart';
import 'grid_layout.dart';
import 'label_layout.dart';
import 'large_radius_arc.dart';

/// The canvas rect minus the disc — the region that is not part of the
/// plane, as one even-odd path.
///
/// **Even-odd rather than `Path.combine(PathOperation.difference, …)`,
/// and that is a bug fix rather than a simplification (Phase 126d).** The
/// boolean difference produced the whole rect — no hole at all — on the
/// web renderer whenever the disc lay *entirely inside* the canvas, and
/// the correct annulus as soon as any part of it hung over an edge. Every
/// test stayed green because the VM harness has a different path-ops
/// implementation from CanvasKit, so the defect was only ever visible in
/// a browser: a hyperbolic document showed a uniformly washed canvas with
/// the rim floating on it, and looked correct the moment the user zoomed
/// far enough to push the boundary off screen.
///
/// The even-odd rule needs no boolean op to express the same region. A
/// point inside both the rect and the disc has crossing number two, which
/// is even, so it is not filled; a point in the rect alone has one. That
/// is exact, portable and cheaper, and it is the shape to reach for
/// whenever a fill needs a hole in it.
Path outsideDiscPath(Size size, Offset centre, double radius) => Path()
  ..fillType = PathFillType.evenOdd
  ..addRect(Offset.zero & size)
  ..addOval(Rect.fromCircle(center: centre, radius: radius));

/// Where the document's fundamental conic is on screen, or null when its
/// geometry has no real absolute to draw (Phase 126).
///
/// Only the **hyperbolic** absolute is drawable: `x² + y² − w² = 0` is the
/// unit circle, the Beltrami–Klein disc's boundary, and the region outside
/// it is not part of the hyperbolic plane at all — a figure dragged across
/// it does not merely look wrong, it goes undefined. The wash is what
/// makes that legible before it happens.
///
/// The **elliptic** absolute `x² + y² + w² = 0` has no real points, and
/// that is a fact about the geometry rather than a gap in the drawing:
/// elliptic space has no boundary and no unreachable region, the whole
/// real projective plane being the space. Drawing anything would be
/// inventing an edge that is not there. **Euclidean** draws nothing for
/// the mirror-image reason — its absolute is the line at infinity, real
/// enough but with no points in any chart.
///
/// Centre and radius come from the viewport rather than from a projection
/// of the conic, which is exact rather than approximate: the absolute is a
/// world-space circle about the origin, and a circle stays a circle under
/// everything the viewport does to it, rotation included.
({Offset centre, double radius})? absoluteDisc(
  FundamentalConic metric,
  CanvasViewport viewport,
) {
  if (metric != FundamentalConic.hyperbolic) {
    return null;
  }
  final radius = viewport.worldToScreenLength(1);
  if (!radius.isFinite || radius <= 0) {
    return null;
  }
  return (centre: viewport.worldToScreen(Vec2.zero), radius: radius);
}

/// Paints the construction in insertion order (first added = bottom).
///
/// Skips undefined and invisible objects, per the `GeoObject` contract.
/// Stroke widths and point radii come from `ObjectAttributes` and are in
/// logical pixels — they do not scale with zoom (a hairline stays a
/// hairline). A named object with `labelVisible` gets its name painted
/// beside its [labelBaseTopLeft], in the object's own color.
class GeometryPainter extends CustomPainter {
  GeometryPainter({
    required this.construction,
    required this.viewport,
    required this.revision,
    required this.defaultColor,
    required this.selectionColor,
    this.selectedIds = const {},
    this.previewMarkers = const [],
    this.previewObjectIds = const {},
    this.labelDragPreview,
    this.showHidden = false,
    this.showAxes = false,
    this.showGrid = false,
    this.axisColor = const Color(0xFF757575),
    this.gridColor = const Color(0xFFE3E6EA),
    this.absoluteColor = const Color(0xFFB26A00),
    this.absoluteOutsideColor = const Color(0x40B26A00),
  });

  /// Stroke widths of the background layer (logical px) and the font size
  /// of its tick labels.
  static const double _gridStrokeWidth = 1;
  static const double _axisStrokeWidth = 1.5;
  // 12 rather than the original 10 (Phase 54): the smallest text on the
  // canvas follows the larger-defaults pass.
  static const double _tickFontSize = 12;

  /// Screen-px gap between an axis and its tick labels.
  static const double _tickLabelGap = 3;

  /// Radii (logical px) of an in-progress input marker: a filled dot
  /// inside a hollow ring, visually distinct from a plain point.
  static const double _markerDotRadius = 3;
  static const double _markerRingRadius = 7;

  /// How much wider (logical px) a selection halo is than the stroke it
  /// sits under; also the extra radius on a selected point's halo disc.
  static const double _haloExtra = 5;

  static const double _haloAlpha = 0.4;

  /// Opacity factor for hidden objects while [showHidden] is on.
  static const double _hiddenAlpha = 0.35;

  /// Screen-px margin the conic clip box is grown by, and the flatness
  /// (also screen px) the conic sweep is walked to. Half a pixel is under
  /// the antialiasing floor at any zoom.
  static const double _conicClipMargin = 8;
  static const double _conicFlatness = 0.5;

  /// Read live at paint time, in insertion (drawing) order.
  final Construction construction;

  final CanvasViewport viewport;

  /// The construction's revision when the painter was created — the
  /// construction mutates in place, so instance comparison alone can't
  /// drive repaints (same trick as `ConstructionState`). The instance
  /// still matters: `replace()` resets the revision, so a swapped-in
  /// construction can carry the same revision number as the old one.
  final int revision;

  /// Color for objects whose attributes carry no explicit color.
  final Color defaultColor;

  /// Ids of selected objects, drawn with a translucent halo underneath.
  final Set<String> selectedIds;

  /// Base color of the selection halo (alpha is the painter's business).
  final Color selectionColor;

  /// World positions of the active tool's in-progress inputs (see
  /// `ToolInputPreview`), drawn as markers on top of the construction.
  final List<Vec2> previewMarkers;

  /// Ids of existing objects the active tool has consumed as inputs
  /// (see `ToolInputPreview.previewObjectIds`), haloed exactly like a
  /// selection — the union with [selectedIds].
  final Set<String> previewObjectIds;

  /// A label mid-drag: [offset] replaces the object's stored label
  /// offset for this frame only. The canvas holds the drag as widget
  /// state and commits one `ChangeAttributesCommand` at gesture end, so
  /// the construction is never mutated per frame.
  final ({String id, Offset offset})? labelDragPreview;

  /// Renders hidden objects (and their labels) at [_hiddenAlpha] opacity
  /// instead of skipping them — the Show/Hide tool's view state, never
  /// persisted and never on in PNG export (which builds its own painter
  /// and leaves the default false).
  final bool showHidden;

  /// Draws the coordinate axes / the background grid behind every object
  /// (the Phase 36 `DocumentSettings` toggles). Both default off, so
  /// existing callers — exporter included — render byte-identically.
  final bool showAxes;
  final bool showGrid;

  /// Colors for the background layer, from the theme's `CanvasColors`
  /// extension (defaults match the light palette for theme-less callers).
  final Color axisColor;
  final Color gridColor;

  /// The fundamental conic of a non-Euclidean document (Phase 126).
  final Color absoluteColor;

  /// The wash over the region outside it, alpha included (Phase 126b —
  /// it is a theme colour rather than one opacity applied to
  /// [absoluteColor], because the light and dark canvases start from
  /// opposite ends and the same alpha cannot serve both).
  final Color absoluteOutsideColor;

  /// Stroke width (logical px) of the absolute. Heavier than an axis
  /// because it is not chrome: it is the edge of the plane.
  static const double _absoluteStrokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // Infinite lines are drawn with far-away endpoints; the clip keeps
    // that overdraw inside the canvas.
    canvas.clipRect(Offset.zero & size);

    if (showGrid || showAxes) {
      _drawBackground(canvas, size);
    }
    _drawAbsolute(canvas, size);

    for (final object in construction.objects) {
      final hidden = !object.attributes.visible;
      if ((hidden && !showHidden) || !object.isDefined) {
        continue;
      }
      // A hidden object drawn through [showHidden] dims everything it
      // paints — halo, fill, stroke and label — by the same factor.
      final dim = hidden ? _hiddenAlpha : 1.0;
      if (selectedIds.contains(object.id) ||
          previewObjectIds.contains(object.id)) {
        final halo = Paint()
          ..color = selectionColor.withValues(alpha: _haloAlpha * dim)
          ..strokeWidth = object.attributes.strokeWidth + _haloExtra
          ..style = PaintingStyle.stroke;
        _drawObject(canvas, size, object, halo, pointRadiusExtra: _haloExtra);
      }
      final baseColor = Color(
        object.attributes.colorArgb ?? defaultColor.toARGB32(),
      );
      final color = hidden
          ? baseColor.withValues(alpha: baseColor.a * dim)
          : baseColor;
      final fillAlpha = object.attributes.fillAlpha;
      if (fillAlpha != null) {
        _drawFill(
          canvas,
          size,
          object,
          Paint()
            ..color = baseColor.withValues(alpha: fillAlpha * dim)
            ..style = PaintingStyle.fill,
        );
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = object.attributes.strokeWidth
        ..style = PaintingStyle.stroke;
      _drawObject(
        canvas,
        size,
        object,
        paint,
        dashPeriod: object.attributes.dashPeriod,
      );
      final text = labelText(object);
      if (text != null) {
        _drawLabel(canvas, object, text, color);
      }
    }

    final dot = Paint()..color = defaultColor;
    final ring = Paint()
      ..color = defaultColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final marker in previewMarkers) {
      final center = viewport.worldToScreen(marker);
      canvas.drawCircle(center, _markerDotRadius, dot);
      canvas.drawCircle(center, _markerRingRadius, ring);
    }
  }

  /// The Phase 36 background layer: grid hairlines at every multiple of
  /// the adaptive [gridStep], then 1.5-px axes through the world origin
  /// with tick labels — drawn first, so every object paints over it.
  /// Grid and axes are view chrome, not objects: hit testing, selection
  /// and fit never see them.
  /// Draws the document's fundamental conic and washes the region that is
  /// not part of the plane (Phase 126). See [absoluteDisc] for which
  /// geometries have anything to draw and why the other two do not.
  void _drawAbsolute(Canvas canvas, Size size) {
    final disc = absoluteDisc(construction.kernel.metric, viewport);
    if (disc == null) {
      return;
    }
    canvas.drawPath(
      outsideDiscPath(size, disc.centre, disc.radius),
      Paint()..color = absoluteOutsideColor,
    );
    canvas.drawCircle(
      disc.centre,
      disc.radius,
      Paint()
        ..color = absoluteColor
        ..strokeWidth = _absoluteStrokeWidth
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawBackground(Canvas canvas, Size size) {
    final step = gridStep(viewport.state.scale);
    // Grid and axes are world-space (Phase 43 decision): under view
    // rotation they rotate with the content, staying glued to the world
    // axes. The visible world region is then a rotated quad — cover its
    // axis-aligned bounding box (at rotation 0 this reduces exactly to
    // the two screen corners); the canvas clips the overhang.
    final corners = [
      viewport.screenToWorld(Offset.zero),
      viewport.screenToWorld(Offset(size.width, 0)),
      viewport.screenToWorld(Offset(0, size.height)),
      viewport.screenToWorld(Offset(size.width, size.height)),
    ];
    final minX = corners.map((c) => c.x).reduce(math.min);
    final maxX = corners.map((c) => c.x).reduce(math.max);
    final minY = corners.map((c) => c.y).reduce(math.min);
    final maxY = corners.map((c) => c.y).reduce(math.max);

    if (showGrid) {
      final grid = Paint()
        ..color = gridColor
        ..strokeWidth = _gridStrokeWidth;
      for (var i = (minX / step).ceil(); i * step <= maxX; i++) {
        canvas.drawLine(
          viewport.worldToScreen(Vec2(i * step, maxY)),
          viewport.worldToScreen(Vec2(i * step, minY)),
          grid,
        );
      }
      for (var i = (minY / step).ceil(); i * step <= maxY; i++) {
        canvas.drawLine(
          viewport.worldToScreen(Vec2(minX, i * step)),
          viewport.worldToScreen(Vec2(maxX, i * step)),
          grid,
        );
      }
    }

    if (showAxes) {
      final axis = Paint()
        ..color = axisColor
        ..strokeWidth = _axisStrokeWidth;
      final xAxisVisible = minY <= 0 && 0 <= maxY;
      final yAxisVisible = minX <= 0 && 0 <= maxX;
      if (xAxisVisible) {
        canvas.drawLine(
          viewport.worldToScreen(Vec2(minX, 0)),
          viewport.worldToScreen(Vec2(maxX, 0)),
          axis,
        );
      }
      if (yAxisVisible) {
        canvas.drawLine(
          viewport.worldToScreen(Vec2(0, maxY)),
          viewport.worldToScreen(Vec2(0, minY)),
          axis,
        );
      }
      _drawTickLabels(
        canvas,
        size,
        step,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        xAxisVisible: xAxisVisible,
        yAxisVisible: yAxisVisible,
      );
    }
  }

  /// Tick labels at every grid multiple along the visible axes: x labels
  /// below their tick, y labels left of theirs, and a single `0` in the
  /// origin's lower-left quadrant instead of one per axis. Labels ride
  /// their axis — an off-screen axis shows none — and stay screen-upright
  /// at any view rotation (only the tick anchors transform).
  void _drawTickLabels(
    Canvas canvas,
    Size size,
    double step, {
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required bool xAxisVisible,
    required bool yAxisVisible,
  }) {
    void paintLabel(String text, Offset Function(Size textSize) place) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: axisColor, fontSize: _tickFontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, place(textPainter.size));
      textPainter.dispose();
    }

    if (xAxisVisible) {
      for (var i = (minX / step).ceil(); i * step <= maxX; i++) {
        if (i == 0) {
          continue;
        }
        final tick = viewport.worldToScreen(Vec2(i * step, 0));
        paintLabel(
          formatTick(i * step),
          (textSize) =>
              Offset(tick.dx - textSize.width / 2, tick.dy + _tickLabelGap),
        );
      }
    }
    if (yAxisVisible) {
      for (var i = (minY / step).ceil(); i * step <= maxY; i++) {
        if (i == 0) {
          continue;
        }
        final tick = viewport.worldToScreen(Vec2(0, i * step));
        paintLabel(
          formatTick(i * step),
          (textSize) => Offset(
            tick.dx - textSize.width - _tickLabelGap,
            tick.dy - textSize.height / 2,
          ),
        );
      }
    }
    if (xAxisVisible && yAxisVisible) {
      final origin = viewport.worldToScreen(Vec2.zero);
      paintLabel(
        '0',
        (textSize) => Offset(
          origin.dx - textSize.width - _tickLabelGap,
          origin.dy + _tickLabelGap,
        ),
      );
    }
  }

  /// Draws one object with [paint] — both the normal pass and, with a
  /// wider translucent paint plus [pointRadiusExtra], the selection halo.
  ///
  /// [dashPeriod] > 0 draws stroked kinds dashed; the halo pass leaves it
  /// at 0 (a dashed halo under a dashed stroke is unreadable — the halo
  /// is selection UI, not object style). Points fill regardless, and
  /// angle markers stay solid for the wedge's readability.
  void _drawObject(
    Canvas canvas,
    Size size,
    GeoObject object,
    Paint paint, {
    double pointRadiusExtra = 0,
    double dashPeriod = 0,
  }) {
    switch (object) {
      case GeoPoint():
        canvas.drawCircle(
          viewport.worldToScreen(object.position!),
          object.attributes.pointSize + pointRadiusExtra,
          paint..style = PaintingStyle.fill,
        );
      case Segment():
        final start = viewport.worldToScreen(object.start!);
        final end = viewport.worldToScreen(object.end!);
        _drawStraight(canvas, start, end, paint, dashPeriod);
        _drawTickMarks(canvas, start, end, object.attributes.tickMarks, paint);
      case Ray():
        final span = _clipSpan(object);
        if (span != null) {
          _drawStraight(
            canvas,
            viewport.worldToScreen(span.start),
            viewport.worldToScreen(span.end),
            paint,
            dashPeriod,
          );
        } else {
          _drawRay(canvas, size, object, paint, dashPeriod);
        }
      case GeoLine():
        final span = _clipSpan(object);
        if (span != null) {
          _drawStraight(
            canvas,
            viewport.worldToScreen(span.start),
            viewport.worldToScreen(span.end),
            paint,
            dashPeriod,
          );
        } else {
          _drawInfiniteLine(canvas, size, object, paint, dashPeriod);
        }
      case Arc():
        _drawCarrierBranch(
          canvas,
          size,
          object.circle!,
          object.startAngle!,
          object.sweep!,
          paint,
          dashPeriod: dashPeriod,
        );
      case Sector():
        _drawCarrierBranch(
          canvas,
          size,
          object.circle!,
          object.startAngle!,
          object.sweep!,
          paint,
          closeToCenter: true,
          dashPeriod: dashPeriod,
        );
      case GeoCircle():
        final circle = object.circle;
        if (circle == null) {
          // A conic-valued kind that does not project to a centre and
          // radius — an ellipse, parabola, hyperbola or line pair.
          // Circles keep the arm below untouched, so their goldens do
          // not move.
          _drawConic(canvas, size, object.conic!, paint, dashPeriod);
          break;
        }
        final center = viewport.worldToScreen(circle.center);
        final radius = viewport.worldToScreenLength(circle.radius);
        if (radius > largeRadiusThreshold) {
          _drawLargeCircleRim(canvas, size, center, radius, paint, dashPeriod);
        } else if (dashPeriod > 0) {
          final rim = Path()
            ..addOval(Rect.fromCircle(center: center, radius: radius));
          canvas.drawPath(dashPath(rim, dashPeriod), paint);
        } else {
          canvas.drawCircle(center, radius, paint);
        }
      case GeoAngle():
        _drawAngleMarker(canvas, object, paint);
      case GeoPolygon():
        final path = _polygonPath(object);
        canvas.drawPath(
          dashPeriod > 0 ? dashPath(path, dashPeriod) : path,
          paint,
        );
      case GeoMeasurement() || GeoText():
        // Measurements and texts are pure text, painted by the label pass
        // — always with a value part (see labelText), so they never go
        // unpainted.
        break;
      case GeoLocus():
        _drawLocus(canvas, object, paint, dashPeriod);
    }
  }

  /// A locus paints one polyline per non-null sample run — gaps where
  /// the traced point was undefined split the stroke, and a length-1 run
  /// draws no ink (a stroke needs two ends). A gapless full-circle-host
  /// locus closes into a loop: its samples cover one full turn with no
  /// duplicated endpoint, so the closing edge is the painter's to add.
  /// Arc/Sector hosts sweep only their angular extent — an open stroke
  /// whose samples already include both endpoints.
  void _drawLocus(
    Canvas canvas,
    GeoLocus object,
    Paint paint,
    double dashPeriod,
  ) {
    final samples = object.samples!;
    final runs = <Path>[];
    Path? run;
    var runLength = 0;
    void endRun() {
      if (run != null && runLength > 1) {
        runs.add(run!);
      }
      run = null;
      runLength = 0;
    }

    for (final sample in samples) {
      if (sample == null) {
        endRun();
        continue;
      }
      final screen = viewport.worldToScreen(sample);
      if (run == null) {
        run = Path()..moveTo(screen.dx, screen.dy);
        runLength = 1;
      } else {
        run!.lineTo(screen.dx, screen.dy);
        runLength++;
      }
    }
    final gapless = runLength == samples.length;
    endRun();
    final host = object is Locus ? object.driver.curve : null;
    if (gapless &&
        runs.length == 1 &&
        host is GeoCircle &&
        host.angularExtent == null) {
      runs.single.close();
    }
    for (final path in runs) {
      canvas.drawPath(
        dashPeriod > 0 ? dashPath(path, dashPeriod) : path,
        paint,
      );
    }
  }

  /// Paints a conic with no centre-and-radius form — an ellipse,
  /// parabola, hyperbola or degenerate line pair — as one stroke per
  /// visible arc.
  ///
  /// Unlike an infinite line, a conic cannot be drawn by over-extending
  /// past the canvas: a hyperbola runs off in two directions and a
  /// parabola in one, so there is no "far enough".
  /// [ConicShape.polylines] does the clipping in world space instead,
  /// exactly, and returns only what the box can see. The box is grown by
  /// [_conicClipMargin] so an arc leaves the canvas *past* the edge
  /// rather than exactly on it — the canvas' own clip trims the
  /// overshoot, while a join sitting on the boundary would show its
  /// mitre.
  void _drawConic(
    Canvas canvas,
    Size size,
    ConicMatrix conic,
    Paint paint,
    double dashPeriod,
  ) {
    final box = viewport.visibleWorldBox(size, margin: _conicClipMargin);
    final strokes = ConicShape.of(conic).polylines(
      min: box.min,
      max: box.max,
      flatness: viewport.screenToWorldLength(_conicFlatness),
    );
    for (final stroke in strokes) {
      if (stroke.points.length < 2) {
        continue;
      }
      final first = viewport.worldToScreen(stroke.points.first);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final point in stroke.points.skip(1)) {
        final screen = viewport.worldToScreen(point);
        path.lineTo(screen.dx, screen.dy);
      }
      if (stroke.closed) {
        path.close();
      }
      canvas.drawPath(
        dashPeriod > 0 ? dashPath(path, dashPeriod) : path,
        paint,
      );
    }
  }

  /// The closed screen-space outline over a polygon's vertex loop —
  /// shared by the stroke, fill and halo passes.
  Path _polygonPath(GeoPolygon object) {
    final vertices = object.polygonVertices!;
    final first = viewport.worldToScreen(vertices.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final vertex in vertices.skip(1)) {
      final screen = viewport.worldToScreen(vertex);
      path.lineTo(screen.dx, screen.dy);
    }
    return path..close();
  }

  /// The world endpoints of a clipped line/ray's drawn stretch, or null
  /// for the full carrier. The `lineClip == 0` guard skips the helper's
  /// whole-construction scan for the common unclipped case.
  ({Vec2 start, Vec2 end})? _clipSpan(GeoLine object) =>
      object.attributes.lineClip == 0
      ? null
      : lineClipSpan(construction.objects, object);

  /// Equal-length tick marks (congruence notation): [count] short
  /// strokes perpendicular to the [from]→[to] stretch, centered as a
  /// group on its midpoint. Screen-space geometry in logical pixels, so
  /// zoom changes neither tick length nor spacing. Always solid — ticks
  /// are notation, not object style — and painted with the object's
  /// [paint], so the selection-halo pass widens them like the stroke.
  /// A degenerate (coincident-endpoint) stretch has no perpendicular
  /// and draws none.
  void _drawTickMarks(
    Canvas canvas,
    Offset from,
    Offset to,
    int count,
    Paint paint,
  ) {
    if (count <= 0) {
      return;
    }
    final along = to - from;
    final length = along.distance;
    if (length < 1e-9) {
      return;
    }
    const halfTick = 5.0;
    const spacing = 5.0;
    final unit = along / length;
    final normal = Offset(-unit.dy, unit.dx) * halfTick;
    final midpoint = (from + to) / 2;
    for (var i = 0; i < count; i++) {
      final center = midpoint + unit * ((i - (count - 1) / 2) * spacing);
      canvas.drawLine(center - normal, center + normal, paint);
    }
  }

  /// One straight stroke — solid via `drawLine`, or rebuilt as a dashed
  /// path when [dashPeriod] > 0.
  void _drawStraight(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
    double dashPeriod,
  ) {
    if (dashPeriod > 0) {
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
      canvas.drawPath(dashPath(path, dashPeriod), paint);
    } else {
      canvas.drawLine(from, to, paint);
    }
  }

  /// Paints the object's [labelText] at its [labelBaseTopLeft], shifted
  /// by the stored label offset (or the in-progress [labelDragPreview]).
  /// Like stroke widths, the font size and offset are in logical pixels
  /// and do not scale with zoom.
  void _drawLabel(Canvas canvas, GeoObject object, String text, Color color) {
    final preview = labelDragPreview;
    final offset = preview != null && preview.id == object.id
        ? preview.offset
        : Offset(object.attributes.labelDx, object.attributes.labelDy);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: object.attributes.labelFontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      labelBaseTopLeft(object, viewport, textPainter.size) + offset,
    );
    textPainter.dispose();
  }

  /// Draws a ray from its start extending far past the canvas on one side
  /// (the clip in [paint] trims it). Direction comes from the parent
  /// points, not the carrier — the carrier normalizes it away.
  void _drawRay(
    Canvas canvas,
    Size size,
    Ray object,
    Paint paint,
    double dashPeriod,
  ) {
    final start = viewport.worldToScreen(object.start!);
    final along = viewport.worldToScreen(object.throughPosition!) - start;
    final direction = along / along.distance;
    final reach = start.distance + size.width + size.height;
    _drawStraight(canvas, start, start + direction * reach, paint, dashPeriod);
  }

  /// Draws the branch of a circle carrier given by a start angle and a
  /// signed sweep — an arc, or with [closeToCenter] a sector's pie wedge
  /// (the two radii close the outline). World angles are counter-clockwise
  /// with y up; `worldToScreenAngle` folds in the view rotation and the
  /// y-flip. Sweeps only negate — the rotation term cancels in the
  /// difference.
  void _drawCarrierBranch(
    Canvas canvas,
    Size size,
    CircleEq circle,
    double startAngle,
    double sweep,
    Paint paint, {
    bool closeToCenter = false,
    double dashPeriod = 0,
  }) {
    final center = viewport.worldToScreen(circle.center);
    final radius = viewport.worldToScreenLength(circle.radius);
    if (radius > largeRadiusThreshold) {
      _drawLargeCarrierBranch(
        canvas,
        size,
        center,
        radius,
        startAngle,
        sweep,
        paint,
        closeToCenter: closeToCenter,
        dashPeriod: dashPeriod,
      );
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    final screenStart = viewport.worldToScreenAngle(startAngle);
    if (dashPeriod > 0) {
      // The same screen-angle mapping as the solid branch below; with
      // [closeToCenter] the path walks center → arc start → arc → back,
      // so the radii dash too.
      final path = Path();
      if (closeToCenter) {
        path.moveTo(center.dx, center.dy);
      }
      path.arcTo(rect, screenStart, -sweep, !closeToCenter);
      if (closeToCenter) {
        path.close();
      }
      canvas.drawPath(dashPath(path, dashPeriod), paint);
    } else {
      canvas.drawArc(rect, screenStart, -sweep, closeToCenter, paint);
    }
  }

  /// The rim of a screen-space circle too large for `drawCircle` (see
  /// [largeRadiusThreshold]): only the arc that can reach the canvas,
  /// sampled into a polyline so every vertex stays near the viewport.
  void _drawLargeCircleRim(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    Paint paint,
    double dashPeriod,
  ) {
    final window = visibleAngularWindow(
      center: center,
      radius: radius,
      size: size,
      margin: paint.strokeWidth + 1,
    );
    if (window == null) {
      return;
    }
    final path = Path();
    if (window.halfWidth >= math.pi - 1e-9) {
      addSampledArc(path, center, radius, 0, 2 * math.pi);
      path.close();
    } else {
      addSampledArc(
        path,
        center,
        radius,
        window.center - window.halfWidth,
        window.center + window.halfWidth,
      );
    }
    canvas.drawPath(dashPeriod > 0 ? dashPath(path, dashPeriod) : path, paint);
  }

  /// [_drawCarrierBranch]'s fallback past [largeRadiusThreshold]: the
  /// arc's stretches inside the visible window as sampled polylines,
  /// plus — for a sector — the two straight radii, whose far endpoints
  /// rasterize fine (same contract as infinite lines). The sector's
  /// outline becomes disjoint contours here, so its dash phase differs
  /// from the small-radius closed walk; invisible at these sizes.
  void _drawLargeCarrierBranch(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double startAngle,
    double sweep,
    Paint paint, {
    required bool closeToCenter,
    required double dashPeriod,
  }) {
    final window = visibleAngularWindow(
      center: center,
      radius: radius,
      size: size,
      margin: paint.strokeWidth + 1,
    );
    final screenStart = viewport.worldToScreenAngle(startAngle);
    final screenSweep = -sweep;
    final path = Path();
    if (window != null) {
      for (final piece in arcWindowOverlap(
        start: screenStart,
        sweep: screenSweep,
        window: window,
      )) {
        addSampledArc(path, center, radius, piece.start, piece.end);
      }
    }
    if (closeToCenter) {
      for (final angle in [screenStart, screenStart + screenSweep]) {
        final rim = center + Offset(math.cos(angle), math.sin(angle)) * radius;
        path
          ..moveTo(center.dx, center.dy)
          ..lineTo(rim.dx, rim.dy);
      }
    }
    canvas.drawPath(dashPeriod > 0 ? dashPath(path, dashPeriod) : path, paint);
  }

  /// Fills the interior of a fillable kind — a sector's pie wedge, an
  /// angle marker's wedge/square, a polygon's region, or a full circle's
  /// disc — with [fill], drawn under the stroke pass. Other kinds have no
  /// filled form and are skipped; an arc's fill shape is ambiguous
  /// (wedge? circular segment?), so arcs deliberately don't fill.
  void _drawFill(Canvas canvas, Size size, GeoObject object, Paint fill) {
    switch (object) {
      case Sector():
        final circle = object.circle!;
        final center = viewport.worldToScreen(circle.center);
        final radius = viewport.worldToScreenLength(circle.radius);
        if (radius > largeRadiusThreshold) {
          canvas.drawPath(
            _largeSectorFillPath(
              size,
              center,
              radius,
              viewport.worldToScreenAngle(object.startAngle!),
              -object.sweep!,
            ),
            fill,
          );
        } else {
          final rect = Rect.fromCircle(center: center, radius: radius);
          canvas.drawArc(
            rect,
            viewport.worldToScreenAngle(object.startAngle!),
            -object.sweep!,
            true,
            fill,
          );
        }
      case Arc():
        break;
      case GeoCircle():
        final circle = object.circle;
        if (circle == null) {
          // A conic with no centre and radius has no filled form to draw,
          // for the same reason an arc has none — only more so: a
          // hyperbola bounds nothing, a parabola's interior is unbounded,
          // and a clipped ellipse's would have to be closed along the
          // viewport edges. It is also the stance the hit-tester already
          // takes (Phase 119: a conic is a curve, not a region), and the
          // inspector withholds the fill row to match.
          break;
        }
        final center = viewport.worldToScreen(circle.center);
        final radius = viewport.worldToScreenLength(circle.radius);
        if (radius > largeRadiusThreshold) {
          _drawLargeCircleFill(canvas, size, center, radius, fill);
        } else {
          canvas.drawCircle(center, radius, fill);
        }
      case GeoAngle():
        _drawAngleMarker(canvas, object, fill);
      case GeoPolygon():
        canvas.drawPath(_polygonPath(object), fill);
      default:
        break;
    }
  }

  /// Fills the visible part of a disc too large for `drawCircle`: the
  /// whole canvas when the viewport sits inside the disc, nothing when
  /// it sits outside, otherwise the pie slice over the visible window —
  /// within the canvas clip that is exactly the disc's visible region
  /// (every canvas point of the disc lies inside the tangent cone the
  /// window comes from).
  void _drawLargeCircleFill(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    Paint fill,
  ) {
    final window = visibleAngularWindow(
      center: center,
      radius: radius,
      size: size,
      margin: 1,
    );
    if (window == null) {
      final dist = (size.center(Offset.zero) - center).distance;
      if (radius > dist) {
        canvas.drawRect(Offset.zero & size, fill);
      }
      return;
    }
    final path = Path();
    if (window.halfWidth >= math.pi - 1e-9) {
      addSampledArc(path, center, radius, 0, 2 * math.pi);
    } else {
      addSampledArc(
        path,
        center,
        radius,
        window.center - window.halfWidth,
        window.center + window.halfWidth,
      );
      path.lineTo(center.dx, center.dy);
    }
    path.close();
    canvas.drawPath(path, fill);
  }

  /// A huge sector's pie wedge as a fillable polygon: center → rim walk
  /// → close, with the rim sampled densely only inside the visible
  /// window and bridged by straight chords elsewhere. Chords stay inside
  /// the disc and every on-screen wedge point has its rim angle inside
  /// the window, so within the canvas clip the polygon fills the same
  /// pixels as the true wedge.
  Path _largeSectorFillPath(
    Size size,
    Offset center,
    double radius,
    double screenStart,
    double screenSweep,
  ) {
    final a = screenSweep >= 0 ? screenStart : screenStart + screenSweep;
    final b = a + screenSweep.abs();
    final window = visibleAngularWindow(
      center: center,
      radius: radius,
      size: size,
      margin: 1,
    );
    Offset rim(double angle) =>
        center + Offset(math.cos(angle), math.sin(angle)) * radius;
    final path = Path()..moveTo(center.dx, center.dy);
    final start = rim(a);
    path.lineTo(start.dx, start.dy);
    if (window != null) {
      for (final piece in arcWindowOverlap(
        start: a,
        sweep: b - a,
        window: window,
      )) {
        addSampledArc(
          path,
          center,
          radius,
          piece.start,
          piece.end,
          startWithMove: false,
        );
      }
    }
    final end = rim(b);
    path.lineTo(end.dx, end.dy);
    path.close();
    return path;
  }

  /// Draws an angle as a small wedge at its vertex, opening from the
  /// start direction through the sweep (angles negate on screen, as in
  /// [_drawCarrierBranch]). The radius comes from
  /// `attributes.angleMarkerRadius` and is fixed in screen space. A sweep
  /// of exactly π/2 — right angles from perpendicular constructions are
  /// fp-exact — draws the conventional square instead of the arc.
  ///
  /// [paint]'s style decides outline vs interior: the stroke pass and the
  /// fill pass share this geometry.
  void _drawAngleMarker(Canvas canvas, GeoAngle object, Paint paint) {
    final angle = object.angle!;
    if ((angle.sweep - math.pi / 2).abs() <= defaultEpsilon) {
      canvas.drawPath(_rightAngleSquarePath(object), paint);
      return;
    }
    final rect = Rect.fromCircle(
      center: viewport.worldToScreen(angle.vertex),
      radius: object.attributes.angleMarkerRadius,
    );
    canvas.drawArc(
      rect,
      viewport.worldToScreenAngle(angle.startDirection.angle),
      -angle.sweep,
      true,
      paint,
    );
  }

  /// The right-angle marker: a closed square with corners at the vertex,
  /// at 0.7 × the marker radius along each arm, and at their vector sum.
  Path _rightAngleSquarePath(GeoAngle object) {
    final angle = object.angle!;
    final vertex = viewport.worldToScreen(angle.vertex);
    final side = 0.7 * object.attributes.angleMarkerRadius;
    final d1 = angle.startDirection;
    final d2 = d1.rotated(angle.sweep);
    // World directions rotate with the view, then the screen flips y.
    Offset corner(Vec2 d) => vertex + viewport.worldToScreenDirection(d) * side;
    final c1 = corner(d1);
    final c12 = corner(d1 + d2);
    final c2 = corner(d2);
    return Path()
      ..moveTo(vertex.dx, vertex.dy)
      ..lineTo(c1.dx, c1.dy)
      ..lineTo(c12.dx, c12.dy)
      ..lineTo(c2.dx, c2.dy)
      ..close();
  }

  /// Draws the visible stretch of an infinite line by extending far past
  /// the canvas on both sides (the clip in [paint] trims it).
  void _drawInfiniteLine(
    Canvas canvas,
    Size size,
    GeoLine object,
    Paint paint,
    double dashPeriod,
  ) {
    final line = object.line!;
    final anchor = viewport.worldToScreen(line.pointOnLine);
    // Screen-space direction; y-flip is handled by the transform.
    final along =
        viewport.worldToScreen(line.pointOnLine + line.direction) - anchor;
    final direction = along / along.distance;
    // Long enough to cross the whole canvas from wherever the anchor sits
    // (the anchor is the line's closest point to the *world* origin and
    // can be far off-screen when panned/zoomed away).
    final reach = anchor.distance + size.width + size.height;
    _drawStraight(
      canvas,
      anchor - direction * reach,
      anchor + direction * reach,
      paint,
      dashPeriod,
    );
  }

  @override
  bool shouldRepaint(GeometryPainter oldDelegate) =>
      !identical(oldDelegate.construction, construction) ||
      oldDelegate.revision != revision ||
      oldDelegate.viewport.state != viewport.state ||
      oldDelegate.defaultColor != defaultColor ||
      oldDelegate.selectionColor != selectionColor ||
      !setEquals(oldDelegate.selectedIds, selectedIds) ||
      !listEquals(oldDelegate.previewMarkers, previewMarkers) ||
      !setEquals(oldDelegate.previewObjectIds, previewObjectIds) ||
      oldDelegate.labelDragPreview != labelDragPreview ||
      oldDelegate.showHidden != showHidden ||
      oldDelegate.showAxes != showAxes ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.axisColor != axisColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.absoluteColor != absoluteColor ||
      oldDelegate.absoluteOutsideColor != absoluteOutsideColor;
}
