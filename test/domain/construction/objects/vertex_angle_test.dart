import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('VertexAngle', () {
    test('right angle: CCW from the first arm to the second', () {
      final a = FreePoint(id: 'a', position: const Vec2(3, 1));
      final v = FreePoint(id: 'v', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 4));
      final angle = VertexAngle(id: 'g', arm1: a, vertex: v, arm2: b);

      expect(angle.angle!.vertex, const Vec2(1, 1));
      expect(angle.angle!.startDirection.closeTo(const Vec2(1, 0)), isTrue);
      expect(angle.angle!.measure, closeTo(math.pi / 2, 1e-9));
      expect(angle.parents, [a, v, b]);
    });

    test('swapping the arms marks the complementary (reflex) angle', () {
      final a = FreePoint(id: 'a', position: const Vec2(3, 1));
      final v = FreePoint(id: 'v', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 4));
      final reflex = VertexAngle(id: 'g', arm1: b, vertex: v, arm2: a);

      expect(reflex.angle!.measure, closeTo(3 * math.pi / 2, 1e-9));
    });

    test('undefined while an arm sits on the vertex; recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(3, 1));
      final v = FreePoint(id: 'v', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 4));
      final angle = VertexAngle(id: 'g', arm1: a, vertex: v, arm2: b);
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(angle);

      construction.moveFreePoint('a', const Vec2(1, 1));
      expect(angle.isDefined, isFalse);
      expect(angle.angle, isNull);

      construction.moveFreePoint('a', const Vec2(3, 1));
      expect(angle.isDefined, isTrue);
      expect(angle.angle!.measure, closeTo(math.pi / 2, 1e-9));
    });

    test('the measure follows a dragged arm', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 0));
      final v = FreePoint(id: 'v', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(0, 1));
      final angle = VertexAngle(id: 'g', arm1: a, vertex: v, arm2: b);
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(angle);

      construction.moveFreePoint('b', const Vec2(-1, 1));
      expect(angle.angle!.measure, closeTo(3 * math.pi / 4, 1e-9));
    });
  });

  group('projective semantics (Phase 112)', () {
    test('an arm at infinity leaves the angle undefined — a point at '
        'infinity is a direction without a sign', () {
      final v = FreePoint(id: 'v', position: Vec2.zero);
      final a = FreePoint(id: 'a', position: const Vec2(1, 0));
      final inf = StubProjectivePoint(ProjPoint.real(0, 1, 0));
      final angle = VertexAngle(id: 'g', arm1: a, vertex: v, arm2: inf);
      expect(angle.isDefined, isFalse);
      expect(angle.angle, isNull);
    });

    test('a vertex at infinity leaves the angle undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 1));
      final inf = StubProjectivePoint(ProjPoint.real(1, 1, 0));
      final angle = VertexAngle(id: 'g', arm1: a, vertex: inf, arm2: b);
      expect(angle.isDefined, isFalse);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'the measure is invariant under complex rescaling of a parent',
      (a, b, k) {
        final v = Vec2(a.x + 1, b.y - 1);
        if (ProjPoint.lift(a).closeTo(ProjPoint.lift(v)) ||
            ProjPoint.lift(b).closeTo(ProjPoint.lift(v))) {
          return;
        }
        final plain = VertexAngle(
          id: 'g1',
          arm1: StubProjectivePoint(ProjPoint.lift(a)),
          vertex: StubProjectivePoint(ProjPoint.lift(v)),
          arm2: StubProjectivePoint(ProjPoint.lift(b)),
        );
        final scaled = VertexAngle(
          id: 'g2',
          arm1: StubProjectivePoint(ProjPoint.lift(a).scaledBy(k)),
          vertex: StubProjectivePoint(ProjPoint.lift(v).scaledBy(k)),
          arm2: StubProjectivePoint(ProjPoint.lift(b)),
        );
        expect(plain.isDefined, scaled.isDefined);
        if (plain.isDefined) {
          expect(scaled.angle!.measure, closeTo(plain.angle!.measure, 1e-6));
        }
      },
    );
  });
}
