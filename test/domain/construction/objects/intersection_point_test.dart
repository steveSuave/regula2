import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  FreePoint fp(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  LineThroughTwoPoints lineThrough(String id, GeoPointPair pair) =>
      LineThroughTwoPoints(id: id, point1: pair.$1, point2: pair.$2);

  group('IntersectionPoint: line ∩ line', () {
    test('finds the crossing, branch 0', () {
      final l1 = lineThrough('l1', (fp('a', -1, 0), fp('b', 1, 0)));
      final l2 = lineThrough('l2', (fp('c', 0, -1), fp('d', 0, 1)));
      final x = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );
      expect(x.position!.closeTo(Vec2.zero), isTrue);
    });

    test('undefined for parallel lines, recovers when they tilt', () {
      final a = fp('a', 0, 0);
      final b = fp('b', 4, 0);
      final l1 = lineThrough('l1', (a, b));
      final l2 = lineThrough('l2', (fp('c', 0, 1), fp('d', 4, 1)));
      final x = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );
      expect(x.isDefined, isFalse);

      b.position = const Vec2(4, 2); // tilt l1 so they cross
      l1.recompute();
      x.recompute();
      expect(x.isDefined, isTrue);
      expect(x.position!.closeTo(const Vec2(2, 1)), isTrue);
    });
  });

  group('IntersectionPoint: line ∩ circle', () {
    test('branches are ordered along the line direction, both orders', () {
      // Horizontal line left→right through a unit circle at the origin.
      final l = lineThrough('l', (fp('a', -2, 0), fp('b', 2, 0)));
      final k = CircleCenterPoint(
        id: 'k',
        center: fp('c', 0, 0),
        onCircle: fp('p', 1, 0),
      );
      final first = IntersectionPoint(
        id: 'x0',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      // Curve order swapped: branch meaning must not change, because the
      // line's role is fixed by type, not argument position.
      final second = IntersectionPoint(
        id: 'x1',
        curve1: k,
        curve2: l,
        branchIndex: 1,
      );
      expect(first.position!.closeTo(const Vec2(-1, 0)), isTrue);
      expect(second.position!.closeTo(const Vec2(1, 0)), isTrue);
    });

    test('both branches clamp to the single point at tangency', () {
      final l = lineThrough('l', (fp('a', -2, 1), fp('b', 2, 1)));
      final k = CircleCenterPoint(
        id: 'k',
        center: fp('c', 0, 0),
        onCircle: fp('p', 1, 0),
      );
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: l,
        curve2: k,
        branchIndex: 1,
      );
      expect(x0.position!.closeTo(const Vec2(0, 1)), isTrue);
      expect(x1.position!.closeTo(const Vec2(0, 1)), isTrue);
    });

    test('survives a drag through no-intersection and back', () {
      final a = fp('a', -2, 0);
      final b = fp('b', 2, 0);
      final l = lineThrough('l', (a, b));
      final k = CircleCenterPoint(
        id: 'k',
        center: fp('c', 0, 0),
        onCircle: fp('p', 1, 0),
      );
      final x = IntersectionPoint(
        id: 'x',
        curve1: l,
        curve2: k,
        branchIndex: 1,
      );
      expect(x.position!.closeTo(const Vec2(1, 0)), isTrue);

      // Drag the line far above the circle: no intersection.
      a.position = const Vec2(-2, 5);
      b.position = const Vec2(2, 5);
      l.recompute();
      x.recompute();
      expect(x.isDefined, isFalse);

      // Drag back: same branch reappears.
      a.position = const Vec2(-2, 0);
      b.position = const Vec2(2, 0);
      l.recompute();
      x.recompute();
      expect(x.position!.closeTo(const Vec2(1, 0)), isTrue);
    });
  });

  group('IntersectionPoint: circle ∩ circle', () {
    test('branch 0 is left of the directed center line', () {
      // Unit circles at (0,0) and (1,0): intersections at (0.5, ±√3/2).
      // Left of the +x directed center line is +y.
      final k1 = CircleCenterPoint(
        id: 'k1',
        center: fp('c1', 0, 0),
        onCircle: fp('p1', 1, 0),
      );
      final k2 = CircleCenterPoint(
        id: 'k2',
        center: fp('c2', 1, 0),
        onCircle: fp('p2', 2, 0),
      );
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: k1,
        curve2: k2,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: k1,
        curve2: k2,
        branchIndex: 1,
      );
      const root3over2 = 0.8660254037844386;
      expect(x0.position!.closeTo(const Vec2(0.5, root3over2), 1e-9), isTrue);
      expect(x1.position!.closeTo(const Vec2(0.5, -root3over2), 1e-9), isTrue);
    });
  });

  group('IntersectionPoint: construction errors', () {
    test('rejects point parents, self-intersection, bad branch index', () {
      final l = lineThrough('l', (fp('a', 0, 0), fp('b', 1, 0)));
      final l2 = lineThrough('l2', (fp('c', 0, 1), fp('d', 1, 2)));
      final p = fp('p', 0, 0);
      expect(
        () => IntersectionPoint(id: 'x', curve1: l, curve2: p, branchIndex: 0),
        throwsArgumentError,
      );
      expect(
        () => IntersectionPoint(id: 'x', curve1: l, curve2: l, branchIndex: 0),
        throwsArgumentError,
      );
      expect(
        () => IntersectionPoint(id: 'x', curve1: l, curve2: l2, branchIndex: 2),
        throwsArgumentError,
      );
    });
  });
}

typedef GeoPointPair = (FreePoint, FreePoint);
