import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/trapezium_macro_tool.dart';

void main() {
  late int nextId;
  late TrapeziumMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = TrapeziumMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), C(5,2), then picks D from (1,3) — projected
  /// onto the parallel through C, that's (1,2) — and returns the
  /// committed construction.
  Construction buildTrapezium() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    tool.onInput(const ToolInput(Vec2(5, 2)));
    (tool.onInput(const ToolInput(Vec2(1, 3))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  PointOnObject cornerOf(Construction c) =>
      c.objects.whereType<PointOnObject>().single;

  group('TrapeziumMacroTool', () {
    test('three corner taps plus a projected fourth commit one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(tool.onInput(const ToolInput(Vec2(4, 0))), isA<ToolAccepted>());
      expect(
        tool.onInput(const ToolInput(Vec2(5, 2))),
        isA<ToolAccepted>(),
        reason: 'the third corner does not commit — D is still pending',
      );
      final result = tool.onInput(const ToolInput(Vec2(1, 3))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        9,
        reason: '3 free points + 2 sides + parallel + D + 2 sides',
      );
      expect(
        cornerOf(construction).position,
        const Vec2(1, 2),
        reason: 'D is the tap projected onto the parallel through C',
      );

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole trapezium is one undo unit',
      );
    });

    test('the fourth tap never consumes an existing point', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(1, 3));
      construction.add(e);

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      tool.onInput(const ToolInput(Vec2(5, 2)));
      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      result.command.apply(construction);

      expect(
        cornerOf(construction).position,
        const Vec2(1, 2),
        reason: 'the hit point only donates its position',
      );
      expect(
        cornerOf(construction).parents,
        [construction.objects.whereType<ParallelLine>().single],
        reason: 'D is constrained to the parallel, not to the tapped point',
      );

      result.command.undo(construction);
      expect(construction.objects, [
        e,
      ], reason: 'undo leaves the pre-existing point alone');
    });

    test('scaffolding is hidden, corner and sides are visible', () {
      final construction = buildTrapezium();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(hidden, hasLength(1));
      expect(hidden.single, isA<ParallelLine>());

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
      expect(visible.whereType<PointOnObject>(), hasLength(1));
    });

    test('dragging a tapped corner keeps AB parallel to CD', () {
      final construction = buildTrapezium();
      final free = construction.objects.whereType<FreePoint>().toList();
      final a = free[0];

      construction.moveFreePoint(a.id, const Vec2(0, 1));

      final b = free[1].position;
      final c = free[2].position;
      final d = cornerOf(construction).position;
      expect(d, isNotNull);
      final ab = b - a.position;
      final cd = d! - c;
      expect(
        ab.cross(cd).abs(),
        lessThan(1e-9),
        reason: 'CD stays parallel to AB',
      );
      expect(cd.norm, greaterThan(0), reason: 'D did not collapse onto C');
    });

    test('the shape survives a drag through degeneracy', () {
      final construction = buildTrapezium();
      final a = construction.objects.whereType<FreePoint>().first;
      final cornerD = cornerOf(construction);

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerD.position,
        isNull,
        reason: 'coincident A and B leave the parallel undefined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(
        cornerD.position,
        const Vec2(1, 2),
        reason: 'the analytic form is restored, so D comes back in place',
      );
    });

    test('reset mid-collection discards the corners', () {
      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      tool.onInput(const ToolInput(Vec2(5, 2)));
      tool.reset();

      expect(tool.previewPositions, isEmpty);
      expect(
        tool.onInput(const ToolInput(Vec2(9, 9))),
        isA<ToolAccepted>(),
        reason: 'the next tap starts a fresh collection, not a commit',
      );
    });
  });
}
