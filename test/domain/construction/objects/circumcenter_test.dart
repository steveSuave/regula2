import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('Circumcenter', () {
    test('right triangle: circumcenter is the hypotenuse midpoint', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      expect(o.position!.closeTo(const Vec2(2, 1.5)), isTrue);
      expect(o.parents, [a, b, c]);
    });

    test('is equidistant from all three vertices', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 7));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      final p = o.position!;
      final r = p.distanceTo(a.position);
      expect(p.distanceTo(b.position), closeTo(r, 1e-9));
      expect(p.distanceTo(c.position), closeTo(r, 1e-9));
    });

    test('drag through collinearity: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(o);

      construction.moveFreePoint('c', const Vec2(2, 0));
      expect(o.isDefined, isFalse);
      expect(o.position, isNull);

      construction.moveFreePoint('c', const Vec2(0, 3));
      expect(o.isDefined, isTrue);
      expect(o.position!.closeTo(const Vec2(2, 1.5)), isTrue);
    });

    test('dependents chained on an undefined circumcenter go undefined too',
        () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      final m = Midpoint(id: 'm', point1: a, point2: o);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(o)
        ..add(m);

      expect(m.position!.closeTo(const Vec2(1, 0.75)), isTrue);

      construction.moveFreePoint('c', const Vec2(2, 0));
      expect(m.isDefined, isFalse);

      construction.moveFreePoint('c', const Vec2(0, 3));
      expect(m.position!.closeTo(const Vec2(1, 0.75)), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('collinear vertices: at infinity perpendicular to their line, '
        'marked as such (V1: plain undefined)', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      expect(o.isDefined, isFalse);
      expect(o.position, isNull);
      final p = o.projPoint!;
      expect(p.isReal(), isTrue);
      expect(p.isFinite(), isFalse);
      expect(p.closeTo(ProjPoint.real(0, 1, 0)), isTrue,
          reason: 'perpendicular to the x-axis the vertices share');
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
        'recompute is invariant under complex rescaling of a vertex',
        (a, b, k) {
      const c = Vec2(-2, 3);
      if (isCollinear(a, b, c, 1e-3) ||
          a.closeTo(b, 1e-3) ||
          a.closeTo(c, 1e-3) ||
          b.closeTo(c, 1e-3)) {
        return;
      }
      final plain = Circumcenter(
        id: 'o1',
        vertex1: StubProjectivePoint(ProjPoint.lift(a)),
        vertex2: StubProjectivePoint(ProjPoint.lift(b)),
        vertex3: StubProjectivePoint(ProjPoint.lift(c)),
      );
      final scaled = Circumcenter(
        id: 'o2',
        vertex1: StubProjectivePoint(ProjPoint.lift(a).scaledBy(k)),
        vertex2: StubProjectivePoint(ProjPoint.lift(b)),
        vertex3: StubProjectivePoint(ProjPoint.lift(c)),
      );
      expect(scaled.projPoint!.closeTo(plain.projPoint!, 1e-6), isTrue);
    });
  });
}
