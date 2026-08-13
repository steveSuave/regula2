import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/right_trapezium_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late RightTrapeziumMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = RightTrapeziumMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), C(3,2) — D closes the shape at (0,2), the
  /// foot of the perpendicular height through A at C's level.
  Construction buildTrapezium() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    (tool.onInput(const ToolInput(Vec2(3, 2))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  IntersectionPoint cornerD(Construction c) =>
      c.objects.whereType<IntersectionPoint>().single;
  List<FreePoint> freeCorners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// The right-trapezium invariant on the current corner positions.
  void expectRightTrapezium(Construction construction) {
    final free = freeCorners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = free[2].position;
    final d = cornerD(construction).position!;
    final ab = b - a;
    expect(ab.dot(d - a).abs(), lessThan(1e-9), reason: '∠A is right');
    expect(
      ab.cross(c - d).abs(),
      lessThan(1e-9),
      reason: 'DC ∥ AB, so ∠D is right too',
    );
  }

  group('RightTrapeziumMacroTool', () {
    test('three corner taps commit one macro with the derived D', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(const ToolInput(Vec2(4, 0))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(3, 2))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        10,
        reason: '3 free points + 4 sides + perpendicular + parallel + D',
      );
      expect(cornerD(construction).position, const Vec2(0, 2));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole trapezium is one undo unit',
      );
    });

    test('tapping existing points consumes them as corners', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      construction.add(a);

      tool.onInput(ToolInput(a.position, hit: a));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      final result = tool.onInput(const ToolInput(Vec2(3, 2))) as ToolCommitted;
      result.command.apply(construction);

      expect(
        construction.objects.whereType<FreePoint>(),
        hasLength(3),
        reason: 'a was consumed, only B and C are new',
      );

      result.command.undo(construction);
      expect(construction.objects, [a]);
    });

    test('scaffolding is hidden, corners and sides are visible', () {
      final construction = buildTrapezium();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(
        hidden,
        hasLength(2),
        reason: 'the perpendicular and the parallel',
      );

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(cornerD(construction).attributes.visible, isTrue);
    });

    test('dragging any tapped corner keeps the right angles', () {
      final construction = buildTrapezium();
      final free = freeCorners(construction);

      construction.moveFreePoint(free[1].id, const Vec2(5, 1));
      expectRightTrapezium(construction);

      construction.moveFreePoint(free[2].id, const Vec2(2, 4));
      expectRightTrapezium(construction);
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildTrapezium();
      final a = freeCorners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerD(construction).position,
        isNull,
        reason: 'coincident A and B leave the scaffolding undefined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(cornerD(construction).position, const Vec2(0, 2));
    });
  });

  group('derived corner dedup', () {
    test('re-stamping over the same corners reuses the derived corner', () {
      final construction = Construction();
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(4, 0));
      final c = FreePoint(id: 'C', position: const Vec2(2, 2));
      for (final point in [a, b, c]) {
        construction.add(point);
      }
      ToolResult tap(FreePoint point) => tool.onInput(
        ToolInput(point.position, hit: point, objects: construction.objects),
      );

      tap(a);
      tap(b);
      (tap(c) as ToolCommitted).command.apply(construction);
      expect(construction.objects.whereType<IntersectionPoint>(), hasLength(1));
      final before = construction.length;

      tap(a);
      tap(b);
      (tap(c) as ToolCommitted).command.apply(construction);

      expect(
        construction.objects.whereType<IntersectionPoint>(),
        hasLength(1),
        reason: 'the corner is reused, its scaffolding skipped',
      );
      expect(
        construction.length,
        before + 4,
        reason: 'only the four side segments are re-added',
      );
    });
  });
}
