import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/area_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  var nextId = 0;
  String newId() => 'new${nextId++}';

  setUp(() => nextId = 0);

  group('AreaTool', () {
    late FreePoint a, b, c;
    late Polygon polygon;

    setUp(() {
      a = FreePoint(id: 'a', position: const Vec2(0, 0));
      b = FreePoint(id: 'b', position: const Vec2(4, 0));
      c = FreePoint(id: 'c', position: const Vec2(4, 3));
      polygon = Polygon(id: 'p', vertices: [a, b, c]);
    });

    test('a polygon tap commits one AreaMeasurement', () {
      final tool = AreaTool(newId: newId);
      final result = tool.onInput(ToolInput(const Vec2(3, 1), hit: polygon));
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final object = (command as AddObjectCommand).object;
      expect(object, isA<AreaMeasurement>());
      expect((object as AreaMeasurement).subject, same(polygon));
      expect(object.value, 6);
    });

    test('a circle tap commits, and the tool is immediately reusable', () {
      final circle = CircleCenterPoint(id: 'k', center: a, onCircle: b);
      final tool = AreaTool(newId: newId);
      final first = tool.onInput(ToolInput(const Vec2(4, 0), hit: circle));
      expect(first, isA<ToolCommitted>());
      final second = tool.onInput(ToolInput(const Vec2(3, 1), hit: polygon));
      expect(second, isA<ToolCommitted>());
    });

    test('the topmost region is consulted from extraHits past a point hit', () {
      // Tapping near vertex b: the point wins the hit, but the polygon in
      // extraHits is what the tool measures.
      final tool = AreaTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(4, 0), hit: b, extraHits: [polygon]),
      );
      expect(result, isA<ToolCommitted>());
      final object =
          ((result as ToolCommitted).command as AddObjectCommand).object;
      expect((object as AreaMeasurement).subject, same(polygon));
    });

    test('line, point and empty taps are ignored — never the point ladder', () {
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final tool = AreaTool(newId: newId);
      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: line, snapThreshold: 1)),
        isA<ToolIgnored>(),
        reason: 'a line tap must not glue a PointOnObject',
      );
      expect(
        tool.onInput(ToolInput(const Vec2(0, 0), hit: a)),
        isA<ToolIgnored>(),
      );
      expect(
        tool.onInput(const ToolInput(Vec2(100, 100))),
        isA<ToolIgnored>(),
        reason: 'an empty tap must not drop a free point',
      );
      expect(nextId, 0, reason: 'no ids consumed by ignored taps');
    });
  });
}
