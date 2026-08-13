import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/triangle_circle_tool.dart';

void main() {
  late int nextId;
  late TriangleCircleTool tool;

  setUp(() {
    nextId = 0;
    tool = TriangleCircleTool(
      newId: () => 'n${nextId++}',
      buildCircle: NinePointCircle.new,
    );
  });

  group('TriangleCircleTool', () {
    test('three taps on existing points commit just the circle', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(b.position, hit: b)), isA<ToolAccepted>());
      final result = tool.onInput(ToolInput(c.position, hit: c));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final circle = (command as AddObjectCommand).object as NinePointCircle;
      expect(circle.parents, [a, b, c]);
      expect(circle.circle!.center.closeTo(const Vec2(1, 0.75)), isTrue);
    });

    test(
      'taps on empty canvas create free points, grouped in a MacroCommand',
      () {
        final construction = Construction();

        tool.onInput(const ToolInput(Vec2(0, 0)));
        tool.onInput(const ToolInput(Vec2(4, 0)));
        final result = tool.onInput(const ToolInput(Vec2(0, 3)));

        expect(result, isA<ToolCommitted>());
        final command = (result as ToolCommitted).command;
        expect(command, isA<MacroCommand>());

        command.apply(construction);
        expect(construction.length, 4, reason: '3 free points + the circle');
        final circle = construction.objects.last as NinePointCircle;
        expect(circle.circle!.radius, closeTo(1.25, 1e-9));

        command.undo(construction);
        expect(
          construction.isEmpty,
          isTrue,
          reason: 'the whole step is one undo unit',
        );
      },
    );

    test('works for the incircle via the constructor tear-off', () {
      final inTool = TriangleCircleTool(
        newId: () => 'n${nextId++}',
        buildCircle: InscribedCircle.new,
      );
      final construction = Construction();

      inTool.onInput(const ToolInput(Vec2(0, 0)));
      inTool.onInput(const ToolInput(Vec2(4, 0)));
      final result =
          inTool.onInput(const ToolInput(Vec2(0, 3))) as ToolCommitted;

      result.command.apply(construction);
      final circle = construction.objects.last as InscribedCircle;
      expect(circle.circle!.center.closeTo(const Vec2(1, 1)), isTrue);
      expect(circle.circle!.radius, closeTo(1, 1e-9));
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
      b = FreePoint(id: 'b', position: const Vec2(4, 0));
      c = FreePoint(id: 'c', position: const Vec2(0, 3));
      for (final point in [a, b, c]) {
        construction.add(point);
      }
    });

    ToolResult tap(TriangleCircleTool t, FreePoint point) => t.onInput(
      ToolInput(point.position, hit: point, objects: construction.objects),
    );

    test('the same circle twice refuses the completing tap', () {
      tap(tool, a);
      tap(tool, b);
      (tap(tool, c) as ToolCommitted).command.apply(construction);
      expect(construction.objects.whereType<NinePointCircle>(), hasLength(1));

      tap(tool, a);
      tap(tool, b);
      expect(
        tap(tool, c),
        isA<ToolIgnored>(),
        reason: 'the identical nine-point circle already exists',
      );
      expect(construction.objects.whereType<NinePointCircle>(), hasLength(1));
    });

    test('a permutation of the same vertices still refuses', () {
      tap(tool, a);
      tap(tool, b);
      (tap(tool, c) as ToolCommitted).command.apply(construction);

      tap(tool, c);
      tap(tool, a);
      expect(
        tap(tool, b),
        isA<ToolIgnored>(),
        reason: 'the circle is symmetric in its vertices',
      );
      expect(construction.objects.whereType<NinePointCircle>(), hasLength(1));
    });

    test('a different circle kind over the same triangle commits', () {
      tap(tool, a);
      tap(tool, b);
      (tap(tool, c) as ToolCommitted).command.apply(construction);

      final inTool = TriangleCircleTool(
        newId: () => 'n${nextId++}',
        buildCircle: InscribedCircle.new,
      );
      tap(inTool, a);
      tap(inTool, b);
      final result = tap(inTool, c);
      expect(
        result,
        isA<ToolCommitted>(),
        reason:
            'the incircle is a different object than the nine-point '
            'circle over the same vertices',
      );
    });
  });
}
