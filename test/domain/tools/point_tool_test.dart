import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late PointTool tool;

  setUp(() {
    nextId = 0;
    tool = PointTool(newId: () => 'p${nextId++}');
  });

  group('PointTool', () {
    test('tap on empty canvas commits an AddObjectCommand for a FreePoint', () {
      final result = tool.onInput(const ToolInput(Vec2(3, -2)));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final object = (command as AddObjectCommand).object;
      expect(object, isA<FreePoint>());
      expect((object as FreePoint).position, const Vec2(3, -2));
      expect(object.id, 'p0');
    });

    test('committed command adds the point to a construction', () {
      final construction = Construction();
      final result = tool.onInput(const ToolInput(Vec2(1, 1))) as ToolCommitted;

      result.command.apply(construction);

      expect(construction.length, 1);
      final point = construction.objects.single as FreePoint;
      expect(point.position, const Vec2(1, 1));
    });

    test('successive taps produce distinct ids', () {
      final first = tool.onInput(const ToolInput(Vec2.zero)) as ToolCommitted;
      final second = tool.onInput(const ToolInput(Vec2(1, 0))) as ToolCommitted;

      final firstId = (first.command as AddObjectCommand).object.id;
      final secondId = (second.command as AddObjectCommand).object.id;
      expect(firstId, isNot(secondId));
    });

    test('tap that hits an existing point is ignored', () {
      final existing = FreePoint(id: 'x', position: Vec2.zero);

      final result = tool.onInput(ToolInput(Vec2.zero, hit: existing));

      expect(result, isA<ToolIgnored>());
      expect(nextId, 0, reason: 'no id must be consumed for an ignored tap');
    });

    test('tap that hits a line glues a PointOnObject at the projection', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      construction
        ..add(a)
        ..add(b)
        ..add(line);

      final result = tool.onInput(ToolInput(const Vec2(3, 1), hit: line));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final point = (command as AddObjectCommand).object as PointOnObject;
      expect(point.parents, [line]);
      command.apply(construction);
      expect(point.position!.closeTo(const Vec2(3, 0)), isTrue);
    });

    test('tap that hits a circle glues a PointOnObject on the rim', () {
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);

      final result = tool.onInput(ToolInput(const Vec2(0, 5), hit: circle));

      final point =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as PointOnObject;
      expect(point.position!.closeTo(const Vec2(0, 2)), isTrue);
    });

    test('tap near two crossing lines commits an IntersectionPoint', () {
      final l1 = LineThroughTwoPoints(
        id: 'l1',
        point1: FreePoint(id: 'a', position: Vec2.zero),
        point2: FreePoint(id: 'b', position: const Vec2(4, 0)),
      );
      final l2 = LineThroughTwoPoints(
        id: 'l2',
        point1: FreePoint(id: 'c', position: const Vec2(2, -2)),
        point2: FreePoint(id: 'd', position: const Vec2(2, 2)),
      );

      final result = tool.onInput(
        ToolInput(
          const Vec2(2.2, 0.2),
          hit: l1,
          extraHits: [l2],
          snapThreshold: 1,
        ),
      );

      final point =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as IntersectionPoint;
      expect(point.parents, [l1, l2]);
      expect(point.position!.closeTo(const Vec2(2, 0)), isTrue);
    });

    test('reset is safe at any time and the tool keeps working after it', () {
      tool.reset();
      expect(tool.onInput(const ToolInput(Vec2.zero)), isA<ToolCommitted>());
      tool.reset();
    });
  });
}
