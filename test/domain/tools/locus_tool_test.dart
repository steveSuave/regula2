import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/locus_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  var nextId = 0;
  String newId() => 'new${nextId++}';

  setUp(() => nextId = 0);

  group('LocusTool', () {
    late FreePoint center, rim, p;
    late CircleCenterPoint host;
    late PointOnObject driver;
    late Midpoint traced;

    setUp(() {
      center = FreePoint(id: 'o', position: Vec2.zero);
      rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      driver = PointOnObject(id: 'drv', curve: host, parameter: 0.5);
      p = FreePoint(id: 'p', position: const Vec2(4, 0));
      traced = Midpoint(id: 'tr', point1: driver, point2: p);
    });

    test('driver tap, traced tap: one AddObjectCommand of a Locus', () {
      final tool = LocusTool(newId: newId);
      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: driver)),
        isA<ToolAccepted>(),
      );
      expect(tool.previewObjectIds, ['drv'], reason: 'the driver is haloed');
      final result = tool.onInput(ToolInput(const Vec2(3, 0), hit: traced));
      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final locus = (command as AddObjectCommand).object as Locus;
      expect(locus.driver, same(driver));
      expect(locus.traced, same(traced));
      expect(tool.previewObjectIds, isEmpty, reason: 'reset after commit');
    });

    test('the sampling window is baked from the tap-time view', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final lineDriver = PointOnObject(id: 'ldrv', curve: line, parameter: 3);
      final lineTraced = Midpoint(
        id: 'ltr',
        point1: lineDriver,
        point2: lineDriver,
      );
      final tool = LocusTool(newId: newId);
      tool.onInput(ToolInput(const Vec2(3, 0), hit: lineDriver));
      final result = tool.onInput(
        ToolInput(const Vec2(3, 0), hit: lineTraced, viewExtent: 250),
      );
      final locus =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as Locus;
      expect(locus.center, 3, reason: "the driver's tap-time parameter");
      expect(locus.halfSpan, 250, reason: 'the visible world width');
    });

    test('without a viewport the window falls back to halfSpan 100', () {
      final tool = LocusTool(newId: newId);
      tool.onInput(ToolInput(const Vec2(2, 0), hit: driver));
      final result = tool.onInput(ToolInput(const Vec2(3, 0), hit: traced));
      final locus =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as Locus;
      expect(locus.halfSpan, 100);
    });

    test('tap 1 consults the whole hit set for a PointOnObject', () {
      // Tapping the driver where the host circle is topmost: the driver
      // rides in extraHits and must still be consumed.
      final tool = LocusTool(newId: newId);
      final result = tool.onInput(
        ToolInput(const Vec2(2, 0), hit: host, extraHits: [driver]),
      );
      expect(result, isA<ToolAccepted>());
      expect(tool.previewObjectIds, ['drv']);
    });

    test('tap 1 ignores anything that is not a PointOnObject', () {
      final tool = LocusTool(newId: newId);
      expect(
        tool.onInput(ToolInput(const Vec2(4, 0), hit: p)),
        isA<ToolIgnored>(),
        reason: 'a free point cannot drive a sweep',
      );
      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: host)),
        isA<ToolIgnored>(),
        reason: 'a bare curve tap must not glue a PointOnObject',
      );
      expect(
        tool.onInput(ToolInput(const Vec2(9, 9))),
        isA<ToolIgnored>(),
        reason: 'empty canvas never creates points',
      );
    });

    test('tap 2 ignores non-tracing points and keeps collecting', () {
      final tool = LocusTool(newId: newId);
      tool.onInput(ToolInput(const Vec2(2, 0), hit: driver));
      expect(
        tool.onInput(ToolInput(const Vec2(4, 0), hit: p)),
        isA<ToolIgnored>(),
        reason: 'p does not depend on the driver',
      );
      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: driver)),
        isA<ToolIgnored>(),
        reason: 'the driver cannot trace itself',
      );
      expect(tool.onInput(ToolInput(const Vec2(9, 9))), isA<ToolIgnored>());
      // Still armed: a valid traced point commits.
      expect(
        tool.onInput(ToolInput(const Vec2(3, 0), hit: traced)),
        isA<ToolCommitted>(),
      );
    });

    test('reset drops the collected driver', () {
      final tool = LocusTool(newId: newId);
      tool.onInput(ToolInput(const Vec2(2, 0), hit: driver));
      tool.reset();
      expect(tool.previewObjectIds, isEmpty);
      expect(
        tool.onInput(ToolInput(const Vec2(3, 0), hit: traced)),
        isA<ToolIgnored>(),
        reason: 'traced arrived first — the tool restarted from tap 1',
      );
    });
  });
}
