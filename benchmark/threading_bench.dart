// Phase 140 / M-P0 SPIKE: how a long fixpoint runs without freezing the UI.
//
// PLAN pins the shape before any prover code exists: "No isolates on web.
// The prover engine is written as a resumable state machine with an
// explicit work queue from day one — cooperatively chunked on web,
// `Isolate.run`-wrapped on native, Worker-portable later. A straight-line
// fixpoint loop cannot be retrofitted." This harness is the measurement
// that decision is taken against, and it is a spike in the Phase 101
// sense: a synthetic workload of the right *shape*, benchmarked before
// anything depends on the answer.
//
// The workload is DD forward chaining's shape, not a real prover: a fact
// database keyed by canonical form, and rules that derive new facts from
// pairs of known ones, applied in rounds until nothing new appears. What
// makes it representative is the cost profile — a growing set scanned
// against itself, with set membership on the inner loop and a work queue
// that both drains and refills — not the geometry, which is absent.
//
// Three ways of running the same fixpoint are compared:
//
//   straight    the whole fixpoint in one synchronous call. The baseline
//               throughput, and on web the thing that freezes the tab.
//   stepped     the same engine driven through `Fixpoint.step(budget)`,
//               synchronously, with no yielding. Isolates the cost of the
//               resumable *structure* from the cost of yielding.
//   chunked     stepped, yielding between steps with the *Dart-idiomatic*
//               `Future.delayed(Duration.zero)`. This looks like the web
//               plan and is not: on the web targets it compiles to
//               `setTimeout(f, 0)`, which is clamped, and the numbers
//               below are what that clamp does to a fixpoint (154x on
//               dart2wasm; dart2js does not finish). The yield the
//               prover actually uses is a `MessageChannel` macrotask,
//               measured in `test/web/yield_cost_web_test.dart` at 0.048
//               ms against this route's 5.07 ms — in a real browser,
//               because neither the VM nor Node implements the clamp
//               that decides it.
//
// Run on VM (`dart run`), AOT, dart2js and dart2wasm via
// `benchmark/run_threading.sh`. Keep this file Flutter-free — and free of
// `dart:isolate`, which compiles for web and throws at runtime (see
// `isolate_bench.dart`, native-only, for that half).
//
// ignore_for_file: avoid_print

/// A derived fact: a rule, applied to two premises, yielding a key.
///
/// Facts are `int` keys rather than canonicalized strings because the
/// canonicalization cost is M-P2's problem (eqangle/eqratio normal forms)
/// and would swamp exactly the structural cost this spike is measuring.
/// What is kept is the shape: hash-set membership on the inner loop.
typedef Fact = int;

/// The synthetic rule set. Each rule combines two facts into a candidate;
/// the mixing is arbitrary but fixed, so every target derives an
/// identical database and the checksums are comparable.
///
/// The modulus is what makes the fixpoint terminate: candidates collide
/// with facts already known, the new-fact rate decays, and the run
/// reaches quiescence — the same convergence shape a real DD run has,
/// where most rule applications rediscover something. It is also the
/// only dial on how long a run takes (work is ~3·N² applications), and
/// it is set so the straight-line baseline lands in the tens of
/// milliseconds: long enough to measure, short enough to repeat 5×
/// across four compile targets.
const _factSpace = 1 << 11;

int _rule0(Fact a, Fact b) => (a * 3 + b * 5 + 1) % _factSpace;
int _rule1(Fact a, Fact b) => (a ^ (b << 2)) % _factSpace;
int _rule2(Fact a, Fact b) => (a + b * b + 7) % _factSpace;

const _rules = [_rule0, _rule1, _rule2];

/// The engine, as a resumable state machine with an explicit work queue.
///
/// This is the shape PLAN mandates, and the point of writing it here is
/// that the same object serves all three drivers below: [runToFixpoint]
/// is the straight-line loop, and [step] is that loop with a budget and a
/// return. Nothing about the algorithm differs between them — which is
/// the property that cannot be retrofitted onto a straight-line loop, and
/// the reason to pin the shape before the prover is written.
class Fixpoint {
  Fixpoint(List<Fact> seeds) {
    for (final seed in seeds) {
      if (_known.add(seed)) {
        _queue.add(seed);
        _against.add(seed);
      }
    }
  }

  /// Facts derived so far, and the membership test on the inner loop.
  final Set<Fact> _known = {};

  /// Facts whose consequences have not been drawn yet. The explicit
  /// queue *is* the resumability: it and [_known] are the whole of the
  /// engine's state, so a step boundary needs no call stack.
  final List<Fact> _queue = [];

  /// Where the next step resumes inside the current fact's rule sweep.
  /// A step can end mid-fact — with a large database one fact's sweep is
  /// itself too much work for a frame — so the cursor is part of the
  /// state, not a loop variable.
  int _cursorRule = 0;
  int _cursorAgainst = 0;

