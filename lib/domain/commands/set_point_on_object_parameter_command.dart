import '../construction/construction.dart';
import 'command.dart';
import 'move_free_point_command.dart';

/// Slides a constrained point (`PointOnObject`) along its host curve by
/// re-setting its analytic parameter.
///
/// One slide-drag gesture emits exactly one of these, capturing the
/// gesture's start ([from]) and end ([to]) parameters — never one per
/// frame (per-frame motion is the drag-preview carve-out; see CLAUDE.md).
/// Both endpoints are stored so the command can replay in either
/// direction, float-exact.
///
/// [branchChanges] carries the gesture's branch adoptions exactly like
/// `MoveFreePointCommand.branchChanges` (Phase 116b): a traced slide
/// across a degeneracy can leave a downstream `IntersectionPoint` on the
/// other canonical branch than it started, and the command replays the
/// re-pointings alongside the slide so undo/redo restore identity with
/// the parameter.
class SetPointOnObjectParameterCommand implements Command {
  SetPointOnObjectParameterCommand({
    required this.pointId,
    required this.from,
    required this.to,
    this.branchChanges = const [],
  });

  final String pointId;
  final double from;
  final double to;
  final List<BranchChange> branchChanges;

  // Branches first, like MoveFreePointCommand: the closing parameter set
  // recomputes everything downstream over the final indices.
  @override
  void apply(Construction construction) {
    for (final change in branchChanges) {
      construction.setIntersectionBranch(change.id, change.to);
    }
    construction.setPointOnObjectParameter(pointId, to);
  }

  @override
  void undo(Construction construction) {
    for (final change in branchChanges) {
      construction.setIntersectionBranch(change.id, change.from);
    }
    construction.setPointOnObjectParameter(pointId, from);
  }
}
