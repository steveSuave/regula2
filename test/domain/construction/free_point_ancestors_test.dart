import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/free_point_ancestors.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  Set<String> idsOf(Iterable<FreePoint> points) => {
    for (final point in points) point.id,
  };

  group('freePointAncestors', () {
    test('a free point is its own singleton ancestor set', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      expect(idsOf(freePointAncestors(a)), {'a'});
    });

    test('first-level derived object collects its parents', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      expect(idsOf(freePointAncestors(m)), {'a', 'b'});
    });

    test('deep chains reach the roots; diamonds count shared roots once', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 3));
      // Diamond: both lines share a; the intersection sees a once.
      final l1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: a, point2: c);
      final x = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );

      expect(idsOf(freePointAncestors(x)), {'a', 'b', 'c'});
    });

    test('a segment over a derived point digs through it', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 2));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final s = Segment(id: 's', point1: m, point2: c);

      expect(idsOf(freePointAncestors(s)), {'a', 'b', 'c'});
    });
  });
}
