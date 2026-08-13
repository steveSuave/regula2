import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/apollonius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('ApolloniusCircle', () {
    test('ratio 2 over a 3-unit base: center (4, 0), radius 2', () {
      // C = (2, 0) has |CA| = 2, |CB| = 1 — ratio 2.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final k = ApolloniusCircle(id: 'k', point1: a, point2: b, point3: c);
      expect(k.circle!.center.closeTo(const Vec2(4, 0)), isTrue);
      expect(k.circle!.radius, closeTo(2, 1e-9));
      expect(k.parents, [a, b, c]);
    });

    test('passes through the ratio point itself', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 7));
      final k = ApolloniusCircle(id: 'k', point1: a, point2: b, point3: c);
      expect(k.circle!.distanceTo(c.position), lessThan(1e-9));
    });

    test('drag C through the perpendicular bisector: undefined, recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final k = ApolloniusCircle(id: 'k', point1: a, point2: b, point3: c);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(k);

      // Equidistant from A and B — the locus degenerates to the bisector.
      construction.moveFreePoint('c', const Vec2(1.5, 2));
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);

      construction.moveFreePoint('c', const Vec2(2, 0));
      expect(k.isDefined, isTrue);
      expect(k.circle!.center.closeTo(const Vec2(4, 0)), isTrue);
    });

    test('undefined while C coincides with A or B, or A with B', () {
      const pa = Vec2(0, 0);
      const pb = Vec2(3, 0);
      ApolloniusCircle at(Vec2 pc, [Vec2 pbOverride = pb]) => ApolloniusCircle(
        id: 'k',
        point1: FreePoint(id: 'a', position: pa),
        point2: FreePoint(id: 'b', position: pbOverride),
        point3: FreePoint(id: 'c', position: pc),
      );
      expect(at(pa).isDefined, isFalse);
      expect(at(pb).isDefined, isFalse);
      expect(at(const Vec2(2, 0), pa).isDefined, isFalse);
    });
  });

  group('projective semantics (Phase 109)', () {
    test('an equidistant ratio point carries (perpendicular bisector, ℓ∞) '
        '(V2)', () {
      final k = ApolloniusCircle(
        id: 'k',
        point1: FreePoint(id: 'a', position: const Vec2(0, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(4, 0)),
        point3: FreePoint(id: 'c', position: const Vec2(2, 3)),
      );
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);
      expect(
        k.conic!.closeTo(
          ConicMatrix.linePair(ProjLine.real(1, 0, -2), ProjLine.infinity),
        ),
        isTrue,
      );
    });

    Glados3(any.nonZeroComplex, any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of parents',
      (s1, s2, s3) {
        final a = StubProjectivePoint(ProjPoint.real(0, 0), id: 'a');
        final b = StubProjectivePoint(ProjPoint.real(3, 0), id: 'b');
        final c = StubProjectivePoint(ProjPoint.real(2, 0), id: 'c');
        final k = ApolloniusCircle(id: 'k', point1: a, point2: b, point3: c);
        final reference = k.conic!;
        a.value = a.value!.scaledBy(s1);
        b.value = b.value!.scaledBy(s2);
        c.value = c.value!.scaledBy(s3);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        expect(k.circle!.center.closeTo(const Vec2(4, 0), 1e-9), isTrue);
        expect(k.circle!.radius, closeTo(2, 1e-9));
      },
    );
  });
}
