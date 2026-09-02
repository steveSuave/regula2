import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_angle_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/tools/fixed_angle_line_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FixedAngleLineTool tool;
  final third = Rational.fromInts(1, 3);

  setUp(() {
    nextId = 0;
    tool = FixedAngleLineTool(newId: () => 'n${nextId++}', turn: third);
  });

  Construction reference() {
    final construction = Construction();
    construction.add(FreePoint(id: 'a', position: Vec2.zero));
    construction.add(FreePoint(id: 'b', position: const Vec2(4, 0)));
    construction.add(
      LineThroughTwoPoints(
        id: 'l',
        point1: construction.byId('a')! as FreePoint,
        point2: construction.byId('b')! as FreePoint,
      ),
    );
    return construction;
  }

  group('FixedAngleLineTool', () {
    test('line then empty canvas commits a free point plus the line, as '
        'one undo unit', () {
      final construction = reference();
      final line = construction.byId('l')! as LineThroughTwoPoints;

      expect(
        tool.onInput(ToolInput(const Vec2(2, 0), hit: line)),
        isA<ToolAccepted>(),
      );
      final result = tool.onInput(const ToolInput(Vec2(1, 1))) as ToolCommitted;
      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);

      final built = construction.objects.whereType<FixedAngleLine>().single;
      expect(built.turn, third);
      expect(identical(built.reference, line), isTrue);
      expect(built.through, isA<FreePoint>());
      expect(built.through.position, const Vec2(1, 1));
      // 60° from the x-axis: the line carries (1, 1) + (cos 60°, sin 60°).
      final direction = built.line!.direction;
      expect(direction.x.abs(), closeTo(0.5, 1e-12));
      expect(direction.y.abs(), closeTo(0.8660254037844386, 1e-12));

      result.command.undo(construction);
      expect(construction.length, 3, reason: 'point and line undo together');
    });

    test('an existing point is reused, in either tap order', () {
      final construction = reference();
      final line = construction.byId('l')! as LineThroughTwoPoints;
      final p = FreePoint(id: 'p', position: const Vec2(1, 1));
      construction.add(p);

      tool.onInput(ToolInput(p.position, hit: p));
      final result =
          tool.onInput(ToolInput(const Vec2(2, 0), hit: line)) as ToolCommitted;
      expect(
        result.command,
        isA<AddObjectCommand>(),
        reason: 'nothing but the line is added',
      );
      result.command.apply(construction);
      final built = construction.objects.whereType<FixedAngleLine>().single;
      expect(identical(built.through, p), isTrue);
    });

    test('a Cayley–Klein document refuses every input outright', () {
      final construction = reference();
      final line = construction.byId('l')! as LineThroughTwoPoints;
      expect(
        tool.onInput(
          ToolInput(const Vec2(2, 0), hit: line, absolute: Absolute.hyperbolic),
        ),
        isA<ToolIgnored>(),
      );
      expect(
        tool.onInput(
          const ToolInput(Vec2(1, 1), absolute: Absolute.hyperbolic),
        ),
        isA<ToolIgnored>(),
      );
      expect(
        tool.hasPartialInput,
        isFalse,
        reason: 'a refused tap collects nothing',
      );
    });

    test('the turn must already be the canonical residue', () {
      expect(
        () =>
            FixedAngleLineTool(newId: () => 'x', turn: Rational.fromInts(4, 3)),
        throwsArgumentError,
      );
      expect(
        () => FixedAngleLineTool(
          newId: () => 'x',
          turn: Rational.fromInts(-1, 3),
        ),
        throwsArgumentError,
      );
      // Zero is a residue: a line at 0° is the parallel, honestly drawn.
      expect(
        FixedAngleLineTool(newId: () => 'x', turn: Rational.zero).turn,
        Rational.zero,
      );
    });
  });
}
