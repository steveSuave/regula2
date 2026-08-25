// Phase 167: the prover against a real benchmark, for the first time.
//
// `docs/PLAN.md` ends five separate measurements with the same sentence
// — "the corpus is the limiting factor, not the algebra". The seven
// fixtures in `test/fixtures/` cannot show a prover feature working or
// failing: four independent pieces of M-P3 measured to zero on them, the
// whole length system yields one fact on one document, and 276
// auxiliary candidates yield two unlocks. This runs the engine over
// Newclid's problem corpus instead — 879 goals drawn from the
// JGEX/AlphaGeometry benchmark, the IMO and its shortlist — and reports
// what it proves.
//
// It reports refusals as loudly as answers. A translator that quietly
// dropped what it could not read would make the whole number a
// measurement of the translator's taste, so every problem lands in
// exactly one bucket and the buckets sum to the corpus.
//
// The corpus is *not* vendored: it is someone else's data and 300
// problems do not belong in `test/fixtures/`, which is v1's permanent
// save-format corpus. Point `--corpus` at a checkout.
//
// Run: dart run benchmark/corpus_bench.dart
//      dart run benchmark/corpus_bench.dart --corpus=/path/to/problems_datasets
//      dart run benchmark/corpus_bench.dart --files=examples.txt --limit=20
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

import '../test/corpus/newclid_problem.dart';
import '../test/corpus/newclid_translation.dart';

/// The provider's own numbers, so the benchmark measures the engine the
/// app runs rather than a more generous one.
const int chunkBudget = 250;
const int applicationBudget = 30000;

const String defaultCorpus = 'Code/var/Newclid/newclid/problems_datasets';

/// Where a problem ended up. Every problem lands in exactly one.
enum Bucket {
  proved,
  refuted,
  unproved,
  undecided,
  unknownMacro,
  unsupportedGoal,
  unsupportedClause,
  degenerate,
  goalFalseInFigure,
  parseError,
}

class Row {
  Row(
    this.source,
    this.name,
    this.bucket, {
    this.applications = 0,
    this.ms = 0,
  });

  final String source;
  final String name;
  final Bucket bucket;
  final int applications;
  final int ms;
}

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '.';
  var corpus = '$home/$defaultCorpus';
  var limit = -1;
  var only = <String>{};
  var verbose = false;
  for (final arg in args) {
    if (arg.startsWith('--corpus=')) {
      corpus = arg.substring('--corpus='.length);
    } else if (arg.startsWith('--limit=')) {
      limit = int.parse(arg.substring('--limit='.length));
    } else if (arg.startsWith('--files=')) {
      only = arg.substring('--files='.length).split(',').toSet();
    } else if (arg == '--verbose') {
      verbose = true;
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 2;
      return;
    }
  }

  final directory = Directory(corpus);
  if (!directory.existsSync()) {
    stderr.writeln(
      'no corpus at $corpus\n'
      'pass --corpus=<newclid>/newclid/problems_datasets',
    );
    exitCode = 2;
    return;
  }

  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final rows = <Row>[];
  final started = DateTime.now();
  for (final file in files) {
    final source = file.uri.pathSegments.last;
    if (only.isNotEmpty && !only.contains(source)) continue;
    final parsed = parseNewclidProblems(
      file.readAsStringSync(),
      source: source,
    );
    for (final error in parsed.errors) {
      stderr.writeln('$error');
      rows.add(Row(source, error.name, Bucket.parseError));
    }
    final problems = parsed.problems;
    var seen = 0;
    for (final problem in problems) {
      if (limit >= 0 && seen >= limit) break;
      seen++;
      rows.add(await _measure(problem, verbose: verbose));
    }
  }

  _report(rows, DateTime.now().difference(started));
}

