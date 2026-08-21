import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/incenter.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';

void main() {
  Construction build(Iterable<GeoObject> objects) {
    final construction = Construction();
    for (final object in objects) {
      construction.add(object);
    }
    return construction;
  }

  /// Extracts the hypotheses and pins the table's whole point: every
  /// emitted statement is a *theorem* of the construction, so every one
  /// must survive the filter's perturbations. A kind whose emission
  /// fails here is asserting something its construction does not
  /// guarantee — the unsoundness the extraction exists to never commit.
  List<Predicate> extractAndPin(List<GeoObject> objects) {
    final construction = build(objects);
    final emitted = hypotheses(construction.objects);
    final filter = DiagramFilter.probe(construction.objects);
    for (final predicate in emitted) {
      expect(
        filter.holds(predicate),
        isTrue,
        reason:
            '$predicate is emitted as a hypothesis but is not a '
            'theorem of the construction',
      );
    }
    return emitted;
  }

  /// Spelling-blind membership: the emission and the expectation may
  /// name the same statement in different argument orders.
  Matcher hasFact(Predicate expected) =>
      contains(predicate((Predicate p) => Fact.of(p) == Fact.of(expected)));

  group('incidence-shaped hypotheses', () {
    test('three points a line kind puts on one line are collinear', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(5, 3));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final glued = PointOnObject(id: 'p', curve: line, parameter: 2.0);

      final emitted = extractAndPin([a, b, line, glued]);

      expect(emitted, hasFact(Predicate(PredicateKind.coll, [a, b, glued])));
    });

    test('four points on a circle are concyclic, and radii are congruent', () {
      final o = FreePoint(id: 'o', position: const Vec2(1, 1));
      final rim = FreePoint(id: 'r', position: const Vec2(4, 1));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final p1 = PointOnObject(id: 'p1', curve: circle, parameter: 0.7);
      final p2 = PointOnObject(id: 'p2', curve: circle, parameter: 2.1);
      final p3 = PointOnObject(id: 'p3', curve: circle, parameter: 4.4);

      final emitted = extractAndPin([o, rim, circle, p1, p2, p3]);

      expect(
        emitted,
        hasFact(Predicate(PredicateKind.cyclic, [rim, p1, p2, p3])),
      );
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, rim, o, p1])));
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, p2, o, p3])));
    });

    test('a conic-valued kind emits no cyclic — a conic is not a circle', () {
      final points = [
        FreePoint(id: 'a', position: const Vec2(0, 0)),
        FreePoint(id: 'b', position: const Vec2(4, 0)),
        FreePoint(id: 'c', position: const Vec2(5, 2)),
        FreePoint(id: 'd', position: const Vec2(2, 4)),
        FreePoint(id: 'e', position: const Vec2(-1, 2)),
      ];
      final conic = FivePointConic(id: 'k', points: points);

      final emitted = hypotheses(build([...points, conic]).objects);

      expect(
        emitted.where((p) => p.kind == PredicateKind.cyclic),
        isEmpty,
        reason: 'five generic points lie on a conic, not on a circle',
      );
    });
  });

  group('point kinds', () {
    test('Midpoint emits midp', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 2));
      final m = Midpoint(id: 'm', point1: a, point2: b);

      final emitted = extractAndPin([a, b, m]);

      expect(emitted, hasFact(Predicate(PredicateKind.midp, [m, a, b])));
    });

    test('SegmentRatioPoint is collinear; the exact half is midp', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 2));
      final third = SegmentRatioPoint(
        id: 't',
        point1: a,
        point2: b,
        ratio: 0.25,
      );
      final half = SegmentRatioPoint(id: 'h', point1: a, point2: b, ratio: 0.5);

      final emitted = extractAndPin([a, b, third, half]);

      expect(emitted, hasFact(Predicate(PredicateKind.coll, [third, a, b])));
      expect(emitted, hasFact(Predicate(PredicateKind.midp, [half, a, b])));
      expect(
        emitted,
        isNot(hasFact(Predicate(PredicateKind.midp, [third, a, b]))),
        reason: 'a quarter point is not a midpoint',
      );
    });

    test('HomotheticPoint is collinear with its center and source', () {
      final p = FreePoint(id: 'p', position: const Vec2(3, 1));
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final h = HomotheticPoint(id: 'h', point: p, center: o, ratio: 2.5);

      final emitted = extractAndPin([p, o, h]);

      expect(emitted, hasFact(Predicate(PredicateKind.coll, [h, o, p])));
    });

    test('HarmonicConjugatePoint emits coll and the harmonic eqratio', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      // The third point must be *structurally* on the join, or the
      // conjugate goes undefined the moment a probe perturbs the rig.
      final c = PointOnObject(id: 'c', curve: line, parameter: 1.0);
      final d = HarmonicConjugatePoint(
        id: 'd',
        point1: a,
        point2: b,
        point3: c,
      );

      final emitted = extractAndPin([a, b, line, c, d]);

      expect(emitted, hasFact(Predicate(PredicateKind.coll, [d, a, b])));
      expect(
        emitted,
        hasFact(Predicate(PredicateKind.eqratio, [a, c, c, b, a, d, d, b])),
      );
    });

    test('the reflection family emits its congruences', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(5, 1));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final s = FreePoint(id: 's', position: const Vec2(2, 4));
      final r = ReflectedPoint(id: 'r', point: s, mirror: mirror);
      final o = FreePoint(id: 'o', position: const Vec2(7, 7));
      final central = CentralReflectionPoint(id: 'cr', point: s, center: o);
      final rotated = RotatedPoint(id: 'rot', point: s, center: o, angle: 0.7);
      final from = FreePoint(id: 'f', position: const Vec2(1, 1));
      final to = FreePoint(id: 't', position: const Vec2(3, 2));
      final translated = TranslatedPoint(
        id: 'tr',
        point: s,
        vectorFrom: from,
        vectorTo: to,
      );

      final emitted = extractAndPin([
        a,
        b,
        mirror,
        s,
        r,
        o,
        central,
        rotated,
        from,
        to,
        translated,
      ]);

      // Mirror reflection: every construction point on the mirror is
      // equidistant from source and image, and the segment is
      // perpendicular to the mirror.
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [a, s, a, r])));
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [b, s, b, r])));
      expect(emitted, hasFact(Predicate(PredicateKind.perp, [s, r, a, b])));
      // Central reflection: the center is the midpoint.
      expect(emitted, hasFact(Predicate(PredicateKind.midp, [o, s, central])));
      // Rotation preserves the distance to the center.
      expect(
        emitted,
        hasFact(Predicate(PredicateKind.cong, [o, s, o, rotated])),
      );
      // Translation: image displacement is the vector, in length and
      // direction.
      expect(
        emitted,
        hasFact(Predicate(PredicateKind.cong, [s, translated, from, to])),
      );
      expect(
        emitted,
        hasFact(Predicate(PredicateKind.para, [s, translated, from, to])),
      );
    });

    test('ProjectionPoint is on the line and the drop is perpendicular', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(5, 1));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final s = FreePoint(id: 's', position: const Vec2(2, 4));
      final f = ProjectionPoint(id: 'f', point: s, line: line);

      final emitted = extractAndPin([a, b, line, s, f]);

      expect(emitted, hasFact(Predicate(PredicateKind.coll, [f, a, b])));
      expect(emitted, hasFact(Predicate(PredicateKind.perp, [s, f, a, b])));
    });

    test('triangle centers emit their defining relations', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      final h = Orthocenter(id: 'h', vertex1: a, vertex2: b, vertex3: c);
      final i = Incenter(id: 'i', vertex1: a, vertex2: b, vertex3: c);

      final emitted = extractAndPin([a, b, c, o, h, i]);

      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, a, o, b])));
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, a, o, c])));
      expect(emitted, hasFact(Predicate(PredicateKind.perp, [h, a, b, c])));
      expect(emitted, hasFact(Predicate(PredicateKind.perp, [h, b, a, c])));
      expect(emitted, hasFact(Predicate(PredicateKind.perp, [h, c, a, b])));
      expect(
        emitted,
        hasFact(Predicate(PredicateKind.eqangle, [a, b, a, i, a, i, a, c])),
      );
    });

    test('CircleCenter of a three-point circle knows its radii', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      final o = CircleCenter(id: 'o', circle: circle);

      final emitted = extractAndPin([a, b, c, circle, o]);

      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, a, o, b])));
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, b, o, c])));
    });
  });

  group('line kinds', () {
    test('ParallelLine emits para through witness pairs', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final l = ParallelLine(id: 'l', through: c, reference: ab);
      final glued = PointOnObject(id: 'p', curve: l, parameter: 2.0);

      final emitted = extractAndPin([a, b, ab, c, l, glued]);

      expect(emitted, hasFact(Predicate(PredicateKind.para, [c, glued, a, b])));
    });

    test('a ParallelLine with one known point emits nothing about it', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final l = ParallelLine(id: 'l', through: c, reference: ab);

      final emitted = extractAndPin([a, b, ab, c, l]);

      expect(
        emitted.where((p) => p.kind == PredicateKind.para),
        isEmpty,
        reason: 'DD has no name for a line with one point on it',
      );
    });

    test('PerpendicularLine emits perp through witness pairs', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final l = PerpendicularLine(id: 'l', through: c, reference: ab);
      final glued = PointOnObject(id: 'p', curve: l, parameter: 2.0);

      final emitted = extractAndPin([a, b, ab, c, l, glued]);

      expect(emitted, hasFact(Predicate(PredicateKind.perp, [c, glued, a, b])));
    });

    test(
      'PerpendicularBisectorLine emits cong per point and perp per pair',
      () {
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(6, 2));
        final bisector = PerpendicularBisectorLine(
          id: 'pb',
          point1: a,
          point2: b,
        );
        // The midpoint of exactly (a, b) is on the bisector by the Phase
        // 44b derived incidence — it is the second witness point.
        final m = Midpoint(id: 'm', point1: a, point2: b);
        final glued = PointOnObject(id: 'p', curve: bisector, parameter: 3.0);

        final emitted = extractAndPin([a, b, bisector, m, glued]);

        expect(
          emitted,
          hasFact(Predicate(PredicateKind.cong, [glued, a, glued, b])),
        );
        expect(emitted, hasFact(Predicate(PredicateKind.cong, [m, a, m, b])));
        expect(
          emitted,
          hasFact(Predicate(PredicateKind.perp, [m, glued, a, b])),
        );
      },
    );

    test('AngleBisectorLine emits eqangle for each point on it', () {
      final arm1 = FreePoint(id: 'p', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final arm2 = FreePoint(id: 'q', position: const Vec2(0, 4));
      final bisector = AngleBisectorLine(
        id: 'bi',
        arm1: arm1,
        vertex: v,
        arm2: arm2,
      );
      final glued = PointOnObject(id: 'g', curve: bisector, parameter: 2.0);

      final emitted = extractAndPin([arm1, v, arm2, bisector, glued]);

      expect(
        emitted,
        hasFact(
          Predicate(PredicateKind.eqangle, [
            v,
            arm1,
            v,
            glued,
            v,
            glued,
            v,
            arm2,
          ]),
        ),
      );
    });

    test('TwoLineBisectorLine emits eqangle on either branch', () {
      for (final branch in [0, 1]) {
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(4, 0));
        final c = FreePoint(id: 'c', position: const Vec2(1, 3));
        final line1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
        final line2 = LineThroughTwoPoints(id: 'l2', point1: a, point2: c);
        final bisector = TwoLineBisectorLine(
          id: 'bi',
          line1: line1,
          line2: line2,
          branch: branch,
        );
        // The shared defining point a is the crossing, on the bisector
        // by derived incidence; the glued point is the second witness.
        final glued = PointOnObject(id: 'g', curve: bisector, parameter: 2.0);

        final emitted = extractAndPin([a, b, c, line1, line2, bisector, glued]);

        expect(
          emitted,
          hasFact(
            Predicate(PredicateKind.eqangle, [a, b, a, glued, a, glued, a, c]),
          ),
          reason:
              'branch $branch — mod π the external bisector satisfies '
              'the same eqangle',
        );
      }
    });
  });

  group('circle kinds', () {
    test('DiameterCircle emits Thales for every other point on it', () {
      final p = FreePoint(id: 'p', position: const Vec2(0, 0));
      final q = FreePoint(id: 'q', position: const Vec2(6, 0));
      final circle = DiameterCircle(id: 'c', point1: p, point2: q);
      final x = PointOnObject(id: 'x', curve: circle, parameter: 1.0);

      final emitted = extractAndPin([p, q, circle, x]);

      expect(emitted, hasFact(Predicate(PredicateKind.perp, [x, p, x, q])));
    });

    test('CompassCircle transfers its radius as cong', () {
      final p = FreePoint(id: 'p', position: const Vec2(0, 0));
      final q = FreePoint(id: 'q', position: const Vec2(3, 1));
      final o = FreePoint(id: 'o', position: const Vec2(7, 2));
      final circle = CompassCircle(
        id: 'c',
        radiusPoint1: p,
        radiusPoint2: q,
        center: o,
      );
      final x = PointOnObject(id: 'x', curve: circle, parameter: 1.0);

      final emitted = extractAndPin([p, q, o, circle, x]);

      expect(emitted, hasFact(Predicate(PredicateKind.cong, [o, x, p, q])));
    });
  });

  group('contract', () {
    test('emission order is deterministic', () {
      List<String> emit() {
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(6, 0));
        final c = FreePoint(id: 'c', position: const Vec2(2, 5));
        final m = Midpoint(id: 'm', point1: a, point2: b);
        final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
        final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
        final l = ParallelLine(id: 'l', through: c, reference: ab);
        final g = PointOnObject(id: 'g', curve: l, parameter: 1.0);
        final objects = build([a, b, c, m, o, ab, l, g]).objects;
        return [for (final p in hypotheses(objects)) '$p'];
      }

      expect(emit(), emit());
    });

    test('a proper absolute is refused', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      expect(
        () => hypotheses(build([a]).objects, absolute: Absolute.hyperbolic),
        throwsArgumentError,
      );
    });
  });
}
