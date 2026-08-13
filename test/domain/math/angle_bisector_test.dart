import 'package:glados/glados.dart';
import 'package:regula/domain/math/angle_bisector.dart';
import 'package:regula/domain/math/intersections.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('angleBisector', () {
    test('right angle at the origin: y = x', () {
      final bisector = angleBisector(
        const Vec2(5, 0),
        Vec2.zero,
        const Vec2(0, 5),
      )!;
      expect(
        bisector.closeTo(LineEq.throughPoints(Vec2.zero, const Vec2(1, 1))),
        isTrue,
      );
    });

    test('arm distance does not matter', () {
      final near = angleBisector(
        const Vec2(1, 0),
        Vec2.zero,
        const Vec2(0, 1),
      )!;
      final far = angleBisector(
        const Vec2(1000, 0),
        Vec2.zero,
        const Vec2(0, 0.001),
      )!;
      expect(near.closeTo(far, 1e-6), isTrue);
    });

    test('opposite rays: the perpendicular at the vertex', () {
      final bisector = angleBisector(
        const Vec2(-3, 2),
        const Vec2(1, 2),
        const Vec2(7, 2),
      )!;
      expect(bisector.contains(const Vec2(1, 2)), isTrue);
      expect(bisector.contains(const Vec2(1, 100)), isTrue);
    });

    test('arms on the same ray: the ray itself', () {
      final bisector = angleBisector(
        const Vec2(2, 2),
        Vec2.zero,
        const Vec2(5, 5),
      )!;
      expect(
        bisector.closeTo(LineEq.throughPoints(Vec2.zero, const Vec2(1, 1))),
        isTrue,
      );
    });

    test('an arm coincident with the vertex: null', () {
      expect(angleBisector(Vec2.zero, Vec2.zero, const Vec2(1, 0)), isNull);
      expect(angleBisector(const Vec2(1, 0), Vec2.zero, Vec2.zero), isNull);
    });

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'contains the vertex and is equidistant from equal-length arm marks',
      (arm1, vertex, arm2) {
        final bisector = angleBisector(arm1, vertex, arm2);
        if (bisector == null) {
          return; // an arm sat (nearly) on the vertex — nothing to check
        }
        expect(bisector.distanceTo(vertex), lessThan(1e-6));
        // The defining property: points at equal arc length along either arm
        // are equidistant from the bisector.
        final u = (arm1 - vertex).normalized();
        final v = (arm2 - vertex).normalized();
        expect(
          bisector.distanceTo(vertex + u),
          closeTo(bisector.distanceTo(vertex + v), 1e-6),
        );
      },
    );

    Glados2(any.vec2, any.vec2).test('symmetric in its arms', (arm1, arm2) {
      final forward = angleBisector(arm1, Vec2.zero, arm2);
      final backward = angleBisector(arm2, Vec2.zero, arm1);
      if (forward == null || backward == null) {
        expect(forward, backward);
        return;
      }
      expect(forward.closeTo(backward, 1e-6), isTrue);
    });
  });

  group('twoLineBisector', () {
    final xAxis = LineEq.throughPoints(Vec2.zero, const Vec2(1, 0));
    final yAxis = LineEq.throughPoints(Vec2.zero, const Vec2(0, 1));

    test('the axes: branch 0 is y = x, branch 1 is y = −x', () {
      final sum = twoLineBisector(xAxis, yAxis, 0)!;
      final diff = twoLineBisector(xAxis, yAxis, 1)!;
      expect(
        sum.closeTo(LineEq.throughPoints(Vec2.zero, const Vec2(1, 1))),
        isTrue,
      );
      expect(
        diff.closeTo(LineEq.throughPoints(Vec2.zero, const Vec2(1, -1))),
        isTrue,
      );
    });

    test('parallel and anti-parallel lines: null', () {
      final shifted = LineEq.throughPoints(const Vec2(0, 1), const Vec2(1, 1));
      final reversed = LineEq.throughPoints(const Vec2(1, 1), const Vec2(0, 1));
      expect(twoLineBisector(xAxis, shifted, 0), isNull);
      expect(twoLineBisector(xAxis, reversed, 0), isNull);
      expect(twoLineBisector(xAxis, reversed, 1), isNull);
    });

    Glados2(
      any.vec2,
      any.vec2,
    ).test('both branches pass the crossing, are perpendicular to each other '
        'and equidistant from the two lines', (p, q) {
      final line1 = LineEq.pointDirection(Vec2.zero, const Vec2(1, 0.5));
      if (p.closeTo(q)) {
        return;
      }
      final LineEq line2;
      try {
        line2 = LineEq.throughPoints(p, q);
      } on ArgumentError {
        return;
      }
      final b0 = twoLineBisector(line1, line2, 0);
      final b1 = twoLineBisector(line1, line2, 1);
      if (b0 == null || b1 == null) {
        expect(b0, b1, reason: 'branches go undefined together');
        return;
      }
      final crossing = intersectLineLine(line1, line2).single;
      expect(b0.distanceTo(crossing), lessThan(1e-6));
      expect(b1.distanceTo(crossing), lessThan(1e-6));
      expect(
        b0.direction.dot(b1.direction).abs(),
        lessThan(1e-6),
        reason: 'the two bisectors are a perpendicular pair',
      );
      // The defining property: any point on a bisector is equidistant
      // from both lines.
      for (final probe in [b0.pointAt(3), b1.pointAt(-2)]) {
        expect(line1.distanceTo(probe), closeTo(line2.distanceTo(probe), 1e-6));
      }
    });
  });
}
