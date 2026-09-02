import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/stated_radius_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/tools/stated_radius_circle_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late StatedRadiusCircleTool tool;
  final fiveHalves = Rational.fromInts(5, 2);

  setUp(() {
    nextId = 0;
    tool = StatedRadiusCircleTool(
      newId: () => 'n${nextId++}',
      radius: fiveHalves,
    );
  });

  group('StatedRadiusCircleTool', () {
    test('an empty-canvas tap commits a free centre plus the circle', () {
      final construction = Construction();
      final result =
          tool.onInput(const ToolInput(Vec2(3, -1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 2);
      final circle = construction.objects
          .whereType<StatedRadiusCircle>()
          .single;
      expect(circle.radius, fiveHalves, reason: 'exact, not a double');
      expect(circle.circle!.center, const Vec2(3, -1));
      expect(circle.circle!.radius, 2.5);
      expect(circle.center, isA<FreePoint>());

      result.command.undo(construction);
      expect(construction.isEmpty, isTrue, reason: 'one undo unit');
    });

    test('a tap on an existing point reuses it as the centre', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(1, 1));
      construction.add(e);

      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      expect(result.command, isA<AddObjectCommand>());
      result.command.apply(construction);
      final circle = construction.objects
          .whereType<StatedRadiusCircle>()
          .single;
      expect(identical(circle.center, e), isTrue);
    });

    test('a Cayley–Klein document refuses the tap', () {
      expect(
        tool.onInput(
          const ToolInput(Vec2(3, -1), absolute: Absolute.hyperbolic),
        ),
        isA<ToolIgnored>(),
      );
      expect(tool.hasPartialInput, isFalse);
      expect(tool.availableUnder(Absolute.hyperbolic), isFalse);
      expect(tool.availableUnder(Absolute.euclidean), isTrue);
    });

    test('the radius must be positive', () {
      expect(
        () => StatedRadiusCircleTool(newId: () => 'x', radius: Rational.zero),
        throwsArgumentError,
      );
      expect(
        () => StatedRadiusCircleTool(
          newId: () => 'x',
          radius: Rational.fromInts(-1, 2),
        ),
        throwsArgumentError,
      );
    });
  });
}
