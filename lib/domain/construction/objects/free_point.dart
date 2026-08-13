import '../../math/vec2.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// A user-placed point — the only directly mutable object in the graph.
///
/// Everything else derives from free points; dragging one and recomputing
/// its transitive dependents is the app's core interaction.
///
/// Migrated (Phase 107): stores a [ProjPoint]. Until the tracing engine
/// complexifies drags (Phase 113+), mutation only ever stores real finite
/// lifts (`[x, y, 1]` with `w` exactly one), so [position] reads the chart
/// coordinates back exactly — total at any magnitude — and a free point is
/// always defined.
class FreePoint extends GeoPoint {
  FreePoint({required super.id, required Vec2 position, super.attributes})
    : _projPoint = ProjPoint.lift(position);

  ProjPoint _projPoint;

  @override
  ProjPoint get projPoint => _projPoint;

  @override
  Vec2 get position => Vec2(_projPoint.x.re, _projPoint.y.re);

  /// Mutated only by `Construction.moveFreePoint` (via commands) so every
  /// move goes through dependent recomputation.
  set position(Vec2 value) => _projPoint = ProjPoint.lift(value);

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute() {
    // Free points are roots: nothing to derive.
  }
}
