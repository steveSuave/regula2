import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/scaled_compass_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

void main() {
  group('ScaledCompassCircle', () {
    (FreePoint, FreePoint, FreePoint) rig() => (
      FreePoint(id: 'o', position: const Vec2(1, 1)),
      FreePoint(id: 'p', position: const Vec2(0, 0)),
      FreePoint(id: 'q', position: const Vec2(3, 0)),
    );

    test('radius is the stated multiple of the compassed distance', () {
      final (o, p, q) = rig();
      final k = ScaledCompassCircle(
        id: 'k',
        center: o,
        radiusPoint1: p,
        radiusPoint2: q,
        factor: Rational.fromInts(2, 3),
      );
      expect(k.circle!.center.closeTo(const Vec2(1, 1)), isTrue);
      expect(k.circle!.radius, closeTo(2, 1e-12));
      expect(k.parents, [o, p, q]);
    });

    test('tracks a dragged span; coincident span points give the '
        'zero-radius circle', () {
      final construction = Construction();
      final (o, p, q) = rig();
      final k = ScaledCompassCircle(
        id: 'k',
        center: o,
        radiusPoint1: p,
        radiusPoint2: q,
        factor: Rational.fromInts(2, 1),
      );
      construction
        ..add(o)
        ..add(p)
        ..add(q)
        ..add(k);
      construction.moveFreePoint('q', const Vec2(0, 2));
      expect(k.circle!.radius, closeTo(4, 1e-12));
      // The CompassCircle convention through degeneracy.
      construction.moveFreePoint('q', const Vec2(0, 0));
      expect(k.circle!.radius, 0);
    });

    test('the factor is positive, enforced', () {
      final (o, p, q) = rig();
      expect(
        () => ScaledCompassCircle(
          id: 'k',
          center: o,
          radiusPoint1: p,
          radiusPoint2: q,
          factor: Rational.zero,
        ),
        throwsArgumentError,
      );
    });

    test('Euclidean only: a proper absolute leaves it undefined', () {
      final (o, p, q) = rig();
      final k = ScaledCompassCircle(
        id: 'k',
        center: o,
        radiusPoint1: p,
        radiusPoint2: q,
        factor: Rational.fromInts(1, 2),
      );
      k.recompute(Absolute.hyperbolic);
      expect(k.conic, isNull);
      expect(k.circle, isNull);
      k.recompute();
      expect(k.isDefined, isTrue);
    });
  });
}
