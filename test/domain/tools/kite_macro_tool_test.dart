import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/kite_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late KiteMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = KiteMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps apex A(0,0), side vertex B(1,2), apex C(4,0) — D mirrors B
  /// across the diagonal AC (the x-axis) to (1,−2).
  Construction buildKite() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(1, 2)));
    (tool.onInput(const ToolInput(Vec2(4, 0))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  SegmentRatioPoint cornerD(Construction c) =>
      c.objects.whereType<SegmentRatioPoint>().single;
  List<FreePoint> freeCorners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// Pairwise-equal adjacent sides on the current corner positions.
  void expectKite(Construction construction) {
    final free = freeCorners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = free[2].position;
    final d = cornerD(construction).position!;
    expect((d - a).norm, closeTo((b - a).norm, 1e-9), reason: '|AD| = |AB|');
    expect((d - c).norm, closeTo((b - c).norm, 1e-9), reason: '|CD| = |CB|');
  }

  group('KiteMacroTool', () {
    test('apex, side vertex, apex taps commit one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(const ToolInput(Vec2(1, 2))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(4, 0))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        11,
        reason:
            '3 free points + diagonal + 4 sides + mirror '
            'perpendicular + foot + D',
      );
      expect(cornerD(construction).position, const Vec2(1, -2));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole kite is one undo unit',
      );
    });

    test('the diagonal is hidden, corners and sides are visible', () {
      final construction = buildKite();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(
        hidden,
        hasLength(3),
        reason: 'the diagonal, the mirror perpendicular and its foot',
      );
      expect(
        hidden.whereType<Segment>(),
        hasLength(1),
        reason: 'the diagonal AC is a hidden segment serving as the axis',
      );

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(cornerD(construction).attributes.visible, isTrue);
    });

    test('dragging any tapped corner keeps the shape a kite', () {
      final construction = buildKite();
      final free = freeCorners(construction);

      construction.moveFreePoint(free[1].id, const Vec2(2, 1));
      expectKite(construction);

      construction.moveFreePoint(free[0].id, const Vec2(-1, 1));
      expectKite(construction);
    });

    test('B dragged across the diagonal flips the kite continuously', () {
      final construction = buildKite();
      final b = freeCorners(construction)[1];

      construction.moveFreePoint(b.id, const Vec2(1, -2));
      expect(
        cornerD(construction).position,
        const Vec2(1, 2),
        reason: 'D mirrors to the other side',
      );
      expectKite(construction);

      construction.moveFreePoint(b.id, const Vec2(2, 0));
      expect(
        cornerD(construction).position,
        const Vec2(2, 0),
        reason: 'B on the diagonal is the flat kite, D ≡ B',
      );
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildKite();
      final a = freeCorners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerD(construction).position,
        isNull,
        reason: 'coincident apexes leave the diagonal carrier undefined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(cornerD(construction).position, const Vec2(1, -2));
    });
  });

  group('derived corner dedup', () {
    test('re-stamping over the same corners reuses the mirrored corner', () {
      final construction = Construction();
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(1, 2));
      final c = FreePoint(id: 'C', position: const Vec2(4, 0));
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
