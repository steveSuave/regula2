import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('CompassCircle', () {
    test('carries the radius-point distance to the center', () {
      final r1 = FreePoint(id: 'r1', position: const Vec2(0, 0));
      final r2 = FreePoint(id: 'r2', position: const Vec2(3, 4));
      final c = FreePoint(id: 'c', position: const Vec2(10, -2));
      final k = CompassCircle(
        id: 'k',
        radiusPoint1: r1,
        radiusPoint2: r2,
        center: c,
      );
      expect(k.circle!.center, const Vec2(10, -2));
      expect(k.circle!.radius, closeTo(5, 1e-9));
      expect(k.parents, [r1, r2, c]);
    });

    test('tracks moved parents through the construction', () {
      final construction = Construction();
      final r1 = FreePoint(id: 'r1', position: const Vec2(0, 0));
      final r2 = FreePoint(id: 'r2', position: const Vec2(2, 0));
      final c = FreePoint(id: 'c', position: const Vec2(5, 5));
      final k = CompassCircle(
        id: 'k',
        radiusPoint1: r1,
        radiusPoint2: r2,
        center: c,
      );
      construction
        ..add(r1)
        ..add(r2)
        ..add(c)
        ..add(k);

      construction.moveFreePoint('r2', const Vec2(7, 0));
      expect(k.circle!.radius, closeTo(7, 1e-9));

      construction.moveFreePoint('c', Vec2.zero);
      expect(k.circle!.center, Vec2.zero);
    });

    test(
      'coincident radius points give a zero-radius circle, not undefined',
      () {
        final r1 = FreePoint(id: 'r1', position: const Vec2(1, 1));
        final r2 = FreePoint(id: 'r2', position: const Vec2(1, 1));
        final c = FreePoint(id: 'c', position: const Vec2(4, 4));
        final k = CompassCircle(
          id: 'k',
          radiusPoint1: r1,
          radiusPoint2: r2,
          center: c,
        );
        expect(k.isDefined, isTrue);
        expect(k.circle!.radius, 0);
      },
    );
  });

  group('projective semantics (Phase 109)', () {
    Glados3(any.nonZeroComplex, any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of parents',
      (s1, s2, s3) {
        final r1 = StubProjectivePoint(ProjPoint.real(0, 0), id: 'r1');
        final r2 = StubProjectivePoint(ProjPoint.real(3, 4), id: 'r2');
        final c = StubProjectivePoint(ProjPoint.real(10, -4), id: 'c');
        final k = CompassCircle(
          id: 'k',
          radiusPoint1: r1,
          radiusPoint2: r2,
          center: c,
        );
        final reference = k.conic!;
        r1.value = r1.value!.scaledBy(s1);
        r2.value = r2.value!.scaledBy(s2);
        c.value = c.value!.scaledBy(s3);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        expect(
          k.circle!.closeTo(CircleEq(const Vec2(10, -4), 5), 1e-9),
          isTrue,
        );
      },
    );

    test('a radius point at infinity carries the double line at infinity '
        '(V2)', () {
      final k = CompassCircle(
        id: 'k',
        radiusPoint1: StubProjectivePoint(
          const ProjPoint(Complex.one, Complex.zero, Complex.zero),
          id: 'r1',
        ),
        radiusPoint2: StubProjectivePoint(ProjPoint.real(1, 1), id: 'r2'),
        center: StubProjectivePoint(ProjPoint.real(0, 0), id: 'c'),
      );
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);
      expect(
        k.conic!.closeTo(
          ConicMatrix.linePair(ProjLine.infinity, ProjLine.infinity),
        ),
        isTrue,
      );
    });
  });
}
