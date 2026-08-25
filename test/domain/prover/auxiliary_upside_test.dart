/// What an auxiliary point would buy, measured before the search that
/// would look for one (Phase 153, JGEX's A2).
///
/// The checklist says a search "needs a budget and an order, both
/// measured rather than chosen". This is that measurement, in the shape
/// Phases 151b and 152e used: enumerate the whole candidate space, add
/// each point *one at a time* to a fresh copy of the document, run the
/// exchange to quiescence, and read off what it reaches that the
/// baseline cannot.
///
/// **The metric is entailment, not the fact set, and the difference is
/// most of the answer.** A first pass compared fact sets and reported
/// unlocks on six of seven fixtures — every one of them a re-spelling.
/// Adding any point at all to `no-locus.rgl` "unlocks"
/// `para(F,G,F,B)`, which is the hypothesis `coll(F,G,B)` said in
/// `para` language: the baseline's angle closure entails it and
/// declines to *publish* it, because a `para` whose two pairs share a
/// point is a degeneracy (`AngleTranslation.conclusions`). So a
/// candidate has unlocked something only when the baseline exchange
/// cannot answer it on ask either — which is `Prover.resolve`, the
/// question a user's *Ask* already goes through.
///
/// Facts mentioning the proposed point are not counted. An auxiliary
/// construction earns its place by what it proves about the figure the
/// user drew; a statement about a point they did not draw is the
/// search's own scaffolding.
///
/// **The result: 2 candidates out of 276, one fact, one document — and
/// it is the document that motivated the phase.** On
/// `perp-true-unproved.rgl` the midpoint of `BC`, which is the point
/// JGEX's dialog says it constructed, reaches `perp(C,D,D,F)`; so does
/// the midpoint of `BF`, on the same line. Nothing else in the corpus
/// unlocks anything, in any family. Both unlocks are *midpoints*: the
/// 87 feet of perpendiculars and 45 intersections across the seven
/// documents buy nothing at all, which settles the checklist's order —
/// midpoints first was a guess and is a measurement.
///
/// **Cost, which is the budget half of the box.** A candidate costs a
/// full re-run — probe, hypotheses, exchange — so one pass of the
/// search is (candidates) × (baseline run), with no shortcut measured
/// here. On `provoleas2.json` that is 78 candidates at 643 ms against a
/// 368 ms baseline: 50 s for one pass, and the *worst single candidate*
/// is 4.4 s, twelve times the document's own run. `tangent-chase.rgl`
/// is 36 × 462 ms = 17 s. The probe is not the cost (2 ms of the 50 s);
/// the exchange is. So a search that tries every candidate is not
/// something a user waits through, and an order is not a nicety.
///
/// Those two documents are 67 of the sweep's 74 seconds, so they are
/// measured in `benchmark/auxiliary_search_bench.dart` — which reports
/// the timings as well, timings not being a thing to assert — and this
/// file sweeps the five that a suite can carry, in 12 s. The two were
/// measured in session 176 at a 200 000 cap with every candidate run
/// reaching quiescence: 0 unlocks from 78 and 36 candidates.
///
/// **What this does not measure, and should not be read as measuring.**
/// One point at a time: a theorem needing two auxiliary points would
/// come back as a zero here, and JGEX constructs more than one on
/// harder documents. And the corpus is seven documents whose theorems
/// the table already reaches — the standing finding of Phase 152e,
/// which four other measurements landed on before this one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/prover/auxiliary_points.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  /// The five the suite carries; see the library comment for the two it
  /// does not and what they measured.
  const fixtures = [
    'test/fixtures/locus3.json',
    'test/fixtures/apatitos-topos.rgl',
    'test/fixtures/no-locus.rgl',
    'test/fixtures/perp-true-unproved.rgl',
    'test/fixtures/tangent-chord.rgl',
  ];

  /// High enough that every run in the sweep reaches quiescence, which
  /// is what makes a zero unconditional rather than "zero so far".
  const cap = 200000;

  Construction load(String path) => decodeDocument(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  ).construction;

  ({FactDatabase database, Prover prover, bool complete}) prove(
    Construction construction,
  ) {
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final prover = Prover(database: database, filter: filter)
      ..run(maxApplications: cap);
    return (database: database, prover: prover, complete: prover.isComplete);
  }

  /// Every candidate on [path], with the facts about the document's own
  /// points that it reaches and the baseline cannot answer.
  ///
  /// The baseline prover is asked with [Prover.resolve], which records
  /// what it confirms. That is monotone and sound — it only ever stores
  /// statements the baseline already entails — so the screen does not
  /// drift as the sweep goes on.
  ({Map<String, List<Fact>> unlocks, int candidates, bool allComplete}) sweep(
    String path,
  ) {
    final base = load(path);
    final baseline = prove(base);
    final basePoints = <String, GeoPoint>{
      for (final object in base.objects)
        if (object is GeoPoint) object.id: object,
    };
    final names = <String, String>{
      for (final object in base.objects)
        object.id: object.attributes.name.isNotEmpty
            ? object.attributes.name
            : object.id,
    };
    String spell(AuxiliaryCandidate candidate) {
      var out = '$candidate';
      names.forEach((id, name) => out = out.replaceAll(id, name));
      return out;
    }

    final count = auxiliaryCandidates(base.objects).length;
    final unlocks = <String, List<Fact>>{};
    var allComplete = baseline.complete;
    for (var i = 0; i < count; i++) {
      final fresh = load(path);
      final candidates = auxiliaryCandidates(fresh.objects);
      fresh.add(candidates[i].build('aux'));
      final run = prove(fresh);
      allComplete = allComplete && run.complete;
      final novel = <Fact>[];
      for (final fact in run.database.facts) {
        final ids = [for (final point in fact.points) point.id];
        if (ids.any((id) => !basePoints.containsKey(id))) continue;
        final here = Fact(fact.kind, [for (final id in ids) basePoints[id]!]);
        if (baseline.prover.resolve(here)) continue;
        novel.add(here);
      }
      if (novel.isNotEmpty) unlocks[spell(candidates[i])] = novel;
    }
    return (unlocks: unlocks, candidates: count, allComplete: allComplete);
  }

  test('the JGEX document: the point it names is the point that pays', () {
    // `perp-true-unproved.rgl` is the fixture a user's JGEX screenshot
    // overturned two sessions' claims about (Phase 150). JGEX's dialog
    // said how it got there: it constructed the midpoint of our BC.
    // Phase 150 added that point *by hand* and pinned that the rules
    // alone do not reach the theorem. This is the other half — that a
    // search over the whole candidate space would find that point, and
    // very nearly only that point.
    final result = sweep('test/fixtures/perp-true-unproved.rgl');
    expect(result.candidates, 26);
    expect(result.allComplete, isTrue);

    expect(
      result.unlocks.keys,
      unorderedEquals(<String>['midpoint(B,C)', 'midpoint(B,F)']),
      reason: 'JGEX\'s own point, and one more midpoint on the same line',
    );
    for (final entry in result.unlocks.entries) {
      expect(entry.value, hasLength(1), reason: entry.key);
      final fact = entry.value.single;
      expect(fact.kind, PredicateKind.perp);
      expect(
        {for (final point in fact.points) point.attributes.name},
        {'C', 'D', 'F'},
        reason: 'perp(C,D,D,F) — the theorem, and the only thing unlocked',
      );
    }
  });

  test('the theorem is a certificate once the point is there', () {
    // The unlock is worth nothing if the proof does not verify: a
    // search that proposes points and reports unreadable steps has not
    // answered the user's question.
    final construction = load('test/fixtures/perp-true-unproved.rgl');
    final candidates = auxiliaryCandidates(construction.objects);
    GeoPoint named(String name) => construction.objects
        .whereType<GeoPoint>()
        .firstWhere((point) => point.attributes.name == name);
    final wanted = ([named('B').id, named('C').id]..sort()).join('|');
    final chosen = candidates.singleWhere(
      (candidate) =>
          candidate.family == AuxiliaryFamily.midpoint &&
          ([
                for (final parent in candidate.parents) parent.id,
              ]..sort()).join('|') ==
              wanted,
    );
    construction.add(chosen.build('aux'));

    final run = prove(construction);
    final goal = Fact(PredicateKind.perp, [
      named('C'),
      named('D'),
      named('D'),
      named('F'),
    ]);
    expect(run.database.contains(goal), isTrue);
    final proof = Proof.of(goal, run.database);
    expect(proof.verify(), isEmpty);
    expect(
      proof.deductions.any(
        (step) => step.fact.points.any((point) => point.id == 'aux'),
      ),
      isTrue,
      reason:
          'the proof cites the invented point — which is the whole '
          'reason the checklist wants it named in the step list',
    );
  });

  test('nothing else in the corpus unlocks anything, in any family', () {
    for (final path in fixtures) {
      final result = sweep(path);
      expect(result.allComplete, isTrue, reason: '$path did not converge');
      final unlocks = Map.of(result.unlocks);
      if (path == 'test/fixtures/perp-true-unproved.rgl') {
        // Pinned in full by the first test.
        unlocks.removeWhere(
          (candidate, _) =>
              candidate == 'midpoint(B,C)' || candidate == 'midpoint(B,F)',
        );
      }
      expect(
        unlocks,
        isEmpty,
        reason: '$path: ${result.candidates} candidates were tried',
      );
    }
  });

  test('the fact set is the wrong metric, and this is why', () {
    // Kept because it is the trap: comparing fact sets makes an
    // auxiliary point look useful on documents where it is not, and
    // reading `para(F,G,F,B)` as new content would have made every
    // number in this file wrong by an order of magnitude.
    final construction = load('test/fixtures/no-locus.rgl');
    GeoPoint named(String name) => construction.objects
        .whereType<GeoPoint>()
        .firstWhere((point) => point.attributes.name == name);
    final restatement = Fact(PredicateKind.para, [
      named('F'),
      named('G'),
      named('F'),
      named('B'),
    ]);

    final baseline = prove(construction);
    expect(
      baseline.database.contains(restatement),
      isFalse,
      reason: 'the closure declines to publish a para that shares a point',
    );
    expect(
      baseline.prover.resolve(restatement),
      isTrue,
      reason: 'and entails it all the same, off the hypothesis coll(F,G,B)',
    );
  });
}
