import '../construction/objects/fixed_angle_line.dart';
import '../math/rational.dart';
import 'point_and_line_tool.dart';
import 'tool.dart';

/// Collects a point and a reference line — in either order, the
/// `PointAndLineTool` flow — and emits the `FixedAngleLine` through the
/// point at the stated [turn] from the line (Phase 184, the app-facing
/// half of PLAN §"The constants stack"). The turn comes from a dialog
/// before the tool activates, in degrees, and arrives here already
/// reduced to the carrier's residue: a rational in units of π in
/// `[0, 1)`.
///
/// A dedicated class rather than a closure over the turn for the reason
/// `FixedRadiusCircleTool` gives: the toolbar keys its highlights and
/// its availability rows on tool identity.
///
/// Euclidean-only, like the object it builds: a rational turn of π is a
/// statement in the chart's angle measure, so in a Cayley–Klein
/// document every input is refused outright — a disabled toolbar row
/// says why, and the refusal here is the same fact enforced where the
/// gesture arrives (the `MultiPointTool.availableUnder` arrangement, for
/// a tool whose base class has no such hook).
class FixedAngleLineTool extends PointAndLineTool {
  /// Throws [ArgumentError] on a turn outside `[0, 1)` — the object's
  /// own contract, checked at the tool so a mis-built dialog fails when
  /// the tool is picked and not on the second tap.
  FixedAngleLineTool({required super.newId, required this.turn})
    : super(build: _builder(turn)) {
    if (turn != turn.modOne()) {
      throw ArgumentError.value(
        turn,
        'turn',
        'a stated angle is a residue mod 1, in [0, 1)',
      );
    }
  }

  /// The stated angle from the reference line to the new one, in units
  /// of π, canonical in `[0, 1)`. Exact and fixed for the tool's lifetime.
  final Rational turn;

  static PointAndLineBuilder _builder(Rational turn) =>
      ({required id, required through, required reference}) => FixedAngleLine(
        id: id,
        through: through,
        reference: reference,
        turn: turn,
      );

  @override
  ToolResult onInput(ToolInput input) =>
      input.absolute.isEuclidean ? super.onInput(input) : const ToolIgnored();
}
