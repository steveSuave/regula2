import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('ReflectedPoint', () {
    test('mirrors across the line on construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(1, 3));
      final r = ReflectedPoint(id: 'r', point: p, mirror: mirror);
      expect(r.position!.closeTo(const Vec2(1, -3)), isTrue);
      expect(r.parents, [p, mirror]);
    });

    test('a point on the mirror is its own image', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(2, 2));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(5, 5));
      final r = ReflectedPoint(id: 'r', point: p, mirror: mirror);
      expect(r.position!.closeTo(const Vec2(5, 5)), isTrue);
    });

    test('double reflection is the identity', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(3, -4));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(7, 1.5));
      final once = ReflectedPoint(id: 'r1', point: p, mirror: mirror);
      final twice = ReflectedPoint(id: 'r2', point: once, mirror: mirror);
      expect(twice.position!.closeTo(p.position, 1e-9), isTrue);
    });

    test('mirror is the perpendicular bisector of point and image', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, -2));
      final b = FreePoint(id: 'b', position: const Vec2(4, 5));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(-3, 6));
      final r = ReflectedPoint(id: 'r', point: p, mirror: mirror);
      final image = r.position!;
      // Equidistant, and the midpoint lies on the mirror.
      expect(
        mirror.line!.distanceTo(p.position),
        closeTo(mirror.line!.distanceTo(image), 1e-9),
      );
      expect(mirror.line!.contains(p.position.lerp(image, 0.5), 1e-9), isTrue);
    });

    test('tracks moved parents after recompute', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(1, 3));
      final r = ReflectedPoint(id: 'r', point: p, mirror: mirror);

      p.position = const Vec2(2, -5);
      r.recompute();
      expect(r.position!.closeTo(const Vec2(2, 5)), isTrue);

      // Rotate the mirror to the y-axis: reflection flips x instead.
      b.position = const Vec2(0, 4);
      mirror.recompute();
      r.recompute();
      expect(r.position!.closeTo(const Vec2(-2, -5)), isTrue);
    });

    test('undefined while the mirror is, recovers after', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(1, 3));
      final r = ReflectedPoint(id: 'r', point: p, mirror: mirror);
      expect(r.isDefined, isFalse);

      b.position = const Vec2(4, 0);
      mirror.recompute();
      r.recompute();
      expect(r.isDefined, isTrue);
      expect(r.position!.closeTo(const Vec2(1, -3)), isTrue);
    });
  });

  group('projective semantics (Phase 108)', () {
    Glados3(any.vec2, any.vec2, any.vec2).test(
      'agrees with the V1 affine formula through the object graph',
      (v, p, q) {
        if (p.closeTo(q, 1e-3)) {
          return;
        }
        final a = FreePoint(id: 'a', position: p);
        final b = FreePoint(id: 'b', position: q);
        final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
        final r = ReflectedPoint(
          id: 'r',
          point: FreePoint(id: 'p', position: v),
          mirror: mirror,
        );
        final expected = LineEq.throughPoints(p, q).reflect(v);
        expect(
          r.position!.closeTo(expected, 1e-6 * (1 + expected.norm)),
          isTrue,
        );
      },
    );

    test('a point at infinity reflects to the mirrored direction at '
        'infinity, marked as such', () {
      final mirror = StubProjectiveLine(ProjLine.real(0, 1, 0)); // x-axis
      final r = ReflectedPoint(
        id: 'r',
        point: StubProjectivePoint(ProjPoint.real(1, 2, 0)),
        mirror: mirror,
      );
      expect(r.isDefined, isFalse);
      expect(r.position, isNull);
      final image = r.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(image.closeTo(ProjPoint.real(1, -2, 0)), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a parent',
      (v, q, k) {
        if (v.closeTo(q, 1e-3)) {
          return;
        }
        final axis = ProjLine.lift(LineEq.throughPoints(v, q));
        ReflectedPoint build(ProjPoint point, ProjLine mirror) =>
            ReflectedPoint(
              id: 'r',
              point: StubProjectivePoint(point),
              mirror: StubProjectiveLine(mirror),
            );
        final witness = ProjPoint.real(-3, 7);
        final plain = build(witness, axis);
        final scaledPoint = build(witness.scaledBy(k), axis);
        final scaledMirror = build(witness, axis.scaledBy(k));
        expect(scaledPoint.projPoint!.closeTo(plain.projPoint!), isTrue);
        expect(scaledMirror.projPoint!.closeTo(plain.projPoint!), isTrue);
      },
    );
  });
}
