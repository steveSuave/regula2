import '../construction/construction.dart';
import '../construction/document_kernel.dart';
import '../construction/geometry_change.dart';
import 'command.dart';

/// Changes the document's geometry — the Cayley–Klein absolute every
/// metric recompute is founded on.
///
/// A geometry switch touches every derived object in the construction, so
/// it is an edit and belongs in the undo history like any other. What
/// makes it unlike the others is that its *effect* is not recoverable from
/// its inputs: `Construction.switchKernel` re-points each intersection
/// point at the crossing nearest where it was, by chordal match, and
/// nearest-match is not invertible. Running the match backwards can land a
/// point somewhere it never was, and a point that had no position at the
/// switch was never matched in either direction.
///
/// So the command **records** what the switch decided ([change]) and
/// replays those addresses verbatim on undo and redo. The first [apply]
/// performs the switch; every later one restores the recorded end state.
/// That also makes redo cheap and exact rather than a second guess at the
/// same question.
///
/// [change] is null until the command has been applied once, and is what
/// the UI reads to tell the user which points were re-addressed — the same
/// obligation the decoder's `repairedIntersections` carries.
class SetGeometryCommand implements Command {
  SetGeometryCommand(this.kernel);

  /// The geometry to switch to.
  final DocumentKernel kernel;

  GeometryChange? _change;

  /// What the switch did, or null before it has run once.
  GeometryChange? get change => _change;

  @override
  void apply(Construction construction) {
    final recorded = _change;
    if (recorded == null) {
      _change = construction.switchKernel(kernel);
      return;
    }
    construction.replayKernel(recorded.to, recorded.addressesAfter);
  }

  @override
  void undo(Construction construction) {
    final recorded = _change;
    if (recorded == null) {
      throw StateError('SetGeometryCommand.undo before apply');
    }
    construction.replayKernel(recorded.from, recorded.addressesBefore);
  }
}
