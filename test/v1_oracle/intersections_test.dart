import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

import '../domain/math/generators.dart';
import 'intersections.dart';

void main() {
  final xAxis = LineEq.throughPoints(Vec2.zero, const Vec2(1, 0));
  final yAxis = LineEq.throughPoints(Vec2.zero, const Vec2(0, 1));
  final unitCircle = CircleEq(Vec2.zero, 1);

  group('line ∩ line unit tests', () {
    test('axes cross at the origin', () {
      final pts = intersectLineLine(xAxis, yAxis);
      expect(pts, hasLength(1));
      expect(pts.single.closeTo(Vec2.zero, 1e-12), isTrue);
    });

    test('oblique crossing at a known point', () {
      final l1 = LineEq.throughPoints(Vec2.zero, const Vec2(1, 1));
      final l2 = LineEq.throughPoints(const Vec2(0, 2), const Vec2(2, 0));
      final pts = intersectLineLine(l1, l2);
      expect(pts, hasLength(1));
      expect(pts.single.closeTo(const Vec2(1, 1), 1e-12), isTrue);
    });

    test('parallel lines do not intersect', () {
      final l1 = LineEq.throughPoints(Vec2.zero, const Vec2(1, 0));
      final l2 = LineEq.throughPoints(const Vec2(0, 1), const Vec2(1, 1));
      expect(intersectLineLine(l1, l2), isEmpty);
    });

    test('coincident lines return empty (infinitely many points)', () {
      final l1 = LineEq.throughPoints(Vec2.zero, const Vec2(1, 1));
      final l2 = LineEq.throughPoints(const Vec2(2, 2), const Vec2(3, 3));
      expect(intersectLineLine(l1, l2), isEmpty);
    });
  });

  group('line ∩ circle unit tests', () {
    test('secant: ordered along the line direction', () {
      final pts = intersectLineCircle(xAxis, unitCircle);
      expect(pts, hasLength(2));
      expect(pts[0].closeTo(const Vec2(-1, 0), 1e-12), isTrue);
      expect(pts[1].closeTo(const Vec2(1, 0), 1e-12), isTrue);
    });

    test('tangent line touches at one point', () {
      final tangent = LineEq.throughPoints(const Vec2(0, 1), const Vec2(1, 1));
      final pts = intersectLineCircle(tangent, unitCircle);
      expect(pts, hasLength(1));
      expect(pts.single.closeTo(const Vec2(0, 1), 1e-12), isTrue);
    });

    test('near-tangent line within epsilon counts as tangent', () {
      final nearTangent = LineEq.throughPoints(
        const Vec2(0, 1 + 1e-12),
        const Vec2(1, 1 + 1e-12),
      );
      expect(intersectLineCircle(nearTangent, unitCircle), hasLength(1));
    });

    test('distant line misses', () {
      final miss = LineEq.throughPoints(const Vec2(0, 2), const Vec2(1, 2));
      expect(intersectLineCircle(miss, unitCircle), isEmpty);
    });

    test('point-circle on the line intersects at the center', () {
      final point = CircleEq(const Vec2(3, 0), 0);
      final pts = intersectLineCircle(xAxis, point);
      expect(pts, hasLength(1));
      expect(pts.single.closeTo(const Vec2(3, 0), 1e-12), isTrue);
    });
  });

  group('circle ∩ circle unit tests', () {
    test('two-point case: first point left of the directed center line', () {
      final other = CircleEq(const Vec2(1, 0), 1);
      final pts = intersectCircleCircle(unitCircle, other);
      expect(pts, hasLength(2));
      final h = math.sqrt(3) / 2;
      expect(pts[0].closeTo(Vec2(0.5, h), 1e-12), isTrue);
      expect(pts[1].closeTo(Vec2(0.5, -h), 1e-12), isTrue);
    });

    test('external tangency', () {
      final other = CircleEq(const Vec2(3, 0), 2);
      final pts = intersectCircleCircle(unitCircle, other);
      expect(pts, hasLength(1));
      expect(pts.single.closeTo(const Vec2(1, 0), 1e-12), isTrue);
    });

    test('internal tangency', () {
      final outer = CircleEq(Vec2.zero, 3);
      final inner = CircleEq(const Vec2(1, 0), 2);
      final pts = intersectCircleCircle(outer, inner);
      expect(pts, hasLength(1));
      expect(pts.single.closeTo(const Vec2(3, 0), 1e-12), isTrue);
    });

    test('separate circles miss', () {
      expect(
        intersectCircleCircle(unitCircle, CircleEq(const Vec2(5, 0), 1)),
        isEmpty,
      );
    });

    test('contained circle misses', () {
      expect(
        intersectCircleCircle(
          CircleEq(Vec2.zero, 5),
          CircleEq(const Vec2(1, 0), 1),
        ),
        isEmpty,
      );
    });

    test('concentric and coincident circles return empty', () {
      expect(
        intersectCircleCircle(unitCircle, CircleEq(Vec2.zero, 2)),
        isEmpty,
      );
      expect(
        intersectCircleCircle(unitCircle, CircleEq(Vec2.zero, 1)),
        isEmpty,
      );
    });
  });

  group('intersection properties', () {
    Glados2(any.lineEq, any.lineEq).test(
      'line-line intersection lies on both lines',
      (l1, l2) {
        // A coarse parallel cutoff keeps the system well-conditioned; the
        // point's accuracy degrades as the lines approach parallel.
        final pts = intersectLineLine(l1, l2, 1e-3);
        if (pts.isEmpty) return;
        expect(l1.distanceTo(pts.single), closeTo(0, 1e-6));
        expect(l2.distanceTo(pts.single), closeTo(0, 1e-6));
      },
    );

    Glados2(any.lineEq, any.circleEq).test(
      'line-circle intersections lie on both objects',
      (l, c) {
        for (final p in intersectLineCircle(l, c)) {
          expect(l.distanceTo(p), closeTo(0, 1e-6));
          expect(c.distanceTo(p), closeTo(0, 1e-6));
        }
      },
    );

    Glados2(any.circleEq, any.vec2).test(
      'line through the center cuts a full diameter',
      (c, dir) {
        if (dir == Vec2.zero) return;
        final l = LineEq.pointDirection(c.center, dir);
        final pts = intersectLineCircle(l, c);
        expect(pts, hasLength(2));
        expect(pts[0].distanceTo(pts[1]), closeTo(2 * c.radius, 1e-6));
      },
    );

    Glados2(any.circleEq, any.circleEq).test(
      'circle-circle intersections lie on both circles',
      (c1, c2) {
        for (final p in intersectCircleCircle(c1, c2)) {
          expect(c1.distanceTo(p), closeTo(0, 1e-6));
          expect(c2.distanceTo(p), closeTo(0, 1e-6));
        }
      },
    );

    Glados2(any.circleEq, any.circleEq).test(
      'argument order does not change the intersection set',
      (c1, c2) {
        final ab = intersectCircleCircle(c1, c2);
        final ba = intersectCircleCircle(c2, c1);
        expect(ab.length, ba.length);
        for (final p in ab) {
          expect(ba.any((q) => q.closeTo(p, 1e-6)), isTrue);
        }
      },
    );
  });
}
