import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/harmonic_conjugate_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late HarmonicConjugateTool tool;

  setUp(() {
    nextId = 0;
    tool = HarmonicConjugateTool(newId: () => 'n${nextId++}');
  });

  group('HarmonicConjugateTool', () {
    test('three taps on existing points commit just the conjugate', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 0));

      expect(tool.onInput(ToolInput(a.position, hit: a)), isA<ToolAccepted>());
      expect(tool.onInput(ToolInput(b.position, hit: b)), isA<ToolAccepted>());
      final result = tool.onInput(ToolInput(c.position, hit: c));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<AddObjectCommand>());
      final conjugate =
          (command as AddObjectCommand).object as HarmonicConjugatePoint;
      expect(conjugate.parents, [
        a,
        b,
        c,
      ], reason: 'tap order is base pair A, B, then C');
      expect(conjugate.position!.closeTo(const Vec2(-2, 0)), isTrue);
    });

    test('taps on empty canvas create free points, one undo unit', () {
      final construction = Construction();

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      final result = tool.onInput(const ToolInput(Vec2(1, 0)));

      expect(result, isA<ToolCommitted>());
      final command = (result as ToolCommitted).command;
      expect(command, isA<MacroCommand>());

      command.apply(construction);
      expect(construction.length, 4, reason: '3 free points + the conjugate');
      final conjugate = construction.objects.last as HarmonicConjugatePoint;
      expect(conjugate.position!.closeTo(const Vec2(-2, 0)), isTrue);

      command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole step is one undo unit',
      );
    });

    test('non-collinear taps still commit an undefined conjugate that '
        'recovers', () {
      final construction = Construction();

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      final result = tool.onInput(const ToolInput(Vec2(1, 3))) as ToolCommitted;
      result.command.apply(construction);

      final conjugate = construction.objects.last as HarmonicConjugatePoint;
      expect(conjugate.isDefined, isFalse);

      construction.moveFreePoint(conjugate.point3.id, const Vec2(1, 0));
      expect(conjugate.isDefined, isTrue);
      expect(conjugate.position!.closeTo(const Vec2(-2, 0)), isTrue);
    });

    test('an existing conjugate over the same parents refuses the '
        'completing tap, in either base-pair order', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 0));
      final existing = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );
      final construction = Construction()
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(existing);
      final objects = construction.objects.toList();

      ToolResult tap(FreePoint p) =>
          tool.onInput(ToolInput(p.position, hit: p, objects: objects));

      expect(tap(a), isA<ToolAccepted>());
      expect(tap(b), isA<ToolAccepted>());
      expect(
        tap(c),
        isA<ToolIgnored>(),
        reason: 'the conjugate of the same triple already exists',
      );

      // The conjugate is symmetric in A and B, so the swapped base pair
      // is the same construction and dedupes too.
      tool.reset();
      expect(tap(b), isA<ToolAccepted>());
      expect(tap(a), isA<ToolAccepted>());
      expect(tap(c), isA<ToolIgnored>());

      // A different C is a genuinely different conjugate and commits.
      final e = FreePoint(id: 'e', position: const Vec2(3, 0));
      construction.add(e);
      final withE = construction.objects.toList();
      tool.reset();
      tool.onInput(ToolInput(a.position, hit: a, objects: withE));
      tool.onInput(ToolInput(b.position, hit: b, objects: withE));
      expect(
        tool.onInput(ToolInput(e.position, hit: e, objects: withE)),
        isA<ToolCommitted>(),
      );
    });
  });
}
