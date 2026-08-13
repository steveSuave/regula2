import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/rectangle_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late RectangleMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = RectangleMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), then picks the height from (5,3) — projected
  /// onto the perpendicular through B, corner C lands at (4,3) and D
  /// closes the shape at (0,3).
  Construction buildRectangle() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    (tool.onInput(const ToolInput(Vec2(5, 3))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  PointOnObject cornerC(Construction c) =>
      c.objects.whereType<PointOnObject>().single;
  IntersectionPoint cornerD(Construction c) =>
      c.objects.whereType<IntersectionPoint>().single;
  List<FreePoint> freeCorners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// The rectangle invariant on the current corner positions.
  void expectRectangle(Construction construction) {
    final free = freeCorners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = cornerC(construction).position!;
    final d = cornerD(construction).position!;
    final ab = b - a;
    expect(ab.dot(c - b).abs(), lessThan(1e-9), reason: '∠B is right');
    expect(ab.dot(d - a).abs(), lessThan(1e-9), reason: '∠A is right');
    expect(ab.cross(c - d).abs(), lessThan(1e-9), reason: 'DC ∥ AB');
  }

  group('RectangleMacroTool', () {
    test('two corner taps plus a projected height commit one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(
        tool.onInput(const ToolInput(Vec2(4, 0))),
        isA<ToolAccepted>(),
        reason: 'the second corner does not commit — the height is pending',
      );
      final result = tool.onInput(const ToolInput(Vec2(5, 3))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        11,
        reason:
            '2 free points + 4 sides + 2 perpendiculars + parallel '
            '+ C + D',
      );
      expect(
        cornerC(construction).position,
        const Vec2(4, 3),
        reason: 'C is the tap projected onto the perpendicular through B',
      );
      expect(cornerD(construction).position, const Vec2(0, 3));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole rectangle is one undo unit',
      );
    });

    test('the height tap never consumes an existing point', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(5, 3));
      construction.add(e);

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      result.command.apply(construction);

      expect(
        cornerC(construction).position,
        const Vec2(4, 3),
        reason: 'the hit point only donates its position',
      );

      result.command.undo(construction);
      expect(construction.objects, [e]);
    });

    test('scaffolding is hidden, corners and sides are visible', () {
      final construction = buildRectangle();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(
        hidden,
        hasLength(3),
        reason: 'two perpendiculars and the parallel',
      );

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(cornerC(construction).attributes.visible, isTrue);
      expect(cornerD(construction).attributes.visible, isTrue);
    });

    test('dragging a tapped corner keeps the shape a rectangle', () {
      final construction = buildRectangle();
      final a = freeCorners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(1, 1));
      expectRectangle(construction);

      construction.moveFreePoint(a.id, const Vec2(-2, 0.5));
      expectRectangle(construction);
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildRectangle();
      final a = freeCorners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerC(construction).position,
        isNull,
        reason: 'coincident A and B leave the perpendicular undefined',
      );
      expect(cornerD(construction).position, isNull);

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(cornerC(construction).position, const Vec2(4, 3));
      expect(cornerD(construction).position, const Vec2(0, 3));
    });

    test('reset mid-collection discards the corners', () {
      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      tool.reset();

      expect(tool.previewPositions, isEmpty);
      expect(
        tool.onInput(const ToolInput(Vec2(9, 9))),
        isA<ToolAccepted>(),
        reason: 'the next tap starts a fresh collection, not a commit',
      );
    });
  });
}
