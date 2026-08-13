import 'package:glados/glados.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('LineEq unit tests', () {
    test('normalizes raw coefficients to a unit normal', () {
      final l = LineEq(3, 4, 10);
      expect(l.a, closeTo(0.6, 1e-12));
      expect(l.b, closeTo(0.8, 1e-12));
      expect(l.c, closeTo(2, 1e-12));
      expect(l.normal.norm, closeTo(1, 1e-12));
    });

    test('throws when a and b are both zero', () {
      expect(() => LineEq(0, 0, 1), throwsArgumentError);
    });

    test('throughPoints throws on coincident points', () {
      expect(
        () => LineEq.throughPoints(const Vec2(1, 1), const Vec2(1, 1)),
        throwsArgumentError,
      );
    });

    test('pointDirection throws on a zero direction', () {
      expect(
        () => LineEq.pointDirection(const Vec2(1, 1), Vec2.zero),
        throwsArgumentError,
      );
    });

    test('horizontal line', () {
      final h = LineEq.throughPoints(const Vec2(0, 2), const Vec2(5, 2));
      expect(h.contains(const Vec2(-3, 2)), isTrue);
      expect(h.distanceTo(const Vec2(0, 5)), closeTo(3, 1e-12));
    });

    test('vertical line', () {
      final v = LineEq.throughPoints(const Vec2(1, 0), const Vec2(1, 7));
      expect(v.contains(const Vec2(1, -4)), isTrue);
      expect(v.distanceTo(const Vec2(4, 0)), closeTo(3, 1e-12));
    });

    test('signed distance flips sign across the line', () {
      final l = LineEq.throughPoints(Vec2.zero, const Vec2(1, 0));
      final above = l.signedDistanceTo(const Vec2(0, 3));
      final below = l.signedDistanceTo(const Vec2(0, -3));
      expect(above.abs(), closeTo(3, 1e-12));
      expect(below.abs(), closeTo(3, 1e-12));
      expect(above.sign, -below.sign);
    });

    test('direction is perpendicular to normal', () {
      final l = LineEq(3, 4, 10);
      expect(l.normal.dot(l.direction), 0);
    });

    test('reflect mirrors across the line', () {
      final l = LineEq(0, 1, -2); // y = 2
      expect(l.reflect(const Vec2(3, 5)).closeTo(const Vec2(3, -1)), isTrue);
      // A point on the line is its own image.
      expect(l.reflect(const Vec2(7, 2)).closeTo(const Vec2(7, 2)), isTrue);
    });

    test('isCollinear on known cases', () {
      expect(
        isCollinear(Vec2.zero, const Vec2(1, 1), const Vec2(2, 2)),
        isTrue,
      );
      expect(
        isCollinear(Vec2.zero, const Vec2(1, 0), const Vec2(0, 1)),
        isFalse,
      );
      // Degenerate: two coincident points are always collinear with anything.
      expect(isCollinear(Vec2.zero, Vec2.zero, const Vec2(3, 7)), isTrue);
    });
  });

  group('LineEq properties', () {
    Glados2(any.vec2, any.vec2).test('line through two points contains both', (
      p,
      q,
    ) {
      if (p == q) return;
      final l = LineEq.throughPoints(p, q);
      expect(l.distanceTo(p), closeTo(0, 1e-9));
      expect(l.distanceTo(q), closeTo(0, 1e-9));
    });

    Glados2(any.vec2, any.vec2).test(
      'point order does not change the line geometrically',
      (p, q) {
        if (p == q) return;
        final l1 = LineEq.throughPoints(p, q);
        final l2 = LineEq.throughPoints(q, p);
        expect(l1.closeTo(l2, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'projection lies on the line and realizes the distance',
      (p, q, x) {
        if (p == q) return;
        final l = LineEq.throughPoints(p, q);
        final proj = l.project(x);
        expect(l.distanceTo(proj), closeTo(0, 1e-9));
        expect(x.distanceTo(proj), closeTo(l.distanceTo(x), 1e-9));
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test('translated line is parallel', (
      p,
      q,
      offset,
    ) {
      if (p == q) return;
      final l1 = LineEq.throughPoints(p, q);
      final l2 = LineEq.throughPoints(p + offset, q + offset);
      expect(l1.isParallelTo(l2, 1e-6), isTrue);
    });

    Glados3(any.vec2, any.vec2, any.unitInterval).test(
      'points on a segment are collinear with its endpoints',
      (a, b, t) {
        expect(isCollinear(a, b, a.lerp(b, t)), isTrue);
      },
    );

    Glados2(any.vec2, any.vec2).test('pointOnLine lies on the line', (p, q) {
      if (p == q) return;
      final l = LineEq.throughPoints(p, q);
      expect(l.distanceTo(l.pointOnLine), closeTo(0, 1e-9));
    });

    test('pointAt walks the direction from the anchor', () {
      final l = LineEq(0, 1, -2); // y = 2, direction (1, 0)
      expect(l.pointAt(0).closeTo(l.pointOnLine), isTrue);
      expect(l.pointAt(3).closeTo(const Vec2(3, 2)), isTrue);
      expect(l.parameterAt(const Vec2(3, 7)), closeTo(3, 1e-12));
    });

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'pointAt(parameterAt(p)) is the projection of p',
      (p, q, r) {
        if (p == q) return;
        final l = LineEq.throughPoints(p, q);
        expect(l.pointAt(l.parameterAt(r)).closeTo(l.project(r), 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'double reflection is identity',
      (p, q, x) {
        if (p == q) return;
        final l = LineEq.throughPoints(p, q);
        expect(l.reflect(l.reflect(x)).closeTo(x, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'reflection negates the signed distance',
      (p, q, x) {
        if (p == q) return;
        final l = LineEq.throughPoints(p, q);
        expect(
          l.signedDistanceTo(l.reflect(x)),
          closeTo(-l.signedDistanceTo(x), 1e-9),
        );
      },
    );

    Glados2(any.vec2, any.vec2).test(
      'reflection across the perpendicular bisector swaps the points',
      (a, b) {
        if (a == b) return;
        final mid = a.lerp(b, 0.5);
        final bisector = LineEq.pointDirection(mid, (b - a).perpendicular);
        expect(bisector.reflect(a).closeTo(b, 1e-6), isTrue);
        expect(bisector.reflect(b).closeTo(a, 1e-6), isTrue);
      },
    );
  });
}
