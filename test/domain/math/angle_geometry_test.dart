import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/angle_geometry.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('ccwSweep', () {
    test('quarter turn up is π/2, back down is 3π/2', () {
      expect(ccwSweep(0, math.pi / 2), closeTo(math.pi / 2, 1e-12));
      expect(ccwSweep(math.pi / 2, 0), closeTo(3 * math.pi / 2, 1e-12));
    });

    test('equal angles sweep 0, even across the atan2 seam', () {
      expect(ccwSweep(1.25, 1.25), 0);
      expect(ccwSweep(math.pi, -math.pi), closeTo(0, 1e-12));
    });

    test('a tiny clockwise difference stays below 2π', () {
      final sweep = ccwSweep(1e-18, 0);
      expect(sweep, lessThan(2 * math.pi));
      expect(sweep, greaterThanOrEqualTo(0));
    });

    Glados2(any.coordinate, any.coordinate).test(
      'is in [0, 2π) and pairs with the reverse sweep to a full turn',
      (a, b) {
        final forward = ccwSweep(a, b);
        final backward = ccwSweep(b, a);
        expect(forward, greaterThanOrEqualTo(0));
        expect(forward, lessThan(2 * math.pi));
        if (forward != 0 && backward != 0) {
          expect(forward + backward, closeTo(2 * math.pi, 1e-9));
        }
      },
    );
  });

  group('sweepThrough', () {
    test('via on the CCW path: positive sweep to the end', () {
      expect(sweepThrough(0, math.pi / 2, math.pi), closeTo(math.pi, 1e-12));
    });

    test('via on the other side: negative (clockwise) sweep', () {
      expect(sweepThrough(0, -math.pi / 2, math.pi), closeTo(-math.pi, 1e-12));
    });

    test('via at an endpoint counts as on the CCW path', () {
      expect(sweepThrough(0, 0, math.pi / 2), closeTo(math.pi / 2, 1e-12));
      expect(
        sweepThrough(0, math.pi / 2, math.pi / 2),
        closeTo(math.pi / 2, 1e-12),
      );
    });

    Glados2(any.coordinate, any.coordinate).test(
      'magnitude never exceeds a full turn',
      (start, end) {
        final sweep = sweepThrough(start, (start + end) / 2, end);
        expect(sweep.abs(), lessThanOrEqualTo(2 * math.pi));
      },
    );
  });

  group('angularDistance', () {
    test('takes the shorter way around', () {
      expect(angularDistance(0, math.pi / 2), closeTo(math.pi / 2, 1e-12));
      expect(angularDistance(0, 3 * math.pi / 2), closeTo(math.pi / 2, 1e-12));
      expect(
        angularDistance(-3 * math.pi / 4, math.pi),
        closeTo(math.pi / 4, 1e-12),
        reason: 'wraps across the atan2 seam',
      );
    });

    test('zero for equal angles, π for opposite ones', () {
      expect(angularDistance(1.25, 1.25), 0);
      expect(angularDistance(0, math.pi), closeTo(math.pi, 1e-12));
    });

    Glados2(any.coordinate, any.coordinate).test(
      'is symmetric and within [0, π]',
      (a, b) {
        final distance = angularDistance(a, b);
        expect(distance, greaterThanOrEqualTo(0));
        expect(distance, lessThanOrEqualTo(math.pi));
        expect(angularDistance(b, a), closeTo(distance, 1e-9));
      },
    );
  });

  group('AngleGeometry', () {
    test('rejects a sweep outside [0, 2π)', () {
      expect(
        () => AngleGeometry(Vec2.zero, const Vec2(1, 0), -0.1),
        throwsArgumentError,
      );
      expect(
        () => AngleGeometry(Vec2.zero, const Vec2(1, 0), 2 * math.pi),
        throwsArgumentError,
      );
      expect(
        () => AngleGeometry(Vec2.zero, const Vec2(1, 0), double.nan),
        throwsArgumentError,
      );
    });

    test('endDirection is startDirection rotated CCW by sweep', () {
      final angle = AngleGeometry(Vec2.zero, const Vec2(1, 0), math.pi / 2);
      expect(angle.endDirection.closeTo(const Vec2(0, 1)), isTrue);
    });

    group('fromRays', () {
      test('right angle at a shifted vertex', () {
        final angle = AngleGeometry.fromRays(
          const Vec2(3, 1),
          const Vec2(1, 1),
          const Vec2(1, 5),
        )!;
        expect(angle.vertex, const Vec2(1, 1));
        expect(angle.startDirection.closeTo(const Vec2(1, 0)), isTrue);
        expect(angle.measure, closeTo(math.pi / 2, 1e-12));
      });

      test('swapping the arms gives the complementary sweep', () {
        final reflex = AngleGeometry.fromRays(
          const Vec2(1, 5),
          const Vec2(1, 1),
          const Vec2(3, 1),
        )!;
        expect(reflex.measure, closeTo(3 * math.pi / 2, 1e-12));
      });

      test('an arm coincident with the vertex: null', () {
        expect(
          AngleGeometry.fromRays(Vec2.zero, Vec2.zero, const Vec2(1, 0)),
          isNull,
        );
        expect(
          AngleGeometry.fromRays(const Vec2(1, 0), Vec2.zero, Vec2.zero),
          isNull,
        );
      });

      Glados3(any.vec2, any.vec2, any.vec2).test(
        'sweeps of the two arm orders total a full turn (arms apart)',
        (arm1, vertex, arm2) {
          final forward = AngleGeometry.fromRays(arm1, vertex, arm2);
          final backward = AngleGeometry.fromRays(arm2, vertex, arm1);
          if (forward == null || backward == null) {
            return; // An arm sat on the vertex.
          }
          if (forward.sweep == 0 || backward.sweep == 0) {
            expect(forward.sweep, closeTo(backward.sweep, 1e-9));
          } else {
            expect(forward.sweep + backward.sweep, closeTo(2 * math.pi, 1e-9));
          }
        },
      );
    });

    group('betweenLines', () {
      test('perpendicular lines: a right angle', () {
        final angle = AngleGeometry.betweenLines(
          const Vec2(2, 3),
          const Vec2(1, 0),
          const Vec2(0, -5),
        )!;
        expect(angle.vertex, const Vec2(2, 3));
        expect(angle.measure, closeTo(math.pi / 2, 1e-12));
      });

      test('an obtuse crossing reports the acute angle', () {
        // Directions 120° apart → the lines meet at 60°.
        final angle = AngleGeometry.betweenLines(
          Vec2.zero,
          const Vec2(1, 0),
          Vec2(math.cos(2 * math.pi / 3), math.sin(2 * math.pi / 3)),
        )!;
        expect(angle.measure, closeTo(math.pi / 3, 1e-12));
      });

      test('parallel or zero directions: null', () {
        expect(
          AngleGeometry.betweenLines(
            Vec2.zero,
            const Vec2(1, 1),
            const Vec2(-2, -2),
          ),
          isNull,
        );
        expect(
          AngleGeometry.betweenLines(Vec2.zero, const Vec2(1, 0), Vec2.zero),
          isNull,
        );
      });

      test('is symmetric in the two directions', () {
        final ab = AngleGeometry.betweenLines(
          Vec2.zero,
          const Vec2(1, 0),
          const Vec2(1, 2),
        )!;
        final ba = AngleGeometry.betweenLines(
          Vec2.zero,
          const Vec2(1, 2),
          const Vec2(1, 0),
        )!;
        expect(ab.closeTo(ba), isTrue);
      });

      Glados2(any.vec2, any.vec2).test(
        'sweep is always acute or right and opens CCW',
        (direction1, direction2) {
          final angle = AngleGeometry.betweenLines(
            Vec2.zero,
            direction1,
            direction2,
          );
          if (angle == null) {
            return;
          }
          expect(angle.sweep, greaterThan(0));
          expect(angle.sweep, lessThanOrEqualTo(math.pi / 2 + 1e-12));
          expect(
            angle.startDirection.cross(angle.endDirection),
            greaterThan(0),
          );
        },
      );
    });
  });
}
