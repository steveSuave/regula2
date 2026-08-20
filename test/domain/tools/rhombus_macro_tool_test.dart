import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
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

  group('RhombusMacroTool under a proper absolute (Phase 138)', () {
    /// A hyperbolic rhombus from the same three taps, well inside the
    /// disc: corners A, B and a direction for C.
    (Construction, RhombusMacroTool) hyperbolicRhombus() {
      const absolute = Absolute.hyperbolic;
      final construction = Construction(
        kernel: DocumentKernel(metric: FundamentalConic.hyperbolic),
      );
      for (final tap in const [Vec2(0, 0), Vec2(0.4, 0), Vec2(0.4, 0.5)]) {
        final result = tool.onInput(ToolInput(tap, absolute: absolute));
        if (result is ToolCommitted) {
          result.command.apply(construction);
        }
      }
      return (construction, tool);
    }

    /// The figure's visible corners, in build order: A, B, C, D.
    List<GeoPoint> cornersOf(Construction c) => [
      for (final o in c.objects)
        if (o is GeoPoint && o.attributes.visible) o,
    ];

    test('D is a reflection, not an intersection', () {
      final (construction, _) = hyperbolicRhombus();

      expect(
        cornersOf(construction).last,
        isA<ReflectedPoint>(),
        reason: 'corner D is B mirrored in the diagonal AC',
      );
      expect(
        construction.objects.whereType<IntersectionPoint>(),
        isEmpty,
        reason: 'the CK route has no branch to pick at all',
      );
      expect(
        construction.length,
        10,
        reason:
            '2 free points + 4 sides + circle + hidden diagonal + C + D — '
            'one object fewer than the Euclidean route, the reflection '
            'carrying no scaffolding',
      );
    });

    test('sliding C once around its circle never jumps D', () {
      // The pin on the design, and the reason the Euclid I.1 route PLAN
      // recorded was not taken: B lies on both of I.1's compass circles,
      // so its two crossings are B and D — and they *swap* as B crosses
      // the axis, which sliding C right around does twice. Measured on
      // this very rig, the I.1 route lands D on B at the crossing (a
      // single step of 0.80 world units) and leaves it pinned there for
      // the rest of the sweep, the figure folded flat onto triangle ABC
      // with no drag that recovers it.
      final (construction, _) = hyperbolicRhombus();
      final corners = cornersOf(construction);
      final cornerC = corners[2] as PointOnObject;
      final cornerD = corners[3];

      final start = cornerC.parameter;
      var previous = cornerD.position!;
      var worst = 0.0;
      const steps = 600;
      for (var i = 1; i <= steps; i++) {
        // π, not 2π: a general conic is swept by `ConicShape`'s pencil
        // angle, which is a bijection from [0, π) onto the whole curve.
        construction.setPointOnObjectParameter(
          cornerC.id,
          start + math.pi * i / steps,
        );
        final now = cornerD.position;
        expect(now, isNotNull, reason: 'D stays defined all the way round');
        worst = math.max(worst, now!.distanceTo(previous));
        previous = now;
      }

      expect(
        worst,
        lessThan(0.05),
        reason: 'D rides the sweep continuously — 0.80 is the swap',
      );
      expect(
        previous.distanceTo(cornerD.position!),
        lessThan(1e-9),
        reason: 'and a full period returns it where it started',
      );
    });

    test('D meets B only where the rhombus is genuinely flat', () {
      // The swap is invisible to the obvious test: D ≡ B satisfies
      // |CD| = |CB| and |DA| = |BA| trivially, so a folded rhombus is
      // still equilateral. What separates the two is *where* D touches B
      // — only where B lies on the diagonal AC, which is the flat figure
      // and is reached continuously.
      final (construction, _) = hyperbolicRhombus();
      final corners = cornersOf(construction);
      final cornerC = corners[2] as PointOnObject;
      final (a, b, cornerD) = (corners[0], corners[1], corners[3]);

      final start = cornerC.parameter;
      const steps = 600;
      for (var i = 0; i <= steps; i++) {
        construction.setPointOnObjectParameter(
          cornerC.id,
          start + math.pi * i / steps,
        );
        if (cornerD.position!.distanceTo(b.position!) > 1e-3) {
          continue;
        }
        // B is on the diagonal AC — measured in the chart, where the
        // window above is also stated, so the two are comparable.
        final diagonal = a.projPoint!.join(cornerC.projPoint!).toLineEq()!;
        expect(
          diagonal.distanceTo(b.position!),
          lessThan(1e-3),
          reason: 'D touches B only on the flat figure',
        );
      }
    });

    test('all four sides stay equal through the whole sweep', () {
      const absolute = Absolute.hyperbolic;
      final (construction, _) = hyperbolicRhombus();
      final corners = cornersOf(construction);
      final cornerC = corners[2] as PointOnObject;
      final (a, b, cornerD) = (corners[0], corners[1], corners[3]);

      double span(GeoPoint p, GeoPoint q) =>
          distanceBetween(absolute, p.projPoint!, q.projPoint!)!;

      final start = cornerC.parameter;
      const steps = 200;
      for (var i = 0; i <= steps; i++) {
        construction.setPointOnObjectParameter(
          cornerC.id,
          start + math.pi * i / steps,
        );
        final side = span(a, b);
        for (final pair in [(b, cornerC), (cornerC, cornerD), (cornerD, a)]) {
          expect(span(pair.$1, pair.$2), closeTo(side, 1e-9));
        }
      }
    });
  });
}
