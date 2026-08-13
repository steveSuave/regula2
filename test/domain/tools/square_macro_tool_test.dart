import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/square_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late SquareMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = SquareMacroTool(newId: () => 'n${nextId++}');
  });

  /// The two derived corners, in (C, D) order — C is adjacent to the
  /// second tapped corner B, D to the first tapped corner A.
  (IntersectionPoint, IntersectionPoint) cornersOf(Construction c) {
    final corners = c.objects.whereType<IntersectionPoint>().toList();
    expect(corners, hasLength(2));
    return (corners[0], corners[1]);
  }

  group('SquareMacroTool', () {
    test('two empty-canvas taps commit the whole square as one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(4, 0))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        12,
        reason:
            '2 free points + side + 2 perps + 2 circles + '
            '2 corners + 3 sides',
      );

      final (cornerC, cornerD) = cornersOf(construction);
      expect(
        cornerC.position,
        const Vec2(4, 4),
        reason: 'the square lies to the left of the A→B direction',
      );
      expect(cornerD.position, const Vec2(0, 4));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole square is one undo unit',
      );
    });

    test('tapping two existing points reuses them', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 4));
      construction
        ..add(a)
        ..add(b);

      tool.onInput(ToolInput(a.position, hit: a));
      final result =
          tool.onInput(ToolInput(b.position, hit: b)) as ToolCommitted;
      result.command.apply(construction);

      expect(construction.length, 12, reason: 'no new free points');
      expect(construction.objects.whereType<FreePoint>(), [a, b]);
      final (cornerC, cornerD) = cornersOf(construction);
      // A→B points up (+y), so its CCW normal points -x.
      expect(cornerC.position, const Vec2(-2, 4));
      expect(cornerD.position, const Vec2(-2, 1));

      result.command.undo(construction);
      expect(construction.objects, [
        a,
        b,
      ], reason: 'undo leaves the pre-existing corners alone');
    });

    test('scaffolding is hidden, corners and sides are visible', () {
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(0, 0)));
      (tool.onInput(const ToolInput(Vec2(4, 0))) as ToolCommitted).command
          .apply(construction);

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(hidden, hasLength(4));
      expect(hidden.whereType<PerpendicularLine>(), hasLength(2));
      expect(hidden.whereType<CompassCircle>(), hasLength(2));

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(visible.whereType<IntersectionPoint>(), hasLength(2));
    });

    test('dragging a tapped corner keeps the shape a square', () {
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(0, 0)));
      (tool.onInput(const ToolInput(Vec2(4, 0))) as ToolCommitted).command
          .apply(construction);
      final a = construction.objects.whereType<FreePoint>().first;

      construction.moveFreePoint(a.id, const Vec2(0, 2));

      // A=(0,2), B=(4,0): side AB direction (2,-1)/√5, CCW normal (1,2)/√5,
      // |AB| = √20, so the offset to the far corners is (2,4).
      final (cornerC, cornerD) = cornersOf(construction);
      expect(cornerC.position!.x, closeTo(6, 1e-9));
      expect(cornerC.position!.y, closeTo(4, 1e-9));
      expect(cornerD.position!.x, closeTo(2, 1e-9));
      expect(cornerD.position!.y, closeTo(6, 1e-9));
    });

    test('the square survives a drag through degeneracy', () {
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(0, 0)));
      (tool.onInput(const ToolInput(Vec2(4, 0))) as ToolCommitted).command
          .apply(construction);
      final a = construction.objects.whereType<FreePoint>().first;
      final (cornerC, cornerD) = cornersOf(construction);

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerC.position,
        isNull,
        reason: 'coincident corners leave the square undefined',
      );
      expect(cornerD.position, isNull);

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(cornerC.position, const Vec2(4, 4));
      expect(cornerD.position, const Vec2(0, 4));
    });

    test('the same existing point twice is ignored', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolIgnored>());
      expect(tool.collectedVertices, hasLength(1));
    });
  });

  group('derived corner dedup', () {
    test('re-stamping over the same corners reuses both derived corners', () {
      final construction = Construction();
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(4, 0));
      construction.add(a);
      construction.add(b);
      ToolResult tap(FreePoint point) => tool.onInput(
        ToolInput(point.position, hit: point, objects: construction.objects),
      );

      tap(a);
      (tap(b) as ToolCommitted).command.apply(construction);
      final corners = construction.objects
          .whereType<IntersectionPoint>()
          .toList();
      expect(corners, hasLength(2));
      final before = construction.length;

      tap(a);
      (tap(b) as ToolCommitted).command.apply(construction);

      expect(
        construction.length,
        before + 4,
        reason: 'only the four side segments are re-added',
      );
      expect(
        construction.objects.whereType<IntersectionPoint>().toList(),
        corners,
        reason: 'both corners are reused, none stacked',
      );
      expect(
        construction.objects.whereType<PerpendicularLine>(),
        hasLength(2),
        reason: 'reused corners bring no new scaffolding',
      );
      expect(construction.objects.whereType<CompassCircle>(), hasLength(2));
    });
  });
}
