import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';

void main() {
  group('Polygon', () {
    test('exposes its vertex positions in loop order', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(4, 3));
      final d = FreePoint(id: 'd', position: const Vec2(0, 3));
      final polygon = Polygon(id: 'p', vertices: [a, b, c, d]);
      expect(polygon.isDefined, isTrue);
      expect(polygon.polygonVertices, const [
        Vec2(0, 0),
        Vec2(4, 0),
        Vec2(4, 3),
        Vec2(0, 3),
      ]);
      expect(polygon.parents, [a, b, c, d]);
    });

    test('rejects fewer than 3 vertices', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      expect(() => Polygon(id: 'p', vertices: [a, b]), throwsArgumentError);
      expect(() => Polygon(id: 'p', vertices: []), throwsArgumentError);
    });

    test('recompute tracks a dragged vertex', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final polygon = Polygon(id: 'p', vertices: [a, b, c]);

      c.position = const Vec2(2, 5);
      polygon.recompute();
      expect(polygon.polygonVertices![2], const Vec2(2, 5));
    });

    test('undefined while any vertex is, recovers when it does', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final center = FreePoint(id: 'o', position: const Vec2(0, 3));
      final rim = FreePoint(id: 'rim', position: const Vec2(0, -1));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      // Radius 4 across the line at y = 0: the crossing exists. Shrinking
      // the radius below 3 lifts the circle off the line, the crossing —
      // and with it the polygon — goes undefined.
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
      );
      final polygon = Polygon(id: 'p', vertices: [a, b, crossing]);
      expect(polygon.isDefined, isTrue);

      rim.position = const Vec2(0, 2);
      circle.recompute();
      crossing.recompute();
      polygon.recompute();
      expect(polygon.isDefined, isFalse);
      expect(polygon.polygonVertices, isNull);

      rim.position = const Vec2(0, -1);
      circle.recompute();
      crossing.recompute();
      polygon.recompute();
      expect(polygon.isDefined, isTrue);
    });

    test('a collinear or self-intersecting loop stays defined', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final c = FreePoint(id: 'c', position: const Vec2(4, 0));
      expect(
        Polygon(id: 'flat', vertices: [a, b, c]).isDefined,
        isTrue,
        reason: 'collinear vertices are a drawable (degenerate) outline',
      );

      final p = FreePoint(id: 'p', position: const Vec2(0, 0));
      final q = FreePoint(id: 'q', position: const Vec2(4, 0));
      final r = FreePoint(id: 'r', position: const Vec2(0, 3));
      final s = FreePoint(id: 's', position: const Vec2(4, 3));
      expect(
        Polygon(id: 'bowtie', vertices: [p, q, r, s]).isDefined,
        isTrue,
        reason: 'a self-intersecting loop still draws',
      );
    });

    test('the vertex list is fixed at construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final mutable = [a, b, c];
      final polygon = Polygon(id: 'p', vertices: mutable);

      mutable.removeLast();
      expect(polygon.vertices.length, 3, reason: 'the list is copied');
      expect(() => polygon.vertices.add(a), throwsUnsupportedError);
    });
  });

  group('projective semantics (Phase 112)', () {
    test('a vertex at infinity leaves the polygon undefined — no partial '
        'outline', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final inf = StubProjectivePoint(ProjPoint.real(1, 1, 0));
      final polygon = Polygon(id: 'p', vertices: [a, b, inf]);
      expect(polygon.isDefined, isFalse);
      expect(polygon.polygonVertices, isNull);
    });
  });
}
