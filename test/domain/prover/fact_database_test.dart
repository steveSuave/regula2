import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/predicate.dart';

void main() {
  FreePoint free(String id) => FreePoint(id: id, position: Vec2.zero);

  final a = free('a');
  final b = free('b');
  final c = free('c');
  final d = free('d');

  Fact coll(List<FreePoint> points) => Fact(PredicateKind.coll, points);
  Fact para(List<FreePoint> points) => Fact(PredicateKind.para, points);

  test('an empty database', () {
    final db = FactDatabase();
    expect(db.isEmpty, isTrue);
    expect(db.isNotEmpty, isFalse);
    expect(db.length, 0);
    expect(db.facts, isEmpty);
    expect(db.contains(coll([a, b, c])), isFalse);
    expect(db.derivationOf(coll([a, b, c])), isNull);
  });

  test('a hypothesis is a given: no rule, no premises', () {
    final db = FactDatabase();
    expect(db.addHypothesis(coll([a, b, c])), isTrue);
    final derivation = db.derivationOf(coll([a, b, c]))!;
    expect(derivation.isHypothesis, isTrue);
    expect(derivation.rule, isNull);
    expect(derivation.premises, isEmpty);
    expect(db.length, 1);
  });

  test('one statement written two ways is stored once', () {
    // The whole reason the database is keyed on canonical forms: a rule
    // that rediscovers a conclusion in a new spelling must not grow the
    // set, or forward chaining never reaches quiescence.
    final db = FactDatabase();
    expect(db.addHypothesis(para([a, b, c, d])), isTrue);
    expect(db.addHypothesis(para([d, c, b, a])), isFalse);
    expect(db.addHypothesis(para([c, d, a, b])), isFalse);
    expect(db.length, 1);
  });

  test('first insert wins, and it is the acyclicity argument', () {
    final db = FactDatabase();
    final premise = coll([a, b, c]);
    final conclusion = para([a, b, c, d]);
    db.addHypothesis(premise);
    expect(db.add(conclusion, Derivation('r1', [premise])), isTrue);

    // Re-derived by a longer route — legal, cites only present facts,
    // and ignored. The original derivation stands, so every premise
    // stays strictly older than its conclusion and the proof DAG cannot
    // close a cycle.
    expect(db.add(premise, Derivation('r2', [conclusion])), isFalse);
    expect(db.derivationOf(premise)!.isHypothesis, isTrue);
    expect(db.derivationOf(conclusion)!.rule, 'r1');
    expect(db.length, 2);
  });

  test('a derivation may not cite a fact the database does not hold', () {
    final db = FactDatabase();
    final absent = coll([a, b, c]);
    expect(
      () => db.add(para([a, b, c, d]), Derivation('r1', [absent])),
      throwsStateError,
    );
    expect(db.isEmpty, isTrue);

    // And the check is on the canonical form, not the spelling: the
    // premise is present, written differently.
    db.addHypothesis(coll([c, b, a]));
    expect(db.add(para([a, b, c, d]), Derivation('r1', [absent])), isTrue);
  });

  test('every premise precedes its conclusion in iteration order', () {
    // The structural form of the same invariant, over a small chain.
    final db = FactDatabase();
    final first = coll([a, b, c]);
    final second = coll([a, b, d]);
    final third = para([a, b, c, d]);
    final fourth = para([a, c, b, d]);
    db.addHypothesis(first);
    db.addHypothesis(second);
    db.add(third, Derivation('r1', [first, second]));
    db.add(fourth, Derivation('r2', [third, first]));

    final order = db.facts.toList();
    expect(order, [first, second, third, fourth]);
    for (var i = 0; i < order.length; i++) {
      for (final premise in db.derivationOf(order[i])!.premises) {
        expect(
          order.indexOf(premise),
          lessThan(i),
          reason: '$premise should precede ${order[i]}',
        );
      }
    }
  });

  test('a derivation prints as a rule over its premises', () {
    expect(const Derivation.hypothesis().toString(), 'hypothesis');
    expect(
      Derivation('r1', [
        coll([a, b, c]),
      ]).toString(),
      'r1(coll(a, b, c))',
    );
  });

  test('a derivation does not adopt the caller list', () {
    final premises = [
      coll([a, b, c]),
    ];
    final derivation = Derivation('r1', premises);
    expect(
      () => derivation.premises.add(coll([a, b, d])),
      throwsUnsupportedError,
    );
  });
}
