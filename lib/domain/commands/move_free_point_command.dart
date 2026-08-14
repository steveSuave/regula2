import '../construction/construction.dart';
import '../math/vec2.dart';
import 'command.dart';

/// One intersection point re-pointed by a traced drag: the gesture ended
/// with the trace on the other canonical branch than it started (see
/// [MoveFreePointCommand.branchChanges]).
typedef BranchChange = ({String id, int from, int to});

/// Moves a free point from one position to another.
///
/// One drag gesture emits exactly one of these, capturing the gesture's
/// start ([from]) and end ([to]) — never one per frame (per-frame motion
/// is the drag-preview carve-out; see CLAUDE.md). Both endpoints are
/// stored so the command can replay in either direction.
///
/// [branchChanges] carries the gesture's branch adoptions (Phase 116): a
/// traced drag across a degeneracy can leave an affected
/// `IntersectionPoint` on the other canonical branch than it started —
/// the trace held the *root* still while the canonical ordering flipped
/// underneath it. The command replays those re-pointings alongside the
/// move so undo/redo restore branch identity exactly, not just the
/// position. Empty for static drags and for traced drags that crossed
/// nothing.
class MoveFreePointCommand implements Command {
  MoveFreePointCommand({
    required this.pointId,
    required this.from,
    required this.to,
    this.branchChanges = const [],
  });

  final String pointId;
  final Vec2 from;
  final Vec2 to;
  final List<BranchChange> branchChanges;

  // Branches first, so the closing moveFreePoint recomputes everything
  // downstream of the dragged point in one topological pass over the
  // final indices (every changed intersection depends on the point —
  // that is how the trace reached it).
  @override
  void apply(Construction construction) {
    for (final change in branchChanges) {
      construction.setIntersectionBranch(change.id, change.to);
    }
    construction.moveFreePoint(pointId, to);
  }

  @override
  void undo(Construction construction) {
    for (final change in branchChanges) {
      construction.setIntersectionBranch(change.id, change.from);
    }
    construction.moveFreePoint(pointId, from);
  }
}
