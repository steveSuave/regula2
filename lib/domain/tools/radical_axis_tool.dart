import '../commands/add_object_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/radical_axis_line.dart';
import '../math/vec2.dart';
import 'tool.dart';

/// Collects two distinct circles, then creates their [RadicalAxisLine] —
/// the first "click two circles" tool: `PointAndLineTool`'s slot
/// collection with `IntersectionTool`'s curve-tap rules.
///
/// Both inputs must be existing circles, so empty-canvas, point, line
/// and other taps are ignored — there is no point ladder, the circles
/// themselves are the inputs. The first collected circle is haloed via
/// [previewObjectIds]. An existing radical axis over the same two circle
/// instances (in either order — the axis is symmetric) refuses the
/// completing tap instead of stacking a duplicate, the structural-dedupe
/// rule of `HarmonicConjugateTool` and `TriangleCircleTool`; no numeric
/// probe is needed because sameness here is parent-instance identity.
class RadicalAxisTool implements ToolInputPreview {
  RadicalAxisTool({required this.newId});

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  GeoCircle? _first;

  @override
  bool get hasPartialInput => _first != null;

  @override
  List<Vec2> get previewPositions => const [];

  @override
  List<String> get previewObjectIds => [?_first?.id];

  @override
  ToolResult onInput(ToolInput input) {
    final hit = input.hit;
    if (hit is! GeoCircle) {
      return const ToolIgnored();
    }
    final first = _first;
    if (first == null) {
      _first = hit;
      return const ToolAccepted();
    }
    if (identical(first, hit) || _existingAxis(input.objects, first, hit)) {
      return const ToolIgnored();
    }
    _first = null;
    return ToolCommitted(
      AddObjectCommand(
        RadicalAxisLine(id: newId(), circle1: first, circle2: hit),
      ),
    );
  }

  static bool _existingAxis(
    Iterable<GeoObject> objects,
    GeoCircle a,
    GeoCircle b,
  ) => objects.any(
    (object) =>
        object is RadicalAxisLine &&
        ((identical(object.circle1, a) && identical(object.circle2, b)) ||
            (identical(object.circle1, b) && identical(object.circle2, a))),
  );

  @override
  void reset() {
    _first = null;
  }
}
