import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
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
  group('DiameterCircle', () {
    test('centered on the midpoint, radius half the endpoint distance', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 8));
      final circle = DiameterCircle(id: 'k', point1: a, point2: b);
      expect(circle.circle!.center, const Vec2(3, 4));
      expect(circle.circle!.radius, 5);
      expect(circle.parents, [a, b]);
    });

    test('passes through both endpoints (they span a diameter)', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 7));
      final circle = DiameterCircle(id: 'k', point1: a, point2: b);
      expect(circle.circle!.distanceTo(a.position), lessThan(1e-9));
      expect(circle.circle!.distanceTo(b.position), lessThan(1e-9));
    });

    test('coincident endpoints give a defined zero-radius circle', () {
      final a = FreePoint(id: 'a', position: const Vec2(2, 3));
      final b = FreePoint(id: 'b', position: const Vec2(2, 3));
      final circle = DiameterCircle(id: 'k', point1: a, point2: b);
      expect(circle.isDefined, isTrue);
      expect(circle.circle!.radius, 0);
    });

    test('tracks a dragged endpoint', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final circle = DiameterCircle(id: 'k', point1: a, point2: b);
      b.position = const Vec2(0, 10);
      circle.recompute();
      expect(circle.circle!.center, const Vec2(0, 5));
      expect(circle.circle!.radius, 5);
    });
  });

  group('projective semantics (Phase 109)', () {
    Glados2(any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of parents',
      (s1, s2) {
        final a = StubProjectivePoint(ProjPoint.real(0, 0), id: 'a');
        final b = StubProjectivePoint(ProjPoint.real(6, 8), id: 'b');
        final k = DiameterCircle(id: 'k', point1: a, point2: b);
        final reference = k.conic!;
        a.value = a.value!.scaledBy(s1);
        b.value = b.value!.scaledBy(s2);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        expect(k.circle!.closeTo(CircleEq(const Vec2(3, 4), 5), 1e-9), isTrue);
      },
    );

    test('an endpoint at infinity carries the Thales limit line pair (V2)', () {
      final k = DiameterCircle(
        id: 'k',
        point1: StubProjectivePoint(ProjPoint.real(1, 2), id: 'a'),
        point2: StubProjectivePoint(
          const ProjPoint(Complex(3), Complex(4), Complex.zero),
          id: 'b',
        ),
      );
      expect(k.isDefined, isFalse);
      // Perpendicular to direction (3, 4) through (1, 2), with ℓ∞.
      expect(
        k.conic!.closeTo(
          ConicMatrix.linePair(ProjLine.real(3, 4, -11), ProjLine.infinity),
        ),
        isTrue,
      );
    });
  });
}
