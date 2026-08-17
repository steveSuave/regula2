import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/math/vec2.dart';

part 'viewport_provider.g.dart';

/// Immutable pan/zoom/rotation state: [pan] is the world-space point at
/// the canvas origin, [scale] is screen pixels per world unit, [rotation]
/// is the view angle in radians — positive turns the content
/// counterclockwise on screen.
///
/// Rotation is pure view state (Phase 43): object coordinates are never
/// touched, and rotation preserves lengths, so hit thresholds and snap
/// radii need no rotation term.
///
/// This is the *state* only. World↔screen transforms (which need screen
/// sizes, i.e. Flutter types) live in the presentation layer's `Viewport`
/// (Phase 5), which is built from this.
class ViewportState {
  const ViewportState({
    this.pan = Vec2.zero,
    this.scale = 1,
    this.rotation = 0,
  });

  final Vec2 pan;
  final double scale;
  final double rotation;

  @override
  bool operator ==(Object other) =>
      other is ViewportState &&
      other.pan == pan &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(pan, scale, rotation);

  @override
  String toString() =>
      'ViewportState(pan: $pan, scale: $scale, rotation: $rotation)';
}

/// Pan/zoom state for the canvas. Not undoable, not persisted with the
/// construction's undo history (the save format snapshots it separately).
///
/// Zoom-about-a-focal-point and scale clamping are gesture concerns,
/// decided where the gestures land (Phases 5 and 8) — this notifier only
/// stores state.
@Riverpod(keepAlive: true, name: 'viewportProvider')
class ViewportNotifier extends _$ViewportNotifier {
  @override
  ViewportState build() => const ViewportState();

  /// Shifts the pan by [delta] (world units).
  void panBy(Vec2 delta) => state = ViewportState(
    pan: state.pan + delta,
    scale: state.scale,
    rotation: state.rotation,
  );

  /// Multiplies the scale by [factor] (> 1 zooms in).
  void zoomBy(double factor) => state = ViewportState(
    pan: state.pan,
    scale: state.scale * factor,
    rotation: state.rotation,
  );

  void set(ViewportState viewport) => state = viewport;

  /// Back to origin at 100 %.
  void reset() => state = const ViewportState();
}