Future<Row> _measure(NewclidProblem problem, {required bool verbose}) async {
  final translation = translateNewclidProblem(problem);
  if (translation is UntranslatableProblem) {
    if (verbose) print('  skip ${problem.name}: ${translation.detail}');
    return Row(problem.source, problem.name, switch (translation.reason) {
      UntranslatableReason.unknownMacro => Bucket.unknownMacro,
      UntranslatableReason.unsupportedGoal => Bucket.unsupportedGoal,
      UntranslatableReason.unsupportedClause => Bucket.unsupportedClause,
      UntranslatableReason.degenerate => Bucket.degenerate,
      UntranslatableReason.goalFalseInFigure => Bucket.goalFalseInFigure,
    });
  }
  final built = translation as TranslatedProblem;
  final objects = built.construction.objects.toList();
  final clock = Stopwatch()..start();
  final filter = DiagramFilter.probe(objects);
  if (!filter.holds(built.question.canonical)) {
    // The translator already refused a goal false in its own figure, so
    // reaching here means the statement fails under perturbation while
    // holding in the drawn position — which is what refutation is.
    return Row(
      problem.source,
      problem.name,
      Bucket.refuted,
      ms: clock.elapsedMilliseconds,
    );
  }
  final database = FactDatabase();
  seedHypotheses(database, hypotheses(objects), filter);
  final engine = Prover(database: database, filter: filter);
  Fact? reached() {
    for (final spelling in built.question.spellings) {
      final fact = Fact.of(spelling);
      if (engine.resolve(fact)) return fact;
    }
    return null;
  }

  await engine.runChunked(
    chunkBudget: chunkBudget,
    maxApplications: applicationBudget,
    stopWhen: () => reached() != null,
  );
  clock.stop();
  final fact = reached();
  final bucket = fact != null
      ? Bucket.proved
      : engine.isComplete
      ? Bucket.unproved
      : Bucket.undecided;
  if (fact != null) {
    // Reading the proof is part of the measurement: a "proved" whose
    // proof does not verify would be worse than an unproved.
    final proof = Proof.of(fact, engine.database);
    final unsound = proof.verify();
    if (unsound.isNotEmpty) {
      stderr.writeln('UNSOUND ${problem.source}:${problem.name} $unsound');
    }
  }
  if (verbose) {
    print(
      '  ${bucket.name.padRight(10)} ${problem.name} '
      '(${engine.applications} apps, ${clock.elapsedMilliseconds} ms)',
    );
  }
  return Row(
    problem.source,
    problem.name,
    bucket,
    applications: engine.applications,
    ms: clock.elapsedMilliseconds,
  );
}

void _report(List<Row> rows, Duration wall) {
  final bySource = <String, List<Row>>{};
  for (final row in rows) {
    bySource.putIfAbsent(row.source, () => []).add(row);
  }
  const answered = {
    Bucket.proved,
    Bucket.refuted,
    Bucket.unproved,
    Bucket.undecided,
  };

  print('');
  print('The prover against Newclid\'s corpus (Phase 167)');
  print('budget $applicationBudget applications, chunk $chunkBudget');
  print('');
  final header = [
    'file',
    'total',
    'built',
    'proved',
    'unprov',
    'undec',
    'refut',
  ].map((cell) => cell.padLeft(8)).join(' ');
  print(header);
  print('-' * header.length);
  for (final entry in bySource.entries) {
    final list = entry.value;
    final built = list.where((row) => answered.contains(row.bucket)).length;
    print(
      [
        entry.key.replaceAll('.txt', ''),
        '${list.length}',
        '$built',
        '${list.where((r) => r.bucket == Bucket.proved).length}',
        '${list.where((r) => r.bucket == Bucket.unproved).length}',
        '${list.where((r) => r.bucket == Bucket.undecided).length}',
        '${list.where((r) => r.bucket == Bucket.refuted).length}',
      ].map((cell) => cell.padLeft(8)).join(' '),
    );
  }
  print('-' * header.length);
  final built = rows.where((row) => answered.contains(row.bucket)).length;
  print(
    [
      'all',
      '${rows.length}',
      '$built',
      '${rows.where((r) => r.bucket == Bucket.proved).length}',
      '${rows.where((r) => r.bucket == Bucket.unproved).length}',
      '${rows.where((r) => r.bucket == Bucket.undecided).length}',
      '${rows.where((r) => r.bucket == Bucket.refuted).length}',
    ].map((cell) => cell.padLeft(8)).join(' '),
  );

  print('');
  print('why the rest did not build');
  for (final bucket in Bucket.values) {
    if (answered.contains(bucket)) continue;
    final count = rows.where((row) => row.bucket == bucket).length;
    if (count == 0) continue;
    print('  ${bucket.name.padRight(20)} $count');
  }

  final timed = rows.where((row) => answered.contains(row.bucket)).toList();
  if (timed.isNotEmpty) {
    final total = timed.fold(0, (sum, row) => sum + row.ms);
    final worst = timed.reduce((a, b) => a.ms >= b.ms ? a : b);
    print('');
    print(
      'prover time $total ms over ${timed.length} problems '
      '(mean ${(total / timed.length).toStringAsFixed(0)} ms, '
      'worst ${worst.ms} ms on ${worst.source}:${worst.name})',
    );
  }
  print('wall ${wall.inSeconds} s');
}
