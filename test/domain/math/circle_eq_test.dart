import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('CircleEq unit tests', () {
    test('unit circle distances', () {
      final c = CircleEq(Vec2.zero, 1);
      expect(c.contains(const Vec2(1, 0)), isTrue);
      expect(c.contains(const Vec2(0, -1)), isTrue);
      expect(c.signedDistanceTo(Vec2.zero), -1);
      expect(c.signedDistanceTo(const Vec2(3, 0)), 2);
      expect(c.distanceTo(const Vec2(3, 0)), 2);
    });

    test('pointAt walks the circle', () {
      final c = CircleEq(const Vec2(2, 1), 3);
      expect(c.pointAt(0).closeTo(const Vec2(5, 1)), isTrue);
      expect(c.pointAt(math.pi / 2).closeTo(const Vec2(2, 4), 1e-12), isTrue);
      expect(c.pointAt(math.pi).closeTo(const Vec2(-1, 1), 1e-12), isTrue);
    });

    test('rejects negative and non-finite radii', () {
      expect(() => CircleEq(Vec2.zero, -1), throwsArgumentError);
      expect(() => CircleEq(Vec2.zero, double.nan), throwsArgumentError);
      expect(() => CircleEq(Vec2.zero, double.infinity), throwsArgumentError);
    });

    test('zero radius is allowed (degenerate point-circle)', () {
      final c = CircleEq(const Vec2(1, 2), 0);
      expect(c.contains(const Vec2(1, 2)), isTrue);
      expect(c.signedDistanceTo(const Vec2(1, 5)), 3);
    });

    test('value equality and hashCode', () {
      expect(CircleEq(const Vec2(1, 2), 3), CircleEq(const Vec2(1, 2), 3));
      expect(
        CircleEq(const Vec2(1, 2), 3).hashCode,
        CircleEq(const Vec2(1, 2), 3).hashCode,
      );
      expect(
        CircleEq(const Vec2(1, 2), 3),
        isNot(CircleEq(const Vec2(1, 2), 4)),
      );
    });
  });

  group('CircleEq properties', () {
    Glados2(any.vec2, any.vec2).test(
      'centerAndPoint passes through the defining point',
      (c, p) {
        final circle = CircleEq.centerAndPoint(c, p);
        expect(circle.contains(p), isTrue);
        expect(circle.radius, c.distanceTo(p));
      },
    );

    Glados3(any.vec2, any.coordinate, any.unitInterval).test(
      'pointAt lies on the circle for any angle',
      (center, r, t) {
        final circle = CircleEq(center, r.abs());
        final p = circle.pointAt(t * 2 * math.pi);
        expect(circle.contains(p, 1e-6), isTrue);
      },
    );

    Glados2(any.vec2, any.coordinate).test(
      'center is radius away from the boundary',
      (center, r) {
        final circle = CircleEq(center, r.abs());
        expect(circle.signedDistanceTo(center), -r.abs());
      },
    );

    test('angleAt reads the polar angle around the center', () {
      final circle = CircleEq(const Vec2(1, 1), 2);
      expect(circle.angleAt(const Vec2(5, 1)), closeTo(0, 1e-12));
      expect(circle.angleAt(const Vec2(1, 9)), closeTo(math.pi / 2, 1e-12));
      expect(circle.angleAt(const Vec2(-4, 1)), closeTo(math.pi, 1e-12));
      expect(
        circle.angleAt(circle.center),
        0,
        reason: 'the center has no direction — documented fallback',
      );
    });

    Glados2(any.vec2, any.vec2).test(
      'pointAt(angleAt(p)) is the radial projection of p',
      (center, p) {
        if (center == p) return;
        final circle = CircleEq(center, 3);
        final projected = circle.pointAt(circle.angleAt(p));
        final toP = p - center;
        final toProjected = projected - center;
        expect(
          toP.cross(toProjected).abs() / toP.norm,
          closeTo(0, 1e-6),
          reason: 'projection stays on the ray center → p',
        );
        expect(toP.dot(toProjected), greaterThan(0));
        expect(circle.contains(projected, 1e-9), isTrue);
      },
    );
  });
}
