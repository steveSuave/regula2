import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/fixed_angle_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/stated_radius_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_translation.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  Construction build(Iterable<GeoObject> objects) {
    final construction = Construction();
    for (final object in objects) {
      construction.add(object);
    }
    return construction;
  }

  /// The Varignon rig: four free points and the midpoints of their
  /// sides. DD reaches the midlines through `midp`, which AR cannot
  /// read; AR then relates them.
  Construction varignon() {
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(6, 1));
    final c = FreePoint(id: 'c', position: const Vec2(7, 5));
    final d = FreePoint(id: 'd', position: const Vec2(1, 4));
    return build([
      a,
      b,
      c,
      d,
      Midpoint(id: 'mab', point1: a, point2: b),
      Midpoint(id: 'mbc', point1: b, point2: c),
      Midpoint(id: 'mcd', point1: c, point2: d),
      Midpoint(id: 'mda', point1: d, point2: a),
    ]);
  }

  Construction jgexDocument() {
    final construction = decodeDocument(
      jsonDecode(
        File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
      ) as Map<String, dynamic>,
    ).construction;
    GeoPoint named(String name) => construction.objects
        .whereType<GeoPoint>()
        .firstWhere((point) => point.attributes.name == name);
    construction.add(
      Midpoint(id: 'aux', point1: named('B'), point2: named('C')),
    );
    return construction;
  }

  ({FactDatabase database, Prover prover}) exchange(
    Construction construction, {
    int? cap,
  }) {
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final prover = Prover(database: database, filter: filter);
    prover.run(maxApplications: cap);
    return (database: database, prover: prover);
  }

  FactDatabase ddAlone(Construction construction, {int cap = 30000}) {
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final engine = ProverEngine(database: database, filter: filter);
    var applied = 0;
    while (!engine.isComplete && applied < cap) {
      applied += engine.step(cap - applied);
    }
    return database;
  }

  List<Fact> angleSteps(FactDatabase database) => [
    for (final fact in database.facts)
      if (database.derivationOf(fact)!.rule == angleArithmeticRule) fact,
  ];

  group('the exchange', () {
    test('reaches more than DD alone, and loses nothing', () {
      final construction = jgexDocument();
      final alone = ddAlone(construction);
      final joint = exchange(construction);

      expect(
        joint.database.facts.toSet(),
        containsAll(alone.facts.toSet()),
        reason: 'a peer engine must never cost the run a fact',
      );
      expect(joint.database.length, greaterThan(alone.length));
      expect(angleSteps(joint.database), isNotEmpty);
    });

    test('and it is a loop, not a pipeline', () {
      // The claim that makes this a facade rather than a post-pass: at
      // least one angle step rests on a fact DD *derived*, which AR
      // could not have had from the hypotheses; and DD in turn pivots
      // what AR published, which is why the run takes more than one
      // pass.
      final joint = exchange(jgexDocument());
      final steps = angleSteps(joint.database);
      expect(steps, isNotEmpty);

      final restsOnDerived = steps.any(
        (step) => joint.database
            .derivationOf(step)!
            .premises
            .any(
              (premise) => !joint.database.derivationOf(premise)!.isHypothesis,
            ),
      );
      expect(
        restsOnDerived,
        isTrue,
        reason: 'AR read something only DD could have produced',
      );
      expect(joint.prover.passes.length, greaterThan(1));
    });

    test('every angle step is a certificate, proof and all', () {
      // `Proof.of` walks the whole sub-DAG, so this checks the DD steps
      // underneath the angle step as well as the step itself.
      final joint = exchange(jgexDocument());
      final steps = angleSteps(joint.database);
      expect(steps, isNotEmpty);
      for (final step in steps) {
        expect(
          Proof.of(step, joint.database).verify(),
          isEmpty,
          reason: 'the proof of $step is not a certificate',
        );
      }
    });

    test('an angle step cites facts the database already holds', () {
      // `FactDatabase.add` enforces it, so this pins that the facade
      // never tries to publish ahead of its premises.
      final joint = exchange(jgexDocument());
      for (final step in angleSteps(joint.database)) {
        final derivation = joint.database.derivationOf(step)!;
        expect(derivation.premises, isNotEmpty);
        for (final premise in derivation.premises) {
          expect(joint.database.contains(premise), isTrue);
        }
      }
    });

    test('on the Varignon rig too, where the midlines come from midp', () {
      final construction = varignon();
      final alone = ddAlone(construction);
      final joint = exchange(construction);
      expect(joint.database.facts.toSet(), containsAll(alone.facts.toSet()));
      for (final step in angleSteps(joint.database)) {
        expect(Proof.of(step, joint.database).verify(), isEmpty);
      }
    });
  });

  group('resolving a question the database does not hold', () {
    /// The parallelogram's angle: ∠(MN, NP) = ∠(QP, MQ), true because
    /// MN ∥ QP and NP ∥ MQ. DD has no `para & para ⇒ eqangle`, so no
    /// run stores it; AR entails it from the two parallels in one row.
    Fact fourSides(Construction construction) {
      GeoPoint at(String id) => construction.byId(id)! as GeoPoint;
      final (m, n, p, q) = (at('mab'), at('mbc'), at('mcd'), at('mda'));
      return Fact.of(
        Predicate(PredicateKind.eqangle, [m, n, n, p, q, p, m, q]),
      );
    }

    test('an entailed eqangle is recorded as a certificate on demand', () {
      final construction = varignon();
      final joint = exchange(construction);
      final fact = fourSides(construction);
      expect(joint.prover.isComplete, isTrue);
      expect(joint.database.contains(fact), isFalse);
      final before = joint.database.length;

      expect(joint.prover.resolve(fact), isTrue);

      expect(joint.database.contains(fact), isTrue);
      expect(joint.database.length, before + 1);
      final derivation = joint.database.derivationOf(fact)!;
      expect(derivation.rule, angleArithmeticRule);
      // Which parallels the certificate cites is the echelon's choice
      // (here the diagonals' midlines, not the sides'); that they are
      // all parallels is the theorem's.
      expect(derivation.premises, isNotEmpty);
      expect(
        derivation.premises.every((p) => p.kind == PredicateKind.para),
        isTrue,
        reason: '${derivation.premises}',
      );
      final proof = Proof.of(fact, joint.database);
      expect(proof.verify(), isEmpty, reason: 'a certificate, not a claim');
      expect(proof.steps.last.chase, isNotNull, reason: 'and it reads');
      // Asked for, not derived toward: the engine stays complete.
      expect(joint.prover.isComplete, isTrue);
      // Idempotent — a second ask is a lookup.
      expect(joint.prover.resolve(fact), isTrue);
      expect(joint.database.length, before + 1);
    });

    test('what the closure does not entail is not recorded', () {
      final construction = varignon();
      final joint = exchange(construction);
      GeoPoint at(String id) => construction.byId(id)! as GeoPoint;
      // ∠(AB, MN) = ∠(MN, NP): not a theorem, not in the closure.
      final fact = Fact.of(
        Predicate(PredicateKind.eqangle, [
          at('a'),
          at('b'),
          at('mab'),
          at('mbc'),
          at('mab'),
          at('mbc'),
          at('mbc'),
          at('mcd'),
        ]),
      );
      final before = joint.database.length;
      expect(joint.prover.resolve(fact), isFalse);
      expect(joint.database.length, before);
      expect(joint.database.contains(fact), isFalse);
    });
  });

  group('what a pass is', () {
    test('a run records its passes and ends on a quiet one', () {
      final joint = exchange(varignon());
      expect(joint.prover.passes, isNotEmpty);
      expect(joint.prover.passes.last.published, 0);
      expect(joint.prover.isComplete, isTrue);
    });

    test('a document with nothing to say takes one quiet pass', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final joint = exchange(build([a, b]));
      expect(joint.database, isEmpty);
      expect(joint.prover.passes.length, 1);
      expect(joint.prover.passes.single.published, 0);
    });

    test('the cap counts DD applications and is respected', () {
      final construction = jgexDocument();
      final joint = exchange(construction, cap: 50);
      expect(joint.prover.applications, lessThanOrEqualTo(50));
      expect(joint.prover.isComplete, isFalse);
      // Everything derived under a cap still stands, and still verifies.
      for (final step in angleSteps(joint.database)) {
        expect(Proof.of(step, joint.database).verify(), isEmpty);
      }
    });

    test('a capped run resumes where it stopped', () {
      final construction = jgexDocument();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);
      prover.run(maxApplications: 200);
      final interim = database.length;
      prover.run(maxApplications: 30000);
      expect(database.length, greaterThan(interim));
      expect(prover.isComplete, isTrue);
    });
  });

  group('chunking changes when, never what', () {
    test('runChunked reaches the same database as run', () async {
      final construction = jgexDocument();
      final straight = exchange(construction);

      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);
      await prover.runChunked(chunkBudget: 64, maxApplications: 30000);

      expect(
        [for (final fact in database.facts) '$fact']..sort(),
        [for (final fact in straight.database.facts) '$fact']..sort(),
      );
    });

    test('runChunked refuses a non-positive chunk', () async {
      final construction = varignon();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      final prover = Prover(database: database, filter: filter);
      expect(() => prover.runChunked(chunkBudget: 0), throwsArgumentError);
    });

    test('a spent budget comes back without touching the event loop', () {
      // Found by a widget test, and a plain `await` would never have
      // shown it: a yield is a timer, and inside `testWidgets`' fake
      // async a caller that awaits this future without pumping waits on
      // a timer nobody fires. So every exit must be taken *before* the
      // yield — which is `ProverEngine.runChunked`'s shape, for exactly
      // this reason.
      final construction = jgexDocument();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);

      fakeAsync((async) {
        var settled = false;
        prover
            .runChunked(chunkBudget: 1000, maxApplications: 3)
            .then((_) => settled = true);
        async.flushMicrotasks();
        expect(
          settled,
          isTrue,
          reason: 'the run is waiting on a timer nobody will fire',
        );
      });
      expect(prover.applications, lessThanOrEqualTo(3));
    });

    test('and so does a stopWhen that is already true', () {
      final construction = jgexDocument();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);
      fakeAsync((async) {
        var settled = false;
        prover
            .runChunked(chunkBudget: 1000, stopWhen: () => true)
            .then((_) => settled = true);
        async.flushMicrotasks();
        expect(settled, isTrue);
      });
    });

    test('a stopWhen ends the exchange early', () async {
      final construction = jgexDocument();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);
      await prover.runChunked(
        chunkBudget: 1 << 20,
        stopWhen: () => database.length > 40,
      );
      expect(prover.isComplete, isFalse);
    });

    test('onPass fires once per pass, the final one included', () async {
      final construction = jgexDocument();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);

      var calls = 0;
      final passes = await prover.runChunked(
        chunkBudget: 64,
        maxApplications: 30000,
        onPass: () => calls++,
      );

      expect(calls, passes, reason: 'one call per pass, none skipped');
      expect(calls, greaterThan(1), reason: 'the rig must actually chunk');
    });

    test('onPass does not fire when the entry checks return', () async {
      final construction = jgexDocument();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);

      var calls = 0;
      await prover.runChunked(
        chunkBudget: 1000,
        stopWhen: () => true,
        onPass: () => calls++,
      );

      expect(calls, 0, reason: 'no pass ran, so there is nothing to report');
    });
  });

  group('an angle step that is not one is refused', () {
    test('verify rejects a fabricated angle_arithmetic step', () {
      // The check re-derives from the record rather than trusting it, so
      // a step whose premises do not entail its conclusion is caught
      // even though the conclusion is perfectly true in the diagram.
      final construction = varignon();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);
      prover.run();

      final points = construction.objects.whereType<GeoPoint>().toList();
      GeoPoint named(String id) => points.firstWhere((point) => point.id == id);
      final paraFacts = [
        for (final fact in database.facts)
          if (fact.kind == PredicateKind.para) fact,
      ];
      expect(paraFacts, isNotEmpty);

      // A true statement, cited from a premise that says nothing about
      // its lines.
      final unrelated = Fact(PredicateKind.para, [
        named('mab'),
        named('mcd'),
        named('mda'),
        named('mbc'),
      ]);
      final wrong = Derivation(angleArithmeticRule, [paraFacts.first]);
      final scratch = FactDatabase();
      scratch.addHypothesis(paraFacts.first);
      expect(scratch.add(unrelated, wrong), isTrue);
      final reasons = Proof.of(unrelated, scratch).verify();
      expect(reasons, isNotEmpty);
    });

    test('and one citing a fact with no angle content', () {
      final construction = varignon();
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final midp = database.facts.firstWhere(
        (fact) => fact.kind == PredicateKind.midp,
      );
      final points = construction.objects.whereType<GeoPoint>().toList();
      GeoPoint named(String id) => points.firstWhere((point) => point.id == id);
      final claim = Fact(PredicateKind.para, [
        named('a'),
        named('b'),
        named('c'),
        named('d'),
      ]);
      final scratch = FactDatabase();
      scratch.addHypothesis(midp);
      scratch.add(claim, Derivation(angleArithmeticRule, [midp]));
      final reasons = Proof.of(claim, scratch).verify();
      expect(reasons, isNotEmpty);
      expect(reasons.first, contains('says nothing about'));
    });
  });

  group('reading a constant the closures entail (Phase 185)', () {
    /// Line AB, C off it, the 60° line through C with a named point P
    /// on it, a stated-radius circle about A through the named R, and
    /// M the midpoint of AB.
    ({Construction construction, Map<String, GeoPoint> at}) constants() {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 1));
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final sixty = FixedAngleLine(
        id: 'sixty',
        through: c,
        reference: ab,
        turn: Rational.fromInts(1, 3),
      );
      final p = PointOnObject(id: 'p', curve: sixty, parameter: 2);
      final circle = StatedRadiusCircle(
        id: 'k',
        center: a,
        radius: Rational.fromInts(5, 2),
      );
      final r = PointOnObject(id: 'r', curve: circle, parameter: 0.7);
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final construction = build([a, b, c, ab, sixty, p, circle, r, m]);
      return (
        construction: construction,
        at: {
          for (final object in construction.objects)
            if (object is GeoPoint) object.id: object,
        },
      );
    }

    test('an angle, a length and a ratio read as their stated values', () {
      final rig = constants();
      final joint = exchange(rig.construction);
      final at = rig.at;
      final prover = joint.prover;
      expect(
        prover.readConstant(PredicateKind.aconst, [
          at['a']!,
          at['b']!,
          at['c']!,
          at['p']!,
        ]),
        Rational.fromInts(1, 3),
      );
      expect(
        prover.readConstant(PredicateKind.aconst, [
          at['c']!,
          at['p']!,
          at['a']!,
          at['b']!,
        ]),
        Rational.fromInts(2, 3),
        reason: 'the turn back is the complement',
      );
      expect(
        prover.readConstant(PredicateKind.lconst, [at['r']!, at['a']!]),
        Rational.fromInts(5, 2),
      );
      expect(
        prover.readConstant(PredicateKind.rconst, [
          at['a']!,
          at['b']!,
          at['a']!,
          at['m']!,
        ]),
        Rational.whole(2),
        reason: 'the midpoint states its half, and the half inverts',
      );
    });

    test('what the closures do not determine reads null, records '
        'nothing, and the value read is then proved on ask', () {
      final rig = constants();
      final joint = exchange(rig.construction);
      final at = rig.at;
      final before = joint.database.length;
      expect(
        joint.prover.readConstant(PredicateKind.aconst, [
          at['a']!,
          at['b']!,
          at['a']!,
          at['c']!,
        ]),
        isNull,
        reason: 'AC is at no stated angle to AB',
      );
      expect(
        joint.prover.readConstant(PredicateKind.lconst, [at['a']!, at['b']!]),
        isNull,
      );
      expect(
        joint.database.length,
        before,
        reason: 'a reading records nothing',
      );

      final value = joint.prover.readConstant(PredicateKind.aconst, [
        at['a']!,
        at['b']!,
        at['c']!,
        at['p']!,
      ])!;
      final fact = Fact(PredicateKind.aconst, [
        at['a']!,
        at['b']!,
        at['c']!,
        at['p']!,
      ], value: value);
      expect(joint.prover.resolve(fact), isTrue);
      expect(Proof.of(fact, joint.database).verify(), isEmpty);
    });

    test('a point-pure kind has no value to read', () {
      final rig = constants();
      final joint = exchange(rig.construction);
      final at = rig.at;
      expect(
        () => joint.prover.readConstant(PredicateKind.para, [
          at['a']!,
          at['b']!,
          at['c']!,
          at['p']!,
        ]),
        throwsArgumentError,
      );
      expect(
        () => joint.prover.readConstant(PredicateKind.lconst, [at['a']!]),
        throwsArgumentError,
      );
    });
  });
}
