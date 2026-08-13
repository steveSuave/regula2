import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/tangents.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('tangentPointsToCircle unit tests', () {
    test('P = (5, 0) against the unit circle', () {
      final points = tangentPointsToCircle(
        const Vec2(5, 0),
        CircleEq(Vec2.zero, 1),
      );
      expect(points, hasLength(2));
      // Tangent points at x = r²/d = 0.2, y = ±√(1 − 0.04); the first
      // lies to the left of the directed center → external line (+x),
      // i.e. on the +y side.
      expect(points[0].x, closeTo(0.2, 1e-12));
      expect(points[0].y, closeTo(0.9797958971132712, 1e-12));
      expect(points[1].x, closeTo(0.2, 1e-12));
      expect(points[1].y, closeTo(-0.9797958971132712, 1e-12));
    });

    test('a point on the circle is its own single tangent point', () {
      final circle = CircleEq(const Vec2(2, 3), 5);
      final onCircle = const Vec2(5, 7); // 3-4-5 offset from the center
      expect(tangentPointsToCircle(onCircle, circle), [onCircle]);
    });

    test('strictly inside yields no tangent points', () {
      final circle = CircleEq(const Vec2(2, 3), 5);
      expect(tangentPointsToCircle(const Vec2(3, 4), circle), isEmpty);
      expect(
        tangentPointsToCircle(circle.center, circle),
        isEmpty,
        reason: 'the center has no direction, let alone tangents',
      );
    });

    test('a degenerate radius yields no tangent points', () {
      expect(
        tangentPointsToCircle(const Vec2(5, 0), CircleEq(Vec2.zero, 0)),
        isEmpty,
      );
    });
  });

  group('tangentPointsToCircle properties', () {
    // A generated point remapped strictly outside the generated circle
    // (at least 1 world unit beyond the rim), keeping its direction from
    // the center so the branch geometry still varies freely.
    (Vec2, CircleEq) outsideCase(Vec2 p, CircleEq circle) {
      final offset = p - circle.center;
      final direction = offset.normSquared == 0
          ? const Vec2(1, 0)
          : offset.normalized();
      final external =
          circle.center + direction * (circle.radius + 1 + offset.norm);
      return (external, circle);
    }

    Glados2(any.vec2, any.circleEq).test('tangent points lie on the circle', (
      p,
      generatedCircle,
    ) {
      final (external, circle) = outsideCase(p, generatedCircle);
      final points = tangentPointsToCircle(external, circle);
      expect(points, hasLength(2));
      final scale = 1 + circle.radius + external.distanceTo(circle.center);
      for (final t in points) {
        expect(circle.distanceTo(t), lessThan(1e-9 * scale));
      }
    });

    Glados2(any.vec2, any.circleEq).test(
      'the radius to a tangent point is perpendicular to the tangent line',
      (p, generatedCircle) {
        final (external, circle) = outsideCase(p, generatedCircle);
        for (final t in tangentPointsToCircle(external, circle)) {
          final radius = t - circle.center;
          final tangent = t - external;
          final cosine = radius.dot(tangent) / (radius.norm * tangent.norm);
          expect(cosine, closeTo(0, 1e-8));
        }
      },
    );

    Glados2(any.vec2, any.circleEq).test(
      'the first point lies left of the directed center → external line',
      (p, generatedCircle) {
        final (external, circle) = outsideCase(p, generatedCircle);
        final points = tangentPointsToCircle(external, circle);
        final toExternal = external - circle.center;
        expect(toExternal.cross(points[0] - circle.center), isPositive);
        expect(toExternal.cross(points[1] - circle.center), isNegative);
      },
    );
  });
}
