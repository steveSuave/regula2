import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/fixed_length_segment_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FixedLengthSegmentTool tool;

  setUp(() {
    nextId = 0;
    tool = FixedLengthSegmentTool(newId: () => 'n${nextId++}', length: 3);
  });

  double segmentLength(Construction c) {
    final segment = c.objects.whereType<Segment>().single;
    return segment.point1.position!.distanceTo(segment.point2.position!);
  }

  group('FixedLengthSegmentTool', () {
    test('endpoint tap plus a direction tap commit one macro', () {
      final construction = Construction();

      expect(
        tool.onInput(const ToolInput(Vec2(1, 1))),
        isA<ToolAccepted>(),
        reason: 'the endpoint does not commit — the direction is pending',
      );
      final result = tool.onInput(const ToolInput(Vec2(5, 1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        4,
        reason: 'free endpoint + hidden circle + B + segment',
      );

      final circle = construction.objects.whereType<FixedRadiusCircle>().single;
      expect(
        circle.attributes.visible,
        isFalse,
        reason: 'the circle is scaffolding',
      );
      final b = construction.objects.whereType<PointOnObject>().single;
      expect(b.attributes.visible, isTrue);
      expect(
        b.position,
        const Vec2(4, 1),
        reason: 'B sits toward the direction tap at distance 3',
      );
      expect(segmentLength(construction), closeTo(3, 1e-12));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole segment is one undo unit',
      );
    });

    test('the length is pinned under dragging A and sliding B', () {
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(1, 1)));
      (tool.onInput(const ToolInput(Vec2(5, 1))) as ToolCommitted).command
          .apply(construction);

      final a = construction.objects.whereType<FreePoint>().single;
      final b = construction.objects.whereType<PointOnObject>().single;

      construction.moveFreePoint(a.id, const Vec2(-7, 2));
      expect(segmentLength(construction), closeTo(3, 1e-12));

      // Sliding B around the hidden circle changes direction, not length.
      construction.setPointOnObjectParameter(b.id, 2.1);
      expect(segmentLength(construction), closeTo(3, 1e-12));
      expect(b.position, isNot(const Vec2(-4, 2)));
    });

    test('the direction tap never consumes an existing point', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(1, 5));
      construction.add(e);

      tool.onInput(const ToolInput(Vec2(1, 1)));
      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      result.command.apply(construction);

      final b = construction.objects.whereType<PointOnObject>().single;
      expect(
        b.position!.distanceTo(const Vec2(1, 4)),
        closeTo(0, 1e-12),
        reason: 'the hit point only donates its position',
      );
      expect(
        b.parents,
        [construction.objects.whereType<FixedRadiusCircle>().single],
        reason: 'B is constrained to the circle, not to the tapped point',
      );
    });

    test('a direction tap exactly on the endpoint falls back to angle 0', () {
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(1, 1)));
      (tool.onInput(const ToolInput(Vec2(1, 1))) as ToolCommitted).command
          .apply(construction);

      final b = construction.objects.whereType<PointOnObject>().single;
      expect(
        b.position,
        const Vec2(4, 1),
        reason: 'no direction — angleAt of the center is 0, B due east',
      );
      expect(segmentLength(construction), closeTo(3, 1e-12));
    });
  });
}
