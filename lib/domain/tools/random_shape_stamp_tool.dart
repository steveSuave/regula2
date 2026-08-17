import 'dart:math' as math;

import '../commands/add_object_command.dart';
import '../commands/command.dart';
import '../commands/macro_command.dart';
import '../construction/objects/free_point.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import 'tool.dart';

/// One tap stamps a randomized simple polygon around it: between
/// [minVertices] and [maxVertices] *free* points at sorted random angles
/// and jittered radii (sorted angles keep the outline from
/// self-intersecting), joined by segments — one `MacroCommand`, fully
/// editable afterwards. Backs the "random triangle" (3–3) and, via
/// [RandomShapeStampTool.convexQuadrilateral], the "random quadrilateral"
/// menu items.
///
/// The tap never consumes or glues to existing objects — a stamp is new
/// geometry by definition. The stamp radius scales with the input's snap
/// threshold (≈10× ≈ 80 screen px at any zoom), falling back to 80 world
/// units when the threshold is 0. [random] is injectable so tests are
/// deterministic.
class RandomShapeStampTool implements Tool {
  RandomShapeStampTool({
    required this.newId,
    required this.minVertices,
    required this.maxVertices,
    math.Random? random,
  }) : assert(minVertices >= 3, 'a polygon needs at least 3 vertices'),
       assert(minVertices <= maxVertices, 'empty vertex-count range'),
       convex = false,
       _random = random ?? math.Random();

  /// Stamps a *strictly convex* random quadrilateral: exactly four
  /// vertices on one circle — sorted distinct angles on a circle are
  /// always in convex position, so there is no radial jitter and no
  /// rejection loop — with the angles drawn by the gap method and one
  /// random anisotropic stretch about the tap for variety (affine maps
  /// preserve convexity).
  RandomShapeStampTool.convexQuadrilateral({
    required this.newId,
    math.Random? random,
  }) : minVertices = 4,
       maxVertices = 4,
       convex = true,
       _random = random ?? math.Random();

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  final int minVertices;
  final int maxVertices;

  /// Convex mode: all vertices on one circle (no radial jitter), gap-method
  /// angles, plus a convexity-preserving stretch.
  final bool convex;

  final math.Random _random;

  /// Minimum angular gap between consecutive vertices in convex mode —
  /// keeps the quadrilateral away from degenerate slivers.
  static const _minGap = 0.25;

  @override
  bool get hasPartialInput => false;

  @override
  ToolResult onInput(ToolInput input) {
    final radius = input.snapThreshold > 0 ? input.snapThreshold * 10 : 80.0;
    final List<Vec2> offsets;
    if (convex) {
      offsets = _convexOffsets(minVertices, radius);
    } else {
      final count =
          minVertices + _random.nextInt(maxVertices - minVertices + 1);
      final angles = List.generate(
        count,
        (_) => _random.nextDouble() * 2 * math.pi,
      )..sort();
      offsets = [
        for (final angle in angles)
          Vec2(math.cos(angle), math.sin(angle)) *
              (radius * (0.5 + 0.5 * _random.nextDouble())),
      ];
    }
    final vertices = [
      for (final offset in offsets)
        FreePoint(id: newId(), position: input.position + offset),
    ];
    final count = vertices.length;
    final commands = <Command>[
      for (final vertex in vertices) AddObjectCommand(vertex),
      for (var k = 0; k < count; k++)
        AddObjectCommand(
          Segment(
            id: newId(),
            point1: vertices[k],
            point2: vertices[(k + 1) % count],
          ),
        ),
    ];
    return ToolCommitted(MacroCommand(commands));
  }

  /// [count] vertex offsets on one circle of [radius], in increasing-angle
  /// (= convex polygon) order. Gap method: [count] uniform draws are
  /// normalized onto 2π minus the reserved minimum gaps and prefix-summed
  /// from a random start, so every consecutive gap — the wrap-around one
  /// included — is at least [_minGap] with no rejection loop. A final
  /// rotate–scale–rotate stretch about the origin (= the tap) varies the
  /// proportions without breaking convexity.
  List<Vec2> _convexOffsets(int count, double radius) {
    final draws = List.generate(count, (_) => _random.nextDouble());
    final drawSum = draws.fold(0.0, (a, b) => a + b);
    final free = 2 * math.pi - count * _minGap;
    var angle = _random.nextDouble() * 2 * math.pi;
    final onCircle = <Vec2>[];
    for (final draw in draws) {
      onCircle.add(Vec2(math.cos(angle), math.sin(angle)) * radius);
      // All-zero draws are astronomically unlikely but representable;
      // fall back to equal gaps rather than divide by zero.
      angle += _minGap + (drawSum > 0 ? draw / drawSum : 1 / count) * free;
    }
    final axis = _random.nextDouble() * math.pi;
    final stretchX = 0.7 + 0.6 * _random.nextDouble();
    final stretchY = 0.7 + 0.6 * _random.nextDouble();
    return [
      for (final offset in onCircle)
        _stretched(offset, axis, stretchX, stretchY),
    ];
  }

  /// [offset] scaled by [stretchX]/[stretchY] along the axes of the frame
  /// rotated by [axis].
  static Vec2 _stretched(
    Vec2 offset,
    double axis,
    double stretchX,
    double stretchY,
  ) {
    final local = offset.rotated(-axis);
    return Vec2(local.x * stretchX, local.y * stretchY).rotated(axis);
  }

  @override
  void reset() {}
}
