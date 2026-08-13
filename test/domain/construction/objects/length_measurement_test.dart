import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/length_measurement.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('LengthMeasurement', () {
    test('circle subject: circumference, anchored at the top of the rim', () {
      final center = FreePoint(id: 'o', position: const Vec2(1, 2));
      final circle = FixedRadiusCircle(id: 'k', center: center, radius: 2.5);
      final length = LengthMeasurement(id: 'len', subject: circle);
      expect(length.isDefined, isTrue);
      expect(length.value, closeTo(5 * math.pi, 1e-12));
      expect(length.anchor!.closeTo(const Vec2(1, 4.5)), isTrue);
      expect(length.parents, [circle]);
    });

    test('arc subject: r·sweep, anchored at the arc midpoint', () {
      // Unit semicircle through (0, 1).
      final s = FreePoint(id: 's', position: const Vec2(1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final e = FreePoint(id: 'e', position: const Vec2(-1, 0));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final length = LengthMeasurement(id: 'len', subject: arc);
      expect(length.value, closeTo(math.pi, 1e-12));
      expect(length.anchor!.closeTo(const Vec2(0, 1)), isTrue);
    });

    test('a clockwise arc measures the same branch', () {
      final s = FreePoint(id: 's', position: const Vec2(-1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final e = FreePoint(id: 'e', position: const Vec2(1, 0));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final length = LengthMeasurement(id: 'len', subject: arc);
      expect(length.value, closeTo(math.pi, 1e-12));
      expect(length.anchor!.closeTo(const Vec2(0, 1)), isTrue);
    });

    test('sector subject: closed-region perimeter 2r + r·sweep', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final s = FreePoint(id: 's', position: const Vec2(2, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 5));
      final sector = Sector(id: 'sec', center: o, start: s, end: e);
      final length = LengthMeasurement(id: 'len', subject: sector);
      expect(
        length.value,
        closeTo(4 + math.pi, 1e-12),
        reason: 'radius 2 quarter wedge — end fixes only the angle',
      );
      expect(
        length.anchor!.closeTo(Vec2(math.sqrt2, math.sqrt2)),
        isTrue,
        reason: 'anchored at the rim midpoint',
      );
    });

    test('recompute tracks the subject', () {
      final center = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'r', position: const Vec2(1, 0));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final length = LengthMeasurement(id: 'len', subject: circle);
      expect(length.value, closeTo(2 * math.pi, 1e-12));

      rim.position = const Vec2(3, 0);
      circle.recompute();
      length.recompute();
      expect(length.value, closeTo(6 * math.pi, 1e-12));
    });

    test('undefined while the subject is, recovers when it does', () {
      final s = FreePoint(id: 's', position: const Vec2(1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final e = FreePoint(id: 'e', position: const Vec2(-1, 0));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final length = LengthMeasurement(id: 'len', subject: arc);
      expect(length.isDefined, isTrue);

      v.position = const Vec2(0, 0);
      arc.recompute();
      length.recompute();
      expect(length.isDefined, isFalse);
      expect(length.value, isNull);
      expect(length.anchor, isNull);

      v.position = const Vec2(0, 1);
      arc.recompute();
      length.recompute();
      expect(length.isDefined, isTrue);
    });

    test('rejects subjects that are not circular', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 1));
      expect(
        () => LengthMeasurement(
          id: 'len',
          subject: Segment(id: 'seg', point1: a, point2: b),
        ),
        throwsArgumentError,
      );
      expect(
        () => LengthMeasurement(
          id: 'len',
          subject: Polygon(id: 'p', vertices: [a, b, c]),
        ),
        throwsArgumentError,
      );
      expect(
        () => LengthMeasurement(id: 'len', subject: a),
        throwsArgumentError,
      );
    });
  });
}
