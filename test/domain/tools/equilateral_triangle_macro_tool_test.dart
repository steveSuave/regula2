import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/equilateral_triangle_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late EquilateralTriangleMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = EquilateralTriangleMacroTool(newId: () => 'n${nextId++}');
  });

  RotatedPoint apex(Construction c) =>
      c.objects.whereType<RotatedPoint>().single;
  List<FreePoint> corners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// All three sides equal on the current corner positions.
  void expectEquilateral(Construction construction) {
    final free = corners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = apex(construction).position!;
    final side = a.distanceTo(b);
    expect(b.distanceTo(c), closeTo(side, 1e-9));
    expect(c.distanceTo(a), closeTo(side, 1e-9));
  }

  group('EquilateralTriangleMacroTool', () {
    test('two taps commit the triangle as one macro, apex left of A→B', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(2, 0))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 6, reason: '2 free corners + apex + 3 sides');
      expect(
        apex(construction).position!.closeTo(Vec2(1, math.sqrt(3)), 1e-12),
        isTrue,
        reason: 'the apex lies to the left of A→B',
      );
      expectEquilateral(construction);
      expect(
        construction.objects.whereType<Segment>(),
        hasLength(3),
        reason: 'no hidden scaffolding — the apex is a plain RotatedPoint',
      );

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole triangle is one undo unit',
      );
    });

    test('existing points are consumed as corners', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      construction
        ..add(a)
        ..add(b);

      tool.onInput(ToolInput(a.position, hit: a));
      final result =
          tool.onInput(ToolInput(b.position, hit: b)) as ToolCommitted;
      result.command.apply(construction);

      expect(
        construction.length,
        6,
        reason: 'the taps added no new free points',
      );
      expect(apex(construction).parents, [b, a]);

      result.command.undo(construction);
      expect(construction.objects, [a, b]);
    });

    test('dragging a corner keeps the triangle equilateral', () {
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(0, 0)));
      (tool.onInput(const ToolInput(Vec2(2, 0))) as ToolCommitted).command
          .apply(construction);
      final a = corners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(-1, 2));
      expectEquilateral(construction);

      construction.moveFreePoint(a.id, const Vec2(5, -3));
      expectEquilateral(construction);
    });
  });

  group('derived apex dedup', () {
    test('re-stamping over the same corners reuses the apex', () {
      final construction = Construction();
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(2, 0));
      construction.add(a);
      construction.add(b);
      ToolResult tap(FreePoint point) => tool.onInput(
        ToolInput(point.position, hit: point, objects: construction.objects),
      );

      tap(a);
      (tap(b) as ToolCommitted).command.apply(construction);
      final apex = construction.objects.whereType<RotatedPoint>().single;
      final before = construction.length;

      tap(a);
      (tap(b) as ToolCommitted).command.apply(construction);

      expect(
        construction.objects.whereType<RotatedPoint>().single,
        same(apex),
        reason: 'the apex is reused, not stacked',
      );
      expect(
        construction.length,
        before + 3,
        reason: 'only the three side segments are re-added',
      );
    });
  });
}
