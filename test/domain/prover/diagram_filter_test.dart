import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/predicate.dart';

void main() {
  Construction build(Iterable<GeoObject> objects) {
    final construction = Construction();
    for (final object in objects) {
      construction.add(object);
    }
    return construction;
  }

  group('DiagramFilter.holds', () {
    test('keeps the Varignon parallel — a theorem of the construction', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 1));
      final c = FreePoint(id: 'c', position: const Vec2(7, 5));
      final d = FreePoint(id: 'd', position: const Vec2(1, 4));
      final mAB = Midpoint(id: 'mab', point1: a, point2: b);
      final mBC = Midpoint(id: 'mbc', point1: b, point2: c);
      final mCD = Midpoint(id: 'mcd', point1: c, point2: d);
      final mDA = Midpoint(id: 'mda', point1: d, point2: a);
      final construction = build([a, b, c, d, mAB, mBC, mCD, mDA]);

      final filter = DiagramFilter.probe(construction.objects);

      // Both midlines are parallel to the diagonal AC, at every
      // configuration of the four free corners.
      expect(
        filter.holds(Predicate(PredicateKind.para, [mAB, mBC, mDA, mCD])),
        isTrue,
      );
      // And their spans are congruent — each is half of AC.
      expect(
        filter.holds(Predicate(PredicateKind.cong, [mAB, mBC, mDA, mCD])),
        isTrue,
      );
    });

    test('kills a coincidence the diagram merely happens to satisfy', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      // A free point *placed* exactly on the midpoint — true in this
      // configuration, in no other.
      final fake = FreePoint(id: 'fake', position: const Vec2(2, 1));
      final construction = build([a, b, fake]);

      final filter = DiagramFilter.probe(construction.objects);

      final claim = Predicate(PredicateKind.midp, [fake, a, b]);
      expect(claim.holdsNow, isTrue, reason: 'true in the base diagram');
      expect(filter.holds(claim), isFalse, reason: 'an accident, not a fact');
    });

    test('a glued point stays collinear while its parameter perturbs', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(5, 3));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final glued = PointOnObject(id: 'p', curve: line, parameter: 2.0);
      final construction = build([a, b, line, glued]);

      final filter = DiagramFilter.probe(construction.objects);

      expect(
        filter.holds(Predicate(PredicateKind.coll, [a, b, glued])),
        isTrue,
      );
      // The same three points are not concyclic or perpendicular —
      // sanity that the filter does not answer true indiscriminately.
      expect(
        filter.holds(Predicate(PredicateKind.perp, [a, b, a, glued])),
        isFalse,
      );
    });

    test('two glued radii of one circle are congruent', () {
      final center = FreePoint(id: 'o', position: const Vec2(1, 1));
      final rim = FreePoint(id: 'r', position: const Vec2(4, 1));
      final circle = CircleCenterPoint(id: 'c', center: center, onCircle: rim);
      final p1 = PointOnObject(id: 'p1', curve: circle, parameter: 0.7);
      final p2 = PointOnObject(id: 'p2', curve: circle, parameter: 2.9);
      final construction = build([center, rim, circle, p1, p2]);

      final filter = DiagramFilter.probe(construction.objects);

      expect(
        filter.holds(Predicate(PredicateKind.cong, [center, p1, center, p2])),
        isTrue,
      );
      expect(
        filter.holds(Predicate(PredicateKind.cong, [center, p1, p1, p2])),
        isFalse,
      );
    });

    test('a point undefined in the diagram answers false, not a throw', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 2));
      final d = FreePoint(id: 'd', position: const Vec2(0, 5));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final p1 = ParallelLine(id: 'p1', through: c, reference: ab);
      final p2 = ParallelLine(id: 'p2', through: d, reference: ab);
      final never = IntersectionPoint(
        id: 'x',
        curve1: p1,
        curve2: p2,
        branchIndex: 0,
      );
      final construction = build([a, b, c, d, ab, p1, p2, never]);

      final filter = DiagramFilter.probe(construction.objects);

      expect(
        filter.holds(Predicate(PredicateKind.coll, [a, b, never])),
        isFalse,
      );
    });

    test('a predicate over a point outside the diagram throws', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final construction = build([a, b]);
      final outside = FreePoint(id: 'z', position: const Vec2(2, 0));

      final filter = DiagramFilter.probe(construction.objects);

      expect(
        () => filter.holds(Predicate(PredicateKind.coll, [a, b, outside])),
        throwsArgumentError,
      );
    });
  });

  group('DiagramFilter.probe', () {
    test('restores the construction bit-exactly', () {
      final a = FreePoint(id: 'a', position: const Vec2(0.1, 0.2));
      final b = FreePoint(id: 'b', position: const Vec2(5, 3));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final glued = PointOnObject(id: 'p', curve: line, parameter: 1.234);
      final m = Midpoint(id: 'm', point1: a, point2: glued);
      final construction = build([a, b, line, glued, m]);
      final before = {
        for (final object in construction.objects)
          if (object is GeoPoint) object: object.position,
      };
      final parameterBefore = glued.parameter;

      DiagramFilter.probe(construction.objects);

      for (final entry in before.entries) {
        expect(entry.key.position, entry.value, reason: entry.key.id);
      }
      expect(glued.parameter, parameterBefore);
    });

    test('restores with an undefined dependent in the graph', () {
      // The parallel to ab through a is *coincident* with ab, so their
      // intersection has no candidates in any configuration — the probe
      // loop runs over a permanently undefined dependent, and restore
      // must still bring the roots back.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final p1 = ParallelLine(id: 'p1', through: a, reference: ab);
      final never = IntersectionPoint(
        id: 'x',
        curve1: ab,
        curve2: p1,
        branchIndex: 0,
      );
      final construction = build([a, b, ab, p1, never]);
      final aBefore = a.position;
      final bBefore = b.position;

      DiagramFilter.probe(construction.objects);

      expect(a.position, aBefore);
      expect(b.position, bBefore);
    });

    test('a proper absolute is refused', () {
      final a = FreePoint(id: 'a', position: const Vec2(0.1, 0.2));
      final construction = build([a]);
      expect(
        () => DiagramFilter.probe(
          construction.objects,
          absolute: Absolute.hyperbolic,
        ),
        throwsArgumentError,
      );
    });

    test('probeCount sets the sampled configurations', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final construction = build([a]);
      final filter = DiagramFilter.probe(
        construction.objects,
        probeCount: 7,
        random: math.Random(1),
      );
      expect(filter.configurationCount, 8);
    });
  });
}
