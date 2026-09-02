import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/ratio_apollonius_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/tools/ratio_apollonius_circle_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  final two = Rational.whole(2);

  RatioApolloniusCircleTool make(Rational ratio) =>
      RatioApolloniusCircleTool(newId: () => 'n${nextId++}', ratio: ratio);

  setUp(() => nextId = 0);

  group('RatioApolloniusCircleTool', () {
    test('A then B on empty canvas commit two points plus the circle', () {
      final tool = make(two);
      final construction = Construction();
      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      final result = tool.onInput(const ToolInput(Vec2(3, 0))) as ToolCommitted;
      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 3);

      final circle = construction.objects
          .whereType<RatioApolloniusCircle>()
          .single;
      expect(circle.ratio, two);
      expect(circle.point1.position, Vec2.zero);
      expect(circle.point2.position, const Vec2(3, 0));
      // |PA| = 2|PB| over A = (0,0), B = (3,0): centre (4, 0), radius 2.
      expect(circle.circle!.center.x, closeTo(4, 1e-12));
      expect(circle.circle!.center.y, closeTo(0, 1e-12));
      expect(circle.circle!.radius, closeTo(2, 1e-12));

      result.command.undo(construction);
      expect(construction.isEmpty, isTrue);
    });

    test('existing points are reused as A and B', () {
      final tool = make(two);
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      construction.add(a);
      construction.add(b);
      tool.onInput(ToolInput(a.position, hit: a));
      final result =
          tool.onInput(ToolInput(b.position, hit: b)) as ToolCommitted;
      expect(result.command, isA<AddObjectCommand>());
      result.command.apply(construction);
      final circle = construction.objects
          .whereType<RatioApolloniusCircle>()
          .single;
      expect(identical(circle.point1, a), isTrue);
      expect(identical(circle.point2, b), isTrue);
    });

    test('ratio 1 builds the perpendicular bisector — the locus is a line', () {
      final tool = make(Rational.one);
      final construction = Construction();
      tool.onInput(const ToolInput(Vec2(0, 0)));
      final result = tool.onInput(const ToolInput(Vec2(3, 0))) as ToolCommitted;
      result.command.apply(construction);
      expect(
        construction.objects.whereType<PerpendicularBisectorLine>(),
        hasLength(1),
      );
      expect(construction.objects.whereType<RatioApolloniusCircle>(), isEmpty);
    });

    test('a Cayley–Klein document refuses the first tap', () {
      final tool = make(two);
      expect(
        tool.onInput(
          const ToolInput(Vec2(0, 0), absolute: Absolute.hyperbolic),
        ),
        isA<ToolIgnored>(),
      );
      expect(tool.hasPartialInput, isFalse);
    });

    test('the ratio must be positive', () {
      expect(() => make(Rational.zero), throwsArgumentError);
      expect(() => make(Rational.fromInts(-1, 2)), throwsArgumentError);
    });
  });
}