  /// The database as a list, for the sweep to index. Part of the state
  /// rather than a local, because a sweep that spans a step boundary
  /// must not re-materialize it: doing so would charge the resumable
  /// engine an O(facts) allocation *per step*, which is an artifact of
  /// the driver rather than a cost of the shape — and at a small budget
  /// it dominates everything being measured.
  ///
  /// Appending to it as facts are derived is deliberate and safe: the
  /// sweep only ever reads at [_cursorAgainst] and up, so a fact added
  /// beyond the cursor is simply swept too. (A `Set` in Dart iterates in
  /// insertion order, so the prefix is stable — but nothing here relies
  /// on that, since the list is now built once and appended to.)
  final List<Fact> _against = [];

  int get factCount => _known.length;
  bool get isDone => _queue.isEmpty;

  /// A checksum of the derived database, so the three drivers and the
  /// four compile targets can be shown to have computed the same thing.
  int get checksum {
    var sum = 0;
    for (final fact in _known) {
      sum = (sum + fact) % 0x7fffffff;
    }
    return sum;
  }

  /// Draws consequences until [budget] rule applications are spent or the
  /// queue drains. Returns the applications actually spent — less than
  /// the budget only at quiescence.
  ///
  /// The budget is counted in *rule applications* rather than facts or
  /// wall-clock: applications are the unit whose cost is flat (one
  /// arithmetic combination plus one set probe), which is what makes a
  /// budget chosen on one machine mean something on another. The same
  /// argument as Phase 139's step budget, and it is not a coincidence —
  /// both are bounding a resumable walk by work rather than by time.
  int step(int budget) {
    var spent = 0;
    while (spent < budget && _queue.isNotEmpty) {
      final fact = _queue.last;
      // Sweep this fact against the database, resuming at the cursor.
      while (_cursorRule < _rules.length) {
        final rule = _rules[_cursorRule];
        while (_cursorAgainst < _against.length) {
          if (spent >= budget) return spent;
          final derived = rule(fact, _against[_cursorAgainst]);
          _cursorAgainst++;
          spent++;
          if (_known.add(derived)) {
            _queue.add(derived);
            _against.add(derived);
          }
        }
        _cursorAgainst = 0;
        _cursorRule++;
      }
      _cursorRule = 0;
      // The fact just swept is not necessarily `_queue.last` any more —
      // facts derived above were appended. Removing by value keeps the
      // machine correct across a step boundary that landed mid-sweep,
      // and is unambiguous because `_known` makes queue entries unique.
      _queue.remove(fact);
    }
    return spent;
  }

  /// The straight-line fixpoint: the baseline, and what a naive engine
  /// would be. Deliberately not implemented in terms of [step] — the
  /// comparison below is meaningless if the baseline pays the stepped
  /// engine's bookkeeping.
  void runToFixpoint() {
    while (_queue.isNotEmpty) {
      final fact = _queue.removeLast();
      for (final rule in _rules) {
        for (var i = 0; i < _against.length; i++) {
          final derived = rule(fact, _against[i]);
          if (_known.add(derived)) {
            _queue.add(derived);
            _against.add(derived);
          }
        }
      }
    }
  }
}

/// Seeds chosen to make a run big enough to matter and small enough to
/// repeat: the fixpoint below settles at a few thousand facts.
List<Fact> _seeds() => [for (var i = 0; i < 12; i++) i * 37 + 1];

// --- the three drivers ------------------------------------------------

int straight() {
  final engine = Fixpoint(_seeds())..runToFixpoint();
  return engine.checksum;
}

int stepped(int budget) {
  final engine = Fixpoint(_seeds());
  while (!engine.isDone) {
    engine.step(budget);
  }
  return engine.checksum;
}

/// The stepped engine, yielding to the event loop between steps so the
/// frame pipeline and input handlers get a turn.
///
/// `Future.delayed(Duration.zero)` rather than a bare `await null` or
/// `scheduleMicrotask`: a microtask does *not* yield to the browser's
/// event loop — the microtask queue drains before the frame does, so a
/// microtask-chunked fixpoint freezes the tab exactly as the straight
/// loop does, while looking asynchronous. That distinction is the whole
/// mechanism, so it is measured rather than asserted (see `microtask`).
///
/// It is also, on web, the *wrong* macrotask: `Future.delayed` is a
/// timer, and timers are clamped. Phase 140 measured the replacement in
/// a browser (`test/web/yield_cost_web_test.dart`); what this driver
/// contributes is the size of the trap, which is what makes the finding
/// worth having.
Future<int> chunked(int budget) async {
  final engine = Fixpoint(_seeds());
  while (!engine.isDone) {
    engine.step(budget);
    await Future<void>.delayed(Duration.zero);
  }
  return engine.checksum;
}

