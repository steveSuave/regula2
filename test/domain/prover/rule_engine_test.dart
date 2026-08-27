import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/rule.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  Construction build(Iterable<GeoObject> objects) {
    final construction = Construction();
    for (final object in objects) {
      construction.add(object);
    }
    return construction;
  }

  Rule ruleNamed(String name) =>
      ddCoreRules.firstWhere((rule) => rule.name == name);

  /// Not in the table since Phase 166 — the angle closure publishes
  /// every `para` it would store — but a perfectly good two-premise
  /// rule for exercising the engine, which is what the Varignon rig
  /// wants: a restricted table with no AR, where the theorem needs a
  /// join. Kept here rather than in `ddCoreRules` so the shipped table
  /// is exactly what the measurements say it is.
  final paraTransitive = Rule.parse(
    'para_transitive',
    'para(a,b,c,d) & para(c,d,e,f) => para(a,b,e,f)',
  );

  /// Seeds exactly [seeds], runs the single [ruleName] to quiescence,
  /// and expects [conclusion] derived by it. Every seed must itself be a
  /// *structural* truth of [objects] — asserted, so a bad rig fails as a
  /// bad rig and not as a rule defect — which in turn makes the
  /// conclusion's survival of the filter part of what is being tested:
  /// the rule under test is claimed to be a theorem, and a conclusion
  /// the filter rejects on a sound rig would expose it.
  void expectRuleFires({
    required String ruleName,
    required List<GeoObject> objects,
    required List<Predicate> seeds,
    required Predicate conclusion,
  }) {
    final construction = build(objects);
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    for (final seed in seeds) {
      expect(
        filter.holds(seed),
        isTrue,
        reason: 'bad rig: seed $seed is not structural',
      );
      database.addHypothesis(Fact.of(seed));
    }
    final engine = ProverEngine(
      database: database,
      filter: filter,
      rules: [ruleNamed(ruleName)],
    );
    engine.run();
    final fact = Fact.of(conclusion);
    expect(
      database.contains(fact),
      isTrue,
      reason: '$ruleName should derive $conclusion',
    );
    final derivation = database.derivationOf(fact)!;
    expect(derivation.rule, ruleName);
    expect(derivation.premises, isNotEmpty);
  }

  group('each rule fires on a rig where it is a theorem', () {
    test('coll_transitive', () {
      // Four points on one line: two colls sharing a pair force the
      // third. The rule that makes a *derived* line-fact re-spellable —
      // `hypotheses` emits every witness pair, but nothing else could.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final c = PointOnObject(id: 'c', curve: ab, parameter: 2);
      final d = PointOnObject(id: 'd', curve: ab, parameter: -3);
      expectRuleFires(
        ruleName: 'coll_transitive',
        objects: [a, b, ab, c, d],
        seeds: [
          Predicate(PredicateKind.coll, [a, b, c]),
          Predicate(PredicateKind.coll, [a, b, d]),
        ],
        conclusion: Predicate(PredicateKind.coll, [a, c, d]),
      );
    });

    test('perp_from_inclination', () {
      // Turn both arms of a right angle through the same angle and it
      // is still a right angle. `uv` is `pq` turned a quarter, `cd` is
      // `ab` turned a quarter, so ab makes the same angle with pq that
      // cd makes with uv — and ab ⟂ cd. Building both quarter turns as
      // `PerpendicularLine` is what makes the two premises structural:
      // they survive the filter's perturbation because the construction
      // holds them, not the coordinates.
      final p = FreePoint(id: 'p', position: const Vec2(0, 0));
      final q = FreePoint(id: 'q', position: const Vec2(5, 1));
      final pq = LineThroughTwoPoints(id: 'pq', point1: p, point2: q);
      final g = FreePoint(id: 'g', position: const Vec2(1, 4));
      final uvLine = PerpendicularLine(id: 'uvLine', through: g, reference: pq);
      final u = PointOnObject(id: 'u', curve: uvLine, parameter: 0);
      final v = PointOnObject(id: 'v', curve: uvLine, parameter: 3);
      final a = FreePoint(id: 'a', position: const Vec2(2, -3));
      final b = FreePoint(id: 'b', position: const Vec2(7, -2));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final h = FreePoint(id: 'h', position: const Vec2(-2, 2));
      final cdLine = PerpendicularLine(id: 'cdLine', through: h, reference: ab);
      final c = PointOnObject(id: 'c', curve: cdLine, parameter: 0);
      final d = PointOnObject(id: 'd', curve: cdLine, parameter: 2);
      expectRuleFires(
        ruleName: 'perp_from_inclination',
        objects: [p, q, pq, g, uvLine, u, v, a, b, ab, h, cdLine, c, d],
        seeds: [
          Predicate(PredicateKind.eqangle, [a, b, p, q, c, d, u, v]),
          Predicate(PredicateKind.perp, [p, q, u, v]),
        ],
        conclusion: Predicate(PredicateKind.perp, [a, b, c, d]),
      );
    });

    test('perp_coll', () {
      // A relation about a *line* survives being renamed by two other
      // points on it. Without this the run stalls holding the statement
      // it needs under the wrong name.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final e = PointOnObject(id: 'e', curve: ab, parameter: 2);
      final f = PointOnObject(id: 'f', curve: ab, parameter: -3);
      final g = FreePoint(id: 'g', position: const Vec2(1, 6));
      final perp = PerpendicularLine(id: 'perp', through: g, reference: ab);
      final c = PointOnObject(id: 'c', curve: perp, parameter: 0);
      final d = PointOnObject(id: 'd', curve: perp, parameter: 3);
      expectRuleFires(
        ruleName: 'perp_coll',
        objects: [a, b, ab, e, f, g, perp, c, d],
        seeds: [
          Predicate(PredicateKind.perp, [a, b, c, d]),
          Predicate(PredicateKind.coll, [a, b, e]),
          Predicate(PredicateKind.coll, [a, b, f]),
        ],
        conclusion: Predicate(PredicateKind.perp, [e, f, c, d]),
      );
    });

    test('orthocentre', () {
      // Two of a triangle's altitudes force the third. Stated on four
      // points because that is what it is — an orthocentric system, in
      // which each point is the orthocentre of the other three. The
      // `Orthocenter` object is here only to make the rig's geometry
      // real; the seeds are two of its three perpendicularities and the
      // conclusion is the one held back.
      final b = FreePoint(id: 'b', position: const Vec2(0, 0));
      final c = FreePoint(id: 'c', position: const Vec2(6, 1));
      final d = FreePoint(id: 'd', position: const Vec2(2, 5));
      final a = Orthocenter(id: 'a', vertex1: b, vertex2: c, vertex3: d);
      expectRuleFires(
        ruleName: 'orthocentre',
        objects: [b, c, d, a],
        seeds: [
          Predicate(PredicateKind.perp, [a, b, c, d]),
          Predicate(PredicateKind.perp, [a, c, b, d]),
        ],
        conclusion: Predicate(PredicateKind.perp, [a, d, b, c]),
      );
    });

    test('perp_perp_para and para_perp_perp', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final l1 = PerpendicularLine(id: 'l1', through: c, reference: ab);
      final d = PointOnObject(id: 'd', curve: l1, parameter: 2);
      final e = FreePoint(id: 'e', position: const Vec2(1, 6));
      final l2 = PerpendicularLine(id: 'l2', through: e, reference: l1);
      final f = PointOnObject(id: 'f', curve: l2, parameter: 2);
      final objects = [a, b, ab, c, l1, d, e, l2, f];
      expectRuleFires(
        ruleName: 'perp_perp_para',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.perp, [c, d, a, b]),
          Predicate(PredicateKind.perp, [e, f, c, d]),
        ],
        conclusion: Predicate(PredicateKind.para, [e, f, a, b]),
      );
      expectRuleFires(
        ruleName: 'para_perp_perp',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.para, [e, f, a, b]),
          Predicate(PredicateKind.perp, [a, b, c, d]),
        ],
        conclusion: Predicate(PredicateKind.perp, [e, f, c, d]),
      );
    });

    test('cong_transitive', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final r = FreePoint(id: 'r', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: r);
      final x = PointOnObject(id: 'x', curve: circle, parameter: 1.1);
      final y = PointOnObject(id: 'y', curve: circle, parameter: 2.7);
      expectRuleFires(
        ruleName: 'cong_transitive',
        objects: [o, r, circle, x, y],
        seeds: [
          Predicate(PredicateKind.cong, [o, r, o, x]),
          Predicate(PredicateKind.cong, [o, x, o, y]),
        ],
        conclusion: Predicate(PredicateKind.cong, [o, r, o, y]),
      );
    });

    test('tangent_chord', () {
      // The alternate-segment theorem: `t` on the circle about `o`, the
      // tangent at `t` carrying `p`, and `a`, `b` on the circle. The
      // angle between the tangent and the chord `ta` equals the
      // inscribed angle on `ta` at `b`.
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(5, 0));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final t = PointOnObject(id: 't', curve: circle, parameter: 2.0);
      final tangent = TangentLine(
        id: 'tan',
        point: t,
        circle: circle,
        branch: 0,
      );
      final p = PointOnObject(id: 'p', curve: tangent, parameter: 3.0);
      final a = PointOnObject(id: 'a', curve: circle, parameter: -1.2);
      final b = PointOnObject(id: 'b', curve: circle, parameter: 0.4);
      final objects = [o, rim, circle, t, tangent, p, a, b];

      // The mod-π spelling the filter accepts is the one the rule
      // concludes; the other reading of "tangent–chord equals inscribed"
      // — the same four segments with the second side's orientation
      // swapped — is false, and a rule concluding it would be caught
      // here by the screen, not by the pattern.
      final filter = DiagramFilter.probe(build(objects).objects);
      expect(
        filter.holds(
          Predicate(PredicateKind.eqangle, [t, p, t, a, b, a, b, t]),
        ),
        isFalse,
        reason: 'the swapped reading is not the theorem',
      );

      expectRuleFires(
        ruleName: 'tangent_chord',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.perp, [o, t, t, p]),
          Predicate(PredicateKind.cong, [o, t, o, a]),
          Predicate(PredicateKind.cong, [o, t, o, b]),
        ],
        conclusion: Predicate(PredicateKind.eqangle, [t, p, t, a, b, t, b, a]),
      );
    });

    test('eqratio_transitive', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final d = FreePoint(id: 'd', position: const Vec2(-3, 4));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final n = Midpoint(id: 'n', point1: a, point2: c);
      final p = Midpoint(id: 'p', point1: a, point2: d);
      expectRuleFires(
        ruleName: 'eqratio_transitive',
        objects: [a, b, c, d, m, n, p],
        seeds: [
          Predicate(PredicateKind.eqratio, [a, m, a, b, a, n, a, c]),
          Predicate(PredicateKind.eqratio, [a, n, a, c, a, p, a, d]),
        ],
        conclusion: Predicate(PredicateKind.eqratio, [a, m, a, b, a, p, a, d]),
      );
    });

    test('cyclic_fifth_point', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final r = FreePoint(id: 'r', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: r);
      final p1 = PointOnObject(id: 'p1', curve: circle, parameter: 0.9);
      final p2 = PointOnObject(id: 'p2', curve: circle, parameter: 2.0);
      final p3 = PointOnObject(id: 'p3', curve: circle, parameter: 3.4);
      final p4 = PointOnObject(id: 'p4', curve: circle, parameter: 5.1);
      expectRuleFires(
        ruleName: 'cyclic_fifth_point',
        objects: [o, r, circle, p1, p2, p3, p4],
        seeds: [
          Predicate(PredicateKind.cyclic, [r, p1, p2, p3]),
          Predicate(PredicateKind.cyclic, [r, p1, p2, p4]),
        ],
        conclusion: Predicate(PredicateKind.cyclic, [p1, p2, p3, p4]),
      );
    });

    test('equidistant_cyclic', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final r = FreePoint(id: 'r', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: r);
      final a = PointOnObject(id: 'a', curve: circle, parameter: 0.9);
      final b = PointOnObject(id: 'b', curve: circle, parameter: 2.0);
      final c = PointOnObject(id: 'c', curve: circle, parameter: 3.4);
      final d = PointOnObject(id: 'd', curve: circle, parameter: 5.1);
      expectRuleFires(
        ruleName: 'equidistant_cyclic',
        objects: [o, r, circle, a, b, c, d],
        seeds: [
          Predicate(PredicateKind.cong, [o, a, o, b]),
          Predicate(PredicateKind.cong, [o, b, o, c]),
          Predicate(PredicateKind.cong, [o, c, o, d]),
        ],
        conclusion: Predicate(PredicateKind.cyclic, [a, b, c, d]),
      );
    });

    test('inscribed_angle and its converse', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 3));
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      final q = PointOnObject(id: 'q', curve: circle, parameter: 2.2);
      final objects = [a, b, c, circle, q];
      expectRuleFires(
        ruleName: 'inscribed_angle',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.cyclic, [a, b, c, q]),
        ],
        conclusion: Predicate(PredicateKind.eqangle, [c, a, c, b, q, a, q, b]),
      );
      expectRuleFires(
        ruleName: 'inscribed_converse',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.eqangle, [c, a, c, b, q, a, q, b]),
        ],
        conclusion: Predicate(PredicateKind.cyclic, [a, b, c, q]),
      );
    });

    test('the midpoint rules', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 2));
      final c = FreePoint(id: 'c', position: const Vec2(1, 5));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final n = Midpoint(id: 'n', point1: a, point2: c);
      final objects = <GeoObject>[a, b, c, m, n];
      final midp = Predicate(PredicateKind.midp, [m, a, b]);
      expectRuleFires(
        ruleName: 'midp_coll',
        objects: objects,
        seeds: [midp],
        conclusion: Predicate(PredicateKind.coll, [m, a, b]),
      );
      expectRuleFires(
        ruleName: 'midp_cong',
        objects: objects,
        seeds: [midp],
        conclusion: Predicate(PredicateKind.cong, [m, a, m, b]),
      );
      expectRuleFires(
        ruleName: 'coll_cong_midp',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.coll, [m, a, b]),
          Predicate(PredicateKind.cong, [m, a, m, b]),
        ],
        conclusion: midp,
      );
      expectRuleFires(
        ruleName: 'midline_para',
        objects: objects,
        seeds: [
          midp,
          Predicate(PredicateKind.midp, [n, a, c]),
        ],
        conclusion: Predicate(PredicateKind.para, [m, n, b, c]),
      );
    });

    test('perp_bisector', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      final m = Midpoint(id: 'm', point1: a, point2: b);
      expectRuleFires(
        ruleName: 'perp_bisector',
        objects: [a, b, c, o, m],
        seeds: [
          Predicate(PredicateKind.cong, [o, a, o, b]),
          Predicate(PredicateKind.cong, [m, a, m, b]),
        ],
        conclusion: Predicate(PredicateKind.perp, [o, m, a, b]),
      );
    });

    test('isosceles_base and its converse', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final r = FreePoint(id: 'r', position: const Vec2(3, 0));
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: r);
      final x = PointOnObject(id: 'x', curve: circle, parameter: 1.3);
      final objects = [o, r, circle, x];
      expectRuleFires(
        ruleName: 'isosceles_base',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.cong, [o, r, o, x]),
        ],
        conclusion: Predicate(PredicateKind.eqangle, [o, r, r, x, r, x, o, x]),
      );
      expectRuleFires(
        ruleName: 'isosceles_converse',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.eqangle, [o, r, r, x, r, x, o, x]),
        ],
        conclusion: Predicate(PredicateKind.cong, [o, r, o, x]),
      );
    });

    test('intercept_eqratio', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final n = Midpoint(id: 'n', point1: a, point2: c);
      expectRuleFires(
        ruleName: 'intercept_eqratio',
        objects: [a, b, c, m, n],
        seeds: [
          Predicate(PredicateKind.coll, [a, m, b]),
          Predicate(PredicateKind.coll, [a, n, c]),
          Predicate(PredicateKind.para, [m, n, b, c]),
        ],
        conclusion: Predicate(PredicateKind.eqratio, [a, m, a, b, a, n, a, c]),
      );
    });

    test('the similarity criteria and their invariants', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final n = Midpoint(id: 'n', point1: a, point2: c);
      final objects = <GeoObject>[a, b, c, m, n];
      // Triangle (a, m, n) is the half-scale of (a, b, c).
      final simtri = Predicate(PredicateKind.simtri, [a, m, n, a, b, c]);
      expectRuleFires(
        ruleName: 'sss_simtri',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.eqratio, [a, m, a, n, a, b, a, c]),
          Predicate(PredicateKind.eqratio, [a, m, m, n, a, b, b, c]),
        ],
        conclusion: simtri,
      );
      expectRuleFires(
        ruleName: 'sas_simtri',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.eqratio, [a, m, a, n, a, b, a, c]),
          Predicate(PredicateKind.eqangle, [a, m, a, n, a, b, a, c]),
        ],
        conclusion: simtri,
      );
      expectRuleFires(
        ruleName: 'aa_simtri',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.eqangle, [a, m, a, n, a, b, a, c]),
          Predicate(PredicateKind.eqangle, [m, a, m, n, b, a, b, c]),
        ],
        conclusion: simtri,
      );
      expectRuleFires(
        ruleName: 'simtri_eqratio',
        objects: objects,
        seeds: [simtri],
        conclusion: Predicate(PredicateKind.eqratio, [a, m, a, n, a, b, a, c]),
      );
    });

    test('contri_cong and simtri_cong_contri', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final o = FreePoint(id: 'o', position: const Vec2(4, 4));
      final ra = CentralReflectionPoint(id: 'ra', point: a, center: o);
      final rb = CentralReflectionPoint(id: 'rb', point: b, center: o);
      final rc = CentralReflectionPoint(id: 'rc', point: c, center: o);
      final objects = <GeoObject>[a, b, c, o, ra, rb, rc];
      final contri = Predicate(PredicateKind.contri, [a, b, c, ra, rb, rc]);
      expectRuleFires(
        ruleName: 'contri_cong',
        objects: objects,
        seeds: [contri],
        conclusion: Predicate(PredicateKind.cong, [a, b, ra, rb]),
      );
      expectRuleFires(
        ruleName: 'simtri_cong_contri',
        objects: objects,
        seeds: [
          Predicate(PredicateKind.simtri, [a, b, c, ra, rb, rc]),
          Predicate(PredicateKind.cong, [a, b, ra, rb]),
        ],
        conclusion: contri,
      );
    });

    test('tangent_lengths', () {
      // Two tangents from one external point. Read as Pythagoras, not as
      // a circle theorem: the premises name no circle, only two right
      // angles at the points of contact and equal distances from `o`.
      // The rig draws the circle anyway so the geometry is real, and the
      // contacts come from the tangents the way a user would get them.
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(4, 0));
      final circle = CircleCenterPoint(id: 'c', center: o, onCircle: rim);
      final p = FreePoint(id: 'p', position: const Vec2(9, 5));
      final t1 = TangentLine(id: 't1', point: p, circle: circle, branch: 0);
      final t2 = TangentLine(id: 't2', point: p, circle: circle, branch: 1);
      final s = IntersectionPoint(
        id: 's',
        curve1: t1,
        curve2: circle,
        branchIndex: 0,
      );
      final t = IntersectionPoint(
        id: 't',
        curve1: t2,
        curve2: circle,
        branchIndex: 0,
      );
      expectRuleFires(
        ruleName: 'tangent_lengths',
        objects: [o, rim, circle, p, t1, t2, s, t],
        seeds: [
          Predicate(PredicateKind.perp, [o, s, s, p]),
          Predicate(PredicateKind.perp, [o, t, t, p]),
          Predicate(PredicateKind.cong, [o, s, o, t]),
        ],
        conclusion: Predicate(PredicateKind.cong, [p, s, p, t]),
      );
    });
  });

  group('the filter carries the side conditions', () {
    test('a degenerate instance fires and is screened, not stored', () {
      // All four segments of the isosceles-converse premise lie on one
      // line, so the eqangle is structurally true (0 = 0) — but the
      // conclusion |oa| = |ob| is false in every configuration. The DD
      // sources attach an ncoll side condition to rules like this; here
      // the screen refuses what the side condition names.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final o = PointOnObject(id: 'o', curve: line, parameter: 1);
      final construction = build([a, b, line, o]);
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      final premise = Predicate(PredicateKind.eqangle, [
        o,
        a,
        a,
        b,
        a,
        b,
        o,
        b,
      ]);
      expect(filter.holds(premise), isTrue, reason: 'collinear angles are 0=0');
      database.addHypothesis(Fact.of(premise));

      final engine = ProverEngine(
        database: database,
        filter: filter,
        rules: [ruleNamed('isosceles_converse')],
      );
      engine.run();

      expect(engine.applications, greaterThan(0), reason: 'the rule fired');
      expect(
        database.contains(Fact(PredicateKind.cong, [o, a, o, b])),
        isFalse,
        reason: 'the screen refused the degenerate conclusion',
      );
    });
  });

  group('the fixpoint', () {
    List<GeoObject> midlineRig() {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final mab = Midpoint(id: 'mab', point1: a, point2: b);
      final mbc = Midpoint(id: 'mbc', point1: b, point2: c);
      return [a, b, c, mab, mbc];
    }

    ProverEngine engineOver(Construction construction, {List<Rule>? rules}) {
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      return ProverEngine(database: database, filter: filter, rules: rules);
    }

    test('runs to quiescence and derives a depth-three chain', () {
      final construction = build(midlineRig());
      final engine = engineOver(construction);
      engine.run();
      expect(engine.isComplete, isTrue);
      expect(engine.step(100), 0, reason: 'quiescence is quiescence');

      final points = {
        for (final object in construction.objects)
          if (object is GeoPoint) object.id: object,
      };
      GeoPoint p(String id) => points[id]!;
      // midp → coll (twice) and midline_para feed intercept_eqratio: the
      // half-ratio at b, three rules deep from the two hypotheses.
      final chain = Fact(PredicateKind.eqratio, [
        p('b'),
        p('mab'),
        p('b'),
        p('a'),
        p('b'),
        p('mbc'),
        p('b'),
        p('c'),
      ]);
      expect(engine.database.contains(chain), isTrue);
      expect(engine.database.derivationOf(chain)!.rule, 'intercept_eqratio');
    });

    test('every premise is strictly older than its conclusion', () {
      final engine = engineOver(build(midlineRig()));
      engine.run();
      final order = <Fact, int>{};
      var index = 0;
      for (final fact in engine.database.facts) {
        order[fact] = index++;
      }
      for (final fact in engine.database.facts) {
        final derivation = engine.database.derivationOf(fact)!;
        for (final premise in derivation.premises) {
          expect(
            order[premise]!,
            lessThan(order[fact]!),
            reason: 'premise $premise of $fact',
          );
        }
      }
    });

    test('chunked at budget 1 reaches the identical database', () {
      final construction = build(midlineRig());
      final straight = engineOver(construction);
      straight.run();
      final chunked = engineOver(construction);
      while (!chunked.isComplete) {
        expect(chunked.step(1), lessThanOrEqualTo(1));
      }
      expect(chunked.applications, straight.applications);
      expect(
        [for (final fact in chunked.database.facts) '$fact'],
        [for (final fact in straight.database.facts) '$fact'],
      );
      expect(
        [
          for (final fact in chunked.database.facts)
            '${chunked.database.derivationOf(fact)}',
        ],
        [
          for (final fact in straight.database.facts)
            '${straight.database.derivationOf(fact)}',
        ],
      );
    });

    test('runChunked derives the straight result through the yield', () async {
      // On the VM the yield is the native arm (a zero timer); the
      // browser gate's prover_yield_web_test pins the web arm. Either
      // way the property is the same: chunking changes when the work
      // happens, never what it derives.
      final construction = build(midlineRig());
      final straight = engineOver(construction);
      straight.run();
      final chunked = engineOver(construction);
      final total = await chunked.runChunked(chunkBudget: 7);
      expect(chunked.isComplete, isTrue);
      expect(total, straight.applications);
      expect(
        [for (final fact in chunked.database.facts) '$fact'],
        [for (final fact in straight.database.facts) '$fact'],
      );
    });

    test('runChunked caps this call, and resumes where it stopped', () async {
      // Quiescence is not something an arbitrary document owes, so a
      // caller with a frame to keep needs a ceiling. What the cap must
      // not do is cost anything: the database it leaves is a fixpoint
      // *prefix*, and resuming reaches the straight run exactly.
      final construction = build(midlineRig());
      final straight = engineOver(construction);
      straight.run();
      expect(
        straight.applications,
        greaterThan(5),
        reason: 'the rig must be long enough for the cap to bind',
      );

      final capped = engineOver(construction);
      final performed = await capped.runChunked(
        chunkBudget: 1000,
        maxApplications: 5,
      );
      expect(performed, 5);
      expect(capped.isComplete, isFalse);

      final rest = await capped.runChunked(chunkBudget: 1000);
      expect(capped.isComplete, isTrue);
      expect(performed + rest, straight.applications);
      expect(
        [for (final fact in capped.database.facts) '$fact'],
        [for (final fact in straight.database.facts) '$fact'],
      );
    });

    test('a cap finer than the chunk still yields between chunks', () async {
      // The cap narrows the chunk rather than replacing it, so a run
      // capped below `chunkBudget` performs exactly the cap.
      final capped = engineOver(build(midlineRig()));
      expect(await capped.runChunked(chunkBudget: 2, maxApplications: 5), 5);
      expect(capped.applications, 5);
    });

    test('runChunked rejects a non-positive chunk and a negative cap', () {
      final engine = engineOver(build(midlineRig()));
      expect(
        () => engine.runChunked(chunkBudget: 0),
        throwsArgumentError,
        reason: 'a zero chunk would spin without ever performing work',
      );
      expect(
        () => engine.runChunked(chunkBudget: 1, maxApplications: -1),
        throwsArgumentError,
      );
    });

    test('a zero cap performs nothing and derives nothing new', () async {
      final engine = engineOver(build(midlineRig()));
      final before = engine.database.length;
      expect(await engine.runChunked(chunkBudget: 10, maxApplications: 0), 0);
      expect(engine.isComplete, isFalse);
      expect(engine.database.length, before);
    });

    test('stopWhen ends the run as soon as the goal is there', () async {
      // A goal-directed caller wants one fact, not quiescence — which is
      // what makes asking *cheaper* than deriving rather than more
      // expensive.
      final construction = build(midlineRig());
      final straight = engineOver(construction);
      straight.run();
      final goal = straight.database.facts.firstWhere(
        (fact) => !straight.database.derivationOf(fact)!.isHypothesis,
      );

      final asked = engineOver(construction);
      await asked.runChunked(
        chunkBudget: 1,
        stopWhen: () => asked.database.contains(goal),
      );

      expect(asked.database.contains(goal), isTrue);
      expect(asked.isComplete, isFalse);
      expect(
        asked.applications,
        lessThan(straight.applications),
        reason: 'stopping at the goal must actually save work',
      );
    });

    test('a goal already present costs no applications at all', () async {
      final engine = engineOver(build(midlineRig()));
      final hypothesis = engine.database.facts.first;

      expect(
        await engine.runChunked(
          chunkBudget: 1000,
          stopWhen: () => engine.database.contains(hypothesis),
        ),
        0,
      );
      expect(engine.applications, 0);
    });

    test('stopWhen never changes what a completed run derives', () async {
      final construction = build(midlineRig());
      final straight = engineOver(construction);
      straight.run();

      // A condition that never fires runs to quiescence unchanged.
      final asked = engineOver(construction);
      await asked.runChunked(chunkBudget: 3, stopWhen: () => false);

      expect(asked.isComplete, isTrue);
      expect(
        [for (final fact in asked.database.facts) '$fact'],
        [for (final fact in straight.database.facts) '$fact'],
      );
    });

    test('step respects its budget', () {
      final engine = engineOver(build(midlineRig()));
      expect(engine.step(5), lessThanOrEqualTo(5));
      expect(() => engine.step(-1), throwsArgumentError);
    });

    test('the JGEX document, once its auxiliary point is there', () async {
      // `test/fixtures/perp-true-unproved.rgl`: right angle at B, D the
      // midpoint of AB, E the midpoint of DB, the perpendicular to CA
      // through E meeting BC at F. `perp(C,D,D,F)` is a theorem.
      //
      // JGEX proves it and says how: it *constructs an auxiliary point*,
      // the midpoint of BC, and reasons from the midlines that appear.
      // Phase 150 followed that trace and found four rules missing here,
      // three of which this proof needs. Both halves are necessary — the
      // rules alone stall, and so does the point alone — and this test
      // pins both directions.
      final construction = decodeDocument(
        jsonDecode(
              File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
            )
            as Map<String, dynamic>,
      ).construction;
      GeoPoint named(String name) => construction.objects
          .whereType<GeoPoint>()
          .firstWhere((point) => point.attributes.name == name);
      final goal = Fact(PredicateKind.perp, [
        named('C'),
        named('D'),
        named('D'),
        named('F'),
      ]);

      final without = engineOver(construction);
      without.run();
      expect(
        without.database.contains(goal),
        isFalse,
        reason: 'the auxiliary point is not optional',
      );

      construction.add(
        Midpoint(id: 'aux', point1: named('B'), point2: named('C')),
      );
      final with_ = engineOver(construction);
      with_.run();

      expect(with_.database.contains(goal), isTrue);
      final proof = Proof.of(goal, with_.database);
      expect(
        proof.verify(),
        isEmpty,
        reason: 'a proof of a user theorem had better be a certificate',
      );
      expect(
        {for (final step in proof.deductions) step.rule},
        containsAll(<String>[
          'midline_para',
          'perp_coll',
          'coll_transitive',
          'orthocentre',
          'para_perp_perp',
        ]),
        reason: 'the four Phase 150 rules are what closed it',
      );
    });

    test('the Varignon parallelogram, via the transitive chain', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 1));
      final c = FreePoint(id: 'c', position: const Vec2(7, 5));
      final d = FreePoint(id: 'd', position: const Vec2(1, 4));
      final mab = Midpoint(id: 'mab', point1: a, point2: b);
      final mbc = Midpoint(id: 'mbc', point1: b, point2: c);
      final mcd = Midpoint(id: 'mcd', point1: c, point2: d);
      final mda = Midpoint(id: 'mda', point1: d, point2: a);
      final construction = build([a, b, c, d, mab, mbc, mcd, mda]);
      final engine = engineOver(
        construction,
        rules: [ruleNamed('midline_para'), paraTransitive],
      );
      engine.run();

      // Both midlines are parallel to the diagonal ac (midline_para),
      // and therefore to each other (para_transitive) — the theorem.
      final varignon = Fact(PredicateKind.para, [mab, mbc, mda, mcd]);
      expect(engine.database.contains(varignon), isTrue);
      expect(engine.database.derivationOf(varignon)!.rule, 'para_transitive');
    });
  });

  group('seedHypotheses', () {
    test('drops a hypothesis the filter refuses', () {
      // A reflected point whose source is glued to its own mirror: the
      // image coincides with the source, so the perpendicularity
      // hypothesis names a zero-length segment and evaluates false —
      // dropped, while the cong hypotheses survive (|as| = |ar| holds
      // trivially with r ≡ s).
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(5, 1));
      final mirror = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final s = PointOnObject(id: 's', curve: mirror, parameter: 2);
      final r = ReflectedPoint(id: 'r', point: s, mirror: mirror);
      final construction = build([a, b, mirror, s, r]);
      final filter = DiagramFilter.probe(construction.objects);
      final emitted = hypotheses(construction.objects);
      final database = FactDatabase();
      final seeded = seedHypotheses(database, emitted, filter);
      expect(seeded, lessThan(emitted.length));
      expect(
        database.contains(Fact(PredicateKind.perp, [s, r, a, b])),
        isFalse,
      );
    });
  });
}
