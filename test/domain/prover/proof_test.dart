import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
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

  FreePoint free(String id, String name, double x, double y) => FreePoint(
    id: id,
    position: Vec2(x, y),
    attributes: ObjectAttributes(name: name),
  );

  ProverEngine engineOver(Construction construction, {List<Rule>? rules}) {
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    return ProverEngine(database: database, filter: filter, rules: rules);
  }

  /// Varignon: the midpoint quadrilateral of any quadrilateral is a
  /// parallelogram. Both midlines are parallel to the diagonal `AC`, so
  /// the goal is three rules and four givens deep — the smallest proof
  /// with genuine structure.
  ({ProverEngine engine, Fact goal}) varignon() {
    final a = free('a', 'A', 0, 0);
    final b = free('b', 'B', 6, 1);
    final c = free('c', 'C', 7, 5);
    final d = free('d', 'D', 1, 4);
    final mab = Midpoint(
      id: 'mab',
      point1: a,
      point2: b,
      attributes: const ObjectAttributes(name: 'M'),
    );
    final mbc = Midpoint(
      id: 'mbc',
      point1: b,
      point2: c,
      attributes: const ObjectAttributes(name: 'N'),
    );
    final mcd = Midpoint(
      id: 'mcd',
      point1: c,
      point2: d,
      attributes: const ObjectAttributes(name: 'P'),
    );
    final mda = Midpoint(
      id: 'mda',
      point1: d,
      point2: a,
      attributes: const ObjectAttributes(name: 'Q'),
    );
    final engine = engineOver(
      build([a, b, c, d, mab, mbc, mcd, mda]),
      rules: [ruleNamed('midline_para'), ruleNamed('para_transitive')],
    );
    engine.run();
    return (
      engine: engine,
      goal: Fact(PredicateKind.para, [mab, mbc, mda, mcd]),
    );
  }

  group('the walk', () {
    test('every citation points upwards, and the goal is last', () {
      final rig = varignon();
      final proof = Proof.of(rig.goal, rig.engine.database);
      expect(proof.steps.last.fact, rig.goal);
      for (final step in proof.steps) {
        expect(step.number, proof.steps.indexOf(step) + 1);
        for (final cited in step.premiseSteps) {
          expect(
            cited,
            lessThan(step.number),
            reason: 'step ${step.number} cites $cited',
          );
        }
      }
    });

    test('states each fact once, however often it is cited', () {
      final rig = varignon();
      final proof = Proof.of(rig.goal, rig.engine.database);
      final stated = {for (final step in proof.steps) step.fact};
      expect(stated.length, proof.steps.length);
    });

    test('carries exactly the goal\'s support, and nothing else derived', () {
      final rig = varignon();
      final database = rig.engine.database;
      final proof = Proof.of(rig.goal, database);

      // The support, computed independently of the walk.
      final support = <Fact>{};
      void collect(Fact fact) {
        if (!support.add(fact)) return;
        for (final premise in database.derivationOf(fact)!.premises) {
          collect(premise);
        }
      }

      collect(rig.goal);
      expect({for (final step in proof.steps) step.fact}, support);
      expect(
        database.length,
        greaterThan(support.length),
        reason:
            'the run derived more than this goal needs, '
            'so the walk is doing real pruning',
      );
    });

    test('splits givens from deductions', () {
      final rig = varignon();
      final proof = Proof.of(rig.goal, rig.engine.database);
      expect(proof.givens.length, 4, reason: 'the four midpoints');
      expect(
        {for (final step in proof.givens) step.fact.kind},
        {PredicateKind.midp},
      );
      expect(proof.deductions.length, 3);
      expect(
        [for (final step in proof.deductions) step.rule],
        ['midline_para', 'midline_para', 'para_transitive'],
      );
      expect(proof.steps.length, proof.givens.length + proof.deductions.length);
    });

    test('reads out as a numbered statement/reason list', () {
      final rig = varignon();
      final proof = Proof.of(rig.goal, rig.engine.database);
      final lines = proof.render().split('\n');
      expect(lines.first, 'Proof of para(M, N, P, Q) — 4 given, 3 deductions');
      expect(lines.length, 8);
      expect(lines.last, contains('para_transitive from '));
      // Points print by the name the figure gives them, never the id.
      expect(proof.render(), isNot(contains('mab')));
      expect('$proof', proof.render());
    });

    test('an unnamed point prints as its id', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final engine = engineOver(
        build([a, b, m]),
        rules: [ruleNamed('midp_coll')],
      );
      engine.run();
      final proof = Proof.of(
        Fact(PredicateKind.coll, [m, a, b]),
        engine.database,
      );
      expect(proof.render(), contains('coll(a, b, m)'));
    });

    test('a goal that is itself a given is a one-line proof', () {
      final rig = varignon();
      final given = rig.engine.database.facts.first;
      final proof = Proof.of(given, rig.engine.database);
      expect(proof.steps.single.isGiven, isTrue);
      expect(proof.steps.single.fact, given);
      expect(proof.deductions, isEmpty);
      expect(proof.render(), contains('1 given, 0 deductions'));
    });

    test('a goal the run never derived is a question, not an empty proof', () {
      final rig = varignon();
      final a = FreePoint(id: 'z1', position: const Vec2(0, 0));
      final b = FreePoint(id: 'z2', position: const Vec2(1, 0));
      final c = FreePoint(id: 'z3', position: const Vec2(2, 0));
      expect(
        () =>
            Proof.of(Fact(PredicateKind.coll, [a, b, c]), rig.engine.database),
        throwsArgumentError,
      );
    });

    test('a deep chain is data, not stack depth', () {
      // 20 000 links: a recursive walk would not survive this, which is
      // why the walk is an explicit stack.
      const links = 20000;
      final points = [
        for (var i = 0; i < links + 2; i++)
          FreePoint(id: 'p$i', position: Vec2(i.toDouble(), 0)),
      ];
      final database = FactDatabase();
      var previous = Fact(PredicateKind.coll, points.sublist(0, 3));
      database.addHypothesis(previous);
      for (var i = 1; i < links; i++) {
        final next = Fact(PredicateKind.coll, points.sublist(i, i + 3));
        database.add(next, Derivation('chain', [previous]));
        previous = next;
      }
      final proof = Proof.of(previous, database);
      expect(proof.steps.length, links);
      expect(proof.steps.first.isGiven, isTrue);
      expect(proof.steps.last.fact, previous);
    });

    test('a cycle throws rather than spins', () {
      // FactDatabase cannot be made to hold one — premises must already
      // be present, and first-insert-wins keeps a fact's derivation the
      // one it was discovered with. The guard is insurance against a
      // future store that forgets that, so the cycle has to be injected
      // to be tested at all.
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final one = Fact(PredicateKind.coll, [a, b, c]);
      final two = Fact(PredicateKind.cong, [a, b, b, c]);
      final database = _CyclicDatabase({
        one: Derivation('bogus', [two]),
        two: Derivation('bogus', [one]),
      });
      expect(() => Proof.of(one, database), throwsStateError);
    });
  });

  group('verify', () {
    test('a proof of a real run is a certificate', () {
      final rig = varignon();
      final proof = Proof.of(rig.goal, rig.engine.database);
      expect(proof.deductions, isNotEmpty);
      expect(proof.verify(), isEmpty);
    });

    test('names the step whose premises do not entail it', () {
      final a = free('a', 'A', 0, 0);
      final b = free('b', 'B', 6, 0);
      final c = free('c', 'C', 2, 5);
      final mab = Midpoint(id: 'mab', point1: a, point2: b);
      final mac = Midpoint(id: 'mac', point1: a, point2: c);
      final construction = build([a, b, c, mab, mac]);
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      final first = Fact(PredicateKind.midp, [mab, a, b]);
      final second = Fact(PredicateKind.midp, [mac, a, c]);
      database.addHypothesis(first);
      database.addHypothesis(second);
      // The conclusion is true — the filter would pass it — and the rule
      // name is the right one. Only the premises are wrong: one midpoint
      // cited twice does not give the midline.
      final conclusion = Predicate(PredicateKind.para, [mab, mac, b, c]);
      expect(filter.holds(conclusion), isTrue, reason: 'bad rig');
      database.add(
        Fact.of(conclusion),
        Derivation('midline_para', [first, first]),
      );
      final proof = Proof.of(Fact.of(conclusion), database);
      expect(proof.verify(), hasLength(1));
      expect(proof.verify().single, startsWith('step 2: '));
      expect(proof.verify().single, contains('midline_para'));
    });
  });
}

/// A store that hands back whatever derivations it is given — including
/// ones `FactDatabase` would refuse.
class _CyclicDatabase extends FactDatabase {
  _CyclicDatabase(this._injected);

  final Map<Fact, Derivation> _injected;

  @override
  bool contains(Fact fact) => _injected.containsKey(fact);

  @override
  Derivation? derivationOf(Fact fact) => _injected[fact];
}
