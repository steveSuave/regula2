import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/stated_radius_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

void main() {
  group('StatedRadiusCircle', () {
    test('draws the circle of the stated radius about its center', () {
      final center = FreePoint(id: 'o', position: const Vec2(2, -1));
      final k = StatedRadiusCircle(
        id: 'k',
        center: center,
        radius: Rational.fromInts(5, 2),
      );
      expect(k.circle!.center.closeTo(const Vec2(2, -1)), isTrue);
      expect(k.circle!.radius, closeTo(2.5, 1e-12));
      expect(k.parents, [center]);
      expect(k.isDefined, isTrue);
    });

    test('the radius is exact, positive, and fixed', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      expect(
        () => StatedRadiusCircle(id: 'k', center: center, radius: Rational.zero),
        throwsArgumentError,
      );
      expect(
        () => StatedRadiusCircle(
          id: 'k',
          center: center,
          radius: Rational.fromInts(-1, 3),
        ),
        throwsArgumentError,
      );
      final k = StatedRadiusCircle(
        id: 'k',
        center: center,
        radius: Rational.fromInts(1, 3),
      );
      expect(k.radius, Rational.fromInts(1, 3));
    });

    test('Euclidean only: a proper absolute leaves it undefined', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final k = StatedRadiusCircle(
        id: 'k',
        center: center,
        radius: Rational.fromInts(2, 1),
      );
      k.recompute(Absolute.hyperbolic);
      expect(k.conic, isNull);
      expect(k.circle, isNull);
      k.recompute();
      expect(k.isDefined, isTrue);
    });
  });
}
