import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('Midpoint', () {
    test('computes the midpoint on construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      expect(m.position, const Vec2(2, 1));
      expect(m.parents, [a, b]);
    });

    test('tracks a moved parent after recompute', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      b.position = const Vec2(0, 6);
      m.recompute();
      expect(m.position, const Vec2(0, 3));
    });

    test('coincident parents are not degenerate', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      expect(m.isDefined, isTrue);
      expect(m.position, const Vec2(1, 1));
    });
  });

  group('projective semantics (Phase 107)', () {
    test('a parent at infinity: the midpoint is that point at infinity, '
        'marked as such', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final inf = StubProjectivePoint(ProjPoint.real(3, 4, 0));
      final m = Midpoint(id: 'm', point1: a, point2: inf);
      expect(m.isDefined, isFalse);
      expect(m.position, isNull);
      final p = m.projPoint!;
      expect(p.isReal(), isTrue);
      expect(p.isFinite(), isFalse);
      expect(p.closeTo(ProjPoint.real(3, 4, 0)), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a parent',
      (p, q, k) {
        final plain = Midpoint(
          id: 'm1',
          point1: StubProjectivePoint(ProjPoint.lift(p)),
          point2: StubProjectivePoint(ProjPoint.lift(q)),
        );
        final scaled = Midpoint(
          id: 'm2',
          point1: StubProjectivePoint(ProjPoint.lift(p).scaledBy(k)),
          point2: StubProjectivePoint(ProjPoint.lift(q)),
        );
        expect(scaled.projPoint!.closeTo(plain.projPoint!), isTrue);
        expect(scaled.position!.closeTo(plain.position!, 1e-6), isTrue);
      },
    );
  });
}
