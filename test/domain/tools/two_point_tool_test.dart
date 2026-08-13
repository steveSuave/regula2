import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/two_point_tool.dart';

void main() {
  late int nextId;

  TwoPointTool toolFor(TwoPointBuilder build) =>
      TwoPointTool(newId: () => 'n${nextId++}', build: build);

  setUp(() => nextId = 0);

  group('TwoPointTool', () {
    test('two taps on existing points commit just the object', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final tool = toolFor(
        (id, p, q) => LineThroughTwoPoints(id: id, point1: p, point2: q),
      );

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      final result = tool.onInput(ToolInput(b.position, hit: b));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final line = (command as AddObjectCommand).object as LineThroughTwoPoints;
      expect(line.parents, [a, b]);
    });

    test('tap order is builder argument order: first tap is the center', () {
      final construction = Construction();
      final tool = toolFor(
        (id, p, q) => CircleCenterPoint(id: id, center: p, onCircle: q),
      );

      tool.onInput(const ToolInput(Vec2(1, 1)));
      final result = tool.onInput(const ToolInput(Vec2(4, 1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 3, reason: '2 free points + the circle');
      final circle = construction.objects.last as CircleCenterPoint;
      expect(circle.circle!.center, const Vec2(1, 1));
      expect(circle.circle!.radius, closeTo(3, 1e-12));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole step is one undo unit',
      );
    });

    test('the same existing point twice is ignored', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final tool = toolFor(
        (id, p, q) => Midpoint(id: id, point1: p, point2: q),
      );

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolIgnored>());
      expect(tool.collectedVertices, hasLength(1));
    });

    test('a tap on a curve collects a glued PointOnObject vertex', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      construction
        ..add(a)
        ..add(b)
        ..add(line);
      final tool = toolFor(
        (id, p, q) => Midpoint(id: id, point1: p, point2: q),
      );

      tool.onInput(ToolInput(const Vec2(1, 0.1), hit: line));
      final result =
          tool.onInput(ToolInput(a.position, hit: a)) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 5, reason: 'glued vertex + the midpoint');
      final vertex = construction.objects.whereType<PointOnObject>().single;
      expect(vertex.parents, [line]);
      expect(
        vertex.position!.closeTo(const Vec2(1, 0)),
        isTrue,
        reason: 'the vertex projects onto the curve',
      );
      final midpoint = construction.objects.whereType<Midpoint>().single;
      expect(midpoint.position!.closeTo(const Vec2(0.5, 0)), isTrue);

      result.command.undo(construction);
      expect(
        construction.length,
        3,
        reason: 'glued vertex and midpoint undo as one unit',
      );
    });

    test(
      'a tap near a curve crossing collects an IntersectionPoint vertex',
      () {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(4, 0));
        final c = FreePoint(id: 'c', position: const Vec2(2, -2));
        final d = FreePoint(id: 'd', position: const Vec2(2, 2));
        final l1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
        final l2 = LineThroughTwoPoints(id: 'l2', point1: c, point2: d);
        construction
          ..add(a)
          ..add(b)
          ..add(c)
          ..add(d)
          ..add(l1)
          ..add(l2);
        final tool = toolFor(
          (id, p, q) => Midpoint(id: id, point1: p, point2: q),
        );

        tool.onInput(
          ToolInput(
            const Vec2(2.1, 0.1),
            hit: l1,
            extraHits: [l2],
            snapThreshold: 1,
          ),
        );
        expect(
          tool.previewPositions,
          hasLength(1),
          reason: 'a not-yet-committed intersection snap keeps its marker',
        );
        expect(tool.previewObjectIds, isEmpty);
        final result =
            tool.onInput(ToolInput(a.position, hit: a)) as ToolCommitted;

        result.command.apply(construction);
        final vertex = construction.objects
            .whereType<IntersectionPoint>()
            .single;
        expect(vertex.parents, [l1, l2]);
        expect(vertex.position!.closeTo(const Vec2(2, 0)), isTrue);
      },
    );

    test('previewPositions tracks collection and clears on commit', () {
      final tool = toolFor(
        (id, p, q) => Midpoint(id: id, point1: p, point2: q),
      );

      expect(tool.previewPositions, isEmpty);
      tool.onInput(const ToolInput(Vec2(2, 3)));
      expect(tool.previewPositions, [const Vec2(2, 3)]);

      tool.onInput(const ToolInput(Vec2(4, 5)));
      expect(tool.previewPositions, isEmpty);
    });

    test('a reused existing point is haloed instead of marked', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final tool = toolFor(
        (id, p, q) => Midpoint(id: id, point1: p, point2: q),
      );

      tool.onInput(ToolInput(a.position, hit: a));
      expect(tool.previewObjectIds, ['a']);
      expect(
        tool.previewPositions,
        isEmpty,
        reason: 'an existing point is haloed, never marked',
      );

      tool.onInput(const ToolInput(Vec2(4, 5)));
      expect(tool.previewObjectIds, isEmpty, reason: 'commit clears state');
    });
  });
}
