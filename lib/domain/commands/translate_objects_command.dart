import '../construction/construction.dart';
import '../construction/objects/free_point.dart';
import '../math/vec2.dart';
import 'command.dart';

/// Rigidly translates a set of free points by one [delta] in a single
/// undo step.
///
/// This is how dragging a *derived* object works: grab a circle's rim and
/// its free-point ancestors all shift by the drag delta, so the circle
/// moves as a whole. Like a free-point drag, one gesture emits exactly one
/// of these.
///
/// [apply] snapshots the pre-move positions and undo restores them
/// verbatim — subtracting [delta] again would be off by an ulp in floating
/// point, violating the exact-round-trip contract of [Command].
class TranslateObjectsCommand implements Command {
  TranslateObjectsCommand({required this.pointIds, required this.delta});

  /// Ids of the [FreePoint]s to move. Duplicates would translate twice;
  /// callers pass a deduplicated ancestor set.
  final List<String> pointIds;

  final Vec2 delta;

  final Map<String, Vec2> _before = {};

  @override
  void apply(Construction construction) {
    // Validate everything up front so a bad id cannot leave the set
    // half-translated.
    final points = [
      for (final id in pointIds)
        switch (construction.byId(id)) {
          final FreePoint p => p,
          _ => throw ArgumentError(
            '$id is not a FreePoint in this construction',
          ),
        },
    ];
    _before.clear();
    for (final point in points) {
      _before[point.id] = point.position;
      construction.moveFreePoint(point.id, point.position + delta);
    }
  }

  @override
  void undo(Construction construction) {
    for (final id in pointIds) {
      construction.moveFreePoint(id, _before[id]!);
    }
  }
}
