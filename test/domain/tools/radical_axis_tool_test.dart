import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/radical_axis_line.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/radical_axis_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FreePoint o1;
  late FreePoint r1;
  late FreePoint o2;
  late FreePoint r2;
  late CircleCenterPoint c1;
  late CircleCenterPoint c2;

  RadicalAxisTool tool() => RadicalAxisTool(newId: () => 'n${nextId++}');

  setUp(() {
    nextId = 0;
    o1 = FreePoint(id: 'o1', position: Vec2.zero);
    r1 = FreePoint(id: 'r1', position: const Vec2(2, 0));
    o2 = FreePoint(id: 'o2', position: const Vec2(4, 0));
    r2 = FreePoint(id: 'r2', position: const Vec2(6, 0));
    c1 = CircleCenterPoint(id: 'c1', center: o1, onCircle: r1);
    c2 = CircleCenterPoint(id: 'c2', center: o2, onCircle: r2);
  });

  group('RadicalAxisTool', () {
    test(
      'two circle taps commit one RadicalAxisLine, parents in tap order',
      () {
        final t = tool();

        expect(t.hasPartialInput, isFalse);
        expect(
          t.onInput(ToolInput(const Vec2(2, 0), hit: c1)),
          isA<ToolAccepted>(),
        );
        expect(t.hasPartialInput, isTrue);
        expect(t.previewObjectIds, ['c1']);
        expect(t.previewPositions, isEmpty);

        final result = t.onInput(ToolInput(const Vec2(6, 0), hit: c2));
        expect(result, isA<ToolCommitted>());
        final command = (result as ToolCommitted).command as AddObjectCommand;
        final axis = command.object as RadicalAxisLine;
        expect(axis.parents, [c1, c2]);
        expect(axis.line!.closeTo(LineEq(1, 0, -2)), isTrue);
        expect(t.hasPartialInput, isFalse);
      },
    );

    test('non-circle and empty-canvas taps are ignored', () {
      final line = LineThroughTwoPoints(id: 'l', point1: o1, point2: o2);
      final t = tool();

      expect(t.onInput(ToolInput(const Vec2(1, 1))), isA<ToolIgnored>());
      expect(
        t.onInput(ToolInput(const Vec2(1, 0), hit: o1)),
        isA<ToolIgnored>(),
      );
      expect(
        t.onInput(ToolInput(const Vec2(2, 0), hit: line)),
        isA<ToolIgnored>(),
      );
      expect(t.hasPartialInput, isFalse);
    });

    test('tapping the collected circle again is ignored, stays armed', () {
      final t = tool();
      t.onInput(ToolInput(const Vec2(2, 0), hit: c1));

      expect(
        t.onInput(ToolInput(const Vec2(-2, 0), hit: c1)),
        isA<ToolIgnored>(),
      );
      expect(t.hasPartialInput, isTrue);
      expect(t.previewObjectIds, ['c1']);
    });

    test('an existing axis over the same pair refuses either tap order', () {
      final existing = RadicalAxisLine(id: 'x', circle1: c1, circle2: c2);
      final objects = [o1, r1, o2, r2, c1, c2, existing];

      for (final (first, second) in [(c1, c2), (c2, c1)]) {
        final t = tool();
        t.onInput(ToolInput(const Vec2(2, 0), hit: first, objects: objects));
        expect(
          t.onInput(ToolInput(const Vec2(6, 0), hit: second, objects: objects)),
          isA<ToolIgnored>(),
          reason: 'axis over (${first.id}, ${second.id}) already exists',
        );
        expect(
          t.hasPartialInput,
          isTrue,
          reason: 'the collected circle stays armed',
        );
      }
    });

    test(
      'a different second circle still commits despite an existing axis',
      () {
        final o3 = FreePoint(id: 'o3', position: const Vec2(0, 5));
        final r3 = FreePoint(id: 'r3', position: const Vec2(1, 5));
        final c3 = CircleCenterPoint(id: 'c3', center: o3, onCircle: r3);
        final existing = RadicalAxisLine(id: 'x', circle1: c1, circle2: c2);
        final objects = [o1, r1, o2, r2, o3, r3, c1, c2, c3, existing];

        final t = tool();
        t.onInput(ToolInput(const Vec2(2, 0), hit: c1, objects: objects));
        expect(
          t.onInput(ToolInput(const Vec2(1, 5), hit: c3, objects: objects)),
          isA<ToolCommitted>(),
        );
      },
    );

    test('reset drops the collected circle', () {
      final t = tool();
      t.onInput(ToolInput(const Vec2(2, 0), hit: c1));
      t.reset();
      expect(t.hasPartialInput, isFalse);
      expect(t.previewObjectIds, isEmpty);
    });
  });
}
