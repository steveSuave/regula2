import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('DistanceMeasurement', () {
    test('value is the distance, anchor the midpoint', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 4));
      final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
      expect(distance.isDefined, isTrue);
      expect(distance.value, 5);
      expect(distance.anchor, const Vec2(1.5, 2));
      expect(distance.parents, [a, b]);
    });

    test('coincident points measure zero, still defined', () {
      final a = FreePoint(id: 'a', position: const Vec2(2, 2));
      final b = FreePoint(id: 'b', position: const Vec2(2, 2));
      final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
      expect(distance.isDefined, isTrue);
      expect(distance.value, 0);
      expect(distance.anchor, const Vec2(2, 2));
    });

    test('recompute tracks a dragged endpoint', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
      expect(distance.value, 1);

      b.position = const Vec2(0, 7);
      distance.recompute();
      expect(distance.value, 7);
      expect(distance.anchor, const Vec2(0, 3.5));
    });

    test('undefined while an endpoint is, recovers when it does', () {
      final a = FreePoint(id: 'a', position: const Vec2(-4, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final center = FreePoint(id: 'o', position: const Vec2(0, 3));
      final rim = FreePoint(id: 'rim', position: const Vec2(0, -1));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
      );
      final distance = DistanceMeasurement(
        id: 'd',
        point1: a,
        point2: crossing,
      );
      expect(distance.isDefined, isTrue);

      // Radius below 3 lifts the circle off the line: the crossing — and
      // with it the measurement — goes undefined.
      rim.position = const Vec2(0, 2);
      circle.recompute();
      crossing.recompute();
      distance.recompute();
      expect(distance.isDefined, isFalse);
      expect(distance.value, isNull);
      expect(distance.anchor, isNull);

      rim.position = const Vec2(0, -1);
      circle.recompute();
      crossing.recompute();
      distance.recompute();
      expect(distance.isDefined, isTrue);
    });
  });
}
