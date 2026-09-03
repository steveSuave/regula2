// Phase 188: which join shapes dominate the uncharged half of a DD pass.
//
// `proverChunkBudget` bounds only the *charged* half of a step — the
// fully-bound premise combinations — and Phase 161 measured that the
// freeze on the slow fixtures is the other half: the join enumeration
// that yields no candidate, advanced without being counted. Phase 163
// repriced it (the worst pass fell to under 300 ms once
// `eqangle_transitive` went) and guessed the remainder was the
// `eqangle × eqangle` joins. This rig replaces the guess with a number:
// the engine tallies every binding attempt per rule (`Prover.tallies`),
// and the report reads the tallies pass by pass at the provider's chunk.
//
// Reports, per fixture: the worst pass (time, visits, applications) with
// its per-rule visit deltas, and the whole run's per-rule tallies —
// both sorted by visits, so the shape the fix should aim at is the top
// line.
//
// Run: dart run benchmark/prover_join_bench.dart [fixture …]
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

const defaultFixtures = [
  'test/fixtures/apatitos-topos.rgl',
  'test/fixtures/tangent-chase.rgl',
  'test/fixtures/provoleas2.json',
  'test/fixtures/perp-true-unproved.rgl',
];

/// The provider's chunk, and its cap (`provoleas2.json` never quiesces).
const chunk = 250;
const cap = 30000;

/// How many rules to list per table.
const top = 8;

void main(List<String> args) {
  for (final path in args.isEmpty ? defaultFixtures : args) {
    final objects = List<GeoObject>.of(
      decodeDocument(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
      ).construction.objects,
    );
    final filter = DiagramFilter.probe(objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(objects), filter);
    final prover = Prover(database: database, filter: filter);

    var worstMicros = 0;
    var worstIndex = -1;
    var worstDelta = <String, RuleTally>{};
    var before = prover.tallies;
    var passes = 0;
    while (!prover.isComplete && prover.applications < cap) {
      final watch = Stopwatch()..start();
      prover.run(maxApplications: chunk);
      watch.stop();
      final after = prover.tallies;
      final micros = watch.elapsedMicroseconds;
      // The first pass pays JIT warm-up; it is only the worst if it is
      // the only one.
      if (micros > worstMicros && (passes > 0 || worstIndex < 0)) {
        worstMicros = micros;
        worstIndex = passes;
        worstDelta = {
          for (final name in after.keys) name: after[name]! - before[name]!,
        };
      }
      before = after;
      passes++;
    }

    final total = prover.tallies;
    final sumAll = RuleTally.sum(total.values);
    final sumWorst = RuleTally.sum(worstDelta.values);
    print(
      '${path.split('/').last}: $passes passes, ${database.facts.length} '
      'facts, complete ${prover.isComplete}',
    );
    print(
      '  run: ${sumAll.visits} visits, ${sumAll.applications} apps, '
      '${sumAll.derived} derived '
      '(${(sumAll.visits / sumAll.applications).toStringAsFixed(0)} '
      'visits/app)',
    );
    _table(total, sumAll);
    print(
      '  worst pass #$worstIndex: ${worstMicros / 1000} ms, '
      '${sumWorst.visits} visits, ${sumWorst.applications} apps, '
      '${sumWorst.derived} derived',
    );
    _table(worstDelta, sumWorst);
  }
}

void _table(Map<String, RuleTally> tallies, RuleTally sum) {
  final rows = tallies.entries.where((e) => e.value.visits > 0).toList()
    ..sort((a, b) => b.value.visits.compareTo(a.value.visits));
  for (final row in rows.take(top)) {
    final t = row.value;
    final share = (100 * t.visits / sum.visits).toStringAsFixed(1);
    print(
      '    ${row.key.padRight(26)} ${t.visits.toString().padLeft(9)} visits '
      '${share.padLeft(5)}%  ${t.applications.toString().padLeft(6)} apps  '
      '${t.derived.toString().padLeft(4)} derived',
    );
  }
}
