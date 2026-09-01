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
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/radical_axis_line.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/rational.dart';

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
    test('Midpoint emits midp, and its 1:2 as an rconst', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 2));
      final m = Midpoint(id: 'm', point1: a, point2: b);

      final emitted = extractAndPin([a, b, m]);

      expect(emitted, hasFact(Predicate(PredicateKind.midp, [m, a, b])));
      // Newclid's R51 as hypothesis emission (Phase 181): the log
      // algebra cannot derive |am|/|ab| = ½ from cong + coll, and the
      // construction guarantees it.
      expect(
        emitted,
        hasFact(
          Predicate(PredicateKind.rconst, [
            a,
            m,
            a,
            b,
          ], value: Rational.fromInts(1, 2)),
        ),
      );
    });

    test('SegmentRatioPoint is collinear; the exact half is midp '
        'and rconst ½', () {
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
        hasFact(
          Predicate(PredicateKind.rconst, [
            a,
            half,
            a,
            b,
          ], value: Rational.fromInts(1, 2)),
        ),
      );
      expect(
        emitted,
        isNot(hasFact(Predicate(PredicateKind.midp, [third, a, b]))),
        reason: 'a quarter point is not a midpoint',
      );
      expect(
        emitted.where((p) => p.kind == PredicateKind.rconst).length,
        1,
        reason:
            'a param ratio is not a stated rational — only the '
            'exact half speaks',
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
      // Central reflection: the center is the midpoint, with its 1:2.
      expect(emitted, hasFact(Predicate(PredicateKind.midp, [o, s, central])));
      expect(
        emitted,
        hasFact(
          Predicate(PredicateKind.rconst, [
            s,
            o,
            s,
            central,
          ], value: Rational.fromInts(1, 2)),
        ),
      );
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

    test('a translated point closes a parallelogram — both pairs of '
        'sides (Phase 173)', () {
      final s = FreePoint(id: 's', position: const Vec2(2, 4));
      final from = FreePoint(id: 'f', position: const Vec2(1, 1));
      final to = FreePoint(id: 't', position: const Vec2(3, 2));
      final t = TranslatedPoint(
        id: 'tr',
        point: s,
        vectorFrom: from,
        vectorTo: to,
      );

      final emitted = extractAndPin([s, from, to, t]);

      // The displacement, which the kind already stated.
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [s, t, from, to])));
      expect(emitted, hasFact(Predicate(PredicateKind.para, [s, t, from, to])));
      // The other pair of sides — the same tie rearranged, since
      // `t - s == to - from` is `from - s == to - t`. Newclid's
      // `parallelogram` states all four; 56 of the 121 hypotheses Phase
      // 173 found the corpus's constructions guarantee and the runs
      // never had were these.
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [s, from, t, to])));
      expect(emitted, hasFact(Predicate(PredicateKind.para, [s, from, t, to])));
    });

    test('the incentre is equidistant from its touch points '
        '(Phase 173)', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 4));
      final i = Incenter(id: 'i', vertex1: a, vertex2: b, vertex3: c);
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final bc = LineThroughTwoPoints(id: 'bc', point1: b, point2: c);
      final ca = LineThroughTwoPoints(id: 'ca', point1: c, point2: a);
      final z = ProjectionPoint(id: 'z', point: i, line: ab);
      final x = ProjectionPoint(id: 'x', point: i, line: bc);
      final y = ProjectionPoint(id: 'y', point: i, line: ca);

      final emitted = extractAndPin([a, b, c, i, ab, bc, ca, z, x, y]);

      // The chain, in the construction's own order — `cong(i,z,i,y)`
      // follows from these two and is deliberately not emitted, which
      // is the chain Newclid's `incenter2` states.
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [i, z, i, x])));
      expect(emitted, hasFact(Predicate(PredicateKind.cong, [i, x, i, y])));
    });

    test('a foot of the incentre on a line that is not a side of its '
        'triangle says nothing', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 4));
      final d = FreePoint(id: 'd', position: const Vec2(5, 5));
      final i = Incenter(id: 'i', vertex1: a, vertex2: b, vertex3: c);
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final ad = LineThroughTwoPoints(id: 'ad', point1: a, point2: d);
      final z = ProjectionPoint(id: 'z', point: i, line: ab);
      final w = ProjectionPoint(id: 'w', point: i, line: ad);

      final emitted = extractAndPin([a, b, c, d, i, ab, ad, z, w]);

      // `ad` carries one vertex, so `w` is not a touch point and the
      // inradius argument does not reach it — a distance that is
      // simply not equal. The structural test is what refuses it; the
      // filter would refuse it too, but only after the claim was made.
      expect(
        emitted,
        isNot(hasFact(Predicate(PredicateKind.cong, [i, z, i, w]))),
      );
      expect(
        emitted,
        isNot(hasFact(Predicate(PredicateKind.cong, [i, w, i, z]))),
      );
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
    test('a coll whose points sit on two copies of one line is emitted '
        '(Phase 164)', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final segment = Segment(id: 'ab', point1: a, point2: b);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final c = PointOnObject(id: 'c', curve: line, parameter: 2.0);
      final facts = hypotheses([a, b, segment, line, c]);

      expect(facts, hasFact(Predicate(PredicateKind.coll, [a, b, c])));
    });

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

  /// Phase 155. `TangentLine` contributed nothing and was not on the
  /// documented list of kinds that contribute nothing deliberately,
  /// which is how the gap should be read. The touch point is computed
  /// inside `recompute` and is not a `GeoPoint`, so the emission waits
  /// for the figure to name one — and a point on both the tangent and
  /// its circle *is* the touch point, since a tangent meets its circle
  /// exactly once.
  group('the circle helpers (Phase 159 made them public)', () {
    test('circleCentre: structural, else a drawn CircleCenter, else null', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(3, 0));
      final byCentre = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      expect(circleCentre(byCentre, [o, rim, byCentre]), same(o));

      final a = FreePoint(id: 'a', position: const Vec2(3, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 3));
      final c = FreePoint(id: 'c2', position: const Vec2(-3, 0));
      final byPoints = ThreePointCircle(
        id: 'k',
        point1: a,
        point2: b,
        point3: c,
      );
      expect(circleCentre(byPoints, [a, b, c, byPoints]), isNull);
      final drawn = CircleCenter(id: 'd', circle: byPoints);
      expect(circleCentre(byPoints, [a, b, c, byPoints, drawn]), same(drawn));
    });

    test('isCircleByConstruction: the three conic kinds are not', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(3, 0));
      expect(
        isCircleByConstruction(
          CircleCenterPoint(id: 'c', center: o, onCircle: rim),
        ),
        isTrue,
      );
      final points = [
        FreePoint(id: 'a', position: const Vec2(0, 0)),
        FreePoint(id: 'b', position: const Vec2(4, 0)),
        FreePoint(id: 'c', position: const Vec2(1, 3)),
        FreePoint(id: 'd', position: const Vec2(5, 4)),
        FreePoint(id: 'e', position: const Vec2(-1, 2)),
      ];
      expect(
        isCircleByConstruction(FivePointConic(id: 'k', points: points)),
        isFalse,
      );
    });
  });

  group('TangentLine', () {
    test('the drawn touch point makes the radius perpendicular', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final p = FreePoint(id: 'p', position: const Vec2(9, 0));
      final tangent = TangentLine(id: 't', point: p, circle: circle, branch: 0);
      final touch = IntersectionPoint(
        id: 'k',
        curve1: tangent,
        curve2: circle,
        branchIndex: 0,
      );

      final emitted = extractAndPin([o, rim, circle, p, tangent, touch]);

      expect(
        emitted,
        hasFact(Predicate(PredicateKind.perp, [o, touch, touch, p])),
      );
    });

    test('no named touch point, nothing said — the silence is the '
        'honest answer, not the old gap', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final p = FreePoint(id: 'p', position: const Vec2(9, 0));
      final tangent = TangentLine(id: 't', point: p, circle: circle, branch: 0);

      final emitted = extractAndPin([o, rim, circle, p, tangent]);

      // The circle's own radius `cong` is still there; what is absent
      // is any statement *about the tangent*.
      expect(
        emitted.where(
          (e) =>
              e.kind == PredicateKind.perp &&
              e.points.any((GeoPoint a) => identical(a, p)),
        ),
        isEmpty,
      );
    });

    test('a circle with no centre of its own borrows the drawn one', () {
      final a = FreePoint(id: 'a', position: const Vec2(3, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 3));
      final c = FreePoint(id: 'c', position: const Vec2(-3, 0));
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      final o = CircleCenter(id: 'o', circle: circle);
      final p = FreePoint(id: 'p', position: const Vec2(9, 4));
      final tangent = TangentLine(id: 't', point: p, circle: circle, branch: 0);
      final touch = IntersectionPoint(
        id: 'j',
        curve1: tangent,
        curve2: circle,
        branchIndex: 0,
      );

      final emitted = extractAndPin([a, b, c, circle, o, p, tangent, touch]);

      expect(
        emitted,
        hasFact(Predicate(PredicateKind.perp, [o, touch, touch, p])),
      );
    });

    test('a tangent to a conic says nothing — the theorem is about '
        'circles', () {
      final points = [
        FreePoint(id: 'a', position: const Vec2(-4, 0)),
        FreePoint(id: 'b', position: const Vec2(4, 0)),
        FreePoint(id: 'c', position: const Vec2(0, 2)),
        FreePoint(id: 'd', position: const Vec2(0, -2)),
        FreePoint(id: 'e', position: const Vec2(3, 1.3228756555)),
      ];
      final conic = FivePointConic(id: 'k', points: points);
      final o = CircleCenter(id: 'o', circle: conic);
      final p = FreePoint(id: 'p', position: const Vec2(9, 5));
      final tangent = TangentLine(id: 't', point: p, circle: conic, branch: 0);
      final touch = IntersectionPoint(
        id: 'j',
        curve1: tangent,
        curve2: conic,
        branchIndex: 0,
      );

      final emitted = hypotheses(
        build([...points, conic, o, p, tangent, touch]).objects,
      );

      // The tangent to an ellipse at `T` is not perpendicular to the
      // join of `T` with the centre, so an unguarded emission would be
      // false about a conic that merely looks round.
      expect(
        emitted.where(
          (e) =>
              e.kind == PredicateKind.perp &&
              e.points.any((GeoPoint a) => identical(a, touch)),
        ),
        isEmpty,
      );
    });
  });

  /// Phase 155's audit. Neither kind had ever been assessed for
  /// emissions the way the circle kinds were, and the point of the
  /// "deliberately nothing" list is that silence is a decision on the
  /// record. Both turned out to contribute, so neither joins it.
  group('PolarLine', () {
    test('the polar is perpendicular to the centre-pole join', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final pole = FreePoint(id: 'p', position: const Vec2(7, 2));
      final polar = PolarLine(id: 'l', point: pole, circle: circle);
      final x = PointOnObject(id: 'x', curve: polar, parameter: 0.5);
      final y = PointOnObject(id: 'y', curve: polar, parameter: 2.5);

      final emitted = extractAndPin([o, rim, circle, pole, polar, x, y]);

      expect(emitted, hasFact(Predicate(PredicateKind.perp, [o, pole, x, y])));
    });

    test('La Hire: a point of contact on the polar is perpendicular to '
        'the radius, with the *pole* as the tangent\'s other point', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final pole = FreePoint(id: 'p', position: const Vec2(8, 0));
      final polar = PolarLine(id: 'l', point: pole, circle: circle);
      final touch = IntersectionPoint(
        id: 'k',
        curve1: polar,
        curve2: circle,
        branchIndex: 0,
      );

      final emitted = extractAndPin([o, rim, circle, pole, polar, touch]);

      expect(
        emitted,
        hasFact(Predicate(PredicateKind.perp, [o, touch, touch, pole])),
      );
    });
  });

  group('RadicalAxisLine', () {
    test('the axis is perpendicular to the line of centres', () {
      final o1 = FreePoint(id: 'o1', position: const Vec2(0, 0));
      final r1 = FreePoint(id: 'r1', position: const Vec2(4, 0));
      final c1 = CircleCenterPoint(id: 'c1', center: o1, onCircle: r1);
      final o2 = FreePoint(id: 'o2', position: const Vec2(5, 1));
      final r2 = FreePoint(id: 'r2', position: const Vec2(8, 1));
      final c2 = CircleCenterPoint(id: 'c2', center: o2, onCircle: r2);
      final axis = RadicalAxisLine(id: 'ax', circle1: c1, circle2: c2);
      final x = PointOnObject(id: 'x', curve: axis, parameter: 0.5);
      final y = PointOnObject(id: 'y', curve: axis, parameter: 3.0);

      final emitted = extractAndPin([o1, r1, c1, o2, r2, c2, axis, x, y]);

      expect(emitted, hasFact(Predicate(PredicateKind.perp, [o1, o2, x, y])));
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
