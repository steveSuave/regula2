import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/point_and_line_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FreePoint a;
  late FreePoint b;
  late LineThroughTwoPoints refLine;

  PointAndLineTool toolFor(PointAndLineBuilder build) =>
      PointAndLineTool(newId: () => 'n${nextId++}', build: build);

  setUp(() {
    nextId = 0;
    a = FreePoint(id: 'a', position: const Vec2(0, 0));
    b = FreePoint(id: 'b', position: const Vec2(4, 0));
    refLine = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
  });

  group('PointAndLineTool', () {
    test('point first or line first, same object either way', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));

      for (final lineFirst in [true, false]) {
        final tool = toolFor(PerpendicularLine.new);
        final inputs = [
          ToolInput(const Vec2(2, 0), hit: refLine),
          ToolInput(p.position, hit: p),
        ];
        if (!lineFirst) {
          inputs.setAll(0, inputs.reversed.toList());
        }

        expect(tool.onInput(inputs[0]), isA<ToolAccepted>());
        final result = tool.onInput(inputs[1]);
        expect(result, isA<ToolCommitted>());
        final command = (result as ToolCommitted).command;
        final derived =
            (command as AddObjectCommand).object as PerpendicularLine;
        expect(
          derived.parents,
          [p, refLine],
          reason:
              'parent order is (through, reference) regardless of '
              'tap order (lineFirst: $lineFirst)',
        );
      }
    });

    test(
      'empty canvas creates a new free point, grouped in one MacroCommand',
      () {
        final construction = Construction()
          ..add(a)
          ..add(b)
          ..add(refLine);
        final tool = toolFor(ParallelLine.new);

        tool.onInput(ToolInput(const Vec2(2, 0), hit: refLine));
        final result =
            tool.onInput(const ToolInput(Vec2(1, 5))) as ToolCommitted;

        expect(result.command, isA<MacroCommand>());
        result.command.apply(construction);
        expect(construction.length, 5, reason: 'the new free point + the line');
        final derived = construction.objects.last as ParallelLine;
        expect(derived.through.position, const Vec2(1, 5));
        expect(derived.line!.isParallelTo(refLine.line!), isTrue);

        result.command.undo(construction);
        expect(
          construction.length,
          3,
          reason: 'the whole step is one undo unit',
        );
      },
    );

    test('a second line, a second point, or any circle is ignored', () {
      final other = LineThroughTwoPoints(
        id: 'm',
        point1: a,
        point2: FreePoint(id: 'c', position: const Vec2(0, 4)),
      );
      final rim = FreePoint(id: 'r', position: const Vec2(1, 0));
      final circle = CircleCenterPoint(id: 'o', center: a, onCircle: rim);
      final tool = toolFor(PerpendicularLine.new);

      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: refLine)),
        isA<ToolAccepted>(),
      );
      expect(
        tool.onInput(ToolInput(const Vec2(1, 2), hit: other)),
        isA<ToolIgnored>(),
      );
      expect(
        tool.onInput(ToolInput(const Vec2(1, 0), hit: circle)),
        isA<ToolIgnored>(),
      );

      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      expect(tool.onInput(ToolInput(p.position, hit: p)), isA<ToolCommitted>());
    });

    test(
      'with the point slot filled, empty canvas is ignored (missed tap)',
      () {
        final p = FreePoint(id: 'p', position: const Vec2(1, 5));
        final tool = toolFor(PerpendicularLine.new);

        tool.onInput(ToolInput(p.position, hit: p));
        expect(tool.onInput(const ToolInput(Vec2(9, 9))), isA<ToolIgnored>());
        expect(
          tool.onInput(ToolInput(const Vec2(2, 0), hit: refLine)),
          isA<ToolCommitted>(),
        );
      },
    );

    test('preview: existing point and line are haloed, no markers', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final tool = toolFor(PerpendicularLine.new);
      expect(tool.previewPositions, isEmpty);
      expect(tool.previewObjectIds, isEmpty);

      tool.onInput(ToolInput(p.position, hit: p));
      expect(tool.previewObjectIds, ['p']);
      expect(
        tool.previewPositions,
        isEmpty,
        reason: 'an existing point is haloed, never marked',
      );

      tool.onInput(ToolInput(const Vec2(2, 3), hit: refLine));
      expect(tool.previewObjectIds, isEmpty, reason: 'commit clears state');
    });

    test('preview: a new free point keeps the dot+ring marker', () {
      final tool = toolFor(PerpendicularLine.new);

      tool.onInput(const ToolInput(Vec2(1, 5)));
      expect(tool.previewPositions, [
        const Vec2(1, 5),
      ], reason: 'the point is not in the construction yet');
      expect(tool.previewObjectIds, isEmpty);

      tool.onInput(ToolInput(const Vec2(2, 3), hit: refLine));
      expect(tool.previewPositions, isEmpty, reason: 'commit clears state');
    });

    test('reset mid-collection discards both slots', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final tool = toolFor(PerpendicularLine.new);

      tool.onInput(ToolInput(const Vec2(2, 0), hit: refLine));
      tool.reset();
      expect(tool.previewObjectIds, isEmpty);

      // A fresh point + line still commits from scratch.
      tool.onInput(ToolInput(p.position, hit: p));
      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: refLine)),
        isA<ToolCommitted>(),
      );
    });
  });
}
