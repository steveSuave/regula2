import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/tools/conic_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;

  ConicTool conicTool() => ConicTool(newId: () => 'n${nextId++}');

  /// Five points of the ellipse x²/4 + y² = 1.
  const ellipse = [
    Vec2(2, 0),
    Vec2(1.0806046117362795, 0.8414709848078965),
    Vec2(-0.8322936730942848, 0.9092974268256817),
    Vec2(-1.979984993200891, 0.1411200080598672),
    Vec2(-1.3072872417272239, -0.7568024953079282),
  ];

  setUp(() => nextId = 0);

  group('ConicTool', () {
    test('five existing points commit just the conic, in tap order', () {
      final points = [
        for (final (i, p) in ellipse.indexed)
          FreePoint(id: 'p$i', position: p),
      ];
      final tool = conicTool();

      for (final p in points.take(4)) {
        expect(
          tool.onInput(ToolInput(p.position, hit: p)),
          isA<ToolAccepted>(),
        );
      }
      final result = tool.onInput(
        ToolInput(points.last.position, hit: points.last),
      );

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      final conic = (command as AddObjectCommand).object as FivePointConic;
      expect(conic.parents, points);
      expect(conic.isDefined, isTrue);
      expect(ConicShape.of(conic.conic!).kind, ConicClass.ellipse);
    });

    test('five canvas taps: 5 free points + the conic in one MacroCommand', () {
      final construction = Construction();
      final tool = conicTool();

      for (final p in ellipse.take(4)) {
        tool.onInput(ToolInput(p));
      }
      final result = tool.onInput(ToolInput(ellipse.last)) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 6);
      final conic = construction.objects.last as FivePointConic;
      expect(conic.isDefined, isTrue);
      for (final p in ellipse) {
        expect(ConicShape.of(conic.conic!).distanceTo(p), lessThan(1e-9));
      }

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole step is one undo unit',
      );
    });

    test('the same point twice is ignored — five *distinct* inputs', () {
      final a = FreePoint(id: 'a', position: ellipse[0]);
      final b = FreePoint(id: 'b', position: ellipse[1]);
      final tool = conicTool();

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolIgnored>());
      expect(tool.onInput(ToolInput(b.position, hit: b)), isA<ToolAccepted>());
      expect(tool.collectedVertices, [a, b]);
    });

    test('a tap on a curve glues a point to it, like every point tool', () {
      final centre = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(1, 0));
      final circle = CircleCenterPoint(id: 'k', center: centre, onCircle: rim);
      final tool = conicTool();

      expect(
        tool.onInput(ToolInput(const Vec2(0, 1.02), hit: circle)),
        isA<ToolAccepted>(),
      );
      final glued = tool.collectedVertices.single;
      expect(glued, isA<PointOnObject>());
      expect(glued.position!.distanceTo(const Vec2(0, 1)), lessThan(1e-9));
    });

    test('a degenerate five-point set still commits, and recovers', () {
      // Four collinear points determine no conic — the object is simply
      // undefined, and a drag of one parent brings it back. Degeneracy is
      // the kind's business, not the tool's.
      final construction = Construction();
      final tool = conicTool();
      const collinear = [
        Vec2(0, 0),
        Vec2(1, 1),
        Vec2(2, 2),
        Vec2(3, 3),
        Vec2(0, 5),
      ];
      for (final p in collinear.take(4)) {
        tool.onInput(ToolInput(p));
      }
      final result = tool.onInput(ToolInput(collinear.last)) as ToolCommitted;
      result.command.apply(construction);

      final conic = construction.objects.last as FivePointConic;
      expect(conic.isDefined, isFalse);

      construction.moveFreePoint(conic.points[3].id, const Vec2(3, 0));
      expect(conic.isDefined, isTrue);
    });

    test('partial input previews the collected points', () {
      final tool = conicTool();
      expect(tool.hasPartialInput, isFalse);
      tool.onInput(const ToolInput(Vec2(2, 0)));
      tool.onInput(const ToolInput(Vec2(0, 1)));
      expect(tool.hasPartialInput, isTrue);
      expect(tool.previewPositions, const [Vec2(2, 0), Vec2(0, 1)]);
      tool.reset();
      expect(tool.hasPartialInput, isFalse);
    });
  });

  test('the sampled ellipse constants are on x²/4 + y² = 1', () {
    // Guards the literals above against a careless edit.
    for (final (i, t) in const [0.0, 1.0, 2.0, 3.0, 4.0].indexed) {
      expect(ellipse[i].x, closeTo(2 * math.cos(t), 1e-15));
      expect(ellipse[i].y, closeTo(math.sin(t), 1e-15));
    }
  });
}
