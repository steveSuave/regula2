import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('ThreePointCircle', () {
    test(
      'right triangle: circumcircle centered on the hypotenuse midpoint',
      () {
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(4, 0));
        final c = FreePoint(id: 'c', position: const Vec2(0, 3));
        final k = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
        expect(k.circle!.center.closeTo(const Vec2(2, 1.5)), isTrue);
        expect(k.circle!.radius, closeTo(2.5, 1e-9));
        expect(k.parents, [a, b, c]);
      },
    );

    test('passes through all three points', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 7));
      final k = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      final circle = k.circle!;
      for (final p in [a, b, c]) {
        expect(
          circle.center.distanceTo(p.position),
          closeTo(circle.radius, 1e-9),
        );
      }
    });

    test('drag through collinearity: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final k = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
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
      expect(k.circle!.center.closeTo(const Vec2(2, 1.5)), isTrue);
    });

    test('coincident points are collinear, so undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final c = FreePoint(id: 'c', position: const Vec2(4, 5));
      final k = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      expect(k.isDefined, isFalse);
    });
  });

  group('projective semantics (Phase 109)', () {
    Glados3(any.vec2, any.vec2, any.vec2).test(
      'the conic passes through I, J and the three parents',
      (p, q, r) {
        if (p.closeTo(q, 1e-3) || q.closeTo(r, 1e-3) || p.closeTo(r, 1e-3)) {
          return;
        }
        final k = ThreePointCircle(
          id: 'k',
          point1: FreePoint(id: 'a', position: p),
          point2: FreePoint(id: 'b', position: q),
          point3: FreePoint(id: 'c', position: r),
        );
        final conic = k.conic!;
        expect(conic.evaluate(circularPointI), Complex.zero);
        expect(conic.evaluate(circularPointJ), Complex.zero);
        for (final v in [p, q, r]) {
          expect(conic.containsPoint(ProjPoint.lift(v)), isTrue);
        }
      },
    );

    Glados3(any.nonZeroComplex, any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of parents',
      (s1, s2, s3) {
        final a = StubProjectivePoint(ProjPoint.real(0, 0), id: 'a');
        final b = StubProjectivePoint(ProjPoint.real(4, 0), id: 'b');
        final c = StubProjectivePoint(ProjPoint.real(0, 3), id: 'c');
        final k = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
        final reference = k.conic!;
        a.value = a.value!.scaledBy(s1);
        b.value = b.value!.scaledBy(s2);
        c.value = c.value!.scaledBy(s3);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        expect(k.circle!.center.closeTo(const Vec2(2, 1.5), 1e-9), isTrue);
      },
    );

    test('collinear points carry the degenerate line-conic (V2)', () {
      final k = ThreePointCircle(
        id: 'k',
        point1: FreePoint(id: 'a', position: const Vec2(0, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(2, 1)),
        point3: FreePoint(id: 'c', position: const Vec2(6, 3)),
      );
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);
      final expected = ConicMatrix.linePair(
        ProjLine.lift(LineEq.throughPoints(Vec2.zero, const Vec2(6, 3))),
        ProjLine.infinity,
      );
      expect(k.conic!.closeTo(expected), isTrue);
    });

    test('a parent at infinity degenerates to (finite join, ℓ∞)', () {
      final k = ThreePointCircle(
        id: 'k',
        point1: StubProjectivePoint(ProjPoint.real(0, 0), id: 'a'),
        point2: StubProjectivePoint(ProjPoint.real(4, 0), id: 'b'),
        point3: StubProjectivePoint(
          const ProjPoint(Complex.zero, Complex.one, Complex.zero),
          id: 'c',
        ),
      );
      expect(k.isDefined, isFalse);
      final expected = ConicMatrix.linePair(
        ProjLine.lift(LineEq.throughPoints(Vec2.zero, const Vec2(4, 0))),
        ProjLine.infinity,
      );
      expect(k.conic!.closeTo(expected), isTrue);
    });
  });
}
