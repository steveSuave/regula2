import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// A user-placed point — the only directly mutable object in the graph.
///
/// Everything else derives from free points; dragging one and recomputing
/// its transitive dependents is the app's core interaction.
///
/// Migrated (Phase 107): stores a [ProjPoint]. Ordinary mutation stores
/// real finite lifts (`[x, y, 1]` with `w` exactly one), so [position]
/// reads the chart coordinates back exactly — total at any magnitude —
/// and a free point is always defined. The one exception is a tracing
/// pass's complex detour (Phase 115, [tracedPosition]), which holds a
/// complex position strictly *inside* one `recomputeAlongPath` call:
/// every pass ends back on a real parameter (bitwise-real coordinates),
/// so nothing outside the pass ever observes a complex free point.
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

  /// The complex-detour mutation (Phase 115): stores a generally complex
  /// homogeneous position while a tracing pass walks the drag parameter
  /// off the real axis. Only `Construction.recomputeAlongPath` may call
  /// this, with `DragPath.evaluate`'s shape (`w` exactly one, so
  /// [position]'s real-part read stays chart-consistent), and it must
  /// leave the point real before the pass returns or throws.
  set tracedPosition(ProjPoint value) => _projPoint = value;

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Free points are roots: nothing to derive.
  }
}
