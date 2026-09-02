import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/random_shape_stamp_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;

  RandomShapeStampTool toolFor({
    required int min,
    required int max,
    int seed = 7,
  }) => RandomShapeStampTool(
    newId: () => 'n${nextId++}',
    minVertices: min,
    maxVertices: max,
    random: math.Random(seed),
  );

  setUp(() => nextId = 0);

  group('RandomShapeStampTool', () {
    test('one tap stamps free vertices joined by segments, one undo unit', () {
      final construction = Construction();
      final tool = toolFor(min: 3, max: 3);

      final result =
          tool.onInput(const ToolInput(Vec2(10, -5))) as ToolCommitted;
      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);

      expect(construction.objects.whereType<FreePoint>(), hasLength(3));
      expect(construction.objects.whereType<Segment>(), hasLength(3));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole stamp is one undo unit',
      );
    });

    test('vertices land in the stamp annulus around the tap', () {
      const tap = Vec2(100, 200);
      const threshold = 4.0; // world units → radius 40
      final construction = Construction();
      final tool = toolFor(min: 4, max: 7);

      final result = tool.onInput(
        const ToolInput(tap, snapThreshold: threshold),
      ) as ToolCommitted;
      result.command.apply(construction);

      for (final vertex in construction.objects.whereType<FreePoint>()) {
        final distance = vertex.position.distanceTo(tap);
        expect(distance, greaterThanOrEqualTo(20));
        expect(distance, lessThanOrEqualTo(40));
      }
    });

    test('the vertex count stays inside the requested range', () {
      for (var seed = 0; seed < 20; seed++) {
        final construction = Construction();
        final tool = toolFor(min: 4, max: 7, seed: seed);
        (tool.onInput(const ToolInput(Vec2(0, 0))) as ToolCommitted).command
            .apply(construction);
        final count = construction.objects.whereType<FreePoint>().length;
        expect(count, inInclusiveRange(4, 7));
        expect(
          construction.objects.whereType<Segment>(),
          hasLength(count),
          reason: 'the outline closes',
        );
      }
    });

    test('the outline is simple — vertices wind around the tap in order', () {
      const tap = Vec2(0, 0);
      final construction = Construction();
      final tool = toolFor(min: 5, max: 5);
      (tool.onInput(const ToolInput(tap)) as ToolCommitted).command.apply(
        construction,
      );

      // The stamp draws its angles in [0, 2π); atan2 lives in [−π, π], so
      // normalize back before comparing the winding order.
      final angles = [
        for (final v in construction.objects.whereType<FreePoint>())
          math.atan2(v.position.y, v.position.x) % (2 * math.pi),
      ];
      final sorted = List.of(angles)..sort();
      expect(angles, sorted, reason: 'sorted angles cannot self-intersect');
    });

    test('the convex quadrilateral is strictly convex for every seed', () {
      const tap = Vec2(3, -8);
      for (var seed = 0; seed < 200; seed++) {
        nextId = 0;
        final construction = Construction();
        final tool = RandomShapeStampTool.convexQuadrilateral(
          newId: () => 'n${nextId++}',
          random: math.Random(seed),
        );
        (tool.onInput(const ToolInput(tap)) as ToolCommitted).command.apply(
          construction,
        );

        // Stamp order is polygon order — the vertices land before the
        // segments in insertion order.
        final corners = [
          for (final v in construction.objects.whereType<FreePoint>())
            v.position,
        ];
        expect(corners, hasLength(4), reason: 'seed $seed');
        final crossProducts = [
          for (var k = 0; k < 4; k++)
            (corners[(k + 1) % 4] - corners[k]).cross(
              corners[(k + 2) % 4] - corners[(k + 1) % 4],
            ),
        ];
        for (final crossProduct in crossProducts) {
          expect(
            crossProduct,
            isNot(0),
            reason: 'seed $seed: no straight or reflex corner',
          );
          expect(
            crossProduct.sign,
            crossProducts.first.sign,
            reason: 'seed $seed: all corners turn the same way',
          );
        }
      }
    });

    test(
      'the convex quadrilateral closes with 4 segments in one undo unit',
      () {
        final construction = Construction();
        final tool = RandomShapeStampTool.convexQuadrilateral(
          newId: () => 'n${nextId++}',
          random: math.Random(11),
        );

        final result =
            tool.onInput(const ToolInput(Vec2(0, 0))) as ToolCommitted;
        expect(result.command, isA<MacroCommand>());
        result.command.apply(construction);

        final vertices = construction.objects.whereType<FreePoint>().toList();
        final segments = construction.objects.whereType<Segment>().toList();
        expect(vertices, hasLength(4));
        expect(segments, hasLength(4));
        for (final vertex in vertices) {
          final degree = segments
              .where((s) => s.point1 == vertex || s.point2 == vertex)
              .length;
          expect(degree, 2, reason: 'the outline closes through every vertex');
        }

        result.command.undo(construction);
        expect(construction.isEmpty, isTrue);
      },
    );

    test('the convex quadrilateral stays centered near the tap', () {
      const tap = Vec2(100, 200);
      const threshold = 4.0; // world units → circle radius 40
      for (var seed = 0; seed < 50; seed++) {
        nextId = 0;
        final construction = Construction();
        final tool = RandomShapeStampTool.convexQuadrilateral(
          newId: () => 'n${nextId++}',
          random: math.Random(seed),
        );
        (tool.onInput(
          const ToolInput(tap, snapThreshold: threshold),
        ) as ToolCommitted).command.apply(construction);

        // On-circle distance 40, stretched by axis factors in [0.7, 1.3].
        for (final vertex in construction.objects.whereType<FreePoint>()) {
          final distance = vertex.position.distanceTo(tap);
          expect(
            distance,
            greaterThanOrEqualTo(40 * 0.7),
            reason: 'seed $seed',
          );
          expect(distance, lessThanOrEqualTo(40 * 1.3), reason: 'seed $seed');
        }
      }
    });

    test('a tap on an existing point stamps beside it, never consuming it', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(0, 0));
      construction.add(e);
      final tool = toolFor(min: 3, max: 3);

      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      result.command.apply(construction);
      expect(
        construction.objects.whereType<FreePoint>(),
        hasLength(4),
        reason: 'three new vertices, the hit point untouched',
      );

      result.command.undo(construction);
      expect(construction.objects, [e]);
    });
  });
}
