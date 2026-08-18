import 'dart:math' as math;
import 'dart:ui';

import '../../application/providers/viewport_provider.dart';
import '../../domain/math/vec2.dart';

/// World↔screen transforms for the canvas, built from a [ViewportState]
/// (never duplicating its data — see the Phase 4 STATUS note).
///
/// Named `CanvasViewport` because Flutter already ships a `Viewport`
/// widget and the two would collide in every file importing
/// `flutter/widgets.dart`.
///
/// Conventions:
/// - World coordinates are y-up (the geometry convention); screen
///   coordinates are y-down (the Flutter convention). This class is the
///   only place the flip happens — painter and hit tester stay flip-free.
/// - `state.pan` is the world-space point at the canvas origin (top-left);
///   `state.scale` is screen pixels per world unit.
/// - `state.rotation` rotates the content about the canvas origin,
///   positive = counterclockwise on screen (Phase 43). The rotation is
///   applied in the y-up frame *before* the flip, so `pan` keeps its
///   meaning at any angle (the origin is the rotation's fixed point).
///   Rotation preserves lengths, so the length helpers carry no term.
class CanvasViewport {
  const CanvasViewport(this.state);

  /// Zoom bounds, in screen pixels per world unit. Wide enough that no
  /// reasonable construction hits them; tight enough that float precision
  /// in the transforms never becomes visible.
  ///
  /// [maxScale] was 50 through Phase 126, which was ample for Euclidean
  /// documents — they are drawn at world coordinates of order tens to
  /// hundreds — and far too tight for a **hyperbolic** one, whose entire
  /// plane is the unit disc: at 50 the whole geometry was 100 pixels
  /// across and could not be worked in. Raised to 2000, which frames the
  /// disc in a typical window at roughly 300 and leaves an order of
  /// magnitude to zoom in with.
  ///
  /// The bound is not a precision cliff and never was. `worldToScreen`
  /// subtracts the pan *before* scaling, so the significant digits are
  /// spent in `world − pan` — a difference bounded by the visible window
  /// in world units, which shrinks as the scale grows. What the ceiling
  /// really guards is the *view*: a gesture that can zoom without limit
  /// loses the figure.
  static const double minScale = 0.05;
  static const double maxScale = 2000;

  /// The ceiling a **fit** may reach, which is deliberately lower than
  /// [maxScale] and used to be the same number.
  ///
  /// Raising [maxScale] for the hyperbolic disc moved six goldens, and
  /// that was the useful part: it showed the two limits were answering
  /// different questions through one constant. "How far may the user
  /// zoom?" is about the view, and a hyperbolic document needs a great
  /// deal of it. "How far may a fit blow a tiny figure up?" is about
  /// taste — a three-point construction one world unit across should not
  /// fill the window at 2000× — and its right answer did not change.
  /// `fittedToAbsolute` takes [maxScale], because the absolute is not a
  /// figure that happens to be small: it is the whole plane.
  static const double maxFitScale = 50;

  final ViewportState state;

  /// The state after multiplying scale by [factor] (> 1 zooms in) while
  /// keeping the world point under [focal] (screen coordinates) exactly
  /// there — the cursor pins the content. Scale is clamped to
  /// [minScale]..[maxScale]; at a bound the state returns unchanged.
  ViewportState zoomedAbout(Offset focal, double factor) {
    final newScale = (state.scale * factor)
        .clamp(minScale, maxScale)
        .toDouble();
    if (newScale == state.scale) {
      return state;
    }
    return pinning(
      world: screenToWorld(focal),
      focal: focal,
      scale: newScale,
      rotation: state.rotation,
    );
  }

  /// The state after shifting the content by [delta] screen pixels
  /// (y-down, like a pointer delta): content follows a rightward/downward
  /// delta, so the world point at the canvas origin moves the other way.
  /// Backs viewport nudging; scale and rotation are untouched.
  ViewportState pannedByScreen(Offset delta) => ViewportState(
    // The new origin world point is whatever currently sits delta
    // *before* the origin — valid at any rotation, since
    // screenToWorld already folds the angle in.
    pan: screenToWorld(-delta),
    scale: state.scale,
    rotation: state.rotation,
  );

