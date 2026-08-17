import 'dart:math' as math;
import 'dart:ui';

import '../../application/providers/viewport_provider.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/math/vec2.dart';
import 'canvas_viewport.dart';

/// Screen pixels kept free around a fitted construction.
const double fitMarginPx = 48;

/// Axis-aligned bounds of the drawable extent of [objects] in the *view
/// frame*: the y-up world frame rotated by [rotation] (the viewport's
/// angle, Phase 61), so the box is screen-aligned at that view angle. At
/// the default `rotation` 0 these are plain world bounds. Null when
/// nothing contributes.
///
/// Hidden and undefined objects don't count — fit frames what the user
/// sees. Per kind: points contribute their position, circles their full
/// carrier disc (arcs/sectors are framed a little loosely, by design —
/// their carrier box is stable while the branch swings during drags;
/// a disc is rotation-invariant, so it rotates as its center ± radius),
/// angles their vertex (the marker is screen-sized), and lines nothing:
/// their carrier is unbounded, and their defining points are objects in
/// the construction contributing on their own.
({Vec2 min, Vec2 max})? visibleWorldBounds(
  Iterable<GeoObject> objects, {
  double rotation = 0,
}) {
  final cos = math.cos(rotation);
  final sin = math.sin(rotation);
  double? minX, minY, maxX, maxY;
  // Extends the box by a point already in the view frame.
  void extend(double x, double y) {
    minX = math.min(minX ?? x, x);
    minY = math.min(minY ?? y, y);
    maxX = math.max(maxX ?? x, x);
    maxY = math.max(maxY ?? y, y);
  }

  // Rotates a world point by +rotation into the view frame — the same
  // R(+θ) `worldToScreen` applies before the flip — then extends.
  void include(double wx, double wy) =>
      extend(wx * cos - wy * sin, wx * sin + wy * cos);

  for (final object in objects) {
    if (!object.attributes.visible || !object.isDefined) {
      continue;
    }
    switch (object) {
      case GeoPoint(:final position?):
        include(position.x, position.y);
      case GeoCircle(:final circle?):
        // A disc is rotation-invariant: rotate the center, then pad by
        // the radius in the view frame (rotating box *corners* would
        // misplace the box at any non-cardinal angle).
        final cx = circle.center.x * cos - circle.center.y * sin;
        final cy = circle.center.x * sin + circle.center.y * cos;
        extend(cx - circle.radius, cy - circle.radius);
        extend(cx + circle.radius, cy + circle.radius);
      case GeoAngle(:final angle?):
        include(angle.vertex.x, angle.vertex.y);
      case GeoPolygon(:final polygonVertices?):
        for (final vertex in polygonVertices) {
          include(vertex.x, vertex.y);
        }
      case GeoMeasurement(:final anchor?):
        include(anchor.x, anchor.y);
      case GeoText(:final anchor):
        include(anchor.x, anchor.y);
      // Core samples, not the full trace: a line-host locus sweeps its
      // whole carrier and a diverging arm reaches astronomically far —
      // fitting on it would zoom the figure down to a dot.
      case GeoLocus(:final coreSamples?):
        for (final sample in coreSamples) {
          include(sample.x, sample.y);
        }
      case GeoLine():
        break;
      // isDefined held above, so the null-payload cases are unreachable;
      // Dart's exhaustiveness checker still wants them spelled out.
      case GeoPoint():
      case GeoCircle():
      case GeoAngle():
      case GeoPolygon():
      case GeoMeasurement():
      case GeoLocus():
        break;
    }
  }
  final left = minX;
  if (left == null) {
    return null;
  }
  return (min: Vec2(left, minY!), max: Vec2(maxX!, maxY!));
}

/// The viewport framing every visible object centered in [canvasSize]
/// with [marginPx] to spare, or null when there is nothing to frame.
///
/// [rotation] is the view angle the framing keeps (Phase 61 — fit
/// frames, the compass levels): extents are measured in the rotated
/// view frame, so the content fits at that angle. Scale is clamped to
/// [CanvasViewport.minScale]..[maxScale]; a zero-size extent (a single
/// point) centers at 100 % instead of zooming to the clamp.
ViewportState? fittedViewport(
  Iterable<GeoObject> objects,
  Size canvasSize, {
  double marginPx = fitMarginPx,
  double rotation = 0,
}) {
  final bounds = visibleWorldBounds(objects, rotation: rotation);
  if (bounds == null || canvasSize.shortestSide <= 0) {
    return null;
  }
  final width = bounds.max.x - bounds.min.x;
  final height = bounds.max.y - bounds.min.y;
  final availableWidth = math.max(1.0, canvasSize.width - 2 * marginPx);
  final availableHeight = math.max(1.0, canvasSize.height - 2 * marginPx);
  final scale = (width <= 0 && height <= 0)
      ? 1.0
      : math
            .min(
              width > 0 ? availableWidth / width : double.infinity,
              height > 0 ? availableHeight / height : double.infinity,
            )
            .clamp(CanvasViewport.minScale, CanvasViewport.maxScale)
            .toDouble();
  // The bounds center, rotated by −rotation back into world axes so
  // `pinning` (which solves in world coordinates) can put it at the
  // canvas center. At rotation 0 this reduces exactly to the old
  // direct pan solve.
  final cos = math.cos(rotation);
  final sin = math.sin(rotation);
  final viewCenterX = (bounds.min.x + bounds.max.x) / 2;
  final viewCenterY = (bounds.min.y + bounds.max.y) / 2;
  return CanvasViewport.pinning(
    world: Vec2(
      viewCenterX * cos + viewCenterY * sin,
      viewCenterY * cos - viewCenterX * sin,
    ),
    focal: Offset(canvasSize.width / 2, canvasSize.height / 2),
    scale: scale,
    rotation: rotation,
  );
}
