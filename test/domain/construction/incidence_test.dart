import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/incidence.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  FreePoint point(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  group('structurallyIncident', () {
    test('hosted and intersection points are incident on their curves', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 2, -2);
      final d = point('d', 2, 2);
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      final other = Segment(id: 'o', point1: a, point2: d);
      final glued = PointOnObject(id: 'g', curve: ab, parameter: 0.25);
      final crossing = IntersectionPoint(
        curve1: ab,
        curve2: cd,
        branchIndex: 0,
        id: 'p',
      );

      expect(structurallyIncident(ab, glued), isTrue);
      expect(structurallyIncident(cd, glued), isFalse);
      expect(structurallyIncident(ab, crossing), isTrue);
      expect(structurallyIncident(cd, crossing), isTrue);
      expect(structurallyIncident(other, crossing), isFalse);
    });

    test('on-carrier defining points are incident, off-carrier ones not', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 2, 2);
      final segment = Segment(id: 's', point1: a, point2: b);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final ray = Ray(id: 'r', origin: a, through: b);
      final perpendicular = PerpendicularLine(
        id: 'pp',
        through: c,
        reference: line,
      );
      final bisector = PerpendicularBisectorLine(
        id: 'pb',
        point1: a,
        point2: b,
      );

      expect(structurallyIncident(segment, a), isTrue);
      expect(structurallyIncident(segment, b), isTrue);
      expect(structurallyIncident(segment, c), isFalse);
      expect(structurallyIncident(line, a), isTrue);
      expect(structurallyIncident(ray, b), isTrue);
      expect(structurallyIncident(perpendicular, c), isTrue);
      expect(
        structurallyIncident(bisector, a),
        isFalse,
        reason: 'a perpendicular bisector does not pass its endpoints',
      );
    });

    test('circle defining points: only those pinned to the carrier', () {
      final o = point('o', 0, 0);
      final rim = point('rim', 4, 0);
      final r1 = point('r1', 10, 0);
      final r2 = point('r2', 13, 0);
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: rim);
      final compass = CompassCircle(
        id: 'cc',
        radiusPoint1: r1,
        radiusPoint2: r2,
        center: o,
      );
      final start = point('as', 4, 0);
      final via = point('av', 0, 4);
      final end = point('ae', -4, 0);
      final arc = Arc(id: 'arc', start: start, via: via, end: end);
      // The sector's end sits off the radius-4 carrier on purpose: it
      // fixes an angle only, so it must not count as incident.
      final farEnd = point('fe', 0, 7);
      final sector = Sector(id: 'sec', center: o, start: rim, end: farEnd);

      expect(structurallyIncident(circle, rim), isTrue);
      expect(structurallyIncident(circle, o), isFalse);
      expect(structurallyIncident(compass, r1), isFalse);
      expect(structurallyIncident(compass, o), isFalse);
      expect(structurallyIncident(arc, start), isTrue);
      expect(structurallyIncident(arc, via), isTrue);
      expect(structurallyIncident(arc, end), isTrue);
      expect(structurallyIncident(sector, rim), isTrue);
      expect(structurallyIncident(sector, farEnd), isFalse);
      expect(structurallyIncident(sector, o), isFalse);
    });

    test('derived: two-line bisector through its parents\' crossing', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 2, -2);
      final d = point('d', 2, 2);
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      final other = Segment(id: 'o', point1: a, point2: d);
      final bisector = TwoLineBisectorLine(
        id: 'bi',
        line1: ab,
        line2: cd,
        branch: 0,
      );
      // Reversed parent order relative to the bisector's.
      final crossing = IntersectionPoint(
        curve1: cd,
        curve2: ab,
        branchIndex: 0,
        id: 'p',
      );
      final otherCrossing = IntersectionPoint(
        curve1: ab,
        curve2: other,
        branchIndex: 0,
        id: 'q',
      );

      expect(structurallyIncident(bisector, crossing), isTrue);
      expect(structurallyIncident(bisector, otherCrossing), isFalse);
    });

    test('derived: two-line bisector through its parents\' shared vertex', () {
      // Two segments hanging off one endpoint: their crossing is the
      // shared defining point itself, no IntersectionPoint anywhere.
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 0, 4);
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final ac = Segment(id: 'ac', point1: a, point2: c);
      final bisector = TwoLineBisectorLine(
        id: 'bi',
        line1: ab,
        line2: ac,
        branch: 0,
      );

      expect(structurallyIncident(bisector, a), isTrue);
      expect(
        structurallyIncident(bisector, b),
        isFalse,
        reason: 'b sits on one parent only',
      );
      final glued = PointOnObject(id: 'g', curve: ab, parameter: 0.5);
      expect(structurallyIncident(bisector, glued), isFalse);
    });

    test('derived: perpendicular bisector through the pair\'s midpoint', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 2, 2);
      final bisector = PerpendicularBisectorLine(
        id: 'pb',
        point1: a,
        point2: b,
      );
      // Reversed pair order relative to the bisector's.
      final mid = Midpoint(id: 'm', point1: b, point2: a);
      final otherMid = Midpoint(id: 'n', point1: a, point2: c);

      expect(structurallyIncident(bisector, mid), isTrue);
      expect(structurallyIncident(bisector, otherMid), isFalse);
    });

    test('mere coincidence is not incidence', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final onCarrier = point('c', 2, 0); // exactly on the line, unrelated
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);

      expect(structurallyIncident(line, onCarrier), isFalse);
    });
  });

  group('coincidentCarriers (Phase 164)', () {
    // Both orders must agree: the relation is symmetric by meaning, and
    // a reader may name either copy first.
    void expectCoincident(GeoLine a, GeoLine b, bool expected) {
      expect(coincidentCarriers(a, b), expected, reason: '${a.id} ~ ${b.id}');
      expect(coincidentCarriers(b, a), expected, reason: '${b.id} ~ ${a.id}');
    }

    test('two-point kinds over the same two points are one carrier', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 0, 3);
      final segment = Segment(id: 'ab', point1: a, point2: b);
      final line = LineThroughTwoPoints(id: 'ba', point1: b, point2: a);
      final ray = Ray(id: 'r', origin: a, through: b);
      final back = Ray(id: 'rr', origin: b, through: a);
      final other = Segment(id: 'ac', point1: a, point2: c);

      expectCoincident(segment, segment, true);
      expectCoincident(segment, line, true);
      expectCoincident(segment, ray, true);
      // A ray and its reverse draw one line: the carrier is what is
      // asked about, not the half of it that is painted.
      expectCoincident(ray, back, true);
      expectCoincident(segment, other, false);
      expectCoincident(line, other, false);
    });

    test(
      'tangents from a point on the circle collapse; external ones do not',
      () {
        final centre = point('o', 0, 0);
        final rim = point('r', 1, 0);
        final circle = CircleCenterPoint(
          id: 'k',
          center: centre,
          onCircle: rim,
        );
        final external = point('p', 3, 0);
        final onCircle = PointOnObject(id: 'q', curve: circle, parameter: 1.0);

        final e0 = TangentLine(
          id: 'e0',
          point: external,
          circle: circle,
          branch: 0,
        );
        final e1 = TangentLine(
          id: 'e1',
          point: external,
          circle: circle,
          branch: 1,
        );
        final e0Again = TangentLine(
          id: 'e0b',
          point: external,
          circle: circle,
          branch: 0,
        );
        expectCoincident(e0, e1, false);
        expectCoincident(e0, e0Again, true);

        for (final touch in [rim, onCircle]) {
          final t0 = TangentLine(
            id: 't0',
            point: touch,
            circle: circle,
            branch: 0,
          );
          final t1 = TangentLine(
            id: 't1',
            point: touch,
            circle: circle,
            branch: 1,
          );
          expectCoincident(t0, t1, true);
          // A different circle, or a different point: not the same line.
          expectCoincident(t0, e0, false);
        }
      },
    );

    test('relative lines coincide through coincident references', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final p = point('p', 1, 2);
      final q = point('q', 2, 2);
      final segment = Segment(id: 'ab', point1: a, point2: b);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);

      final perpSeg = PerpendicularLine(
        id: 'ps',
        through: p,
        reference: segment,
      );
      final perpLine = PerpendicularLine(id: 'pl', through: p, reference: line);
      final perpQ = PerpendicularLine(id: 'pq', through: q, reference: line);
      final parallel = ParallelLine(id: 'par', through: p, reference: line);

      expectCoincident(perpSeg, perpLine, true);
      expectCoincident(perpSeg, perpQ, false);
      expectCoincident(perpLine, parallel, false);
    });

    test('bisectors of one vertex over the same arms coincide', () {
      final v = point('v', 0, 0);
      final a = point('a', 4, 0);
      final b = point('b', 0, 4);
      final c = point('c', -4, 0);
      final first = AngleBisectorLine(id: 'x', arm1: a, vertex: v, arm2: b);
      final swapped = AngleBisectorLine(id: 'y', arm1: b, vertex: v, arm2: a);
      final other = AngleBisectorLine(id: 'z', arm1: a, vertex: v, arm2: c);
      final elsewhere = AngleBisectorLine(id: 'w', arm1: v, vertex: a, arm2: b);

      expectCoincident(first, swapped, true);
      expectCoincident(first, other, false);
      expectCoincident(first, elsewhere, false);
    });

    test('pointsOnCarrier reads across the copies, in construction order', () {
      // `tangent-chord.rgl`'s shape: two tangents at a point on the
      // circle, a point glued to the second. Named through the first,
      // the line still carries the glued point.
      final centre = point('o', 0, 0);
      final rim = point('r', 1, 0);
      final circle = CircleCenterPoint(id: 'k', center: centre, onCircle: rim);
      final c = TangentLine(id: 'c', point: rim, circle: circle, branch: 0);
      final d = TangentLine(id: 'd', point: rim, circle: circle, branch: 1);
      final e = PointOnObject(id: 'e', curve: d, parameter: 2.0);
      final stray = point('s', 5, 5);
      final objects = [centre, rim, circle, c, d, e, stray];

      expect(pointsOnCarrier(objects, c), [rim, e]);
      expect(pointsOnCarrier(objects, d), [rim, e]);
      // A circle has no line twins, and reads as before.
      expect(pointsOnCarrier(objects, circle), [rim]);
    });
  });
}
