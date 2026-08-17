import '../commands/add_object_command.dart';
import '../commands/command.dart';
import '../commands/macro_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/free_point.dart';
import '../math/vec2.dart';
import 'tool.dart';

/// A two-mode tool machine decided by the first tap (Phase 29b, extracted
/// in Phase 46).
///
/// A first tap on a line enters **two-line mode**: the second, distinct
/// line commits [buildFromLines] — one `AddObjectCommand`, no points
/// created; the tap positions are forwarded so the subclass can pick the
/// tapped wedge. A first tap on a point or on empty canvas enters **point
/// mode**, the classic arm–vertex–arm flow committing [buildFromPoints] —
/// except taps on curves are *ignored* rather than run through the Phase
/// 20 ladder: the glued `PointOnObject` by-products outlive the gesture,
/// which reads as fake points for an angle-shaped tool. Modes never mix (a
/// point tap in line mode and a line tap in point mode are ignored), and
/// circle and angle taps are always ignored.
abstract class TwoLineOrThreePointTool implements ToolInputPreview {
  TwoLineOrThreePointTool({required this.newId});

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  /// Two-line-mode result: the object spanning [line1] and [line2], with
  /// the taps that selected them (for wedge picking).
  GeoObject buildFromLines(
    String id,
    GeoLine line1,
    GeoLine line2,
    Vec2 tap1,
    Vec2 tap2,
  );

  /// Point-mode result: the arm–vertex–arm object.
  GeoObject buildFromPoints(
    String id,
    GeoPoint arm1,
    GeoPoint vertex,
    GeoPoint arm2,
  );

  GeoLine? _line1;
  Vec2? _tap1;

  final List<({GeoPoint point, bool isNew})> _points = [];

  @override
  bool get hasPartialInput => _line1 != null || _points.isNotEmpty;

  @override
  List<Vec2> get previewPositions => [
    for (final p in _points)
      if (p.isNew) ?p.point.position,
  ];

  @override
  List<String> get previewObjectIds => [
    ?_line1?.id,
    for (final p in _points)
      if (!p.isNew) p.point.id,
  ];

  @override
  ToolResult onInput(ToolInput input) {
    if (_line1 != null) {
      return _collectSecondLine(input);
    }
    if (input.hit case final GeoLine hit when _points.isEmpty) {
      _line1 = hit;
      _tap1 = input.position;
      return const ToolAccepted();
    }
    return _collectPoint(input);
  }

  ToolResult _collectSecondLine(ToolInput input) {
    final hit = input.hit;
    if (hit is! GeoLine || identical(hit, _line1)) {
      return const ToolIgnored();
    }
    final line1 = _line1!;
    final tap1 = _tap1!;
    reset();
    return ToolCommitted(
      AddObjectCommand(
        buildFromLines(newId(), line1, hit, tap1, input.position),
      ),
    );
  }

  ToolResult _collectPoint(ToolInput input) {
    switch (input.hit) {
      case final GeoPoint hit:
        if (_points.any((p) => identical(p.point, hit))) {
          return const ToolIgnored();
        }
        _points.add((point: hit, isNew: false));
      case null:
        _points.add((
          point: FreePoint(id: newId(), position: input.position),
          isNew: true,
        ));
      default:
        return const ToolIgnored();
    }
    if (_points.length < 3) {
      return const ToolAccepted();
    }
    return _commitPoints();
  }

  /// Point-mode commit, matching `MultiPointTool.commitCollected`: new
  /// free points first, then the built object, one undo unit.
  ToolResult _commitPoints() {
    final points = List.of(_points);
    reset();
    final commands = <Command>[
      for (final p in points)
        if (p.isNew) AddObjectCommand(p.point),
      AddObjectCommand(
        buildFromPoints(
          newId(),
          points[0].point,
          points[1].point,
          points[2].point,
        ),
      ),
    ];
    return ToolCommitted(
      commands.length == 1 ? commands.single : MacroCommand(commands),
    );
  }

  @override
  void reset() {
    _line1 = null;
    _tap1 = null;
    _points.clear();
  }
}
