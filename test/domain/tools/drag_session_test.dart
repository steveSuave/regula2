import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/move_free_point_command.dart';
import 'package:regula/domain/commands/move_text_anchor_command.dart';
import 'package:regula/domain/commands/set_point_on_object_parameter_command.dart';
import 'package:regula/domain/commands/translate_objects_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/drag_session.dart';

void main() {
  late Construction construction;
  late FreePoint a;
  late FreePoint b;
  late Segment segment;
  late Midpoint midpoint;

  setUp(() {
    construction = Construction();
    a = FreePoint(id: 'a', position: Vec2.zero);
    b = FreePoint(id: 'b', position: const Vec2(4, 0));
    segment = Segment(id: 's', point1: a, point2: b);
    midpoint = Midpoint(id: 'm', point1: a, point2: b);
    construction
      ..add(a)
      ..add(b)
      ..add(segment)
      ..add(midpoint);
  });

  group('DragSession.start', () {
    test('refuses derived points', () {
      expect(DragSession.start(construction, midpoint, Vec2.zero), isNull);
    });

    test('a text drags its own anchor, never the referenced geometry', () {
      final text = ExpressionText(
        id: 't',
        content: '{dist(A, B)}',
        anchor: const Vec2(10, 10),
        references: [a, b],
      );
      construction.add(text);

      final session = DragSession.start(
        construction,
        text,
        const Vec2(11, 10),
      )!;
      session.update(const Vec2(211, 60)); // way past any 40 px clamp
      expect(
        text.anchor,
        const Vec2(210, 60),
        reason: 'anchor rides the pointer delta, unclamped',
      );
      expect(a.position, Vec2.zero);
      expect(b.position, const Vec2(4, 0));

      final command = session.end()! as MoveTextAnchorCommand;
      expect(
        text.anchor,
        const Vec2(10, 10),
        reason: 'end rolls the preview back',
      );
      expect(command.textId, 't');
      expect(command.from, const Vec2(10, 10));
      expect(command.to, const Vec2(210, 60));

      command.apply(construction);
      expect(text.anchor, const Vec2(210, 60));
      command.undo(construction);
      expect(text.anchor, const Vec2(10, 10));
    });

    test('a text drag that ends where it started returns null', () {
      final text = ExpressionText(
        id: 't',
        content: 'note',
        anchor: const Vec2(1, 1),
        references: const [],
      );
      construction.add(text);
      final session = DragSession.start(construction, text, Vec2.zero)!;
      session.update(const Vec2(3, 3));
      session.update(Vec2.zero);
      expect(session.end(), isNull);
      expect(text.anchor, const Vec2(1, 1));
    });

    test('cancelling a text drag restores the anchor', () {
      final text = ExpressionText(
        id: 't',
        content: 'note',
        anchor: const Vec2(1, 1),
        references: const [],
      );
      construction.add(text);
      final session = DragSession.start(construction, text, Vec2.zero)!;
      session.update(const Vec2(50, 50));
      session.cancel();
      expect(text.anchor, const Vec2(1, 1));
    });

    test('accepts free points and derived non-points', () {
      expect(DragSession.start(construction, a, Vec2.zero), isNotNull);
      expect(
        DragSession.start(construction, segment, const Vec2(2, 0)),
        isNotNull,
      );
    });
  });

  group('free-point drag', () {
    test('previews per frame, ends with one MoveFreePointCommand', () {
      final session = DragSession.start(construction, a, Vec2.zero)!;

      session.update(const Vec2(1, 1));
      expect(a.position, const Vec2(1, 1));
      expect(
        midpoint.position,
        const Vec2(2.5, 0.5),
        reason: 'dependents recompute per preview frame',
      );

      session.update(const Vec2(2, 3));
      final command = session.end()!;

      expect(
        a.position,
        Vec2.zero,
        reason: 'end rolls the preview back — the command replays it',
      );
      expect(command, isA<MoveFreePointCommand>());
      command.apply(construction);
      expect(a.position, const Vec2(2, 3));
      expect(midpoint.position, const Vec2(3, 1.5));
      command.undo(construction);
      expect(a.position, Vec2.zero);
    });

    test('the delta rides the pointer, not the grab point', () {
      // Grabbed 0.5 away from the point's center: the point must move by
      // the pointer's delta, not jump under the cursor.
      final session = DragSession.start(construction, a, const Vec2(0.5, 0))!;
      session.update(const Vec2(1.5, 2));
      expect(a.position, const Vec2(1, 2));
      session.cancel();
      expect(a.position, Vec2.zero);
    });

    test('zero-delta gesture ends with no command', () {
      final session = DragSession.start(construction, a, Vec2.zero)!;
      expect(session.end(), isNull);

      final grabbed = DragSession.start(construction, a, Vec2.zero)!;
      grabbed.update(const Vec2(1, 0));
      grabbed.update(Vec2.zero); // dragged back home
      expect(grabbed.end(), isNull);
      expect(a.position, Vec2.zero);
    });
  });

  group('free-point drag with gridSnapStep (Phase 45)', () {
    test('preview quantizes per frame, the one command commits snapped', () {
      final session = DragSession.start(
        construction,
        a,
        Vec2.zero,
        gridSnapStep: 2,
      )!;

      session.update(const Vec2(2.7, 1.2));
      expect(
        a.position,
        const Vec2(2, 2),
        reason: 'the preview frame lands on a grid crossing',
      );
      expect(
        midpoint.position,
        const Vec2(3, 1),
        reason: 'dependents recompute from the snapped preview',
      );

      session.update(const Vec2(5.1, 0.8));
      final command = session.end()!;
      expect(a.position, Vec2.zero, reason: 'end rolls the preview back');
      expect(command, isA<MoveFreePointCommand>());
      command.apply(construction);
      expect(
        a.position,
        const Vec2(6, 0),
        reason: 'the command carries the snapped end position',
      );
    });

    test('a drag that quantizes back onto its start commits nothing', () {
      final session = DragSession.start(
        construction,
        a,
        Vec2.zero,
        gridSnapStep: 2,
      )!;
      session.update(const Vec2(0.6, -0.9)); // rounds to (0, 0) — a's start
      expect(a.position, Vec2.zero);
      expect(session.end(), isNull);
    });

    test('an off-grid point snaps onto the grid from the first frame', () {
      final offGrid = FreePoint(id: 'og', position: const Vec2(0.3, 0.4));
      construction.add(offGrid);

      final session = DragSession.start(
        construction,
        offGrid,
        const Vec2(0.3, 0.4),
        gridSnapStep: 1,
      )!;
      session.update(const Vec2(0.5, 0.4)); // delta (0.2, 0) → (0.5, 0.4)
      expect(offGrid.position, const Vec2(1, 0));
      session.cancel();
      expect(
        offGrid.position,
        const Vec2(0.3, 0.4),
        reason: 'cancel restores the off-grid start verbatim',
      );
    });

    test('rigid translations ignore the step — shapes never distort', () {
      final session = DragSession.start(
        construction,
        segment,
        const Vec2(2, 0),
        gridSnapStep: 2,
      )!;

      session.update(const Vec2(3, 1.2));
      expect(
        a.position,
        const Vec2(1, 1.2),
        reason: 'ancestors move by the raw delta, never quantized',
      );
      expect(b.position, const Vec2(5, 1.2));

      final command = session.end()!;
      expect(command, isA<TranslateObjectsCommand>());
      command.apply(construction);
      expect(a.position, const Vec2(1, 1.2));
      expect(b.position, const Vec2(5, 1.2));
      command.undo(construction);
    });

    test('a step of 0 is byte-identical to the unsnapped drag', () {
      final session = DragSession.start(
        construction,
        a,
        Vec2.zero,
        gridSnapStep: 0,
      )!;
      session.update(const Vec2(2.7, 1.2));
      expect(a.position, const Vec2(2.7, 1.2));
      final command = session.end()! as MoveFreePointCommand;
      command.apply(construction);
      expect(a.position, const Vec2(2.7, 1.2));
      command.undo(construction);
    });
  });

  group('derived-object drag', () {
    test('rigidly translates the free ancestors, one command', () {
      final session = DragSession.start(
        construction,
        segment,
        const Vec2(2, 0),
      )!;

      session.update(const Vec2(3, 2));
      expect(a.position, const Vec2(1, 2));
      expect(b.position, const Vec2(5, 2));
      expect(
        midpoint.position,
        const Vec2(3, 2),
        reason: 'the whole configuration translates rigidly',
      );

      final command = session.end()!;
      expect(a.position, Vec2.zero);
      expect(b.position, const Vec2(4, 0));
      expect(command, isA<TranslateObjectsCommand>());

      command.apply(construction);
      expect(a.position, const Vec2(1, 2));
      expect(b.position, const Vec2(5, 2));
      command.undo(construction);
      expect(a.position, Vec2.zero);
      expect(b.position, const Vec2(4, 0));
    });

    test('cancel rolls the preview back', () {
      final session = DragSession.start(
        construction,
        segment,
        const Vec2(2, 0),
      )!;
      session.update(const Vec2(7, -3));
      session.cancel();
      expect(a.position, Vec2.zero);
      expect(b.position, const Vec2(4, 0));
    });

    test('rollback skips points removed mid-session instead of throwing', () {
      final session = DragSession.start(
        construction,
        segment,
        const Vec2(2, 0),
      )!;
      session.update(const Vec2(3, 1));

      // An undo mid-drag can delete a dragged point (and its dependents).
      construction.removeWithDependents('a');

      session.cancel();
      expect(
        b.position,
        const Vec2(4, 0),
        reason: 'the surviving point still rolls back',
      );
    });
  });

  group('CompassCircle drag', () {
    test('moves only the center — the radius points are a measurement', () {
      final center = FreePoint(id: 'c', position: const Vec2(10, 10));
      final compass = CompassCircle(
        id: 'k',
        radiusPoint1: a,
        radiusPoint2: b,
        center: center,
      );
      construction
        ..add(center)
        ..add(compass);
      expect(compass.circle!.radius, 4);

      final session = DragSession.start(
        construction,
        compass,
        const Vec2(14, 10),
      )!;
      session.update(const Vec2(15, 12));
      expect(center.position, const Vec2(11, 12));
      expect(a.position, Vec2.zero, reason: 'radius-defining points stay put');
      expect(b.position, const Vec2(4, 0));
      expect(
        compass.circle!.radius,
        4,
        reason: 'the measured radius is unchanged',
      );

      final command = session.end()!;
      expect(center.position, const Vec2(10, 10));
      expect(command, isA<TranslateObjectsCommand>());
      command.apply(construction);
      expect(center.position, const Vec2(11, 12));
      expect(a.position, Vec2.zero);
      command.undo(construction);
      expect(center.position, const Vec2(10, 10));
    });

    test('a derived center drags through its own free ancestors', () {
      // Center = midpoint of a and b: those ARE radius ancestors too, so
      // the radius may change — the rule is "the center's free ancestors",
      // not "anything but the radius points".
      final compass = CompassCircle(
        id: 'k',
        radiusPoint1: a,
        radiusPoint2: b,
        center: midpoint,
      );
      construction.add(compass);

      final session = DragSession.start(
        construction,
        compass,
        const Vec2(2, 4),
      )!;
      session.update(const Vec2(3, 4));
      expect(a.position, const Vec2(1, 0));
      expect(b.position, const Vec2(5, 0));
      session.cancel();
      expect(a.position, Vec2.zero);
      expect(b.position, const Vec2(4, 0));
    });

    test("a constrained center drags its host curve's free points only", () {
      // Center rides a line through two points unrelated to the radius
      // pair: dragging the compass translates the line's points, while a
      // and b (the measurement) stay put.
      final d = FreePoint(id: 'd', position: const Vec2(0, 10));
      final e = FreePoint(id: 'e', position: const Vec2(10, 10));
      final l1 = LineThroughTwoPoints(id: 'l1', point1: d, point2: e);
      construction
        ..add(d)
        ..add(e)
        ..add(l1);
      final onLine = PointOnObject(id: 'ol', curve: l1, parameter: 5);
      construction.add(onLine);
      final compass = CompassCircle(
        id: 'k',
        radiusPoint1: a,
        radiusPoint2: b,
        center: onLine,
      );
      construction.add(compass);

      final session = DragSession.start(
        construction,
        compass,
        const Vec2(9, 10),
      )!;
      session.update(const Vec2(9, 13));
      expect(d.position, const Vec2(0, 13));
      expect(e.position, const Vec2(10, 13));
      expect(a.position, Vec2.zero);
      expect(b.position, const Vec2(4, 0));
      session.cancel();
      expect(d.position, const Vec2(0, 10));
      expect(e.position, const Vec2(10, 10));
    });
  });

  group('PointOnObject slide-drag', () {
    late PointOnObject onSegment;

    setUp(() {
      // Segment a→b runs along the x axis from 0 to 4; parameter 1 puts
      // the point at (1, 0) (arc-length along the unit direction).
      onSegment = PointOnObject(id: 'p', curve: segment, parameter: 1);
      construction.add(onSegment);
    });

    test('slides along the host line, ends with one parameter command', () {
      final session = DragSession.start(
        construction,
        onSegment,
        const Vec2(1, 0),
      )!;

      session.update(const Vec2(3, 2));
      expect(
        onSegment.position,
        const Vec2(3, 0),
        reason: 'the pointer projects onto the carrier per frame',
      );
      expect(onSegment.parameter, 3);

      final command = session.end()!;
      expect(
        onSegment.parameter,
        1,
        reason: 'end rolls the preview back — the command replays it',
      );
      expect(command, isA<SetPointOnObjectParameterCommand>());
      command.apply(construction);
      expect(onSegment.position, const Vec2(3, 0));
      command.undo(construction);
      expect(onSegment.position, const Vec2(1, 0));
    });

    test('the parameter rides the pointer, not the grab point', () {
      // Grabbed 0.5 short of the point (hit threshold): the point must
      // follow the pointer's motion, not jump under the cursor.
      final session = DragSession.start(
        construction,
        onSegment,
        const Vec2(0.5, 0),
      )!;
      session.update(const Vec2(2.5, 0));
      expect(onSegment.position, const Vec2(3, 0));
      session.cancel();
      expect(onSegment.position, const Vec2(1, 0));
      expect(onSegment.parameter, 1, reason: 'rollback is float-exact');
    });

    test('slide on a segment stops at its endpoints instead of leaving '
        'it', () {
      final session = DragSession.start(
        construction,
        onSegment,
        const Vec2(1, 0),
      )!;
      // Drag far past b: the point must stop on the endpoint, not slide
      // onto the infinite carrier.
      session.update(const Vec2(9, 2));
      expect(onSegment.parameter, 4);
      expect(onSegment.position, const Vec2(4, 0));

      // Reverse past a: it stops at the other endpoint.
      session.update(const Vec2(-3, -2));
      expect(onSegment.parameter, 0);
      expect(onSegment.position, const Vec2(0, 0));

      final command = session.end()! as SetPointOnObjectParameterCommand;
      expect(
        command.to,
        0,
        reason: 'the committed parameter is the clamped one',
      );
    });

    test('zero-motion gesture ends with no command', () {
      final session = DragSession.start(
        construction,
        onSegment,
        const Vec2(1, 0),
      )!;
      expect(session.end(), isNull);
    });

    test('slides around a circle host, staying on the rim', () {
      final center = FreePoint(id: 'c', position: Vec2.zero);
      // b sits at (4, 0), so the circle has radius 4.
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: b);
      final onCircle = PointOnObject(id: 'q', curve: circle, parameter: 0);
      construction
        ..add(center)
        ..add(circle)
        ..add(onCircle);
      expect(onCircle.position, const Vec2(4, 0));

      final session = DragSession.start(
        construction,
        onCircle,
        const Vec2(4, 0),
      )!;
      // Drag toward the top of the circle, from off-rim: the point must
      // radially project back onto the rim.
      session.update(const Vec2(0, 7));
      expect(onCircle.position!.x, closeTo(0, 1e-12));
      expect(onCircle.position!.y, closeTo(4, 1e-12));

      final command = session.end()!;
      expect(onCircle.position, const Vec2(4, 0));
      command.apply(construction);
      expect(onCircle.position!.y, closeTo(4, 1e-12));
    });

    test('slides along a general conic host, staying on the ink '
        '(Phase 132)', () {
      // A conic with no `CircleEq` had no `project` map at all, so
      // `_SlideDragSession.start` answered null and a point glued to a
      // conic could be created but never moved. It slides by the pencil
      // angle now — the same map a tap uses.
      final pts = [
        FreePoint(id: 'c0', position: const Vec2(4, 0)),
        FreePoint(id: 'c1', position: const Vec2(0, 3)),
        FreePoint(id: 'c2', position: const Vec2(-4, 0)),
        FreePoint(id: 'c3', position: const Vec2(0, -3)),
        FreePoint(id: 'c4', position: const Vec2(2.4, 2.4)),
      ];
      final k = FivePointConic(id: 'k', points: pts);
      final glued = PointOnObject.near(
        id: 'q',
        curve: k,
        position: const Vec2(4, 0),
      );
      for (final p in pts) {
        construction.add(p);
      }
      construction
        ..add(k)
        ..add(glued);
      final startedAt = glued.position!;

      final session = DragSession.start(construction, glued, startedAt)!;
      // Drag to the far side of the ellipse, from well off the ink: the
      // point must project back onto the curve.
      session.update(const Vec2(-6, 0.5));
      final moved = glued.position!;
      expect(
        k.conic!.containsPoint(glued.projPoint!, 1e-9),
        isTrue,
        reason: 'a slide never leaves the curve',
      );
      expect(
        (moved - startedAt).norm,
        greaterThan(4),
        reason: 'and it actually went somewhere',
      );

      final command = session.end()!;
      expect(glued.position!.closeTo(startedAt), isTrue, reason: 'rolled back');
      command.apply(construction);
      expect(glued.position!.closeTo(moved), isTrue);
      expect(k.conic!.containsPoint(glued.projPoint!, 1e-9), isTrue);
    });

    test('slide on a sector stops at the wedge ends instead of circling', () {
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final end = FreePoint(id: 'e', position: const Vec2(0, 4));
      // b sits at (4, 0): wedge from angle 0 to π/2, radius 4.
      final sector = Sector(id: 'w', center: center, start: b, end: end);
      final onSector = PointOnObject(
        id: 'q',
        curve: sector,
        parameter: math.pi / 4,
      );
      construction
        ..add(center)
        ..add(end)
        ..add(sector)
        ..add(onSector);

      final session = DragSession.start(
        construction,
        onSector,
        onSector.position!,
      )!;
      // Drag far past the end rim: the point must stop there instead of
      // following the pointer around the carrier.
      session.update(const Vec2(-4, 4));
      expect(onSector.parameter, closeTo(math.pi / 2, 1e-9));
      expect(onSector.position!.closeTo(const Vec2(0, 4)), isTrue);

      // Reverse below the start rim: it stops at the other end.
      session.update(const Vec2(4, -4));
      expect(onSector.parameter, closeTo(0, 1e-9));
      expect(onSector.position!.closeTo(const Vec2(4, 0)), isTrue);

      final command = session.end()! as SetPointOnObjectParameterCommand;
      expect(
        command.to,
        closeTo(0, 1e-9),
        reason: 'the committed parameter is the clamped one',
      );
    });

    test('grabbing near the ±π angular cut never jumps the point a turn', () {
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: b);
      final onCircle = PointOnObject(
        id: 'q',
        curve: circle,
        parameter: math.pi,
      );
      construction
        ..add(center)
        ..add(circle)
        ..add(onCircle);
      expect(onCircle.position!.x, closeTo(-4, 1e-12));

      // Grab a hair below the −x axis: atan2 there is ≈ −π while the
      // parameter is +π — the raw offset is ~2π and must be normalized.
      final session = DragSession.start(
        construction,
        onCircle,
        const Vec2(-4, -1e-9),
      )!;
      session.update(const Vec2(-4, -1e-9));
      expect(
        onCircle.position!.x,
        closeTo(-4, 1e-6),
        reason: 'a still gesture must not move the point',
      );
      expect(onCircle.position!.y, closeTo(0, 1e-6));
      expect(
        onCircle.parameter.abs(),
        lessThan(math.pi + 1e-6),
        reason:
            'the normalized offset keeps the parameter within a '
            'turn (±π may swap sign at the cut — same rim position)',
      );
      session.cancel();
      expect(onCircle.parameter, math.pi, reason: 'rollback is float-exact');
    });

    test('refuses to start while the host curve is undefined', () {
      construction.moveFreePoint('b', Vec2.zero); // a == b: carrier gone
      expect(DragSession.start(construction, onSegment, Vec2.zero), isNull);
      construction.moveFreePoint('b', const Vec2(4, 0));
    });

    test('rollback skips a point removed mid-session instead of throwing', () {
      final session = DragSession.start(
        construction,
        onSegment,
        const Vec2(1, 0),
      )!;
      session.update(const Vec2(2, 0));
      construction.removeWithDependents('p');
      session.cancel(); // must not throw
      expect(construction.contains('p'), isFalse);
    });
  });

  group('conic∩conic drags commit through the session (Phase 120c)', () {
    /// Two ellipses crossing four times, with all four crossings built —
    /// `ellipse-intersection-issue.rgl`. The dragged point is a focus of
    /// the first, so shrinking it takes the crossings complex.
    (Construction, FreePoint, List<IntersectionPoint>) fourWay() {
      final c = Construction();
      FreePoint fp(String id, double x, double y) =>
          FreePoint(id: id, position: Vec2(x, y));
      final free = [
        fp('a1', 276.28515625, -549.99609375),
        fp('a2', 852.93359375, -511.88671875),
        fp('a3', 527.05859375, -349.2734375),
        fp('b1', 558.8051299943472, -469.1066983991435),
        fp('b2', 550.9898345406327, -561.0437497250491),
        fp('b3', 343.23828125, -549.99609375),
      ];
      for (final p in free) {
        c.add(p);
      }
      final e1 = BifocalConic(
        id: 'e1',
        focus1: free[0],
        focus2: free[1],
        point: free[2],
        difference: false,
      );
      final e2 = BifocalConic(
        id: 'e2',
        focus1: free[3],
        focus2: free[4],
        point: free[5],
        difference: false,
      );
      c
        ..add(e1)
        ..add(e2);
      final points = [
        for (var i = 0; i < 4; i++)
          IntersectionPoint(id: 'i$i', curve1: e1, curve2: e2, branchIndex: i),
      ];
      for (final p in points) {
        c.add(p);
      }
      return (c, free[2], points);
    }

    /// One gesture: grab [point], run the waypoints, release, commit.
    void gesture(Construction c, FreePoint point, List<Vec2> waypoints) {
      final session = DragSession.start(c, c.byId(point.id)!, point.position)!;
      for (final w in waypoints) {
        session.update(w);
      }
      session.end()?.apply(c);
    }

    test('a drag that takes four crossings complex and back keeps four '
        'distinct branches — and its command does not throw', () {
      // The engine stopped merging these in Phase 120c, but the gesture's
      // *command* still refused every adoption to index 2 or 3
      // (`setIntersectionBranch` carried its own 0..1 bound), so the
      // re-pointing was thrown away and the app went on merging them.
      // This is the level that catches that: session, end(), apply().
      final (c, dragged, points) = fourWay();
      expect(points.map((p) => p.branchIndex).toSet(), {0, 1, 2, 3});

      gesture(c, dragged, [
        for (var i = 1; i <= 12; i++) Vec2(527, -349.27 + 149.27 * i / 12),
      ]);
      gesture(c, dragged, [
        for (var i = 1; i <= 12; i++) Vec2(527, -200 - 149.27 * i / 12),
      ]);

      expect(
        points.map((p) => p.branchIndex).toSet(),
        hasLength(4),
        reason:
            'branches collapsed: '
            '${points.map((p) => '${p.id}#${p.branchIndex}').join(' ')}',
      );
      // Distinct addresses must mean distinct roots.
      final places = points.map((p) => p.position).toList();
      expect(places, everyElement(isNotNull));
      for (var i = 0; i < places.length; i++) {
        for (var j = i + 1; j < places.length; j++) {
          expect(
            places[i]!.distanceTo(places[j]!),
            greaterThan(1),
            reason: 'i$i and i$j landed on the same root',
          );
        }
      }
    });

    test('undo puts the pre-drag branches back', () {
      final (c, dragged, points) = fourWay();
      final before = [for (final p in points) p.branchIndex];
      final session = DragSession.start(c, c.byId('a3')!, dragged.position)!;
      for (var i = 1; i <= 12; i++) {
        session.update(Vec2(527, -349.27 + 149.27 * i / 12));
      }
      final command = session.end()!;
      command.apply(c);
      command.undo(c);
      expect([for (final p in points) p.branchIndex], before);
    });
  });
}