  /// The state with [scale] (clamped) and [rotation] whose pan puts the
  /// [world] point at the [focal] screen point — the shared solve behind
  /// scroll zoom and the pinch/pan gesture, where the anchor world point
  /// must track a moving focal.
  static ViewportState pinning({
    required Vec2 world,
    required Offset focal,
    required double scale,
    double rotation = 0,
  }) {
    final clamped = scale.clamp(minScale, maxScale).toDouble();
    // Solve screenToWorld(focal) == world for pan: pan = world − R(−θ)·f,
    // where f is the focal in y-up world units.
    final fx = focal.dx / clamped;
    final fy = -focal.dy / clamped;
    final c = math.cos(rotation);
    final s = math.sin(rotation);
    return ViewportState(
      pan: Vec2(world.x - (fx * c + fy * s), world.y - (fy * c - fx * s)),
      scale: clamped,
      rotation: rotation,
    );
  }

  Offset worldToScreen(Vec2 world) {
    final dx = world.x - state.pan.x;
    final dy = world.y - state.pan.y;
    final c = math.cos(state.rotation);
    final s = math.sin(state.rotation);
    // Rotate by +θ in the y-up frame, then scale and flip. At θ = 0 the
    // products reduce exactly to the pre-rotation transform.
    return Offset(
      (dx * c - dy * s) * state.scale,
      -(dx * s + dy * c) * state.scale,
    );
  }

  Vec2 screenToWorld(Offset screen) {
    final rx = screen.dx / state.scale;
    final ry = -screen.dy / state.scale;
    final c = math.cos(state.rotation);
    final s = math.sin(state.rotation);
    // Unflip and unscale, then rotate by −θ back into world axes.
    return Vec2(state.pan.x + rx * c + ry * s, state.pan.y + ry * c - rx * s);
  }

  /// Screen-space polar angle of the world-space polar angle
  /// [worldAngle]: the view rotation composes in, then the y-flip negates
  /// — `worldToScreen(c + r·(cos α, sin α))` lands at screen angle
  /// `worldToScreenAngle(α)` from `worldToScreen(c)`. Angle *sweeps*
  /// (differences) only negate; the rotation term cancels.
  double worldToScreenAngle(double worldAngle) =>
      -(worldAngle + state.rotation);

  /// Screen-space image of the world-space direction [direction]
  /// (rotated, y-flipped, *not* scaled — a unit world direction stays a
  /// unit screen direction).
  Offset worldToScreenDirection(Vec2 direction) {
    final c = math.cos(state.rotation);
    final s = math.sin(state.rotation);
    return Offset(
      direction.x * c - direction.y * s,
      -(direction.x * s + direction.y * c),
    );
  }

  /// Screen pixels covered by [worldLength] world units.
  double worldToScreenLength(double worldLength) => worldLength * state.scale;

  /// World units covered by [screenLength] screen pixels — e.g. the 8 px
  /// hit-test threshold expressed in world units.
  double screenToWorldLength(double screenLength) => screenLength / state.scale;

  /// Axis-aligned world bounds enclosing a [canvasSize] canvas, grown by
  /// [margin] screen pixels on every side.
  ///
  /// The box of the four corners' world images: under a nonzero
  /// [ViewportState.rotation] the visible region is a rotated rectangle,
  /// so this is a superset rather than the region itself. That is the
  /// right side to err on — it is a clip bound for unbounded curves, and
  /// the canvas trims whatever it over-includes.
  ({Vec2 min, Vec2 max}) visibleWorldBox(Size canvasSize, {double margin = 0}) {
    final corners = [
      screenToWorld(Offset(-margin, -margin)),
      screenToWorld(Offset(canvasSize.width + margin, -margin)),
      screenToWorld(Offset(-margin, canvasSize.height + margin)),
      screenToWorld(
        Offset(canvasSize.width + margin, canvasSize.height + margin),
      ),
    ];
    var minX = corners.first.x, maxX = corners.first.x;
    var minY = corners.first.y, maxY = corners.first.y;
    for (final corner in corners.skip(1)) {
      minX = math.min(minX, corner.x);
      maxX = math.max(maxX, corner.x);
      minY = math.min(minY, corner.y);
      maxY = math.max(maxY, corner.y);
    }
    return (min: Vec2(minX, minY), max: Vec2(maxX, maxY));
  }
}
