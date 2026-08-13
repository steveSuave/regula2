import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/slope_measurement.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('SlopeMeasurement', () {
    test('infinite line: rise over run, anchored closest to the origin', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 1));
      final b = FreePoint(id: 'b', position: const Vec2(2, 2));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final slope = SlopeMeasurement(id: 'm', subject: line);
      expect(slope.isDefined, isTrue);
      expect(slope.value, closeTo(0.5, 1e-12));
      expect(slope.anchor!.closeTo(line.line!.pointOnLine), isTrue);
      expect(slope.parents, [line]);
    });

    test('slope is independent of the defining points\' order', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 3));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final ba = LineThroughTwoPoints(id: 'ba', point1: b, point2: a);
      expect(
        SlopeMeasurement(id: 'm1', subject: ab).value,
        closeTo(SlopeMeasurement(id: 'm2', subject: ba).value!, 1e-12),
      );
    });

    test('segment subject anchors at the midpoint', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(5, 3));
      final segment = Segment(id: 's', point1: a, point2: b);
      final slope = SlopeMeasurement(id: 'm', subject: segment);
      expect(slope.value, closeTo(0.5, 1e-12));
      expect(slope.anchor!.closeTo(const Vec2(3, 2)), isTrue);
    });

    test('ray subject anchors at the origin, either carrier orientation', () {
      final o = FreePoint(id: 'o', position: const Vec2(2, 1));
      final t = FreePoint(id: 't', position: const Vec2(4, 5));
      final forward = Ray(id: 'r1', origin: o, through: t);
      final backward = Ray(id: 'r2', origin: t, through: o);
      final m1 = SlopeMeasurement(id: 'm1', subject: forward);
      final m2 = SlopeMeasurement(id: 'm2', subject: backward);
      expect(m1.value, closeTo(2, 1e-12));
      expect(m2.value, closeTo(2, 1e-12));
      expect(m1.anchor!.closeTo(const Vec2(2, 1)), isTrue);
      expect(m2.anchor!.closeTo(const Vec2(4, 5)), isTrue);
    });

    test('horizontal line measures zero', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 2));
      final b = FreePoint(id: 'b', position: const Vec2(3, 2));
      final slope = SlopeMeasurement(
        id: 'm',
        subject: Segment(id: 's', point1: a, point2: b),
      );
      expect(slope.value, 0);
    });

    test('vertical line is undefined, recovers when tilted', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 4));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final slope = SlopeMeasurement(id: 'm', subject: line);
      expect(slope.isDefined, isFalse);
      expect(slope.value, isNull);
      expect(slope.anchor, isNull);

      b.position = const Vec2(5, 4);
      line.recompute();
      slope.recompute();
      expect(slope.isDefined, isTrue);
      expect(slope.value, closeTo(1, 1e-12));
    });

    test('undefined while the subject is, recovers when it does', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(2, 2));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final slope = SlopeMeasurement(id: 'm', subject: line);
      expect(slope.isDefined, isTrue);

      b.position = const Vec2(0, 0);
      line.recompute();
      slope.recompute();
      expect(slope.isDefined, isFalse);

      b.position = const Vec2(2, 2);
      line.recompute();
      slope.recompute();
      expect(slope.isDefined, isTrue);
      expect(slope.value, closeTo(1, 1e-12));
    });

    test('recompute tracks the subject', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 4));
      final segment = Segment(id: 's', point1: a, point2: b);
      final slope = SlopeMeasurement(id: 'm', subject: segment);
      expect(slope.value, closeTo(1, 1e-12));

      b.position = const Vec2(4, 2);
      segment.recompute();
      slope.recompute();
      expect(slope.value, closeTo(0.5, 1e-12));
      expect(slope.anchor!.closeTo(const Vec2(2, 1)), isTrue);
    });

    test('rejects subjects that are not line-valued', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 1));
      expect(() => SlopeMeasurement(id: 'm', subject: a), throwsArgumentError);
      expect(
        () => SlopeMeasurement(
          id: 'm',
          subject: CircleCenterPoint(id: 'k', center: a, onCircle: b),
        ),
        throwsArgumentError,
      );
      expect(
        () => SlopeMeasurement(
          id: 'm',
          subject: Polygon(id: 'p', vertices: [a, b, c]),
        ),
        throwsArgumentError,
      );
    });
  });
}
