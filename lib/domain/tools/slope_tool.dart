import '../commands/add_object_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/slope_measurement.dart';
import 'tool.dart';

/// One tap measures a line's slope: the topmost in-threshold line-valued
/// object (consulted from `hit`/`extraHits`, so a point drawn on the line
/// can't shadow it) becomes a `SlopeMeasurement` in one
/// `AddObjectCommand`. The tap never falls through to the point ladder —
/// this tool measures existing lines, it doesn't create points — and any
/// tap without a line is ignored.
class SlopeTool implements Tool {
  SlopeTool({required this.newId});

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  @override
  bool get hasPartialInput => false;

  @override
  ToolResult onInput(ToolInput input) {
    final subject = input.hits.whereType<GeoLine>().firstOrNull;
    if (subject == null) {
      return const ToolIgnored();
    }
    return ToolCommitted(
      AddObjectCommand(SlopeMeasurement(id: newId(), subject: subject)),
    );
  }

  @override
  void reset() {
    // Stateless: every tap either commits or is ignored.
  }
}
