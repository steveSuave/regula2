import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/angle_tool.dart';
import 'package:regula/domain/tools/delete_tool.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/midpoint_tool.dart';
import 'package:regula/domain/tools/point_and_line_tool.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/domain/tools/tangent_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// `Tool.hasPartialInput` across the hierarchy: false when idle, true
/// exactly while inputs are collected but not yet committed, false again
/// after commit or [Tool.reset] — the contract two-stage cancel (Esc /
/// undo) relies on.
void main() {
  late int nextId;

  setUp(() => nextId = 0);

  String newId() => 'n${nextId++}';

  final a = FreePoint(id: 'a', position: const Vec2(0, 0));
  final b = FreePoint(id: 'b', position: const Vec2(4, 2));

  group('hasPartialInput', () {
    test('MultiPointTool: full collect / commit / reset lifecycle', () {
      final tool = MidpointTool(newId: newId);
      expect(tool.hasPartialInput, isFalse);

      tool.onInput(ToolInput(a.position, hit: a));
      expect(tool.hasPartialInput, isTrue);

      tool.onInput(ToolInput(b.position, hit: b));
      expect(
        tool.hasPartialInput,
        isFalse,
        reason: 'the commit self-resets the tool',
      );

      tool.onInput(ToolInput(a.position, hit: a));
      tool.reset();
      expect(tool.hasPartialInput, isFalse);
    });

    test('TwoLineOrThreePointTool: both modes count as partial', () {
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final lineMode = AngleTool(newId: newId);
      lineMode.onInput(ToolInput(const Vec2(1, 0.5), hit: line));
      expect(lineMode.hasPartialInput, isTrue);

      final pointMode = AngleTool(newId: newId);
      pointMode.onInput(ToolInput(a.position, hit: a));
      expect(pointMode.hasPartialInput, isTrue);
    });

    test('IntersectionTool: armed after the first curve', () {
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final tool = IntersectionTool(newId: newId);
      expect(tool.hasPartialInput, isFalse);

      tool.onInput(ToolInput(const Vec2(1, 0.5), hit: line));
      expect(tool.hasPartialInput, isTrue);

      tool.reset();
      expect(tool.hasPartialInput, isFalse);
    });

    test('PointAndLineTool: either slot alone counts as partial', () {
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final pointFirst = PointAndLineTool(
        newId: newId,
        build: PerpendicularLine.new,
      );
      pointFirst.onInput(ToolInput(a.position, hit: a));
      expect(pointFirst.hasPartialInput, isTrue);

      final lineFirst = PointAndLineTool(
        newId: newId,
        build: PerpendicularLine.new,
      );
      lineFirst.onInput(ToolInput(const Vec2(1, 0.5), hit: line));
      expect(lineFirst.hasPartialInput, isTrue);
    });

    test('TangentTool: a lone collected point counts as partial', () {
      final tool = TangentTool(newId: newId);
      tool.onInput(ToolInput(a.position, hit: a));
      expect(tool.hasPartialInput, isTrue);
    });

    test('single-shot tools never report partial input', () {
      expect(PointTool(newId: newId).hasPartialInput, isFalse);
      expect(const DeleteTool().hasPartialInput, isFalse);
    });
  });
}
