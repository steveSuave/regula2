import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';

void main() {
  group('FreePoint', () {
    test('is a defined root with no parents', () {
      final p = FreePoint(id: 'p1', position: const Vec2(1, 2));
      expect(p.parents, isEmpty);
      expect(p.isDefined, isTrue);
      expect(p.position, const Vec2(1, 2));
    });

    test('position is mutable and recompute is a no-op', () {
      final p = FreePoint(id: 'p1', position: Vec2.zero);
      p.position = const Vec2(3, 4);
      p.recompute();
      expect(p.position, const Vec2(3, 4));
    });
  });

  group('projective view (Phase 107)', () {
    test('stores the exact lift and projects back exactly at any magnitude',
        () {
      final p = FreePoint(id: 'p', position: const Vec2(1e12, -3e12));
      expect(p.projPoint.x, const Complex(1e12));
      expect(p.projPoint.y, const Complex(-3e12));
      expect(p.projPoint.w, Complex.one);
      // Beyond 1/projectiveEpsilon the tolerance-based chart projection
      // would call this "at infinity"; a free point's stored lift has w
      // exactly 1, so the position reads back exactly regardless.
      expect(p.position, const Vec2(1e12, -3e12));
      expect(p.isDefined, isTrue);
    });

    test('the position setter re-lifts', () {
      final p = FreePoint(id: 'p', position: Vec2.zero);
      p.position = const Vec2(3, 4);
      expect(p.projPoint.closeTo(ProjPoint.real(3, 4)), isTrue);
    });
  });
}
