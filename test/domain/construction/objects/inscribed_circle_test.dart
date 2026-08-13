import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';

void main() {
  group('InscribedCircle', () {
    test('3-4-5 right triangle: center (1, 1), radius 1', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final k = InscribedCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      expect(k.circle!.center.closeTo(const Vec2(1, 1)), isTrue);
      expect(k.circle!.radius, closeTo(1, 1e-9));
      expect(k.parents, [a, b, c]);
    });

    test('tangent to all three sides from the inside', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 7));
      final k = InscribedCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      final circle = k.circle!;
      final sides = [
        LineEq.throughPoints(a.position, b.position),
        LineEq.throughPoints(b.position, c.position),
        LineEq.throughPoints(c.position, a.position),
      ];
      for (final side in sides) {
        expect(side.distanceTo(circle.center), closeTo(circle.radius, 1e-9));
      }
    });

    test('drag through collinearity: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final k = InscribedCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(k);

      construction.moveFreePoint('c', const Vec2(2, 0));
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);

      construction.moveFreePoint('c', const Vec2(0, 3));
      expect(k.isDefined, isTrue);
      expect(k.circle!.center.closeTo(const Vec2(1, 1)), isTrue);
    });

    test('coincident points are collinear, so undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final c = FreePoint(id: 'c', position: const Vec2(4, 5));
      final k = InscribedCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      expect(k.isDefined, isFalse);
    });
  });

  group('projective semantics (Phase 109)', () {
    test('recompute is invariant under complex rescaling of vertices', () {
      final a = StubProjectivePoint(ProjPoint.real(0, 0), id: 'a');
      final b = StubProjectivePoint(ProjPoint.real(4, 0), id: 'b');
      final c = StubProjectivePoint(ProjPoint.real(0, 3), id: 'c');
      final k = InscribedCircle(id: 'k', vertex1: a, vertex2: b, vertex3: c);
      final reference = k.conic!;
      for (final s in [
        const Complex(2),
        const Complex(0, 1),
        const Complex(-0.5, 3),
      ]) {
        a.value = ProjPoint.real(0, 0).scaledBy(s);
        b.value = ProjPoint.real(4, 0).scaledBy(s);
        c.value = ProjPoint.real(0, 3).scaledBy(s);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        // 3-4-5 triangle: incenter (1, 1), inradius 1.
        expect(k.circle!.center.closeTo(const Vec2(1, 1), 1e-9), isTrue);
        expect(k.circle!.radius, closeTo(1, 1e-9));
      }
    });

    test('rides along on the affine formula: a vertex at infinity is fully '
        'undefined (no degenerate conic)', () {
      final k = InscribedCircle(
        id: 'k',
        vertex1: StubProjectivePoint(ProjPoint.real(0, 0), id: 'a'),
        vertex2: StubProjectivePoint(ProjPoint.real(4, 0), id: 'b'),
        vertex3: StubProjectivePoint(
          const ProjPoint(Complex.zero, Complex.one, Complex.zero),
          id: 'c',
        ),
      );
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });
  });
}
