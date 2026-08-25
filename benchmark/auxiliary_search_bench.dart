// Phase 153: what an auxiliary-point search costs, and what it buys.
//
// The engine half of A2 is "when the fixpoint stalls without the goal,
// propose points and re-run" — a search, and the checklist asks for its
// budget and its order to be measured rather than chosen. This is the
// exhaustive form of that measurement: every candidate
// (`auxiliaryCandidates`) added one at a time to a fresh copy of the
// document, the exchange run to quiescence, and the facts about the
// document's *own* points that the baseline cannot answer read off.
//
// `test/domain/prover/auxiliary_upside_test.dart` pins the finding on
// the five fixtures a suite can carry and explains the metric — why the
// screen is `Prover.resolve` and not a fact-set difference, which
// over-counts by an order of magnitude. This file adds the two heavy
// documents (68 of the sweep's 77 seconds) and reports the timings,
// timings not being a thing to assert.
//
// Reports, per fixture: the candidate count by family, the baseline
// run, the per-candidate cost, the worst candidate, how many failed to
// converge under the cap, and every unlock with the fact it reached.
//
// Run: dart run benchmark/auxiliary_search_bench.dart
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/prover/auxiliary_points.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

const fixtures = [
  'test/fixtures/locus3.json',
  'test/fixtures/apatitos-topos.rgl',
  'test/fixtures/no-locus.rgl',
  'test/fixtures/perp-true-unproved.rgl',
  'test/fixtures/provoleas2.json',
  'test/fixtures/tangent-chase.rgl',
  'test/fixtures/tangent-chord.rgl',
];

/// High enough that every candidate run in the sweep reaches
/// quiescence — measured, not assumed: at the provider's 30 000 nine of
/// `provoleas2`'s candidates were still deriving, and raising the cap
/// cost 3 seconds of 49 and changed no conclusion.
const cap = 200000;

Construction load(String path) => decodeDocument(
  jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
).construction;

({FactDatabase database, Prover prover, bool complete, int micros}) prove(
  Construction construction,
) {
  final watch = Stopwatch()..start();
  final filter = DiagramFilter.probe(construction.objects);
  final database = FactDatabase();
  seedHypotheses(database, hypotheses(construction.objects), filter);
  final prover = Prover(database: database, filter: filter)
    ..run(maxApplications: cap);
  watch.stop();
  return (
    database: database,
    prover: prover,
    complete: prover.isComplete,
    micros: watch.elapsedMicroseconds,
  );
}

void main() {
  for (final path in fixtures) {
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
    String spell(Object thing) {
      var out = '$thing';
      names.forEach((id, name) => out = out.replaceAll(id, name));
      return out.replaceAll(', ', ',');
    }

    final candidates = auxiliaryCandidates(base.objects);
    final byFamily = <AuxiliaryFamily, int>{};
    for (final candidate in candidates) {
      byFamily[candidate.family] = (byFamily[candidate.family] ?? 0) + 1;
    }

    print('\n$path');
    print(
      '  ${base.objects.length} objects, '
      '${basePoints.length} points, '
      '${candidates.length} candidates '
      '${{for (final e in byFamily.entries) e.key.name: e.value}}',
    );
    print(
      '  baseline ${baseline.database.facts.length} facts, '
      '${baseline.prover.applications} applications, '
      '${(baseline.micros / 1000).toStringAsFixed(1)} ms, '
      'quiescent=${baseline.complete}',
    );

    var total = 0;
    var worst = 0;
    var stalled = 0;
    final unlocks = <String, List<String>>{};
    for (var i = 0; i < candidates.length; i++) {
      final fresh = load(path);
      fresh.add(auxiliaryCandidates(fresh.objects)[i].build('aux'));
      final run = prove(fresh);
      total += run.micros;
      if (run.micros > worst) worst = run.micros;
      if (!run.complete) stalled++;
      final novel = <String>[];
      for (final fact in run.database.facts) {
        final ids = [for (final point in fact.points) point.id];
        if (ids.any((id) => !basePoints.containsKey(id))) continue;
        final here = Fact(fact.kind, [for (final id in ids) basePoints[id]!]);
        if (baseline.prover.resolve(here)) continue;
        novel.add(spell(here));
      }
      if (novel.isNotEmpty) unlocks[spell(candidates[i])] = novel;
    }

    print(
      '  sweep ${(total / 1e6).toStringAsFixed(1)} s, '
      '${(total / candidates.length / 1000).toStringAsFixed(0)} ms per '
      'candidate, worst ${(worst / 1000).toStringAsFixed(0)} ms, '
      '$stalled hit the cap',
    );
    if (unlocks.isEmpty) {
      print('  unlocks: none');
    } else {
      for (final entry in unlocks.entries) {
        print('  unlock ${entry.key} -> ${entry.value.join(" | ")}');
      }
    }
  }
}
