import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/isosceles_triangle_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late IsoscelesTriangleMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = IsoscelesTriangleMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), then the apex from (3,5) — projected onto the
  /// perpendicular bisector x = 2, the apex lands at (2,5).
  Construction buildTriangle() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    (tool.onInput(const ToolInput(Vec2(3, 5))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  PointOnObject apex(Construction c) =>
      c.objects.whereType<PointOnObject>().single;
  List<FreePoint> corners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// The legs stay equal on the current corner positions.
  void expectIsosceles(Construction construction) {
    final free = corners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = apex(construction).position!;
    expect(c.distanceTo(a), closeTo(c.distanceTo(b), 1e-9));
  }

  group('IsoscelesTriangleMacroTool', () {
    test('two base taps plus a projected apex commit one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(
        tool.onInput(const ToolInput(Vec2(4, 0))),
        isA<ToolAccepted>(),
        reason: 'the second corner does not commit — the apex is pending',
      );
      final result = tool.onInput(const ToolInput(Vec2(3, 5))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        8,
        reason:
            '2 free corners + base + midpoint + bisector + apex '
            '+ 2 legs',
      );
      expect(
        apex(construction).position,
        const Vec2(2, 5),
        reason: 'the apex is the tap projected onto the bisector',
      );
      expectIsosceles(construction);

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole triangle is one undo unit',
      );
    });

    test('the apex tap never consumes an existing point', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(3, 5));
      construction.add(e);

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      result.command.apply(construction);

      expect(
        apex(construction).position,
        const Vec2(2, 5),
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
      expect(hidden, hasLength(2), reason: 'the midpoint and the bisector');

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(3));
      expect(apex(construction).attributes.visible, isTrue);
    });

    test('dragging a base corner keeps the legs equal', () {
      final construction = buildTriangle();
      final a = corners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(1, 2));
      expectIsosceles(construction);

      construction.moveFreePoint(a.id, const Vec2(-3, -1));
      expectIsosceles(construction);
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildTriangle();
      final a = corners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        apex(construction).position,
        isNull,
        reason: 'a degenerate base leaves the bisector undefined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(apex(construction).position, const Vec2(2, 5));
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
