// Phase 140 / M-P0: what `Isolate.run` costs, and what it cannot do.
//
// Native-only, deliberately. `dart:isolate` **compiles cleanly for both
// web targets and fails at runtime** — `UnsupportedError: new
// RawReceivePort` on dart2js, a trap on dart2wasm — so an isolate
// smuggled into shared code is a web crash that the compiler will not
// catch and only a browser test will. That asymmetry is half of what
// M-P0 has to record, and it is why this file is separate from
// `threading_bench.dart` rather than a section of it.
//
// The other half is the cost. An isolate is not free: it starts a fresh
// Dart heap, and everything crossing the boundary is copied, since the
// two heaps share nothing. The prover's inputs (a diagram's projected
// positions) are small; its output (a fact database, and a proof DAG
// that references it) is not necessarily. So the question this measures
// is not "is a background thread faster" — obviously it is, it is a
// whole core — but whether the copy at the boundary eats the win, and at
// what size.
//
// Run on VM (`dart run`) and AOT via `benchmark/run_isolate.sh`.
//
// ignore_for_file: avoid_print

import 'dart:isolate';

/// The same synthetic fixpoint `threading_bench.dart` measures, reduced
/// to a top-level function so it can cross an isolate boundary. Kept
/// byte-comparable to that file's engine on purpose: the two benchmarks
/// answer halves of one question and must be measuring one workload.
const _factSpace = 1 << 11;

int _rule0(int a, int b) => (a * 3 + b * 5 + 1) % _factSpace;
int _rule1(int a, int b) => (a ^ (b << 2)) % _factSpace;
int _rule2(int a, int b) => (a + b * b + 7) % _factSpace;

List<int> _fixpoint(List<int> seeds) {
  final known = <int>{};
  final queue = <int>[];
  final against = <int>[];
  for (final seed in seeds) {
    if (known.add(seed)) {
      queue.add(seed);
      against.add(seed);
    }
  }
  while (queue.isNotEmpty) {
    final fact = queue.removeLast();
    for (final rule in [_rule0, _rule1, _rule2]) {
      for (var i = 0; i < against.length; i++) {
        final derived = rule(fact, against[i]);
        if (known.add(derived)) {
          queue.add(derived);
          against.add(derived);
        }
      }
    }
  }
  return against;
}

List<int> _seeds() => [for (var i = 0; i < 12; i++) i * 37 + 1];

/// A trivial round trip: what it costs merely to *have* an isolate.
Future<double> _spawnLatency(int n) async {
  await Isolate.run(() => 0);
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await Isolate.run(() => 0);
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000 / n;
}

/// The round trip carrying a result of [size] ints back — the fact
/// database coming home. Isolates the copy from the spawn by subtracting
/// the latency measured above.
Future<double> _returnCost(int n, int size) async {
  await Isolate.run(() => List<int>.filled(size, 7));
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    final result = await Isolate.run(() => List<int>.filled(size, 7));
    if (result.length != size) throw StateError('bad result');
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000 / n;
}

double _inline(int n) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    _fixpoint(_seeds());
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000 / n;
}

Future<double> _offThread(int n) async {
  await Isolate.run(() => _fixpoint(_seeds()));
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await Isolate.run(() => _fixpoint(_seeds()));
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000 / n;
}

Future<void> main(List<String> args) async {
  final scale = args.isEmpty ? 1 : int.parse(args.first);

  final latency = await _spawnLatency(20 * scale);
  print(
    'Isolate.run round trip, empty      '
    '${latency.toStringAsFixed(3).padLeft(9)} ms'
    '   — the price of having a thread at all',
  );

  print('');
  print('…carrying a result home (the fact database):');
  for (final size in [1000, 10000, 100000, 1000000]) {
    final total = await _returnCost(10 * scale, size);
    final copy = total - latency;
    print(
      '  ${size.toString().padLeft(8)} ints  '
      '${total.toStringAsFixed(3).padLeft(9)} ms  '
      'copy ${copy.toStringAsFixed(3).padLeft(8)} ms  '
      '${(copy / size * 1e6).toStringAsFixed(1).padLeft(6)} ns/int',
    );
  }

  print('');
  final inlineMs = _inline(5 * scale);
  final offMs = await _offThread(5 * scale);
  print(
    'the synthetic fixpoint, inline     '
    '${inlineMs.toStringAsFixed(2).padLeft(9)} ms',
  );
  print(
    'the same, via Isolate.run          '
    '${offMs.toStringAsFixed(2).padLeft(9)} ms'
    '   ${(offMs / inlineMs).toStringAsFixed(2)}x'
    '   (${(offMs - inlineMs).toStringAsFixed(2)} ms of boundary)',
  );
  print('');
  print(
    'Read this as latency, not throughput: the isolate does not make the '
    'work faster, it makes it someone else\'s. What the numbers decide is '
    'the size of job worth exporting — below the round trip, chunking on '
    'the main thread wins outright.',
  );
}
