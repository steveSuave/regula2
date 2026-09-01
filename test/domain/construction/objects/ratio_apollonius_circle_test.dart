import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/ratio_apollonius_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

void main() {
  group('RatioApolloniusCircle', () {
    test('ratio 2 over a 3-unit base: center (4, 0), radius 2', () {
      // The ApolloniusCircle test's figure with the ratio stated instead
      // of carried by a third point.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final k = RatioApolloniusCircle(
        id: 'k',
        point1: a,
        point2: b,
        ratio: Rational.fromInts(2, 1),
      );
      expect(k.circle!.center.closeTo(const Vec2(4, 0)), isTrue);
      expect(k.circle!.radius, closeTo(2, 1e-9));
      expect(k.parents, [a, b]);
    });

    test('every point of the locus has the stated distance ratio', () {
      final a = FreePoint(id: 'a', position: const Vec2(-1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final k = RatioApolloniusCircle(
        id: 'k',
        point1: a,
        point2: b,
        ratio: Rational.fromInts(1, 3),
      );
      final circle = k.circle!;
      for (final t in const [0.0, 1.0, 2.5, 4.0]) {
        final p = circle.pointAt(t);
        expect(
          p.distanceTo(a.position) / p.distanceTo(b.position),
          closeTo(1 / 3, 1e-9),
        );
      }
    });

    test('a ratio below 1 wraps the first anchor, above 1 the second', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final small = RatioApolloniusCircle(
        id: 's',
        point1: a,
        point2: b,
        ratio: Rational.fromInts(1, 2),
      );
      expect(small.circle!.signedDistanceTo(a.position), lessThan(0));
      expect(small.circle!.signedDistanceTo(b.position), greaterThan(0));
    });

    test('ratio 1 is refused: that locus is the perpendicular bisector', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      expect(
        () => RatioApolloniusCircle(
          id: 'k',
          point1: a,
          point2: b,
          ratio: Rational.one,
        ),
        throwsArgumentError,
      );
      expect(
        () => RatioApolloniusCircle(
          id: 'k',
          point1: a,
          point2: b,
          ratio: Rational.zero,
        ),
        throwsArgumentError,
      );
    });

    test('coincident anchors leave it undefined; separating recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final k = RatioApolloniusCircle(
        id: 'k',
        point1: a,
        point2: b,
        ratio: Rational.fromInts(2, 1),
      );
      construction
        ..add(a)
        ..add(b)
        ..add(k);
      construction.moveFreePoint('b', const Vec2(0, 0));
      expect(k.isDefined, isFalse);
      expect(k.circle, isNull);
      construction.moveFreePoint('b', const Vec2(3, 0));
      expect(k.isDefined, isTrue);
    });

    test('Euclidean only: a proper absolute leaves it undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final k = RatioApolloniusCircle(
        id: 'k',
        point1: a,
        point2: b,
        ratio: Rational.fromInts(2, 1),
      );
      k.recompute(Absolute.hyperbolic);
      expect(k.conic, isNull);
      expect(k.circle, isNull);
      k.recompute();
      expect(k.isDefined, isTrue);
    });
  });
}
