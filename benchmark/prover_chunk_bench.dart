// Phase 156: pick `proverChunkBudget` from a measurement, not a guess.
//
// The chunk is the freeze: `Prover.runChunked` yields once per pass, so
// one pass — a DD step of up to `chunkBudget` applications plus one AR
// exchange — is the longest slice the main thread is blocked for, and a
// Stop button cannot be noticed sooner than that. The budget was 1 000,
// chosen when an application was believed to cost a flat amount; Phase
// 145 measured 65 µs to 2.3 ms per application, so the worst chunk had
// to be measured per document rather than derived.
//
// Reports, per fixture and per candidate budget: the number of passes,
// the worst single pass (the freeze), the worst pass after the first
// (the first one pays JIT warm-up), and the run's total. The prologue —
// probe + hypotheses + seed, which runs unyielded before the first pass
// and is a floor no chunk budget can lower — is timed separately.
//
// Run: dart run benchmark/prover_chunk_bench.dart
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

const fixtures = [
  'test/fixtures/locus3.json',
  'test/fixtures/apatitos-topos.rgl',
  'test/fixtures/no-locus.rgl',
  'test/fixtures/perp-true-unproved.rgl',
  'test/fixtures/provoleas2.json',
  'test/fixtures/tangent-chase.rgl',
  'test/fixtures/tangent-chord.rgl',
];

/// The provider's cap: `provoleas2.json` never reaches quiescence, so an
/// uncapped run there is a hang, not a measurement.
const cap = 30000;

void main() {
  for (final path in fixtures) {
    final objects = List<GeoObject>.of(
      decodeDocument(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
      ).construction.objects,
    );

    // The prologue, timed on its own engine. Median of five: probe is
    // randomized perturbation, so single samples wobble.
    final prologues = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      final filter = DiagramFilter.probe(objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(objects), filter);
      watch.stop();
      prologues.add(watch.elapsedMicroseconds);
    }
    prologues.sort();
    print('${path.split('/').last}: prologue ${prologues[2]} µs');

    for (final chunk in [1000, 500, 250, 125]) {
      final filter = DiagramFilter.probe(objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(objects), filter);
      final prover = Prover(database: database, filter: filter);
      var worst = 0;
      var worstWarm = 0;
      var total = 0;
      var passes = 0;
      // One `run(maxApplications: chunk)` call is one pass — the loop
      // inside spends its whole per-call budget on the first pass and
      // breaks — so timing the call times the freeze.
      while (!prover.isComplete && prover.applications < cap) {
        final watch = Stopwatch()..start();
        prover.run(maxApplications: chunk);
        watch.stop();
        final micros = watch.elapsedMicroseconds;
        if (micros > worst) worst = micros;
        if (passes > 0 && micros > worstWarm) worstWarm = micros;
        total += micros;
        passes++;
      }
      print(
        '  chunk $chunk: $passes passes, worst ${worst / 1000} ms '
        '(warm ${worstWarm / 1000} ms), total ${total ~/ 1000} ms, '
        '${prover.applications} apps, complete ${prover.isComplete}',
      );
    }
  }
}