/// The wrong yield, kept as the control: same structure, microtask hop.
/// Its throughput is the cheap half of the comparison; what it does not
/// buy is anything at all, which no throughput number can show.
Future<int> microtask(int budget) async {
  final engine = Fixpoint(_seeds());
  while (!engine.isDone) {
    engine.step(budget);
    await null;
  }
  return engine.checksum;
}

// --- harness ----------------------------------------------------------

/// Warmup ×2, best of 5 — `tracing_bench.dart`'s shape.
double _bench(int Function() run, void Function(int) record) {
  run();
  run();
  var bestUs = double.infinity;
  final sw = Stopwatch();
  for (var i = 0; i < 5; i++) {
    sw
      ..reset()
      ..start();
    record(run());
    sw.stop();
    final us = sw.elapsedMicroseconds.toDouble();
    if (us < bestUs) bestUs = us;
  }
  return bestUs / 1000;
}

Future<double> _benchAsync(
  Future<int> Function() run,
  void Function(int) record,
) async {
  await run();
  var bestUs = double.infinity;
  final sw = Stopwatch();
  for (var i = 0; i < 3; i++) {
    sw
      ..reset()
      ..start();
    record(await run());
    sw.stop();
    final us = sw.elapsedMicroseconds.toDouble();
    if (us < bestUs) bestUs = us;
  }
  return bestUs / 1000;
}

/// One 60 Hz frame. A chunk must fit in what is left of this after the
/// app has drawn — the drag gate already claims up to 19% of an 8 ms
/// kernel budget, so a prover chunk has single-digit milliseconds at best.
const frameMs = 16.7;

final _checksums = <String, int>{};

Future<void> main(List<String> args) async {
  final scale = args.isEmpty ? 1 : int.parse(args.first);
  final budgets = [
    for (final b in [1000, 5000, 20000, 100000, 500000]) b * scale,
  ];

  final engine = Fixpoint(_seeds())..runToFixpoint();
  print(
    'synthetic DD fixpoint: ${engine.factCount} facts at quiescence, '
    'checksum ${engine.checksum}',
  );
  print('');

  final straightMs = _bench(straight, (c) => _checksums['straight'] = c);
  print(
    'straight-line loop     ${straightMs.toStringAsFixed(2).padLeft(8)} ms'
    '   (the baseline; on web this is the frozen tab)',
  );
  print('');

  print('resumable engine, driven synchronously — the cost of the shape:');
  for (final budget in budgets) {
    final ms = _bench(
      () => stepped(budget),
      (c) => _checksums['stepped$budget'] = c,
    );
    print(
      '  budget ${budget.toString().padLeft(8)}  '
      '${ms.toStringAsFixed(2).padLeft(8)} ms  '
      '${(ms / straightMs).toStringAsFixed(2).padLeft(6)}x baseline  '
      '${_stepsFor(budget).toString().padLeft(6)} steps',
    );
  }
  print('');

  print('…and yielding between steps — the web plan:');
  for (final budget in budgets) {
    final ms = await _benchAsync(
      () => chunked(budget),
      (c) => _checksums['chunked$budget'] = c,
    );
    final steps = _stepsFor(budget);
    final perStep = ms / steps;
    print(
      '  budget ${budget.toString().padLeft(8)}  '
      '${ms.toStringAsFixed(2).padLeft(8)} ms  '
      '${(ms / straightMs).toStringAsFixed(2).padLeft(6)}x baseline  '
      '${steps.toString().padLeft(6)} steps  '
      '${perStep.toStringAsFixed(3).padLeft(8)} ms/step'
      '${perStep <= frameMs ? '' : '   <- a step overruns a frame'}',
    );
  }
  print('');

  final microMs = await _benchAsync(
    () => microtask(budgets[1]),
    (c) => _checksums['microtask'] = c,
  );
  print(
    'the wrong yield (microtask, budget ${budgets[1]})  '
    '${microMs.toStringAsFixed(2).padLeft(8)} ms  '
    '${(microMs / straightMs).toStringAsFixed(2)}x baseline — cheaper than '
    'the event-loop hop and worth nothing: the microtask queue drains '
    'before the frame does.',
  );

  final distinct = _checksums.values.toSet();
  print('');
  print(
    distinct.length == 1
        ? 'all drivers agree: checksum ${distinct.single}'
        : 'DRIVERS DISAGREE: $_checksums',
  );
  if (distinct.length != 1) {
    throw StateError('the drivers computed different databases');
  }
}

/// How many steps a run at [budget] takes — measured once, so the
/// per-step column is real rather than derived from an assumption.
int _stepsFor(int budget) {
  final engine = Fixpoint(_seeds());
  var steps = 0;
  while (!engine.isDone) {
    engine.step(budget);
    steps++;
  }
  return steps;
}
