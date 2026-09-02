import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/angle_by_size_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;

  AngleBySizeTool toolFor(double angle) =>
      AngleBySizeTool(newId: () => 'n${nextId++}', angle: angle);

  setUp(() => nextId = 0);

  group('AngleBySizeTool', () {
    test('taps are arm then vertex; commits a RotatedPoint plus a '
        'VertexAngle measuring the size', () {
      final arm = FreePoint(id: 'a', position: const Vec2(1, 0));
      final vertex = FreePoint(id: 'v', position: const Vec2(0, 0));
      final tool = toolFor(math.pi / 3);

      expect(
        tool.onInput(ToolInput(arm.position, hit: arm)),
        isA<ToolAccepted>(),
      );
      final result = tool.onInput(ToolInput(vertex.position, hit: vertex));

      expect(result, isA<ToolCommitted>());
      final construction = Construction()
        ..add(arm)
        ..add(vertex);
      (result as ToolCommitted).command.apply(construction);
      expect(
        construction.length,
        4,
        reason: 'the parents + rotated point + angle marker',
      );

      final rotated = construction.objects.whereType<RotatedPoint>().single;
      expect(rotated.parents, [arm, vertex]);
      expect(rotated.angle, math.pi / 3);
      expect(
        rotated.position!.closeTo(
          Vec2(math.cos(math.pi / 3), math.sin(math.pi / 3)),
          1e-12,
        ),
        isTrue,
      );

      final marker = construction.objects.last as VertexAngle;
      expect(marker.arm1, arm, reason: 'CCW size: tapped arm sweeps first');
      expect(marker.vertex, vertex);
      expect(marker.arm2, rotated);
      expect(marker.angle!.measure, closeTo(math.pi / 3, 1e-12));
    });

    test('a negative size swaps the arms so the marker still measures '
        '|angle|', () {
      final arm = FreePoint(id: 'a', position: const Vec2(1, 0));
      final vertex = FreePoint(id: 'v', position: const Vec2(0, 0));
      final tool = toolFor(-math.pi / 4);

      tool.onInput(ToolInput(arm.position, hit: arm));
      final result = tool.onInput(
        ToolInput(vertex.position, hit: vertex),
      ) as ToolCommitted;
      final construction = Construction()
        ..add(arm)
        ..add(vertex);
      result.command.apply(construction);

      final rotated = construction.objects.whereType<RotatedPoint>().single;
      expect(
        rotated.position!.closeTo(
          Vec2(math.cos(-math.pi / 4), math.sin(-math.pi / 4)),
          1e-12,
        ),
        isTrue,
        reason: 'negative = clockwise',
      );
      final marker = construction.objects.last as VertexAngle;
      expect(marker.arm1, rotated);
      expect(marker.arm2, arm);
      expect(marker.angle!.measure, closeTo(math.pi / 4, 1e-12));
    });

    test('empty-canvas taps create free points, all one undo unit', () {
      final construction = Construction();
      final tool = toolFor(math.pi / 2);

      tool.onInput(const ToolInput(Vec2(2, 1)));
      final result = tool.onInput(const ToolInput(Vec2(1, 1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        4,
        reason: '2 free points + rotation + marker',
      );
      final rotated = construction.objects.whereType<RotatedPoint>().single;
      expect(rotated.position!.closeTo(const Vec2(1, 2), 1e-12), isTrue);

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole step is one undo unit',
      );
    });

    test('the marker follows a dragged arm point', () {
      final construction = Construction();
      final arm = FreePoint(id: 'a', position: const Vec2(1, 0));
      final vertex = FreePoint(id: 'v', position: const Vec2(0, 0));
      construction
        ..add(arm)
        ..add(vertex);
      final tool = toolFor(math.pi / 6);

      tool.onInput(ToolInput(arm.position, hit: arm));
      final result = tool.onInput(
        ToolInput(vertex.position, hit: vertex),
      ) as ToolCommitted;
      result.command.apply(construction);

      construction.moveFreePoint('a', const Vec2(0, 5));
      final marker = construction.objects.whereType<VertexAngle>().single;
      expect(
        marker.angle!.measure,
        closeTo(math.pi / 6, 1e-12),
        reason: 'the size is fixed; the arms turn together',
      );
    });

    test('arm on the vertex leaves the marker undefined and it recovers', () {
      final construction = Construction();
      final arm = FreePoint(id: 'a', position: const Vec2(1, 0));
      final vertex = FreePoint(id: 'v', position: const Vec2(0, 0));
      construction
        ..add(arm)
        ..add(vertex);
      final tool = toolFor(1);

      tool.onInput(ToolInput(arm.position, hit: arm));
      final result = tool.onInput(
        ToolInput(vertex.position, hit: vertex),
      ) as ToolCommitted;
      result.command.apply(construction);

      construction.moveFreePoint('a', const Vec2(0, 0));
      final marker = construction.objects.whereType<VertexAngle>().single;
      expect(marker.angle, isNull);

      construction.moveFreePoint('a', const Vec2(2, 0));
      expect(marker.angle!.measure, closeTo(1, 1e-12));
    });

    test('the same existing point twice is ignored', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 1));
      final tool = toolFor(1);

      expect(tool.onInput(ToolInput(p.position, hit: p)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(p.position, hit: p)), isA<ToolIgnored>());
      expect(tool.collectedVertices, hasLength(1));
    });
  });

  group('rotated arm dedup', () {
    test('laying the same angle off twice reuses the arm point', () {
      final construction = Construction();
      final arm = FreePoint(id: 'arm', position: const Vec2(2, 0));
      final vertex = FreePoint(id: 'v', position: const Vec2(0, 0));
      construction.add(arm);
      construction.add(vertex);
      final tool = toolFor(1);
      ToolResult tap(FreePoint point) => tool.onInput(
        ToolInput(point.position, hit: point, objects: construction.objects),
      );

      tap(arm);
      (tap(vertex) as ToolCommitted).command.apply(construction);
      final rotated = construction.objects.whereType<RotatedPoint>().single;

      tap(arm);
      (tap(vertex) as ToolCommitted).command.apply(construction);

      expect(
        construction.objects.whereType<RotatedPoint>().single,
        same(rotated),
        reason: 'the rotated arm point is reused, not stacked',
      );
      final markers = construction.objects.whereType<VertexAngle>().toList();
      expect(markers, hasLength(2), reason: 'the marker itself is still added');
      expect(
        identical(markers[1].arm2, rotated),
        isTrue,
        reason: 'the second marker is wired to the existing arm point',
      );
    });
  });
}
