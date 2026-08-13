import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/rhombus_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late RhombusMacroTool tool;

  setUp(() {
    nextId = 0;
    tool = RhombusMacroTool(newId: () => 'n${nextId++}');
  });

  /// Taps A(0,0), B(4,0), then picks the adjacent side's direction from
  /// (4,5) — projected onto the circle around B with radius |AB| = 4,
  /// corner C lands at (4,4) and D = A + C − B closes at (0,4).
  Construction buildRhombus() {
    final construction = Construction();
    tool.onInput(const ToolInput(Vec2(0, 0)));
    tool.onInput(const ToolInput(Vec2(4, 0)));
    (tool.onInput(const ToolInput(Vec2(4, 5))) as ToolCommitted).command.apply(
      construction,
    );
    return construction;
  }

  PointOnObject cornerC(Construction c) =>
      c.objects.whereType<PointOnObject>().single;
  IntersectionPoint cornerD(Construction c) =>
      c.objects.whereType<IntersectionPoint>().single;
  List<FreePoint> freeCorners(Construction c) =>
      c.objects.whereType<FreePoint>().toList();

  /// All four sides equal on the current corner positions.
  void expectRhombus(Construction construction) {
    final free = freeCorners(construction);
    final a = free[0].position;
    final b = free[1].position;
    final c = cornerC(construction).position!;
    final d = cornerD(construction).position!;
    final side = (b - a).norm;
    expect((c - b).norm, closeTo(side, 1e-9));
    expect((d - c).norm, closeTo(side, 1e-9));
    expect((a - d).norm, closeTo(side, 1e-9));
  }

  group('RhombusMacroTool', () {
    test('two corner taps plus a direction tap commit one macro', () {
      final construction = Construction();

      expect(tool.onInput(const ToolInput(Vec2(0, 0))), isA<ToolAccepted>());
      expect(
        tool.onInput(const ToolInput(Vec2(4, 0))),
        isA<ToolAccepted>(),
        reason:
            'the second corner does not commit — the direction is '
            'pending',
      );
      final result = tool.onInput(const ToolInput(Vec2(4, 5))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(
        construction.length,
        11,
        reason: '2 free points + 4 sides + circle + 2 parallels + C + D',
      );
      expect(
        cornerC(construction).position,
        const Vec2(4, 4),
        reason: 'C is the tap projected onto the compass circle',
      );
      expect(cornerD(construction).position, const Vec2(0, 4));

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'the whole rhombus is one undo unit',
      );
    });

    test('the direction tap never consumes an existing point', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(4, 5));
      construction.add(e);

      tool.onInput(const ToolInput(Vec2(0, 0)));
      tool.onInput(const ToolInput(Vec2(4, 0)));
      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      result.command.apply(construction);

      expect(
        cornerC(construction).position,
        const Vec2(4, 4),
        reason: 'the hit point only donates its position',
      );

      result.command.undo(construction);
      expect(construction.objects, [e]);
    });

    test('scaffolding is hidden, corners and sides are visible', () {
      final construction = buildRhombus();

      final hidden = construction.objects
          .where((o) => !o.attributes.visible)
          .toList();
      expect(
        hidden,
        hasLength(3),
        reason: 'the compass circle and the two parallels',
      );
      expect(hidden.whereType<CompassCircle>(), hasLength(1));

      final visible = construction.objects.where((o) => o.attributes.visible);
      expect(visible.whereType<Segment>(), hasLength(4));
    });

    test('dragging a tapped corner keeps all four sides equal', () {
      final construction = buildRhombus();
      final free = freeCorners(construction);

      construction.moveFreePoint(free[0].id, const Vec2(1, 1));
      expectRhombus(construction);

      construction.moveFreePoint(free[1].id, const Vec2(6, -1));
      expectRhombus(construction);
    });

    test('coincident corners collapse and recover in place', () {
      final construction = buildRhombus();
      final a = freeCorners(construction)[0];

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        cornerC(construction).position,
        const Vec2(4, 0),
        reason:
            'a zero-radius circle pins C to its center — degenerate '
            'but defined',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(
        cornerC(construction).position,
        const Vec2(4, 4),
        reason:
            'the polar parameter rides the analytic form, so C '
            'returns exactly in place',
      );
      expect(cornerD(construction).position, const Vec2(0, 4));
    });
  });
}
