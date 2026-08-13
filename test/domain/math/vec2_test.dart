import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('Vec2 unit tests', () {
    test('arithmetic operators on known values', () {
      const a = Vec2(3, 4);
      const b = Vec2(-1, 2);
      expect(a + b, const Vec2(2, 6));
      expect(a - b, const Vec2(4, 2));
      expect(-a, const Vec2(-3, -4));
      expect(a * 2, const Vec2(6, 8));
      expect(a / 2, const Vec2(1.5, 2));
    });

    test('norm and distance', () {
      expect(const Vec2(3, 4).norm, 5);
      expect(const Vec2(3, 4).normSquared, 25);
      expect(const Vec2(1, 1).distanceTo(const Vec2(4, 5)), 5);
      expect(const Vec2(1, 1).squaredDistanceTo(const Vec2(4, 5)), 25);
    });

    test('dot and cross on known values', () {
      expect(const Vec2(1, 0).dot(const Vec2(0, 1)), 0);
      expect(const Vec2(2, 3).dot(const Vec2(4, 5)), 23);
      expect(const Vec2(1, 0).cross(const Vec2(0, 1)), 1);
      expect(const Vec2(0, 1).cross(const Vec2(1, 0)), -1);
    });

    test('normalized scales to unit length', () {
      expect(const Vec2(3, 4).normalized(), const Vec2(0.6, 0.8));
    });

    test('normalized throws on the zero vector', () {
      expect(Vec2.zero.normalized, throwsStateError);
    });

    test('angle', () {
      expect(const Vec2(1, 0).angle, 0);
      expect(const Vec2(0, 1).angle, closeTo(math.pi / 2, 1e-12));
      expect(const Vec2(-1, 0).angle, closeTo(math.pi, 1e-12));
    });

    test('rotated by known angles', () {
      expect(
        const Vec2(1, 0).rotated(math.pi / 2).closeTo(const Vec2(0, 1), 1e-12),
        isTrue,
      );
      expect(
        const Vec2(3, 4).rotated(math.pi).closeTo(const Vec2(-3, -4), 1e-12),
        isTrue,
      );
      expect(const Vec2(3, 4).rotated(0), const Vec2(3, 4));
    });

    test('value equality and hashCode', () {
      expect(const Vec2(1, 2), const Vec2(1, 2));
      expect(const Vec2(1, 2).hashCode, const Vec2(1, 2).hashCode);
      expect(const Vec2(1, 2), isNot(const Vec2(2, 1)));
    });
  });

  group('Vec2 properties', () {
    Glados2(any.vec2, any.vec2).test('dot is symmetric', (a, b) {
      expect(a.dot(b), b.dot(a));
    });

    Glados(any.vec2).test('cross with self is zero', (a) {
      expect(a.cross(a), 0);
    });

    Glados2(any.vec2, any.vec2).test('cross is antisymmetric', (a, b) {
      expect(a.cross(b), closeTo(-b.cross(a), 1e-9));
    });

    Glados(any.vec2).test('perpendicular is orthogonal and same length', (a) {
      expect(a.dot(a.perpendicular), 0);
      expect(a.perpendicular.norm, a.norm);
    });

    Glados2(any.vec2, any.vec2).test(
      'distance is symmetric and matches norm of difference',
      (a, b) {
        expect(a.distanceTo(b), b.distanceTo(a));
        expect(a.distanceTo(b), (a - b).norm);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test('triangle inequality', (
      a,
      b,
      c,
    ) {
      expect(
        a.distanceTo(b),
        lessThanOrEqualTo(a.distanceTo(c) + c.distanceTo(b) + 1e-9),
      );
    });

    Glados(any.vec2).test('normalized has unit length', (a) {
      if (a == Vec2.zero) return;
      expect(a.normalized().norm, closeTo(1, 1e-12));
    });

    Glados2(any.vec2, any.vec2).test('addition and subtraction round-trip', (
      a,
      b,
    ) {
      expect((a + b - b).closeTo(a, 1e-9), isTrue);
    });

    Glados2(any.vec2, any.vec2).test('lerp hits both endpoints', (a, b) {
      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1).closeTo(b, 1e-9), isTrue);
    });

    Glados2(any.vec2, any.vec2).test(
      'midpoint is equidistant from both endpoints',
      (a, b) {
        final m = a.lerp(b, 0.5);
        expect(m.distanceTo(a), closeTo(m.distanceTo(b), 1e-9));
      },
    );

    Glados2(any.vec2, any.angle).test('rotation preserves length', (a, t) {
      expect(a.rotated(t).norm, closeTo(a.norm, 1e-9));
    });

    Glados(any.vec2).test('rotation by π/2 is perpendicular', (a) {
      expect(a.rotated(math.pi / 2).closeTo(a.perpendicular, 1e-9), isTrue);
    });

    Glados3(any.vec2, any.angle, any.angle).test(
      'rotations compose additively',
      (a, s, t) {
        expect(a.rotated(s).rotated(t).closeTo(a.rotated(s + t), 1e-6), isTrue);
      },
    );
  });
}
