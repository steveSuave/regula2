import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/polar_line_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FreePoint center;
  late FreePoint rim;
  late CircleCenterPoint circle;

  PolarLineTool newTool() => PolarLineTool(newId: () => 'n${nextId++}');

  setUp(() {
    nextId = 0;
    center = FreePoint(id: 'c', position: Vec2.zero);
    rim = FreePoint(id: 'r', position: const Vec2(1, 0));
    circle = CircleCenterPoint(id: 'circ', center: center, onCircle: rim);
  });

  group('PolarLineTool', () {
    test('point first or circle first, one PolarLine per pair', () {
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
        final command = (result as ToolCommitted).command as AddObjectCommand;
        final polar = command.object as PolarLine;
        expect(polar.parents, [p, circle]);
        // Pole (5, 0) on the unit circle inverts to (1/5, 0): x = 0.2.
        expect(polar.line!.closeTo(LineEq(1, 0, -0.2)), isTrue);
        expect(tool.hasPartialInput, isFalse);
      }
    });

    test('empty canvas creates the pole, whole step is one undo unit', () {
      final construction = Construction()
        ..add(center)
        ..add(rim)
        ..add(circle);
      final tool = newTool();

      tool.onInput(ToolInput(const Vec2(1, 0.05), hit: circle));
      final result = tool.onInput(const ToolInput(Vec2(5, 0))) as ToolCommitted;

      final command = result.command as MacroCommand;
      expect(command.commands, hasLength(2));
      command.apply(construction);
      expect(construction.length, 5, reason: 'new free point + the polar line');
      command.undo(construction);
      expect(construction.length, 3);
    });

    test('a tap on the target circle never glues a PointOnObject', () {
      final tool = newTool();
      tool.onInput(
        ToolInput(const Vec2(1, 0.05), hit: circle, snapThreshold: 0.2),
      );
      final repeat = tool.onInput(
        ToolInput(const Vec2(0, 1.05), hit: circle, snapThreshold: 0.2),
      );
      expect(repeat, isA<ToolIgnored>());

      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final result = tool.onInput(ToolInput(p.position, hit: p));
      expect(result, isA<ToolCommitted>());
      expect(
        ((result as ToolCommitted).command as AddObjectCommand).object,
        isA<PolarLine>(),
      );
    });

    test('an existing polar over the same pair refuses either tap order', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final existing = PolarLine(id: 'x', point: p, circle: circle);
      final objects = [center, rim, p, circle, existing];

      final inputs = [
        ToolInput(p.position, hit: p, objects: objects),
        ToolInput(const Vec2(1, 0.05), hit: circle, objects: objects),
      ];
      for (final circleFirst in [true, false]) {
        final ordered = circleFirst ? inputs.reversed.toList() : inputs;
        final tool = newTool();
        tool.onInput(ordered[0]);
        expect(
          tool.onInput(ordered[1]),
          isA<ToolIgnored>(),
          reason:
              'polar of (p, circ) already exists — circleFirst: '
              '$circleFirst',
        );
        expect(
          tool.hasPartialInput,
          isTrue,
          reason: 'the collected slot stays armed',
        );
      }
    });

    test('a different circle still commits despite an existing polar', () {
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final o2 = FreePoint(id: 'o2', position: const Vec2(0, 5));
      final r2 = FreePoint(id: 'r2', position: const Vec2(1, 5));
      final other = CircleCenterPoint(id: 'c2', center: o2, onCircle: r2);
      final existing = PolarLine(id: 'x', point: p, circle: circle);
      final objects = [center, rim, p, o2, r2, circle, other, existing];

      final tool = newTool();
      tool.onInput(ToolInput(p.position, hit: p, objects: objects));
      expect(
        tool.onInput(ToolInput(const Vec2(1, 5), hit: other, objects: objects)),
        isA<ToolCommitted>(),
      );
    });

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
