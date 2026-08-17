import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('AreaMeasurement', () {
    test('polygon subject: |shoelace| area, vertex-average anchor', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(4, 3));
      final d = FreePoint(id: 'd', position: const Vec2(0, 3));
      final polygon = Polygon(id: 'p', vertices: [a, b, c, d]);
      final area = AreaMeasurement(id: 'ar', subject: polygon);
      expect(area.isDefined, isTrue);
      expect(area.value, 12);
      expect(area.anchor, const Vec2(2, 1.5));
      expect(area.parents, [polygon]);
    });

    test('clockwise loop reports the same positive area', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(4, 3));
      final ccw = AreaMeasurement(
        id: 'ar1',
        subject: Polygon(id: 'p1', vertices: [a, b, c]),
      );
      final cw = AreaMeasurement(
        id: 'ar2',
        subject: Polygon(id: 'p2', vertices: [c, b, a]),
      );
      expect(ccw.value, 6);
      expect(cw.value, 6);
    });

    test('circle subject: πr², center anchor', () {
      final center = FreePoint(id: 'o', position: const Vec2(1, 2));
      final circle = FixedRadiusCircle(id: 'k', center: center, radius: 2.5);
      final area = AreaMeasurement(id: 'ar', subject: circle);
      expect(area.value, closeTo(math.pi * 6.25, 1e-12));
      expect(area.anchor, const Vec2(1, 2));
    });

    test('sector subject: ½r²θ wedge area, centroid anchor', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final s = FreePoint(id: 's', position: const Vec2(2, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 7));
      final sector = Sector(id: 'sec', center: o, start: s, end: e);
      final area = AreaMeasurement(id: 'ar', subject: sector);
      expect(
        area.value,
        closeTo(math.pi, 1e-12),
        reason: 'radius-2 quarter wedge: ½·4·π/2, not the full circle',
      );
      // Wedge centroid: (4r/(3θ))·sin(θ/2) along the bisector (π/4).
      final d = 8 / (3 * math.pi / 2) * math.sin(math.pi / 4);
      expect(
        area.anchor!.closeTo(Vec2(d * math.sqrt1_2, d * math.sqrt1_2)),
        isTrue,
      );
    });

    test('arc subject: the circular segment its chord cuts off', () {
      // Unit semicircle: segment area ½(π − sin π) = π/2, half the disk.
      final s = FreePoint(id: 's', position: const Vec2(1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final e = FreePoint(id: 'e', position: const Vec2(-1, 0));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final area = AreaMeasurement(id: 'ar', subject: arc);
      expect(area.value, closeTo(math.pi / 2, 1e-12));
      // Half-disk centroid: 4r/(3π) up the bisector.
      expect(area.anchor!.closeTo(Vec2(0, 4 / (3 * math.pi))), isTrue);
    });

    test('a clockwise arc reports the same positive segment area', () {
      final s = FreePoint(id: 's', position: const Vec2(-1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final e = FreePoint(id: 'e', position: const Vec2(1, 0));
      final arc = Arc(id: 'arc', start: s, via: v, end: e);
      final area = AreaMeasurement(id: 'ar', subject: arc);
      expect(area.value, closeTo(math.pi / 2, 1e-12));
      expect(area.anchor!.closeTo(Vec2(0, 4 / (3 * math.pi))), isTrue);
    });

    test('recompute tracks the subject', () {
      final center = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'r', position: const Vec2(1, 0));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final area = AreaMeasurement(id: 'ar', subject: circle);
      expect(area.value, closeTo(math.pi, 1e-12));

      rim.position = const Vec2(3, 0);
      circle.recompute();
      area.recompute();
      expect(area.value, closeTo(9 * math.pi, 1e-12));
    });

    test('rejects subjects that are not polygons or circles', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 1));
      final segment = Segment(id: 's', point1: a, point2: b);
      final angle = VertexAngle(id: 'ang', arm1: a, vertex: b, arm2: c);
      expect(
        () => AreaMeasurement(id: 'ar', subject: segment),
        throwsArgumentError,
      );
      expect(() => AreaMeasurement(id: 'ar', subject: a), throwsArgumentError);
      expect(
        () => AreaMeasurement(id: 'ar', subject: angle),
        throwsArgumentError,
      );
    });

    test('undefined while the subject is, recovers when it does', () {
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
      final polygon = Polygon(id: 'p', vertices: [a, b, crossing]);
      final area = AreaMeasurement(id: 'ar', subject: polygon);
      expect(area.isDefined, isTrue);

      rim.position = const Vec2(0, 2);
      circle.recompute();
      crossing.recompute();
      polygon.recompute();
      area.recompute();
      expect(area.isDefined, isFalse);
      expect(area.value, isNull);
      expect(area.anchor, isNull);

      rim.position = const Vec2(0, -1);
      circle.recompute();
      crossing.recompute();
      polygon.recompute();
      area.recompute();
      expect(area.isDefined, isTrue);
    });
  });

  group('projective semantics (Phase 112)', () {
    test('a degenerate line-pair carrier (collinear three-point circle) '
        'leaves the area undefined', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      expect(circle.conic, isNotNull);

      final area = AreaMeasurement(id: 'area', subject: circle);
      expect(area.isDefined, isFalse);
      expect(area.value, isNull);
    });
  });
}
