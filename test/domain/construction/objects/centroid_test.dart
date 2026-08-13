import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('Centroid', () {
    test('computes (a + b + c) / 3 on construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final g = Centroid(id: 'g', vertex1: a, vertex2: b, vertex3: c);
      expect(g.position!.closeTo(const Vec2(4 / 3, 1)), isTrue);
      expect(g.parents, [a, b, c]);
    });

    test('collinear and coincident vertices are not degenerate', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final c = FreePoint(id: 'c', position: const Vec2(2, 2));
      final g = Centroid(id: 'g', vertex1: a, vertex2: b, vertex3: c);
      expect(g.isDefined, isTrue);
      expect(g.position!.closeTo(const Vec2(1, 1)), isTrue);

      b.position = const Vec2(0, 0);
      c.position = const Vec2(0, 0);
      g.recompute();
      expect(g.isDefined, isTrue);
      expect(g.position!.closeTo(const Vec2(0, 0)), isTrue);
    });

    test('tracks a dragged vertex through the construction', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 6));
      final g = Centroid(id: 'g', vertex1: a, vertex2: b, vertex3: c);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(g);

      construction.moveFreePoint('c', const Vec2(3, 9));
      expect(g.position!.closeTo(const Vec2(3, 3)), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('a vertex at infinity: the centroid is that point at infinity, '
        'marked as such', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(3, 4));
      final inf = StubProjectivePoint(ProjPoint.real(1, 1, 0));
      final g = Centroid(id: 'g', vertex1: a, vertex2: b, vertex3: inf);
      expect(g.isDefined, isFalse);
      expect(g.position, isNull);
      final p = g.projPoint!;
      expect(p.isReal(), isTrue);
      expect(p.isFinite(), isFalse);
      expect(p.closeTo(ProjPoint.real(1, 1, 0)), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a vertex',
      (a, b, k) {
        const c = Vec2(-2, 3);
        final plain = Centroid(
          id: 'g1',
          vertex1: StubProjectivePoint(ProjPoint.lift(a)),
          vertex2: StubProjectivePoint(ProjPoint.lift(b)),
          vertex3: StubProjectivePoint(ProjPoint.lift(c)),
        );
        final scaled = Centroid(
          id: 'g2',
          vertex1: StubProjectivePoint(ProjPoint.lift(a).scaledBy(k)),
          vertex2: StubProjectivePoint(ProjPoint.lift(b)),
          vertex3: StubProjectivePoint(ProjPoint.lift(c)),
        );
        expect(scaled.projPoint!.closeTo(plain.projPoint!), isTrue);
        expect(scaled.position!.closeTo(plain.position!, 1e-6), isTrue);
      },
    );
  });
}
