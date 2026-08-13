import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('CircleCenterPoint', () {
    test('circle is centered on the first parent through the second', () {
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final p = FreePoint(id: 'p', position: const Vec2(4, 5));
      final circle = CircleCenterPoint(id: 'k', center: c, onCircle: p);
      expect(circle.circle!.center, const Vec2(1, 1));
      expect(circle.circle!.radius, 5);
    });

    test('coincident parents give a defined zero-radius circle', () {
      final c = FreePoint(id: 'c', position: const Vec2(2, 3));
      final p = FreePoint(id: 'p', position: const Vec2(2, 3));
      final circle = CircleCenterPoint(id: 'k', center: c, onCircle: p);
      expect(circle.isDefined, isTrue);
      expect(circle.circle!.radius, 0);
    });

    test('a full circle offers the whole turn: no angular extent, '
        'clampAngle passes through', () {
      final c = FreePoint(id: 'c', position: Vec2.zero);
      final p = FreePoint(id: 'p', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'k', center: c, onCircle: p);
      expect(circle.angularExtent, isNull);
      expect(circle.clampAngle(5.87), 5.87);
    });

    test('radius tracks a dragged perimeter point', () {
      final c = FreePoint(id: 'c', position: Vec2.zero);
      final p = FreePoint(id: 'p', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'k', center: c, onCircle: p);
      p.position = const Vec2(0, 7);
      circle.recompute();
      expect(circle.circle!.radius, 7);
    });
  });

  group('projective semantics (Phase 109)', () {
    Glados2(any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of parents',
      (s1, s2) {
        final c = StubProjectivePoint(ProjPoint.real(2, 1), id: 'c');
        final p = StubProjectivePoint(ProjPoint.real(7, 1), id: 'p');
        final k = CircleCenterPoint(id: 'k', center: c, onCircle: p);
        final reference = k.conic!;
        c.value = c.value!.scaledBy(s1);
        p.value = p.value!.scaledBy(s2);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
        expect(k.circle!.center.closeTo(const Vec2(2, 1), 1e-9), isTrue);
        expect(k.circle!.radius, closeTo(5, 1e-9));
      },
    );

    test('a rim at infinity carries the double line at infinity (V2)', () {
      final k = CircleCenterPoint(
        id: 'k',
        center: StubProjectivePoint(ProjPoint.real(0, 0), id: 'c'),
        onCircle: StubProjectivePoint(
          const ProjPoint(Complex.one, Complex(2), Complex.zero),
          id: 'p',
        ),
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
