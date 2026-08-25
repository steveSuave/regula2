/// The search for the point JGEX would have constructed (Phase 153).
///
/// `auxiliary_upside_test.dart` measured what there is to find — 2
/// unlocks of 1 fact from 276 candidates — and what an attempt costs: a
/// full prover run per candidate, 50 seconds for one exhaustive pass on
/// `provoleas2.json`. Those two numbers are the whole design. The search
/// is **goal-directed** (it stops at the first candidate that answers
/// the question, because enumerating for its own sake is almost all
/// waste), **ordered** (midpoints first, which is a measurement: every
/// unlock in the corpus is one), and **resumable** (a cursor over
/// candidates, on `ProverEngine`'s Phase 140 precedent, so a caller can
/// drive it in slices and stop).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/auxiliary_points.dart';
import 'package:regula/domain/prover/auxiliary_search.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/length_translation.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  Construction load(String path) => decodeDocument(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  ).construction;

  Construction jgex() => load('test/fixtures/perp-true-unproved.rgl');

  GeoPoint pointNamed(Construction construction, String name) => construction
      .objects
      .whereType<GeoPoint>()
      .firstWhere((point) => point.attributes.name == name);

  /// `perp(C,D,D,F)` — the theorem a user's JGEX screenshot proved on
  /// this document, which Phase 148 had shipped as the *unproved* rig.
  Fact theorem(Construction construction) => Fact(PredicateKind.perp, [
    pointNamed(construction, 'C'),
    pointNamed(construction, 'D'),
    pointNamed(construction, 'D'),
    pointNamed(construction, 'F'),
  ]);

  test('it finds JGEX\'s point, and stops there', () {
    final construction = jgex();
    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: theorem(construction),
    );
    expect(search.candidates, hasLength(26));

    final found = search.run();
    expect(found, isNotNull);
    expect(search.isComplete, isTrue);
    expect(search.isExhausted, isFalse);

    // The point JGEX's dialog says it built: the midpoint of our BC.
    expect(found!.candidate.family, AuxiliaryFamily.midpoint);
    expect(
      {for (final parent in found.candidate.parents) parent.id},
      {pointNamed(construction, 'B').id, pointNamed(construction, 'C').id},
    );

    // Early exit is the saving, and this is its size: the paying
    // candidate is fifth of twenty-six, so ordering does not make the
    // sweep cheap — it makes the answer arrive before the sweep.
    expect(search.tried, 5);
  });

  test('the answer is a certificate that names the invented point', () {
    final construction = jgex();
    final goal = theorem(construction);
    final found = AuxiliarySearch(
      objects: construction.objects,
      goal: goal,
    ).run();

    expect(found!.reached, isTrue);
    expect(found.isQuiescent, isTrue);
    final proof = Proof.of(goal, found.database);
    expect(
      proof.verify(),
      isEmpty,
      reason:
          'a proof the prover invented a point for had better still '
          'be a certificate',
    );
    expect(
      proof.deductions.any(
        (step) =>
            step.fact.points.any((point) => identical(point, found.point)),
      ),
      isTrue,
      reason:
          'the proof cites the point, which is why the user has to be '
          'told about it',
    );
    expect(
      construction.objects.contains(found.point),
      isFalse,
      reason: 'built detached — accepting it stays the caller\'s decision',
    );
  });

  test('a cursor, so the caller decides how long to wait', () {
    final construction = jgex();
    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: theorem(construction),
    );

    expect(search.step(0), 0, reason: 'a zero slice does nothing');
    expect(search.tried, 0);
    expect(() => search.step(-1), throwsArgumentError);

    expect(search.step(3), 3);
    expect(search.found, isNull);
    expect(search.isComplete, isFalse);

    // The fourth slice would take two candidates and stops on the
    // first that answers — a slice is an upper bound, not a quota.
    expect(search.step(10), 2);
    expect(search.tried, 5);
    expect(search.found, isNotNull);

    expect(search.step(10), 0, reason: 'a finished search stays finished');
  });

  test('a family that pays nowhere exhausts, and says so', () {
    // The sweep found every unlock in the corpus among the midpoints;
    // no foot of a perpendicular unlocks anything on any document. So
    // the true theorem above, searched for among feet alone, is the
    // honest exhaustion case: eleven candidates, no answer, and a
    // result that does not pretend the statement is false.
    final construction = jgex();
    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: theorem(construction),
      families: {AuxiliaryFamily.foot},
    );
    expect(search.candidates, hasLength(11));

    expect(search.run(), isNull);
    expect(search.isComplete, isTrue);
    expect(search.isExhausted, isTrue);
    expect(search.tried, 11);
  });

  test('a goal the document already entails answers the first candidate', () {
    // The documented precondition, pinned rather than trusted: the
    // search does not run a baseline, so started against a statement
    // the document already reaches it answers candidate zero — true,
    // and useless, since the point is not why the goal holds. The
    // provider that asks a question has the baseline by the time it
    // gets here.
    final construction = jgex();
    final already = Fact(PredicateKind.midp, [
      pointNamed(construction, 'D'),
      pointNamed(construction, 'A'),
      pointNamed(construction, 'B'),
    ]);
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final baseline = Prover(database: database, filter: filter)..run();
    expect(
      baseline.resolve(already),
      isTrue,
      reason: 'the premise of this test',
    );

    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: already,
    );
    expect(search.run(), isNotNull);
    expect(search.tried, 1);
  });

  test('an attempt counts what the closures answer on ask, not only what '
      'they publish', () {
    // `reached` is `Prover.resolve`, which is the question a user's
    // *Ask* goes through — and the difference is not cosmetic. The
    // length and angle closures publish `cong` and `para`/`perp` and
    // answer `eqratio` and `eqangle` on ask alone, so a membership test
    // would report an `eqratio` goal unreached on a run that proves it.
    //
    // `eqratio(A,D,A,B,D,B,A,B)` is such a statement on this document —
    // D is the midpoint of AB, so it is true, entailed, and unstored.
    // It is also one the run reaches without any help, which is what
    // makes it the clean test of what `reached` *means* rather than of
    // what a search is for.
    final construction = jgex();
    GeoPoint p(String name) => pointNamed(construction, name);
    final askOnly = Fact(PredicateKind.eqratio, [
      p('A'),
      p('D'),
      p('A'),
      p('B'),
      p('D'),
      p('B'),
      p('A'),
      p('B'),
    ]);

    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: askOnly,
      families: {AuxiliaryFamily.midpoint},
    );
    expect(search.step(), 1);
    final attempt = search.found;
    expect(attempt, isNotNull, reason: 'the closure answers it on ask');
    // `resolve` records what it confirms, so a membership test *after*
    // the ask sees it either way; what says the ask is where it came
    // from is the step's rule. The length closure never publishes an
    // `eqratio`, so `length_arithmetic` here is only reachable through
    // the ask path.
    expect(
      Proof.of(askOnly, attempt!.database).deductions.last.rule,
      lengthArithmeticRule,
      reason: 'the closure answered it, having never published it',
    );
  });

  test('the proposed point takes an id the document is not using', () {
    final a = FreePoint(id: 'aux', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 0));
    final c = FreePoint(id: 'c', position: const Vec2(0, 3));
    final construction = Construction();
    for (final object in [a, b, c]) {
      construction.add(object);
    }
    final goal = Fact(PredicateKind.perp, [a, b, a, c]);
    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: goal,
      families: {AuxiliaryFamily.midpoint},
    );
    expect(
      search.pointId,
      'aux2',
      reason: 'the document is already using `aux`',
    );

    // And it is the id the proposal is actually built under, which is
    // the half that would otherwise go unchecked.
    expect(search.candidates.first.build(search.pointId).id, 'aux2');
    expect(search.run(), isNull, reason: 'nothing proves a right angle here');
    expect(search.tried, 3, reason: 'three pairs, three midpoints');
  });

  test('a document with no candidates is exhausted from the start', () {
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final construction = Construction()..add(a);
    final search = AuxiliarySearch(
      objects: construction.objects,
      goal: Fact(PredicateKind.coll, [a, a, a]),
    );
    expect(search.candidates, isEmpty);
    expect(search.isComplete, isTrue);
    expect(search.isExhausted, isTrue);
    expect(search.run(), isNull);
    expect(search.step(5), 0);
  });
}
