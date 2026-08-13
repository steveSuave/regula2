import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/length_measurement.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/distance_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  var nextId = 0;
  String newId() => 'new${nextId++}';

  setUp(() => nextId = 0);

  group('DistanceTool', () {
    late FreePoint a, b;
    late CircleCenterPoint circle;

    setUp(() {
      a = FreePoint(id: 'a', position: const Vec2(0, 0));
      b = FreePoint(id: 'b', position: const Vec2(3, 4));
      circle = CircleCenterPoint(id: 'k', center: a, onCircle: b);
    });

    test('two existing points commit one DistanceMeasurement', () {
      final tool = DistanceTool(newId: newId);
      expect(
        tool.onInput(ToolInput(const Vec2(0, 0), hit: a)),
        isA<ToolAccepted>(),
      );
      final result = tool.onInput(ToolInput(const Vec2(3, 4), hit: b));
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(
        command,
        isA<AddObjectCommand>(),
        reason: 'no new points → a bare add, no macro',
      );
      final distance =
          (command as AddObjectCommand).object as DistanceMeasurement;
      expect(distance.value, 5);
      expect(distance.parents, [a, b]);
    });

    test('empty taps create the endpoints too, all in one undo unit', () {
      final tool = DistanceTool(newId: newId);
      tool.onInput(const ToolInput(Vec2(0, 0)));
      final result = tool.onInput(const ToolInput(Vec2(0, 2)));
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<MacroCommand>());

      final construction = Construction();
      command.apply(construction);
      final objects = construction.objects.toList();
      expect(objects, hasLength(3));
      expect(objects[0], isA<FreePoint>());
      expect(objects[1], isA<FreePoint>());
      expect(objects[2], isA<DistanceMeasurement>());
      expect((objects[2] as DistanceMeasurement).value, 2);

      command.undo(construction);
      expect(construction.isEmpty, isTrue);
    });

    test('a first tap topmost on a circle commits its circumference', () {
      final tool = DistanceTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(5, 0), hit: circle, snapThreshold: 1),
      );
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(
        command,
        isA<AddObjectCommand>(),
        reason: 'one length in one command — no glued point by-product',
      );
      final length = (command as AddObjectCommand).object;
      expect(length, isA<LengthMeasurement>());
      expect((length as LengthMeasurement).subject, same(circle));
      expect(length.value, closeTo(10 * math.pi, 1e-12));
    });

    test('a first tap on an arc commits its arc length, tool reusable', () {
      // Unit semicircle through (0, 1): sweep π, length π.
      final s = FreePoint(id: 's', position: const Vec2(1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final e = FreePoint(id: 'e', position: const Vec2(-1, 0));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final tool = DistanceTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(0, 1), hit: arc, snapThreshold: 1),
      );
      expect(result, isA<ToolCommitted>());
      final length =
          ((result as ToolCommitted).command as AddObjectCommand).object;
      expect((length as LengthMeasurement).value, closeTo(math.pi, 1e-12));

      expect(
        tool.onInput(ToolInput(const Vec2(0, 0), hit: a)),
        isA<ToolAccepted>(),
        reason: 'committing resets nothing — the tool never left idle',
      );
    });

    test('a first tap on a sector commits its full perimeter', () {
      // Quarter wedge of radius 2: 2·2 + 2·π/2.
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final s = FreePoint(id: 's', position: const Vec2(2, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 2));
      final sector = Sector(id: 'sec', center: o, start: s, end: e);
      final tool = DistanceTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(2, 0.5), hit: sector, snapThreshold: 1),
      );
      expect(result, isA<ToolCommitted>());
      final length =
          ((result as ToolCommitted).command as AddObjectCommand).object;
      expect((length as LengthMeasurement).value, closeTo(4 + math.pi, 1e-12));
    });

    test('an in-threshold point outranks the curve — point flow wins', () {
      final tool = DistanceTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(3, 4), hit: b, extraHits: [circle]),
      );
      expect(
        result,
        isA<ToolAccepted>(),
        reason: 'the rim point starts a point-to-point measurement',
      );
      expect(nextId, 0);
    });

    test('with one point collected, a curve tap glues as before', () {
      final tool = DistanceTool(newId: newId);
      tool.onInput(ToolInput(const Vec2(3, 4), hit: b));
      final result = tool.onInput(
        ToolInput(const Vec2(-3, -4), hit: circle, snapThreshold: 1),
      );
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(
        command,
        isA<MacroCommand>(),
        reason: 'glued point + measurement land together',
      );

      final construction = Construction()
        ..add(a)
        ..add(b)
        ..add(circle);
      command.apply(construction);
      final objects = construction.objects.toList();
      expect(objects[3], isA<PointOnObject>());
      expect(objects[4], isA<DistanceMeasurement>());
      expect(
        (objects[4] as DistanceMeasurement).value,
        closeTo(10, 1e-12),
        reason: 'diameter: rim point to the antipodal glued point',
      );
    });
  });
}
