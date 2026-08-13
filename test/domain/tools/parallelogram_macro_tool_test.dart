import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/parallelogram_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late ParallelogramMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = ParallelogramMacroTool(newId: () => 'n${nextId++}');
  });

  /// Applies three empty-canvas taps A(0,0), B(4,0), C(5,2) and returns
  /// the committed construction.
  Construction buildParallelogram() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    (tool.onInput(const ToolInput(Vec2(5, 2))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  IntersectionPoint cornerOf(Construction c) =>
      c.objects.whereType<IntersectionPoint>().single;

  group('ParallelogramMacroTool', () {
    test('three empty-canvas taps commit the whole shape as one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(const ToolInput(Vec2(4, 0))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(5, 2))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        10,
        reason: '3 free points + 2 sides + 2 parallels + corner + 2 sides',
      );
      expect(
        cornerOf(construction).position,
        const Vec2(1, 2),
        reason: 'D = A + (C − B)',
      );

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole parallelogram is one undo unit',
      );
    });

    test('scaffolding is hidden, corner and sides are visible', () {
      final construction = buildParallelogram();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(hidden, hasLength(2));
      expect(hidden.whereType<ParallelLine>(), hasLength(2));

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(visible.whereType<IntersectionPoint>(), hasLength(1));
    });

    test('dragging a tapped corner keeps the shape a parallelogram', () {
      final construction = buildParallelogram();
      final b = construction.objects.whereType<FreePoint>().elementAt(1);

      construction.moveFreePoint(b.id, const Vec2(2, 1));

      final d = cornerOf(construction).position!;
      expect(d.x, closeTo(3, 1e-9), reason: 'D tracks A + (C − B)');
      expect(d.y, closeTo(1, 1e-9));
    });

    test('the shape survives a drag through collinearity', () {
      final construction = buildParallelogram();
      final c = construction.objects.whereType<FreePoint>().elementAt(2);
      final cornerD = cornerOf(construction);

      construction.moveFreePoint(c.id, const Vec2(2, 0));
      expect(
        cornerD.position,
        isNull,
        reason: 'collinear corners make the two parallels parallel',
      );

      construction.moveFreePoint(c.id, const Vec2(5, 2));
      expect(cornerD.position, const Vec2(1, 2));
    });
  });

  group('derived corner dedup', () {
    test('completing over three side-midpoints reuses the fourth midpoint', () {
      // The reported duplicate (Varignon): a quadrilateral with all four
      // side midpoints, then the parallelogram macro over three of them —
      // its fourth corner lands identically on the fourth midpoint.
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(6, 1));
      final c = FreePoint(id: 'C', position: const Vec2(7, 5));
      final d = FreePoint(id: 'D', position: const Vec2(1, 4));
      final mAB = Midpoint(id: 'mAB', point1: a, point2: b);
      final mBC = Midpoint(id: 'mBC', point1: b, point2: c);
      final mCD = Midpoint(id: 'mCD', point1: c, point2: d);
      final mDA = Midpoint(id: 'mDA', point1: d, point2: a);
      final construction = Construction();
      for (final object in [a, b, c, d, mAB, mBC, mCD, mDA]) {
        construction.add(object);
      }

      ToolResult tap(Midpoint point) => tool.onInput(
        ToolInput(point.position!, hit: point, objects: construction.objects),
      );
      tap(mBC);
      tap(mAB);
      final result = tap(mDA) as ToolCommitted;
      result.command.apply(construction);

      expect(
        construction.objects.whereType<IntersectionPoint>(),
        isEmpty,
        reason: 'the corner is the existing midpoint, not a new point',
      );
      expect(
        construction.objects.whereType<ParallelLine>(),
        isEmpty,
        reason: 'scaffolding for a reused corner is not added',
      );
      final closing = construction.objects.whereType<Segment>().where(
        (s) => identical(s.point1, mCD) || identical(s.point2, mCD),
      );
      expect(
        closing,
        hasLength(2),
        reason: 'both closing sides attach to the existing midpoint',
      );

      result.command.undo(construction);
      expect(
        construction.length,
        8,
        reason: 'undo removes only what the macro added',
      );
    });

    test('an accidentally coincident point keeps the derived corner', () {
      final construction = Construction();
      construction.add(FreePoint(id: 'stray', position: const Vec2(1, 2)));

      ToolResult tap(Vec2 position) =>
          tool.onInput(ToolInput(position, objects: construction.objects));
      tap(const Vec2(0, 0));
      tap(const Vec2(4, 0));
      final result = tap(const Vec2(5, 2)) as ToolCommitted;
      result.command.apply(construction);

      final corner = construction.objects.whereType<IntersectionPoint>().single;
      expect(
        corner.position,
        const Vec2(1, 2),
        reason: 'the corner still lands on the stray point…',
      );
      expect(
        construction.objects.whereType<ParallelLine>(),
        hasLength(2),
        reason:
            '…but stays independently derived: the coincidence does '
            'not survive perturbation of the stray free point',
      );
    });
  });
}
