import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/questions.dart';
import 'package:regula/domain/prover/rule.dart';
import 'package:regula/domain/prover/rule_engine.dart';

/// Phase 163: the tangent–chord theorem, on the user's own figure, and
/// the rule that was deleted to afford it.
///
/// `test/fixtures/tangent-chord.rgl` (session 170's report): a circle
/// about `A` through `B`, `C` and `D` on it, chords `BC`, `BD`, `DC`,
/// the tangent at `C` with `E` on it. The theorem is
/// `∠(CE, CB) = ∠(DC, DB)`. Phase 162 made the chip read it as the user
/// would; the run then answered *unproved*, because the inscribed-angle
/// road needs a fourth point on the circle this figure does not have,
/// and the rule that reaches it directly had been measured and dropped
/// in Phase 155. It is back, and its price was `eqangle_transitive`'s —
/// see the notes beside both in `rule.dart`.
void main() {
  Construction load(String name) => decodeDocument(
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>,
  ).construction;

  GeoPoint named(Construction construction, String name) => construction.objects
      .whereType<GeoPoint>()
      .firstWhere((point) => point.attributes.name == name);

  ({FactDatabase database, Prover prover}) exchange(
    Construction construction,
    DiagramFilter filter,
  ) {
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final prover = Prover(database: database, filter: filter)..run();
    return (database: database, prover: prover);
  }

  group('tangent-chord.rgl', () {
    late Construction construction;
    late DiagramFilter filter;
    late Predicate theorem;

    setUp(() {
      construction = load('tangent-chord.rgl');
      filter = DiagramFilter.probe(construction.objects);
      GeoPoint p(String name) => named(construction, name);
      theorem = Predicate(PredicateKind.eqangle, [
        p('C'),
        p('E'),
        p('C'),
        p('B'),
        p('D'),
        p('C'),
        p('D'),
        p('B'),
      ]);
    });

    test('the tangency reaches the document, and the theorem is true', () {
      GeoPoint p(String name) => named(construction, name);
      final tangency = Fact.of(
        Predicate(PredicateKind.perp, [p('A'), p('C'), p('C'), p('E')]),
      );
      expect(
        hypotheses(construction.objects).map(Fact.of),
        contains(tangency),
        reason: 'the tangent at C, with E named on it, is a hypothesis',
      );
      expect(filter.holds(theorem), isTrue);
    });

    test('the run proves it by tangent_chord, and the proof certifies', () {
      final run = exchange(construction, filter);
      final goal = Fact.of(theorem);

      expect(run.prover.isComplete, isTrue);
      expect(run.database.contains(goal), isTrue);
      expect(run.database.derivationOf(goal)!.rule, 'tangent_chord');

      final proof = Proof.of(goal, run.database);
      expect(proof.verify(), isEmpty);
      // One deduction over three givens: the tangency and two radii.
      expect(proof.steps.where((step) => step.rule != null), hasLength(1));
      expect(
        proof.steps.where((step) => step.rule == null).map((s) => s.fact.kind),
        unorderedEquals([
          PredicateKind.perp,
          PredicateKind.cong,
          PredicateKind.cong,
        ]),
      );
    });

    test('asked through either tangent, the answer is the same proof '
        '(Phase 164)', () {
      final byName = {
        for (final o in construction.objects) o.attributes.name: o.id,
      };
      final run = exchange(construction, filter);
      for (final tangent in ['c', 'd']) {
        final questions = askableQuestions(
          construction.objects,
          selectedIds: {
            byName['b']!,
            byName[tangent]!,
            byName['e']!,
            byName['f']!,
          },
        );
        expect(questions, isNotEmpty, reason: 'via $tangent');
        final derived = questions.first.spellings
            .map(Fact.of)
            .firstWhere(run.prover.resolve);
        expect(
          run.database.derivationOf(derived)!.rule,
          'tangent_chord',
          reason: 'via $tangent',
        );
      }
    });

    test('without the rule the figure has no route', () {
      // The reason the rule is back: on this figure the theorem is not
      // reachable any other way, which is what Phase 155's measurement
      // on `tangent-chase.rgl` could not see.
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(
        database: database,
        filter: filter,
        rules: ddCoreRules.where((r) => r.name != 'tangent_chord').toList(),
      )..run();
      expect(prover.isComplete, isTrue);
      expect(prover.resolve(Fact.of(theorem)), isFalse);
    });
  });

  test('eqangle transitivity is the closure\'s, not a rule\'s', () {
    // `eqangle_transitive` was deleted in Phase 163. What it would have
    // stored is every composite of two stored `eqangle`s sharing a side;
    // on a document that runs to quiescence, every such composite must
    // be answered by the closure — which is the row sum the rule was.
    final construction = load('tangent-chase.rgl');
    final filter = DiagramFilter.probe(construction.objects);
    final run = exchange(construction, filter);
    expect(run.prover.isComplete, isTrue);
    expect(
      ddCoreRules.map((r) => r.name),
      isNot(contains('eqangle_transitive')),
    );

    final angles = run.database.facts
        .where((fact) => fact.kind == PredicateKind.eqangle)
        .toList();
    expect(angles.length, greaterThan(10), reason: 'the rig has chains');

    var composites = 0;
    for (final first in angles) {
      for (final second in angles) {
        if (identical(first, second)) continue;
        for (final left in orbitArguments(first.kind, first.points)) {
          for (final right in orbitArguments(second.kind, second.points)) {
            if (!_sameSide(left.sublist(4), right.sublist(0, 4))) continue;
            final composite = Predicate(PredicateKind.eqangle, [
              ...left.sublist(0, 4),
              ...right.sublist(4),
            ]);
            if (_degenerate(composite)) continue;
            composites++;
            expect(
              run.prover.resolve(Fact.of(composite)),
              isTrue,
              reason: 'the closure must hold $composite',
            );
          }
        }
      }
    }
    expect(composites, greaterThan(0));
  });
}

bool _sameSide(List<GeoPoint> a, List<GeoPoint> b) {
  for (var i = 0; i < 4; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

/// A composite whose two sides are the same pair of lines, or that names
/// a zero segment, is not a statement the rule would have stored either.
bool _degenerate(Predicate composite) {
  final p = composite.points;
  for (var i = 0; i < 8; i += 2) {
    if (identical(p[i], p[i + 1])) return true;
  }
  return _sameSide(p.sublist(0, 4), p.sublist(4));
}
