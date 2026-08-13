import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/angle_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FreePoint o;
  late FreePoint x;
  late FreePoint y;
  late LineThroughTwoPoints xAxis;
  late LineThroughTwoPoints yAxis;

  AngleTool tool() => AngleTool(newId: () => 'n${nextId++}');

  setUp(() {
    nextId = 0;
    o = FreePoint(id: 'o', position: Vec2.zero);
    x = FreePoint(id: 'x', position: const Vec2(4, 0));
    y = FreePoint(id: 'y', position: const Vec2(0, 4));
    xAxis = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
    yAxis = LineThroughTwoPoints(id: 'v', point1: o, point2: y);
  });

  group('AngleTool — two-line mode', () {
    test('two line taps commit one LineAngle, zero points', () {
      final t = tool();
      expect(
        t.onInput(ToolInput(const Vec2(3, 0.1), hit: xAxis)),
        isA<ToolAccepted>(),
      );
      final result = t.onInput(ToolInput(const Vec2(0.1, 3), hit: yAxis));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final angle = (command as AddObjectCommand).object as LineAngle;
      expect(angle.parents, [xAxis, yAxis]);
      expect(angle.angle!.vertex.closeTo(Vec2.zero), isTrue);
      expect(
        angle.angle!.measure,
        closeTo(math.pi / 2, 1e-9),
        reason: 'first-quadrant taps pick the first-quadrant wedge',
      );
    });

    test('segments count through their carriers', () {
      final t = tool();
      final side1 = Segment(id: 's1', point1: o, point2: x);
      final side2 = Segment(id: 's2', point1: o, point2: y);

      t.onInput(ToolInput(const Vec2(2, 0), hit: side1));
      final result = t.onInput(ToolInput(const Vec2(0, 2), hit: side2));
      expect(result, isA<ToolCommitted>());
      expect(
        ((result as ToolCommitted).command as AddObjectCommand).object,
        isA<LineAngle>(),
      );
    });

    test('the same line twice, points, circles and empty taps are ignored', () {
      final t = tool();
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: x);
      t.onInput(ToolInput(const Vec2(2, 0), hit: xAxis));

      expect(
        t.onInput(ToolInput(const Vec2(3, 0), hit: xAxis)),
        isA<ToolIgnored>(),
      );
      expect(
        t.onInput(ToolInput(Vec2.zero, hit: o)),
        isA<ToolIgnored>(),
        reason: 'modes never mix — no point collection after a line',
      );
      expect(
        t.onInput(ToolInput(const Vec2(4, 0), hit: circle)),
        isA<ToolIgnored>(),
      );
      expect(t.onInput(const ToolInput(Vec2(9, 9))), isA<ToolIgnored>());
    });

    test('the collected line is haloed, no marker', () {
      final t = tool();
      t.onInput(ToolInput(const Vec2(2, 0.2), hit: xAxis));

      expect(t.previewObjectIds, ['h']);
      expect(t.previewPositions, isEmpty);
    });
  });

  group('AngleTool — point mode', () {
    test('three existing points commit just the VertexAngle', () {
      final t = tool();
      t.onInput(ToolInput(x.position, hit: x));
      t.onInput(ToolInput(o.position, hit: o));
      final result = t.onInput(ToolInput(y.position, hit: y));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final angle = (command as AddObjectCommand).object as VertexAngle;
      expect(angle.parents, [x, o, y], reason: 'tap order is arm, vertex, arm');
      expect(angle.angle!.vertex.closeTo(Vec2.zero), isTrue);
      expect(angle.angle!.measure, closeTo(math.pi / 2, 1e-9));
    });

    test('empty-canvas taps create free points, one MacroCommand', () {
      final construction = Construction();
      final t = tool();
      t.onInput(const ToolInput(Vec2(4, 0)));
      t.onInput(const ToolInput(Vec2(0, 0)));
      final result = t.onInput(const ToolInput(Vec2(0, 4)));

      final macro = (result as ToolCommitted).command as MacroCommand;
      macro.apply(construction);
      expect(construction.length, 4, reason: '3 free points + the angle');
      expect(construction.objects.whereType<FreePoint>().length, 3);
      macro.undo(construction);
      expect(construction.length, 0, reason: 'one undo unit');
    });

    test('curve taps are ignored — no glued by-product points', () {
      final t = tool();
      t.onInput(ToolInput(x.position, hit: x));

      expect(
        t.onInput(
          ToolInput(
            const Vec2(2, 0.1),
            hit: xAxis,
            extraHits: [yAxis],
            snapThreshold: 1,
          ),
        ),
        isA<ToolIgnored>(),
        reason: 'a line tap in point mode must not glue a PointOnObject',
      );
      // The collection is still just the first point; two more existing
      // points complete it.
      t.onInput(ToolInput(o.position, hit: o));
      expect(t.onInput(ToolInput(y.position, hit: y)), isA<ToolCommitted>());
    });

    test('an already-collected point is refused', () {
      final t = tool();
      t.onInput(ToolInput(x.position, hit: x));
      expect(t.onInput(ToolInput(x.position, hit: x)), isA<ToolIgnored>());
    });

    test('existing points are haloed, new free points keep the marker', () {
      final t = tool();
      t.onInput(ToolInput(x.position, hit: x));
      t.onInput(const ToolInput(Vec2(1, 1)));

      expect(t.previewObjectIds, ['x']);
      expect(t.previewPositions, [const Vec2(1, 1)]);
    });

    test('reset clears both modes', () {
      final t = tool()
        ..onInput(ToolInput(const Vec2(2, 0), hit: xAxis))
        ..reset();
      expect(t.previewObjectIds, isEmpty);
      // After reset a point tap enters point mode from scratch.
      expect(t.onInput(ToolInput(x.position, hit: x)), isA<ToolAccepted>());

      t.reset();
      expect(t.previewObjectIds, isEmpty);
      expect(t.previewPositions, isEmpty);
    });
  });
}
