import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('HarmonicConjugatePoint', () {
    test('the fourth harmonic of the quarter point on construction', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 0));
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );
      expect(d.position!.closeTo(const Vec2(-2, 0)), isTrue);
      expect(d.parents, [a, b, c]);
    });

    test('undefined while the points are not collinear, recovers after', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );
      expect(d.isDefined, isFalse);

      c.position = const Vec2(1, 0);
      d.recompute();
      expect(d.isDefined, isTrue);
      expect(d.position!.closeTo(const Vec2(-2, 0)), isTrue);
    });

    test('undefined while C is the midpoint of AB (conjugate at infinity)', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );
      expect(d.isDefined, isFalse);
    });

    test('undefined while the base pair coincides', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final c = FreePoint(id: 'c', position: const Vec2(3, 1));
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );
      expect(d.isDefined, isFalse);
    });

    test('tracks moved parents after recompute', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 0));
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );

      // Slide C outside the segment: the conjugate returns inside.
      c.position = const Vec2(-2, 0);
      d.recompute();
      expect(
        d.position!.closeTo(const Vec2(1, 0)),
        isTrue,
        reason: 'the harmonic map is an involution',
      );
    });
  });

  group('projective semantics (Phase 108)', () {
    test('C at the midpoint conjugates to the join\'s point at infinity '
        'instead of going undefined (V2 semantics change)', () {
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: FreePoint(id: 'a', position: const Vec2(1, 1)),
        point2: FreePoint(id: 'b', position: const Vec2(5, 3)),
        point3: FreePoint(id: 'c', position: const Vec2(3, 2)),
      );
      expect(d.isDefined, isFalse);
      expect(d.position, isNull);
      final image = d.projPoint!;
      expect(image.isReal(), isTrue);
      expect(image.isFinite(), isFalse);
      expect(
        image.closeTo(ProjPoint.real(4, 2, 0)),
        isTrue,
        reason: 'the direction of AB',
      );
    });

    test('still undefined with a null view while the points are not '
        'collinear or the base pair coincides', () {
      final offLine = HarmonicConjugatePoint(
        id: 'd',
        point1: FreePoint(id: 'a', position: const Vec2(0, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(4, 0)),
        point3: FreePoint(id: 'c', position: const Vec2(1, 2)),
      );
      expect(offLine.isDefined, isFalse);
      expect(offLine.projPoint, isNull);

      final coincident = HarmonicConjugatePoint(
        id: 'd',
        point1: FreePoint(id: 'a', position: const Vec2(1, 1)),
        point2: FreePoint(id: 'b', position: const Vec2(1, 1)),
        point3: FreePoint(id: 'c', position: const Vec2(1, 1)),
      );
      expect(coincident.isDefined, isFalse);
      expect(coincident.projPoint, isNull);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a parent',
      (a, b, k) {
        if (a.closeTo(b, 1e-3)) {
          return;
        }
        final pa = ProjPoint.lift(a);
        final pb = ProjPoint.lift(b);
        final pc = ProjPoint.lift(a.lerp(b, 0.25));
        HarmonicConjugatePoint build(ProjPoint x, ProjPoint y, ProjPoint z) =>
            HarmonicConjugatePoint(
              id: 'd',
              point1: StubProjectivePoint(x),
              point2: StubProjectivePoint(y),
              point3: StubProjectivePoint(z),
            );
        final plain = build(pa, pb, pc);
        expect(
          build(pa.scaledBy(k), pb, pc).projPoint!.closeTo(plain.projPoint!),
          isTrue,
        );
        expect(
          build(pa, pb.scaledBy(k), pc).projPoint!.closeTo(plain.projPoint!),
          isTrue,
        );
        expect(
          build(pa, pb, pc.scaledBy(k)).projPoint!.closeTo(plain.projPoint!),
          isTrue,
        );
      },
    );
  });
}
