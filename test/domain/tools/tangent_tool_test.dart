import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/tangent_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FreePoint center;
  late FreePoint rim;
  late CircleCenterPoint circle;

  TangentTool newTool() => TangentTool(newId: () => 'n${nextId++}');

  setUp(() {
    nextId = 0;
    center = FreePoint(id: 'c', position: Vec2.zero);
    rim = FreePoint(id: 'r', position: const Vec2(1, 0));
    circle = CircleCenterPoint(id: 'circ', center: center, onCircle: rim);
  });

  List<TangentLine> tangentsOf(MacroCommand command) => [
    for (final c in command.commands)
      if ((c as AddObjectCommand).object case final TangentLine t) t,
  ];

  group('TangentTool', () {
    test('point first or circle first, both tangents in one MacroCommand', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));

      for (final circleFirst in [true, false]) {
        final tool = newTool();
        final inputs = [
          ToolInput(const Vec2(1, 0.05), hit: circle),
          ToolInput(p.position, hit: p),
        ];
        if (!circleFirst) {
          inputs.setAll(0, inputs.reversed.toList());
        }

        expect(tool.onInput(inputs[0]), isA<ToolAccepted>());
        final result = tool.onInput(inputs[1]);
        expect(
          result,
          isA<ToolCommitted>(),
          reason: 'circleFirst: $circleFirst',
        );
        final command = (result as ToolCommitted).command as MacroCommand;
        expect(
          command.commands,
          hasLength(2),
          reason: 'existing point — only the two tangents are added',
        );
        final tangents = tangentsOf(command);
        expect([for (final t in tangents) t.branch], [0, 1]);
        for (final t in tangents) {
          expect(t.parents, [p, circle]);
          expect(t.line!.distanceTo(Vec2.zero), closeTo(1, 1e-12));
        }
      }
    });

    test('a point on the circle gets one tangent, not two (Phase 164)', () {
      // Both branches from a point on the circle are the tangent at that
      // point; emitting both put one line in the document twice.
      final tool = newTool();
      expect(
        tool.onInput(ToolInput(const Vec2(1, 0.05), hit: circle)),
        isA<ToolAccepted>(),
      );
      final result = tool.onInput(ToolInput(rim.position, hit: rim));
      final command = (result as ToolCommitted).command as MacroCommand;
      expect(command.commands, hasLength(1));
      final tangents = tangentsOf(command);
      expect(tangents.single.branch, 0);
      expect(tangents.single.parents, [rim, circle]);
      expect(tangents.single.line!.distanceTo(Vec2.zero), closeTo(1, 1e-12));
    });

    test('empty canvas creates the point, whole step is one undo unit', () {
      final construction = Construction()
        ..add(center)
        ..add(rim)
        ..add(circle);
      final tool = newTool();

      tool.onInput(ToolInput(const Vec2(1, 0.05), hit: circle));
      final result = tool.onInput(const ToolInput(Vec2(5, 0))) as ToolCommitted;

      final command = result.command as MacroCommand;
      expect(command.commands, hasLength(3));
      command.apply(construction);
      expect(
        construction.length,
        6,
        reason: 'new free point + two tangent lines',
      );
      command.undo(construction);
      expect(construction.length, 3);
    });

    test('a tap on the target circle never glues a PointOnObject', () {
      final tool = newTool();
      tool.onInput(
        ToolInput(const Vec2(1, 0.05), hit: circle, snapThreshold: 0.2),
      );
      // Second tap also lands on the circle: with the circle slot full it
      // must be ignored — not resolved into a glued point.
      final repeat = tool.onInput(
        ToolInput(const Vec2(0, 1.05), hit: circle, snapThreshold: 0.2),
      );
      expect(repeat, isA<ToolIgnored>());

      // The collection is still live: a point tap completes the pair.
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final result = tool.onInput(ToolInput(p.position, hit: p));
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command as MacroCommand;
      expect(
        command.commands.map((c) => (c as AddObjectCommand).object),
        everyElement(isA<TangentLine>()),
      );
    });

    test('the circle is consulted from extraHits before the point ladder', () {
      final other = FreePoint(id: 'o', position: const Vec2(0, 3));
      final line = LineThroughTwoPoints(id: 'l', point1: rim, point2: other);
      final tool = newTool();
      // The tap's topmost hit is the line, with the circle in threshold
      // behind it: the circle slot must win — no glue, no crossing snap.
      final result = tool.onInput(
        ToolInput(
          const Vec2(1, 0.05),
          hit: line,
          extraHits: [circle],
          snapThreshold: 0.2,
        ),
      );
      expect(result, isA<ToolAccepted>());
      expect(tool.previewObjectIds, ['circ']);
      expect(tool.previewPositions, isEmpty);
    });

    test(
      'with the circle slot full, a line tap still glues via the ladder',
      () {
        final other = FreePoint(id: 'o', position: const Vec2(-2, 3));
        final far = FreePoint(id: 'f', position: const Vec2(-2, -3));
        final line = LineThroughTwoPoints(id: 'l', point1: other, point2: far);
        final tool = newTool();
        tool.onInput(ToolInput(const Vec2(1, 0.05), hit: circle));
        final result = tool.onInput(
          ToolInput(const Vec2(-2, 1), hit: line, snapThreshold: 0.2),
        );
        expect(result, isA<ToolCommitted>());
        final command = (result as ToolCommitted).command as MacroCommand;
        expect(command.commands, hasLength(3));
        final glued = (command.commands.first as AddObjectCommand).object;
        expect(glued, isA<PointOnObject>());
        expect((glued as PointOnObject).curve, line);
      },
    );

    test('previews: existing inputs haloed, new point keeps the marker', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final existing = newTool()..onInput(ToolInput(p.position, hit: p));
      expect(existing.previewObjectIds, ['p']);
      expect(existing.previewPositions, isEmpty);

      final fresh = newTool()..onInput(const ToolInput(Vec2(5, 0)));
      expect(fresh.previewObjectIds, isEmpty);
      expect(fresh.previewPositions, [const Vec2(5, 0)]);

      fresh.reset();
      expect(fresh.previewPositions, isEmpty);
    });

    test('a second point input is ignored', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final q = FreePoint(id: 'q', position: const Vec2(0, 5));
      final tool = newTool()..onInput(ToolInput(p.position, hit: p));
      expect(tool.onInput(ToolInput(q.position, hit: q)), isA<ToolIgnored>());
      expect(tool.previewObjectIds, ['p']);
    });
  });
}
