import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('LineThroughTwoPoints', () {
    test('line contains both defining points', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 4));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expect(l.isDefined, isTrue);
      expect(l.line!.contains(a.position), isTrue);
      expect(l.line!.contains(b.position), isTrue);
    });

    test('an infinite line offers the whole carrier: no parameter extent, '
        'clampParameter passes through', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 4));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expect(l.parameterExtent, isNull);
      expect(l.clampParameter(-1234.5), -1234.5);
    });

    test('undefined while points coincide, recovers when they separate', () {
      final a = FreePoint(id: 'a', position: const Vec2(2, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 2));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expect(l.isDefined, isTrue);

      b.position = const Vec2(2, 2); // drag onto a: degenerate
      l.recompute();
      expect(l.isDefined, isFalse);
      expect(l.line, isNull);

      b.position = const Vec2(2, 7); // drag away: defined again
      l.recompute();
      expect(l.isDefined, isTrue);
      expect(l.line!.contains(const Vec2(2, 5)), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('a parent at infinity: the real line through the finite parent '
        'in that direction (V1: undefined)', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final inf = StubProjectivePoint(ProjPoint.real(3, 4, 0));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: inf);
      expect(l.isDefined, isTrue);
      expect(l.line!.contains(const Vec2(1, 2)), isTrue);
      expect(l.line!.contains(const Vec2(4, 6)), isTrue,
          reason: 'runs in the direction (3, 4)');
    });

    test('projectively coincident parents at different complex scales: '
        'undefined', () {
      final a = StubProjectivePoint(ProjPoint.real(1, 2));
      final b = StubProjectivePoint(
        ProjPoint.real(1, 2).scaledBy(const Complex(0, 3)),
      );
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expect(l.isDefined, isFalse);
      expect(l.projLine, isNull);
    });

    test('the affine view is the oriented projection of the carrier', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(2, 1));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expect(ProjLine.lift(l.line!).closeTo(l.projLine!), isTrue);
      expect(l.line!.direction.dot(const Vec2(2, 1)), greaterThan(0),
          reason: 'V1 orientation runs point1 → point2');
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
        'recompute is invariant under complex rescaling of a parent',
        (p, q, k) {
      if (p.closeTo(q, 1e-3)) {
        return;
      }
      final plain = LineThroughTwoPoints(
        id: 'l1',
        point1: StubProjectivePoint(ProjPoint.lift(p)),
        point2: StubProjectivePoint(ProjPoint.lift(q)),
      );
      final scaled = LineThroughTwoPoints(
        id: 'l2',
        point1: StubProjectivePoint(ProjPoint.lift(p).scaledBy(k)),
        point2: StubProjectivePoint(ProjPoint.lift(q)),
      );
      expect(scaled.projLine!.closeTo(plain.projLine!), isTrue);
      expect(scaled.line!.closeTo(plain.line!), isTrue);
    });
  });
}
