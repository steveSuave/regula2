import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/focal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/tools/bifocal_conic_tool.dart';
import 'package:regula/domain/tools/focal_conic_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  setUp(() => nextId = 0);
  String newId() => 'n${nextId++}';

  group('FocalConicTool', () {
    LineThroughTwoPoints directrix() => LineThroughTwoPoints(
      id: 'l',
      point1: FreePoint(id: 'd1', position: const Vec2(-1, -1)),
      point2: FreePoint(id: 'd2', position: const Vec2(-1, 1)),
    );

    test('focus then directrix: the parabola, at eccentricity 1', () {
      final focus = FreePoint(id: 'f', position: Vec2.zero);
      final line = directrix();
      final tool = FocalConicTool(newId: newId);

      expect(
        tool.onInput(ToolInput(focus.position, hit: focus)),
        isA<ToolAccepted>(),
      );
      final result = tool.onInput(ToolInput(const Vec2(-1, 0), hit: line));

      expect(result, isA<ToolCommitted>());
      final conic =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as FocalConic;
      expect(conic.eccentricity, 1);
      expect(conic.focus, focus);
      expect(conic.directrix, line);
      expect(ConicShape.of(conic.conic!).kind, ConicClass.parabola);
    });

    test('directrix then focus: the same conic, either order', () {
      final line = directrix();
      final tool = FocalConicTool(newId: newId);
      expect(
        tool.onInput(ToolInput(const Vec2(-1, 0), hit: line)),
        isA<ToolAccepted>(),
      );
      final result =
          tool.onInput(const ToolInput(Vec2.zero)) as ToolCommitted;
      // An empty-canvas tap drops the focus, so the step is a macro.
      expect(result.command, isA<MacroCommand>());
      final construction = Construction()
        ..add(line.point1)
        ..add(line.point2)
        ..add(line);
      result.command.apply(construction);
      final conic = construction.objects.last as FocalConic;
      expect(ConicShape.of(conic.conic!).kind, ConicClass.parabola);

      result.command.undo(construction);
      expect(construction.length, 3, reason: 'one undo unit');
    });

    test('a chosen eccentricity rides through to the object', () {
      for (final (e, expected) in const [
        (0.5, ConicClass.ellipse),
        (1.0, ConicClass.parabola),
        (2.0, ConicClass.hyperbola),
      ]) {
        final focus = FreePoint(id: 'f', position: const Vec2(2, -1));
        final line = directrix();
        final tool = FocalConicTool(newId: newId, eccentricity: e);
        tool.onInput(ToolInput(focus.position, hit: focus));
        final result =
            tool.onInput(ToolInput(const Vec2(-1, 0), hit: line))
                as ToolCommitted;
        final conic =
            (result.command as AddObjectCommand).object as FocalConic;
        expect(conic.eccentricity, e);
        expect(ConicShape.of(conic.conic!).kind, expected);
      }
    });

    test('a circle tap is ignored — the directrix is a line', () {
      final tool = FocalConicTool(newId: newId);
      expect(tool.hasPartialInput, isFalse);
      tool.onInput(const ToolInput(Vec2.zero));
      expect(tool.hasPartialInput, isTrue);
      expect(
        tool.onInput(const ToolInput(Vec2(3, 3))),
        isA<ToolIgnored>(),
        reason: 'the point slot is already filled',
      );
    });
  });

  group('BifocalConicTool', () {
    const f1 = Vec2(-3, 0);
    const f2 = Vec2(3, 0);
    const on = Vec2(5, 0);

    test('three canvas taps: 3 free points + the conic in one undo unit', () {
      for (final (difference, expected) in const [
        (false, ConicClass.ellipse),
        (true, ConicClass.hyperbola),
      ]) {
        final construction = Construction();
        final tool = BifocalConicTool(newId: newId, difference: difference);
        tool.onInput(const ToolInput(f1));
        tool.onInput(const ToolInput(f2));
        final result = tool.onInput(
          ToolInput(difference ? const Vec2(1, 4) : on),
        ) as ToolCommitted;

        expect(result.command, isA<MacroCommand>());
        result.command.apply(construction);
        expect(construction.length, 4);
        final conic = construction.objects.last as BifocalConic;
        expect(conic.difference, difference);
        expect(ConicShape.of(conic.conic!).kind, expected);

        result.command.undo(construction);
        expect(construction.isEmpty, isTrue);
      }
    });

    test('tap order is foci, foci, then the point on the conic', () {
      final a = FreePoint(id: 'a', position: f1);
      final b = FreePoint(id: 'b', position: f2);
      final p = FreePoint(id: 'p', position: on);
      final tool = BifocalConicTool(newId: newId, difference: false);
      tool.onInput(ToolInput(a.position, hit: a));
      tool.onInput(ToolInput(b.position, hit: b));
      final result = tool.onInput(ToolInput(p.position, hit: p));

      final conic =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as BifocalConic;
      expect([conic.focus1, conic.focus2, conic.point], [a, b, p]);
      // The point is on the conic; the foci are not.
      final shape = ConicShape.of(conic.conic!);
      expect(shape.distanceTo(on), lessThan(1e-9));
      expect(shape.distanceTo(f1), greaterThan(1));
    });

    test('the same point twice is ignored — three distinct inputs', () {
      final a = FreePoint(id: 'a', position: f1);
      final tool = BifocalConicTool(newId: newId, difference: false);
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolIgnored>());
      expect(tool.collectedVertices, [a]);
    });

    test('coincident foci still commit, and recover on a drag', () {
      final construction = Construction();
      final tool = BifocalConicTool(newId: newId, difference: false);
      tool.onInput(const ToolInput(f1));
      tool.onInput(const ToolInput(Vec2(-3, 0.0000000001)));
      final result = tool.onInput(const ToolInput(on)) as ToolCommitted;
      result.command.apply(construction);

      final conic = construction.objects.last as BifocalConic;
      expect(conic.isDefined, isFalse);
      construction.moveFreePoint(conic.focus2.id, f2);
      expect(conic.isDefined, isTrue);
    });
  });
}
