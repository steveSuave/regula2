import 'dart:math' as math;
import 'dart:ui';

import '../../application/providers/viewport_provider.dart';
import '../../domain/construction/document_kernel.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/math/vec2.dart';
import '../../domain/projective/conic_matrix.dart';
import '../../domain/projective/conic_shape.dart';
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
      // A Cayley–Klein circle is a conic bitangent to the absolute, so
      // it projects to no centre and radius (Phase 126) and is framed by
      // its conic's own support intervals instead (Phase 130): the box
      // in the *view* frame is the extent between the tangent lines
      // normal to each view axis, which is one call per axis with the
      // axis as the normal — no rotating of the conic, and exact.
      //
      // Null for anything unbounded, which is the same answer this
      // function already gives a line: a hyperbola has two real tangents
      // normal to a direction and runs out between them, so a box built
      // on them would frame a curve that is not there.
      case GeoCircle(:final conic?):
        final box = _conicViewBox(conic, cos, sin);
        if (box != null) {
          extend(box.min.x, box.min.y);
          extend(box.max.x, box.max.y);
        }
      case GeoCircle():
      // isDefined held above, so the remaining null-payload cases are
      // unreachable; Dart's exhaustiveness checker still wants them.
      case GeoPoint():
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

/// [conic]'s bounding box in the view frame — the frame rotated so that
/// `(cos, sin)` is its x axis — or null when the conic has no bounded ink
/// to frame.
///
/// One [ConicShape.extentAlong] per view axis, with the axis as the
/// line's normal, so the rotation costs a different argument rather than
/// a transformed conic.
({Vec2 min, Vec2 max})? _conicViewBox(
  ConicMatrix conic,
  double cos,
  double sin,
) {
  final shape = ConicShape.of(conic);
  final across = shape.extentAlong(cos, sin);
  final along = shape.extentAlong(-sin, cos);
  if (across == null || along == null) {
    return null;
  }
  return (min: Vec2(across.min, along.min), max: Vec2(across.max, along.max));
}

/// The viewport framing the Cayley–Klein absolute — the unit disc — in
/// [canvasSize], or null when the document's geometry has no real
/// absolute to frame (Phase 126).
///
/// A hyperbolic document lives *inside the unit circle*, and the app's
/// default scale is one pixel per world unit, so on entering hyperbolic
/// geometry the entire plane is a two-pixel dot at the origin while the
/// figure sits hundreds of units outside it — outside the plane, where
/// angles collapse to zero and nothing means what it says. Framing the
/// disc is how the user is shown where the geometry is; without it the
/// mode is technically present and practically invisible.
///
/// Deliberately frames *only* the absolute, not the union of the absolute
/// and the construction. A figure built in Euclidean world coordinates is
/// typically hundreds of units across, and fitting both would put the
/// plane back in the corner as a dot.
ViewportState? fittedToAbsolute(
  FundamentalConic metric,
  Size canvasSize, {
  double marginPx = fitMarginPx,
  double rotation = 0,
}) {
  if (metric != FundamentalConic.hyperbolic) {
    return null;
  }
  final usable = math.min(
    canvasSize.width - 2 * marginPx,
    canvasSize.height - 2 * marginPx,
  );
  if (usable <= 0) {
    return null;
  }
  // The absolute is the unit circle about the world origin, so the scale
  // that fits it is half the usable extent — and the pan has to be
  // *solved*, like every other fit: `ViewportState.pan` is the world
  // point at screen (0, 0), not the one at the canvas centre.
  return CanvasViewport.pinning(
    world: Vec2.zero,
    focal: Offset(canvasSize.width / 2, canvasSize.height / 2),
    scale: usable / 2,
    rotation: rotation,
  );
}

/// The viewport framing every visible object centered in [canvasSize]
/// with [marginPx] to spare, or null when there is nothing to frame.
///
/// [rotation] is the view angle the framing keeps (Phase 61 — fit
/// frames, the compass levels): extents are measured in the rotated
/// view frame, so the content fits at that angle. Scale is clamped to
/// [CanvasViewport.minScale]..[CanvasViewport.maxFitScale]; a zero-size
/// extent (a single
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
            .clamp(CanvasViewport.minScale, CanvasViewport.maxFitScale)
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
