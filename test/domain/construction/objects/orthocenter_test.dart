import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

void main() {
  group('Orthocenter', () {
    test('right triangle: orthocenter is the right-angle vertex', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final h = Orthocenter(id: 'h', vertex1: a, vertex2: b, vertex3: c);
      expect(h.position!.closeTo(const Vec2(0, 0)), isTrue);
      expect(h.parents, [a, b, c]);
    });

    test('equilateral triangle: orthocenter coincides with the centroid', () {
      const apex = Vec2(1, 1.7320508075688772); // (1, √3)
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final c = FreePoint(id: 'c', position: apex);
      final h = Orthocenter(id: 'h', vertex1: a, vertex2: b, vertex3: c);
      expect(h.position!.closeTo((const Vec2(2, 0) + apex) / 3, 1e-9), isTrue);
    });

    test('drag through collinearity: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final h = Orthocenter(id: 'h', vertex1: a, vertex2: b, vertex3: c);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(h);

      construction.moveFreePoint('c', const Vec2(2, 0));
      expect(h.isDefined, isFalse);

      construction.moveFreePoint('c', const Vec2(4, 3));
      expect(h.isDefined, isTrue);
      // Right angle now at b = (4, 0).
      expect(h.position!.closeTo(const Vec2(4, 0)), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('collinear vertices: at infinity perpendicular to their line, '
        'marked as such (V1: plain undefined)', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final h = Orthocenter(id: 'h', vertex1: a, vertex2: b, vertex3: c);
      expect(h.isDefined, isFalse);
      expect(h.position, isNull);
      final p = h.projPoint!;
      expect(p.isReal(), isTrue);
      expect(p.isFinite(), isFalse);
      expect(
        p.closeTo(ProjPoint.real(0, 1, 0)),
        isTrue,
        reason: 'the altitudes are all vertical: they meet straight up',
      );
    });

    test('coincident vertices: the altitudes merge — undefined outright', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(1, 2));
      final c = FreePoint(id: 'c', position: const Vec2(4, 0));
      final h = Orthocenter(id: 'h', vertex1: a, vertex2: b, vertex3: c);
      expect(h.isDefined, isFalse);
      expect(h.projPoint, isNull);
    });
  });
}
