import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/polygon_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late PolygonTool tool;

  setUp(() {
    nextId = 0;
    tool = PolygonTool(newId: () => 'n${nextId++}');
  });

  /// A tap with the snap threshold the canvas always supplies — close
  /// detection on new vertices needs it, like intersection snapping.
  ToolInput tap(Vec2 position, {GeoObject? hit}) =>
      ToolInput(position, hit: hit, snapThreshold: 0.5);

  group('PolygonTool', () {
    test('three empty taps + a close tap commit points and polygon as one '
        'macro with fillAlpha baked in', () {
      final construction = Construction();

      expect(tool.onInput(tap(const Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(tap(const Vec2(4, 0))), isA<ToolAccepted>());
      expect(tool.onInput(tap(const Vec2(2, 3))), isA<ToolAccepted>());
      final result = tool.onInput(tap(const Vec2(0.1, -0.1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 4, reason: '3 free points + the polygon');

      final polygon = construction.objects.whereType<Polygon>().single;
      expect(polygon.polygonVertices, const [
        Vec2(0, 0),
        Vec2(4, 0),
        Vec2(2, 3),
      ]);
      expect(polygon.attributes.fillAlpha, PolygonTool.defaultFillAlpha);
      expect(polygon.attributes.visible, isTrue);

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole polygon is one undo unit',
      );
    });

    test('a close tap with fewer than 3 vertices is ignored', () {
      expect(tool.onInput(tap(const Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(tap(const Vec2(4, 0))), isA<ToolAccepted>());
      expect(
        tool.onInput(tap(const Vec2(0, 0))),
        isA<ToolIgnored>(),
        reason: 'two vertices cannot close',
      );
      expect(
        tool.previewPositions,
        hasLength(2),
        reason: 'the refused tap collected nothing',
      );
    });

    test('a tap on a collected non-first vertex is ignored', () {
      expect(tool.onInput(tap(const Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(tap(const Vec2(4, 0))), isA<ToolAccepted>());
      expect(tool.onInput(tap(const Vec2(2, 3))), isA<ToolAccepted>());
      expect(
        tool.onInput(tap(const Vec2(4.1, 0.1))),
        isA<ToolIgnored>(),
        reason: 'no self-touching rings',
      );
      expect(tool.previewPositions, hasLength(3));
    });

    test('existing points are reused; re-tapping the first closes', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(4, 3));
      final d = FreePoint(id: 'd', position: const Vec2(0, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(d);

      tool.onInput(tap(a.position, hit: a));
      tool.onInput(tap(b.position, hit: b));
      tool.onInput(tap(c.position, hit: c));
      tool.onInput(tap(d.position, hit: d));
      expect(tool.previewObjectIds, ['a', 'b', 'c', 'd']);

      final result = tool.onInput(tap(a.position, hit: a)) as ToolCommitted;
      result.command.apply(construction);
      expect(construction.length, 5, reason: 'only the polygon is new');

      final polygon = construction.objects.whereType<Polygon>().single;
      expect(polygon.vertices, [a, b, c, d]);

      result.command.undo(construction);
      expect(construction.objects, [a, b, c, d]);
    });

    test('a tap on a collected existing vertex (not the first) is ignored', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      tool.onInput(tap(a.position, hit: a));
      tool.onInput(tap(b.position, hit: b));
      tool.onInput(tap(const Vec2(2, 3)));

      expect(tool.onInput(tap(b.position, hit: b)), isA<ToolIgnored>());
      expect(tool.collectedVertices, hasLength(3));
    });

    test('an existing point right next to a new vertex is still a new '
        'vertex, not a close', () {
      final a = FreePoint(id: 'a', position: const Vec2(0.2, 0));
      expect(
        tool.onInput(tap(const Vec2(0, 0))),
        isA<ToolAccepted>(),
        reason: 'first vertex: a private free point',
      );
      expect(tool.onInput(tap(const Vec2(4, 0))), isA<ToolAccepted>());
      expect(tool.onInput(tap(const Vec2(2, 3))), isA<ToolAccepted>());

      expect(
        tool.onInput(tap(const Vec2(0.2, 0), hit: a)),
        isA<ToolAccepted>(),
        reason: 'a point hit means that point, even near vertex 1',
      );
      expect(tool.collectedVertices, hasLength(4));
    });

    test('curve taps glue via the ladder', () {
      final center = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);

      expect(
        tool.onInput(tap(const Vec2(0.1, 2.1), hit: circle)),
        isA<ToolAccepted>(),
      );
      expect(
        tool.collectedVertices.single,
        isA<PointOnObject>(),
        reason: 'the ladder glues near-curve taps, macros keep that',
      );
    });

    test('reset drops the collection', () {
      tool.onInput(tap(const Vec2(0, 0)));
      tool.onInput(tap(const Vec2(4, 0)));
      tool.reset();
      expect(tool.previewPositions, isEmpty);
      expect(
        tool.onInput(tap(const Vec2(0, 0))),
        isA<ToolAccepted>(),
        reason: 'the old first vertex is gone — this collects anew',
      );
    });
  });
}
