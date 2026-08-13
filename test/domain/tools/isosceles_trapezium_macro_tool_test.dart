import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/isosceles_trapezium_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late IsoscelesTrapeziumMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = IsoscelesTrapeziumMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), C(3,2) — D mirrors C across the perpendicular
  /// bisector of AB (the line x = 2) to (1,2).
  Construction buildTrapezium() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    (tool.onInput(const ToolInput(Vec2(3, 2))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  SegmentRatioPoint cornerD(Construction c) =>
      c.objects.whereType<SegmentRatioPoint>().single;
  List<FreePoint> freeCorners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// Equal legs + parallel bases on the current corner positions.
  void expectIsosceles(Construction construction) {
    final free = freeCorners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = free[2].position;
    final d = cornerD(construction).position!;
    expect(
      (c - b).norm,
      closeTo((d - a).norm, 1e-9),
      reason: 'the legs stay equal',
    );
    expect((b - a).cross(c - d).abs(), lessThan(1e-9), reason: 'DC ∥ AB');
  }

  group('IsoscelesTrapeziumMacroTool', () {
    test('three corner taps commit one macro with the mirrored D', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(const ToolInput(Vec2(4, 0))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(3, 2))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        12,
        reason:
            '3 free points + 4 sides + midpoint + axis + mirror '
            'perpendicular + foot + D',
      );
      expect(cornerD(construction).position, const Vec2(1, 2));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole trapezium is one undo unit',
      );
    });

    test('scaffolding is hidden, corners and sides are visible', () {
      final construction = buildTrapezium();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(
        hidden,
        hasLength(4),
        reason: 'midpoint, axis, mirror perpendicular and its foot',
      );

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(cornerD(construction).attributes.visible, isTrue);
    });

    test('dragging any tapped corner keeps the trapezium isosceles', () {
      final construction = buildTrapezium();
      final free = freeCorners(construction);

      construction.moveFreePoint(free[2].id, const Vec2(5, 1));
      expectIsosceles(construction);

      construction.moveFreePoint(free[0].id, const Vec2(-1, 0.5));
      expectIsosceles(construction);
    });

    test('C dragged across the axis keeps the shape isosceles — no flip', () {
      final construction = buildTrapezium();
      final c = freeCorners(construction)[2];

      construction.moveFreePoint(c.id, const Vec2(0.5, 2));
      expect(
        cornerD(construction).position,
        const Vec2(3.5, 2),
        reason: 'D mirrors through the axis smoothly',
      );
      expectIsosceles(construction);
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildTrapezium();
      final a = freeCorners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerD(construction).position,
        isNull,
        reason: 'coincident A and B leave the axis undefined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(cornerD(construction).position, const Vec2(1, 2));
    });
  });

  group('derived corner dedup', () {
    test('re-stamping over the same corners reuses the mirrored corner', () {
      final construction = Construction();
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(4, 0));
      final c = FreePoint(id: 'C', position: const Vec2(3, 2));
      for (final point in [a, b, c]) {
        construction.add(point);
      }
      ToolResult tap(FreePoint point) => tool.onInput(
        ToolInput(point.position, hit: point, objects: construction.objects),
      );

      tap(a);
      tap(b);
      (tap(c) as ToolCommitted).command.apply(construction);
      expect(construction.objects.whereType<SegmentRatioPoint>(), hasLength(1));
      final before = construction.length;

      tap(a);
      tap(b);
      (tap(c) as ToolCommitted).command.apply(construction);

      expect(
        construction.objects.whereType<SegmentRatioPoint>(),
        hasLength(1),
        reason: 'the mirrored corner is reused, its scaffolding skipped',
      );
      expect(
        construction.length,
        before + 4,
        reason: 'only the four side segments are re-added',
      );
    });
  });
}
