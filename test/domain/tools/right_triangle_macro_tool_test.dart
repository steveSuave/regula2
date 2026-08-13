import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/right_triangle_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late RightTriangleMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = RightTriangleMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), then C from (5,3) — projected onto the
  /// perpendicular through B, C lands at (4,3).
  Construction buildTriangle() {
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
  List<FreePoint> corners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// The right angle at B on the current corner positions.
  void expectRightAngle(Construction construction) {
    final free = corners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = cornerC(construction).position!;
    expect((a - b).dot(c - b).abs(), lessThan(1e-9), reason: '∠B is right');
  }

  group('RightTriangleMacroTool', () {
    test('two base taps plus a projected third corner commit one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(
        tool.onInput(const ToolInput(Vec2(4, 0))),
        isA<ToolAccepted>(),
        reason: 'the second corner does not commit — C is pending',
      );
      final result = tool.onInput(const ToolInput(Vec2(5, 3))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        7,
        reason: '2 free corners + base + perpendicular + C + 2 sides',
      );
      expect(
        cornerC(construction).position,
        const Vec2(4, 3),
        reason: 'C is the tap projected onto the perpendicular through B',
      );
      expectRightAngle(construction);

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole triangle is one undo unit',
      );
    });

    test('the third tap never consumes an existing point', () {
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
      final construction = buildTriangle();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(hidden, hasLength(1), reason: 'the perpendicular through B');

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(3));
      expect(cornerC(construction).attributes.visible, isTrue);
    });

    test('dragging a corner keeps the right angle at B', () {
      final construction = buildTriangle();
      final a = corners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(1, 2));
      expectRightAngle(construction);

      construction.moveFreePoint(a.id, const Vec2(-3, -1));
      expectRightAngle(construction);
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildTriangle();
      final a = corners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerC(construction).position,
        isNull,
        reason: 'coincident A and B leave the perpendicular undefined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(cornerC(construction).position, const Vec2(4, 3));
    });
  });
}
