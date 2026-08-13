import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/triangle_center_tool.dart';

void main() {
  late int nextId;
  late TriangleCenterTool tool;

  setUp(() {
    nextId = 0;
    tool = TriangleCenterTool(
      newId: () => 'n${nextId++}',
      buildCenter: Centroid.new,
    );
  });

  group('TriangleCenterTool', () {
    test('three taps on existing points commit just the center', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 6));

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(b.position, hit: b)), isA<ToolAccepted>());
      final result = tool.onInput(ToolInput(c.position, hit: c));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final center = (command as AddObjectCommand).object as Centroid;
      expect(center.parents, [a, b, c]);
    });

    test(
      'taps on empty canvas create free points, grouped in a MacroCommand',
      () {
        final construction = Construction();

        tool.onInput(const ToolInput(Vec2(0, 0)));
        tool.onInput(const ToolInput(Vec2(6, 0)));
        final result = tool.onInput(const ToolInput(Vec2(0, 6)));

        expect(result, isA<ToolCommitted>());
        final command = (result as ToolCommitted).command;
        expect(command, isA<MacroCommand>());

        command.apply(construction);
        expect(construction.length, 4, reason: '3 free points + the center');
        final center = construction.objects.last as Centroid;
        expect(center.position!.closeTo(const Vec2(2, 2)), isTrue);

        command.undo(construction);
        expect(
          construction.isEmpty,
          isTrue,
          reason: 'the whole step is one undo unit',
        );
      },
    );

    test('mixed input: only the new free points get add commands', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      construction.add(a);

      tool.onInput(ToolInput(a.position, hit: a));
      tool.onInput(const ToolInput(Vec2(6, 0)));
      final result = tool.onInput(const ToolInput(Vec2(0, 6))) as ToolCommitted;

      final macro = result.command as MacroCommand;
      expect(
        macro.commands,
        hasLength(3),
        reason:
            '2 new free points + the center; the existing point is not '
            're-added',
      );

      macro.apply(construction);
      expect(construction.length, 4);
      macro.undo(construction);
      expect(
        construction.objects.single,
        a,
        reason: 'undo must not remove the pre-existing vertex',
      );
    });

    test('the same existing point twice is ignored', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolIgnored>());
      expect(tool.collectedVertices, hasLength(1));
    });

    test('a tap on a line collects a glued PointOnObject vertex', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 2));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);

      final result = tool.onInput(ToolInput(const Vec2(1, 1), hit: line));

      expect(result, isA<ToolAccepted>());
      final vertex = tool.collectedVertices.single;
      expect(vertex, isA<PointOnObject>());
      expect(vertex.parents, [line]);
    });

    test(
      'collectedVertices exposes in-progress input and empties on commit',
      () {
        expect(tool.collectedVertices, isEmpty);
        tool.onInput(const ToolInput(Vec2(0, 0)));
        tool.onInput(const ToolInput(Vec2(6, 0)));
        expect(tool.collectedVertices, hasLength(2));

        tool.onInput(const ToolInput(Vec2(0, 6)));
        expect(
          tool.collectedVertices,
          isEmpty,
          reason: 'ToolCommitted implies the tool is back in initial state',
        );
      },
    );

    test('reset discards collected vertices and the tool keeps working', () {
      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(6, 0)));
      tool.reset();
      expect(tool.collectedVertices, isEmpty);

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(6, 0)));
      expect(tool.onInput(const ToolInput(Vec2(0, 6))), isA<ToolCommitted>());
    });

    test('works for every center via constructor tear-offs', () {
      final circumTool = TriangleCenterTool(
        newId: () => 'n${nextId++}',
        buildCenter: Circumcenter.new,
      );
      final construction = Construction();

      circumTool.onInput(const ToolInput(Vec2(0, 0)));
      circumTool.onInput(const ToolInput(Vec2(4, 0)));
      final result =
          circumTool.onInput(const ToolInput(Vec2(0, 3))) as ToolCommitted;

      result.command.apply(construction);
      final center = construction.objects.last as Circumcenter;
      expect(center.position!.closeTo(const Vec2(2, 1.5)), isTrue);
    });
  });

  group('dedup refusals', () {
    late Construction construction;
    late FreePoint a;
    late FreePoint b;
    late FreePoint c;

    setUp(() {
      construction = Construction();
      a = FreePoint(id: 'a', position: const Vec2(0, 0));
      b = FreePoint(id: 'b', position: const Vec2(6, 0));
      c = FreePoint(id: 'c', position: const Vec2(0, 6));
      for (final point in [a, b, c]) {
        construction.add(point);
      }
    });

    ToolResult tap(TriangleCenterTool t, FreePoint point) => t.onInput(
      ToolInput(point.position, hit: point, objects: construction.objects),
    );

    test('the same center twice refuses the completing tap', () {
      tap(tool, a);
      tap(tool, b);
      (tap(tool, c) as ToolCommitted).command.apply(construction);
      expect(construction.objects.whereType<Centroid>(), hasLength(1));

      tap(tool, a);
      tap(tool, b);
      expect(
        tap(tool, c),
        isA<ToolIgnored>(),
        reason: 'the identical centroid already exists',
      );
      expect(construction.objects.whereType<Centroid>(), hasLength(1));
    });

    test('a manually built medians crossing stands in for the centroid', () {
      final midBC = Midpoint(id: 'mbc', point1: b, point2: c);
      final midAC = Midpoint(id: 'mac', point1: a, point2: c);
      final median1 = LineThroughTwoPoints(id: 'm1', point1: a, point2: midBC);
      final median2 = LineThroughTwoPoints(id: 'm2', point1: b, point2: midAC);
      final crossing = IntersectionPoint(
        id: 'g',
        curve1: median1,
        curve2: median2,
        branchIndex: 0,
      );
      for (final object in [midBC, midAC, median1, median2, crossing]) {
        construction.add(object);
      }

      tap(tool, a);
      tap(tool, b);
      expect(
        tap(tool, c),
        isA<ToolIgnored>(),
        reason:
            'the medians crossing IS the centroid, by theorem — no '
            'structural check can see it, the identity probe does',
      );
      expect(construction.objects.whereType<Centroid>(), isEmpty);
    });
  });
}
