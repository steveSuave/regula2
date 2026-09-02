import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/scaled_compass_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/tools/scaled_compass_circle_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  final threeHalves = Rational.fromInts(3, 2);

  ScaledCompassCircleTool make(Rational factor) =>
      ScaledCompassCircleTool(newId: () => 'n${nextId++}', factor: factor);

  setUp(() => nextId = 0);

  group('ScaledCompassCircleTool', () {
    test('span, span, centre — three canvas taps commit one undo unit', () {
      final tool = make(threeHalves);
      final construction = Construction();
      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(const ToolInput(Vec2(4, 0))), isA<ToolAccepted>());
      final result =
          tool.onInput(const ToolInput(Vec2(10, 10))) as ToolCommitted;
      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 4);

      final circle = construction.objects
          .whereType<ScaledCompassCircle>()
          .single;
      expect(circle.factor, threeHalves);
      expect(circle.center.position, const Vec2(10, 10));
      expect(circle.radiusPoint1.position, Vec2.zero);
      expect(circle.radiusPoint2.position, const Vec2(4, 0));
      expect(circle.circle!.radius, closeTo(6, 1e-12), reason: '3/2 · 4');

      result.command.undo(construction);
      expect(construction.isEmpty, isTrue);
    });

    test('existing points are reused, the same point twice is ignored', () {
      final tool = make(threeHalves);
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(10, 10));
      construction.add(a);
      construction.add(b);
      construction.add(c);

      tool.onInput(ToolInput(a.position, hit: a));
      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolIgnored>());
      tool.onInput(ToolInput(b.position, hit: b));
      final result =
          tool.onInput(ToolInput(c.position, hit: c)) as ToolCommitted;
      expect(result.command, isA<AddObjectCommand>());
      result.command.apply(construction);
      final circle = construction.objects
          .whereType<ScaledCompassCircle>()
          .single;
      expect(identical(circle.radiusPoint1, a), isTrue);
      expect(identical(circle.radiusPoint2, b), isTrue);
      expect(identical(circle.center, c), isTrue);
    });

    test(
      'factor 1 builds the plain compass circle — the plainer statement',
      () {
        final tool = make(Rational.one);
        final construction = Construction();
        tool.onInput(const ToolInput(Vec2(0, 0)));
        tool.onInput(const ToolInput(Vec2(4, 0)));
        final result =
            tool.onInput(const ToolInput(Vec2(10, 10))) as ToolCommitted;
        result.command.apply(construction);
        expect(construction.objects.whereType<CompassCircle>(), hasLength(1));
        expect(construction.objects.whereType<ScaledCompassCircle>(), isEmpty);
      },
    );

    test('a Cayley–Klein document refuses the first tap', () {
      final tool = make(threeHalves);
      expect(
        tool.onInput(
          const ToolInput(Vec2(0, 0), absolute: Absolute.hyperbolic),
        ),
        isA<ToolIgnored>(),
      );
      expect(tool.hasPartialInput, isFalse);
    });

    test('the factor must be positive', () {
      expect(() => make(Rational.zero), throwsArgumentError);
      expect(() => make(Rational.fromInts(-3, 2)), throwsArgumentError);
    });
  });
}
