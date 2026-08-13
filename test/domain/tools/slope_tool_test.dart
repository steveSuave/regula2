import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/slope_measurement.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/slope_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  var nextId = 0;
  String newId() => 'new${nextId++}';

  setUp(() => nextId = 0);

  group('SlopeTool', () {
    late FreePoint a, b;
    late LineThroughTwoPoints line;

    setUp(() {
      a = FreePoint(id: 'a', position: const Vec2(0, 0));
      b = FreePoint(id: 'b', position: const Vec2(2, 1));
      line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    });

    test('a line tap commits one SlopeMeasurement', () {
      final tool = SlopeTool(newId: newId);
      final result = tool.onInput(ToolInput(const Vec2(1, 0.5), hit: line));
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final object = (command as AddObjectCommand).object;
      expect(object, isA<SlopeMeasurement>());
      expect((object as SlopeMeasurement).subject, same(line));
      expect(object.value, closeTo(0.5, 1e-12));
    });

    test('a segment tap commits, and the tool is immediately reusable', () {
      final segment = Segment(id: 's', point1: a, point2: b);
      final tool = SlopeTool(newId: newId);
      final first = tool.onInput(ToolInput(const Vec2(1, 0.5), hit: segment));
      expect(first, isA<ToolCommitted>());
      final second = tool.onInput(ToolInput(const Vec2(1, 0.5), hit: line));
      expect(second, isA<ToolCommitted>());
    });

    test('the topmost line is consulted from extraHits past a point hit', () {
      // Tapping near a: the point wins the hit, but the line in extraHits
      // is what the tool measures.
      final tool = SlopeTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(0, 0), hit: a, extraHits: [line]),
      );
      expect(result, isA<ToolCommitted>());
      final object =
          ((result as ToolCommitted).command as AddObjectCommand).object;
      expect((object as SlopeMeasurement).subject, same(line));
    });

    test(
      'polygon, point and empty taps are ignored — never the point ladder',
      () {
        final c = FreePoint(id: 'c', position: const Vec2(0, 1));
        final polygon = Polygon(id: 'p', vertices: [a, b, c]);
        final tool = SlopeTool(newId: newId);
        expect(
          tool.onInput(ToolInput(const Vec2(1, 0.4), hit: polygon)),
          isA<ToolIgnored>(),
          reason: 'a polygon edge is not a line-valued object',
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
      },
    );

    test(
      'a vertical line commits an infinite slope (V2 semantics, Phase 112)',
      () {
        final top = FreePoint(id: 't', position: const Vec2(0, 3));
        final vertical = LineThroughTwoPoints(id: 'v', point1: a, point2: top);
        final tool = SlopeTool(newId: newId);
        final result = tool.onInput(ToolInput(const Vec2(0, 1), hit: vertical));
        expect(result, isA<ToolCommitted>());
        final object =
            ((result as ToolCommitted).command as AddObjectCommand).object;
        expect((object as SlopeMeasurement).isDefined, isTrue);
        expect(object.value, double.infinity);
      },
    );
  });
}
