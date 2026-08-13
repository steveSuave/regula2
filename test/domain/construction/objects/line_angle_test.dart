import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('LineAngle', () {
    test('marks the acute angle at the crossing', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: const Vec2(4, 0));
      final d = FreePoint(id: 'd', position: const Vec2(1, 1));
      final l1 = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: o, point2: d);
      final angle = LineAngle(id: 'g', line1: l1, line2: l2);

      expect(angle.angle!.vertex.closeTo(Vec2.zero), isTrue);
      expect(angle.angle!.measure, closeTo(math.pi / 4, 1e-9));
      expect(angle.parents, [l1, l2]);
    });

    test('is order-independent and never obtuse', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: const Vec2(4, 0));
      // Direction 120° from the x-axis: the lines cross at 60°.
      final d = FreePoint(id: 'd', position: const Vec2(-1, 1.7320508));
      final l1 = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: o, point2: d);

      final ab = LineAngle(id: 'g1', line1: l1, line2: l2);
      final ba = LineAngle(id: 'g2', line1: l2, line2: l1);
      expect(ab.angle!.measure, closeTo(math.pi / 3, 1e-6));
      expect(ba.angle!.measure, closeTo(math.pi / 3, 1e-6));
    });

    test('segments work through their carriers, vertex beyond the extents', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(2, 2));
      final c = FreePoint(id: 'c', position: const Vec2(1, -1));
      final d = FreePoint(id: 'd', position: const Vec2(2, -2));
      final s1 = Segment(id: 's1', point1: a, point2: b);
      final s2 = Segment(id: 's2', point1: c, point2: d);
      final angle = LineAngle(id: 'g', line1: s1, line2: s2);

      expect(angle.angle!.vertex.closeTo(Vec2.zero), isTrue);
      expect(angle.angle!.measure, closeTo(math.pi / 2, 1e-9));
    });

    test('undefined while parallel; recovers when the crossing returns', () {
      final construction = Construction();
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: const Vec2(4, 0));
      final p = FreePoint(id: 'p', position: const Vec2(0, 1));
      final q = FreePoint(id: 'q', position: const Vec2(4, 2));
      final l1 = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: p, point2: q);
      final angle = LineAngle(id: 'g', line1: l1, line2: l2);
      construction
        ..add(o)
        ..add(x)
        ..add(p)
        ..add(q)
        ..add(l1)
        ..add(l2)
        ..add(angle);

      expect(angle.isDefined, isTrue);

      construction.moveFreePoint('q', const Vec2(4, 1));
      expect(angle.isDefined, isFalse);
      expect(angle.angle, isNull);

      construction.moveFreePoint('q', const Vec2(4, 2));
      expect(angle.isDefined, isTrue);
    });

    test('sign validation: partial or non-unit signs are rejected', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: const Vec2(4, 0));
      final d = FreePoint(id: 'd', position: const Vec2(1, 1));
      final l1 = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: o, point2: d);

      expect(
        () => LineAngle(id: 'g', line1: l1, line2: l2, sign1: 1),
        throwsArgumentError,
      );
      expect(
        () => LineAngle(id: 'g', line1: l1, line2: l2, sign2: -1),
        throwsArgumentError,
      );
      expect(
        () => LineAngle(id: 'g', line1: l1, line2: l2, sign1: 2, sign2: 1),
        throwsArgumentError,
      );
      expect(
        () => LineAngle(id: 'g', line1: l1, line2: l2, sign1: 1, sign2: 0),
        throwsArgumentError,
      );
    });

    test('undefined while a parent line is undefined', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: Vec2.zero); // coincident
      final p = FreePoint(id: 'p', position: const Vec2(0, 1));
      final q = FreePoint(id: 'q', position: const Vec2(4, 2));
      final broken = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: p, point2: q);

      expect(LineAngle(id: 'g', line1: broken, line2: l2).isDefined, isFalse);
    });
  });

  group('LineAngle.near (tap-picked wedge)', () {
    // The x-axis and a 60° line, crossing at the origin. Half-directions
    // by angle: +x = 0°, −x = 180°, +d = 60°, −d = 240°.
    late LineThroughTwoPoints xAxis;
    late LineThroughTwoPoints sixty;
    late FreePoint d;
    late Construction construction;

    setUp(() {
      construction = Construction();
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: const Vec2(4, 0));
      d = FreePoint(id: 'd', position: Vec2(1, math.sqrt(3)));
      xAxis = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      sixty = LineThroughTwoPoints(id: 'l2', point1: o, point2: d);
      construction
        ..add(o)
        ..add(x)
        ..add(d)
        ..add(xAxis)
        ..add(sixty);
    });

    LineAngle near(String id, Vec2 tap1, Vec2 tap2) => LineAngle.near(
      id: id,
      line1: xAxis,
      line2: sixty,
      tap1: tap1,
      tap2: tap2,
    );

    void expectWedge(LineAngle angle, double sweep, double startAngle) {
      expect(angle.angle!.measure, closeTo(sweep, 1e-9));
      expect(
        angle.angle!.startDirection.closeTo(
          Vec2(math.cos(startAngle), math.sin(startAngle)),
          1e-9,
        ),
        isTrue,
        reason:
            'start arm should point at ${startAngle * 180 / math.pi}°, '
            'got ${angle.angle!.startDirection}',
      );
    }

    test('the four tap-half combinations mark their own wedge', () {
      // Taps near +x / +d: the acute wedge from 0° to 60°.
      expectWedge(
        near('a', const Vec2(3, 0.1), const Vec2(1.1, 1.7)),
        math.pi / 3,
        0,
      );
      // Taps near +x / −d: the obtuse wedge from 240° around to 360°.
      expectWedge(
        near('b', const Vec2(3, 0.1), const Vec2(-1.1, -1.7)),
        2 * math.pi / 3,
        4 * math.pi / 3,
      );
      // Taps near −x / +d: the obtuse wedge from 60° to 180°.
      expectWedge(
        near('c', const Vec2(-3, 0.1), const Vec2(1.1, 1.7)),
        2 * math.pi / 3,
        math.pi / 3,
      );
      // Taps near −x / −d: the acute wedge from 180° to 240°.
      expectWedge(
        near('d', const Vec2(-3, 0.1), const Vec2(-1.1, -1.7)),
        math.pi / 3,
        math.pi,
      );
    });

    test('right angle: the marked quadrant is the tapped one', () {
      // Rotate the second line to vertical: taps in quadrant II must put
      // both arms on quadrant II's boundary (+y start arm, −x end arm).
      construction.moveFreePoint('d', const Vec2(0, 4));
      final angle = LineAngle.near(
        id: 'g',
        line1: xAxis,
        line2: sixty,
        tap1: const Vec2(-3, 0.1),
        tap2: const Vec2(-0.1, 3),
      );

      expect(angle.angle!.measure, closeTo(math.pi / 2, 1e-9));
      expect(angle.angle!.startDirection.closeTo(const Vec2(0, 1)), isTrue);
      expect(angle.angle!.endDirection.closeTo(const Vec2(-1, 0)), isTrue);
    });

    test('the wedge follows drags continuously — no flip mid-drag', () {
      final angle = near('g', const Vec2(-3, 0.1), const Vec2(1.1, 1.7));
      construction.add(angle);
      expectWedge(angle, 2 * math.pi / 3, math.pi / 3);

      // Sweep the 60° line towards 90° in small steps: the marked wedge
      // must shrink smoothly from 120° to 90° with the start arm tracking
      // the rotating carrier — never jumping to the complementary pair.
      var previousStart = angle.angle!.startDirection;
      for (var degrees = 60; degrees <= 90; degrees += 5) {
        final radians = degrees * math.pi / 180;
        construction.moveFreePoint(
          'd',
          Vec2(2 * math.cos(radians), 2 * math.sin(radians)),
        );
        final geometry = angle.angle!;
        expect(geometry.measure, closeTo(math.pi - radians, 1e-9));
        expect(
          geometry.startDirection.dot(previousStart),
          greaterThan(0.9),
          reason: 'start arm flipped at $degrees°',
        );
        previousStart = geometry.startDirection;
      }
    });

    test('falls back to +1/+1 while the carriers are coincident', () {
      // d onto the x-axis: `sixty` collapses onto `xAxis`, the meet is
      // the zero triple — no vertex to take a tap side from.
      construction.moveFreePoint('d', const Vec2(4, 0));
      final angle = near('g', const Vec2(-3, 0.1), const Vec2(-1, -1));
      construction.add(angle);

      expect(angle.sign1, 1);
      expect(angle.sign2, 1);
      expect(angle.isDefined, isFalse);

      construction.moveFreePoint('d', Vec2(1, math.sqrt(3)));
      expect(angle.isDefined, isTrue);
      expect(angle.angle!.measure, closeTo(math.pi / 3, 1e-9));
    });

    test('nearly parallel carriers mark their genuine tiny wedge '
        '(V2 semantics, Phase 112: the V1 direction band is gone)', () {
      // Both lines pass through the origin; tilting `sixty` down to
      // 2.5e-13 rad leaves a genuine crossing there. V1's absolute
      // 1e-9 direction band called this "parallel" and went undefined;
      // the projective meet finds the vertex.
      construction.moveFreePoint('d', const Vec2(4, 1e-12));
      final angle = near('g', const Vec2(-3, 0.1), const Vec2(-1, -1));
      construction.add(angle);

      expect(angle.sign1, -1, reason: 'taps sit on the −x / −d halves');
      expect(angle.sign2, -1);
      expect(angle.isDefined, isTrue);
      expect(angle.angle!.vertex.closeTo(Vec2.zero), isTrue);
      expect(angle.angle!.measure, closeTo(2.5e-13, 1e-14));
    });

    test('null signs keep the legacy acute fold under every tap side', () {
      final legacy = LineAngle(id: 'g', line1: xAxis, line2: sixty);
      expect(legacy.sign1, isNull);
      expect(legacy.sign2, isNull);
      expect(legacy.angle!.measure, closeTo(math.pi / 3, 1e-9));
    });
  });

  group('projective semantics (Phase 112)', () {
    test('distinct exact parallels meet at infinity — undefined', () {
      // y = 0 and y = 1: the meet is [1 : 0 : 0], real but not finite.
      final l1 = StubProjectiveLine(ProjLine.real(0, 1, 0));
      final l2 = StubProjectiveLine(ProjLine.real(0, 1, -1));
      final angle = LineAngle(id: 'g', line1: l1, line2: l2);
      expect(angle.isDefined, isFalse);
      expect(angle.angle, isNull);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'the legacy fold is invariant under complex rescaling of a carrier',
      (p, q, k) {
        if (ProjPoint.lift(p).closeTo(ProjPoint.lift(q))) return;
        // A real line through p and q against the x-axis; the legacy
        // fold is orientation-free, so the un-anchored stub serves.
        final carrier = ProjPoint.lift(p).join(ProjPoint.lift(q));
        final xAxis = ProjLine.real(0, 1, 0);
        final plain = LineAngle(
          id: 'g1',
          line1: StubProjectiveLine(carrier),
          line2: StubProjectiveLine(xAxis),
        );
        final scaled = LineAngle(
          id: 'g2',
          line1: StubProjectiveLine(carrier.scaledBy(k)),
          line2: StubProjectiveLine(xAxis),
        );
        expect(plain.isDefined, scaled.isDefined);
        if (plain.isDefined) {
          expect(
            scaled.angle!.measure,
            closeTo(plain.angle!.measure, 1e-6),
          );
          expect(
            scaled.angle!.vertex.closeTo(plain.angle!.vertex, 1e-6),
            isTrue,
          );
        }
      },
    );
  });
}
