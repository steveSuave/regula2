import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('CentralReflectionPoint', () {
    test('reflects about the center on construction', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 3));
      final c = FreePoint(id: 'c', position: const Vec2(2, 1));
      final r = CentralReflectionPoint(id: 'r', point: p, center: c);
      expect(r.position, const Vec2(3, -1));
      expect(r.parents, [p, c]);
    });

    test('center is the midpoint of point and image', () {
      final p = FreePoint(id: 'p', position: const Vec2(-4, 7));
      final c = FreePoint(id: 'c', position: const Vec2(1.5, -2));
      final r = CentralReflectionPoint(id: 'r', point: p, center: c);
      expect(
        p.position.lerp(r.position!, 0.5).closeTo(c.position, 1e-12),
        isTrue,
      );
    });

    test('double reflection is the identity', () {
      final p = FreePoint(id: 'p', position: const Vec2(3, -8));
      final c = FreePoint(id: 'c', position: const Vec2(-1, 2));
      final once = CentralReflectionPoint(id: 'r1', point: p, center: c);
      final twice = CentralReflectionPoint(id: 'r2', point: once, center: c);
      expect(twice.position, p.position);
    });

    test('a point at the center is its own image', () {
      final p = FreePoint(id: 'p', position: const Vec2(2, 2));
      final c = FreePoint(id: 'c', position: const Vec2(2, 2));
      final r = CentralReflectionPoint(id: 'r', point: p, center: c);
      expect(r.isDefined, isTrue);
      expect(r.position, const Vec2(2, 2));
    });

    test('tracks moved parents after recompute', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 0));
      final r = CentralReflectionPoint(id: 'r', point: p, center: c);
      c.position = const Vec2(3, 3);
      r.recompute();
      expect(r.position, const Vec2(5, 6));
    });

    test('undefined while a parent is, recovers after', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final onLine = PointOnObject(id: 'q', curve: line, parameter: 2);
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final r = CentralReflectionPoint(id: 'r', point: onLine, center: c);
      expect(r.isDefined, isFalse);

      b.position = const Vec2(1, 0); // line and onLine come back: (2, 0)
      line.recompute();
      onLine.recompute();
      r.recompute();
      expect(r.isDefined, isTrue);
      expect(r.position, const Vec2(0, 2));
    });
  });

  group('projective semantics (Phase 108)', () {
    test('a half-turn fixes a point at infinity, marked as such', () {
      final r = CentralReflectionPoint(
        id: 'r',
        point: StubProjectivePoint(ProjPoint.real(1, 2, 0)),
        center: FreePoint(id: 'c', position: const Vec2(3, -1)),
      );
      expect(r.isDefined, isFalse);
      expect(r.position, isNull);
      final image = r.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(image.closeTo(ProjPoint.real(1, 2, 0)), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
        'recompute is invariant under complex rescaling of a parent',
        (p, c, k) {
      CentralReflectionPoint build(ProjPoint point, ProjPoint center) =>
          CentralReflectionPoint(
            id: 'r',
            point: StubProjectivePoint(point),
            center: StubProjectivePoint(center),
          );
      final plain = build(ProjPoint.lift(p), ProjPoint.lift(c));
      final scaledPoint = build(ProjPoint.lift(p).scaledBy(k), ProjPoint.lift(c));
      final scaledCenter =
          build(ProjPoint.lift(p), ProjPoint.lift(c).scaledBy(k));
      expect(scaledPoint.projPoint!.closeTo(plain.projPoint!), isTrue);
      expect(scaledCenter.projPoint!.closeTo(plain.projPoint!), isTrue);
    });
  });
}
