import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/prover/carriers.dart';
import '../../domain/prover/diagram_filter.dart';
import '../../domain/prover/fact.dart';
import '../../domain/prover/fact_database.dart';
import '../../domain/prover/hypotheses.dart';
import '../../domain/prover/proof.dart';
import '../../domain/prover/prover.dart';
import '../../domain/prover/questions.dart';
import '../../domain/prover/rule_engine.dart';
import 'construction_provider.dart';

part 'prover_provider.g.dart';

/// Rule applications per chunk between event-loop yields.
///
/// The chunk is the freeze — one pass is the longest slice the main
/// thread is blocked for, and a [ProverNotifier.stop] cannot be noticed
/// sooner — so the number comes from measuring the worst single pass per
/// fixture (`benchmark/prover_chunk_bench.dart`, VM, 2026-08-24), not
/// from a flat per-application cost, which Phase 145 already disproved.
///
/// **The budget bounds only the charged half of a pass, and the
/// measurement's finding is that the uncharged half dominates the worst
/// pass on half the corpus.** Worst pass at chunk 1000 / 500 / 250 / 125:
/// `provoleas2` 53 / 36 / 24 / 18 ms, `perp-true-unproved` 58 / 54 / 52 /
/// 51 ms (first pass; warm 7 / 4 / 2.3 / 1.8 ms), `locus3` 102 / 75 / 71 /
/// 43 ms — but `apatitos-topos` 1 415 / 1 388 / 1 388 / 1 275 ms and
/// `tangent-chase` 2 620 / 2 522 / 2 456 / 2 253 ms, essentially flat,
/// because their cost is the join enumeration that yields no candidate,
/// which is advanced without being charged as an application. No chunk
/// budget can make those passes frame-sized; bounding the enumeration is
/// engine work and its own phase (see Phase 156's notes in TODO).
///
/// **250 is the knee where the budget does bind**: on the blowup
/// document it turns a 53 ms worst pass into 24 ms — a dropped frame,
/// not a freeze — for a measured cost of +17 % total wall on the capped
/// run (809 → 951 ms, the extra AR exchanges) and +7 % applications on
/// `perp-true-unproved` (4 896 → 5 232, same fixpoint). 125 buys 6 ms
/// more for another +20 % wall: past the knee.
///
/// The unyielded prologue (probe + hypotheses + seed) measures 47–430 µs
/// across the corpus — a floor Stop cannot lower, and one that needs no
/// lowering.
const int proverChunkBudget = 250;

/// The ceiling on one [ProverNotifier.prove] call, in rule applications.
///
/// **Quiescence is not something a real document owes**, and that was a
/// measurement rather than a caution: `test/fixtures/provoleas2.json`
/// (27 objects, 23 hypotheses) was still deriving after 200 000
/// applications — the `eqangle` join blowup Session 156 named as
/// structural. Phase 163 found the blowup was one rule,
/// `eqangle_transitive` (128 orbit forms joined against 128), and
/// deleted it; that document now reaches quiescence at 25 826
/// applications and every fixture in the corpus converges under this
/// cap. The ceiling stays, because the next document is not the corpus:
/// exhaustion is a reported *state*, not a failure — everything derived
/// so far is a fixpoint prefix, and the engine resumes exactly where it
/// stopped ([ProverNotifier.proveMore]).
///
/// **30 000 was ~2 s in the regime where the cap bound** (~65 µs per
/// application on the VM, on the blowup rig as it was); documents that
/// reach quiescence do it in hundreds to tens of thousands of
/// applications. It stays counted in applications rather than milliseconds for
/// the Phase 139/140 reason — a run's outcome must be a function of the
/// document, not of the machine — with the honest caveat recorded in the
/// Phase 145 notes: an application's cost is *not* flat on the real rule
/// set (65 µs to 2.3 ms across the fixtures), because the join
/// enumeration that yields no candidate is not charged as one. The cap
/// bounds work in the engine's own unit; the wall-clock it buys is
/// document-dependent.
const int proverApplicationBudget = 30000;

/// What the prover has to say about one asked question (PLAN §M-P4).
///
/// **Three answers, not two, and the middle one is the point.** The
/// numeric filter sits beside the prover, so "false" and "true but out
/// of reach" are separable — and they are entirely different news. A
/// tool that collapsed them into "no" would tell a user their correct
/// theorem was wrong.
enum ProverVerdict {
  /// A perturbation breaks it, so it is not a theorem of the
  /// construction — answered by the filter alone, with no run at all.
  refuted,

  /// True in every sampled configuration, and the run finished without
  /// deriving it: past the DD core's reach. `perp-true-unproved.rgl` is
  /// the fixture, and closing this gap is what M-P3 is for.
  unproved,

  /// True, and derived: [ProverAnswer.proof] is the certificate.
  proved,

  /// True, and the run ran out of budget before settling it. Says
  /// nothing about reachability — which is exactly why it is not
  /// [unproved]. [ProverNotifier.askMore] spends more.
  undecided,
}

/// A question and the verdict on it.
class ProverAnswer {
  const ProverAnswer({
    required this.question,
    required this.verdict,
    this.proof,
  });

  final ProverQuestion question;
  final ProverVerdict verdict;

  /// The proof, exactly when [verdict] is [ProverVerdict.proved] — under
  /// whichever spelling the run happened to derive.
  final Proof? proof;

  @override
  bool operator ==(Object other) =>
      other is ProverAnswer &&
      identical(other.question, question) &&
      other.verdict == verdict &&
      identical(other.proof, proof);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(question), verdict, identityHashCode(proof));

  @override
  String toString() => 'ProverAnswer(${question.kind.name}, ${verdict.name})';
}

/// What the prover has to say about the document (PLAN §M-P4).
sealed class ProverState {
  const ProverState();
}

/// Nothing has been asked yet. The document is not un-proved; it is
/// un-queried — DD is the on-demand path, and this is what "on demand"
/// looks like before the demand.
class ProverIdle extends ProverState {
  const ProverIdle();

  @override
  bool operator ==(Object other) => other is ProverIdle;

  @override
  int get hashCode => (ProverIdle).hashCode;

  @override
  String toString() => 'ProverIdle()';
}

/// A run is in flight over the construction as of [revision].
class ProverRunning extends ProverState {
  const ProverRunning(this.revision, {this.applications = 0});

  final int revision;

  /// Rule applications spent so far, republished once per pass — what
  /// turns "the app is frozen" into "it is working, and here is how
  /// hard". Zero until the first pass reports.
  final int applications;

  @override
  bool operator ==(Object other) =>
      other is ProverRunning &&
      other.revision == revision &&
      other.applications == applications;

  @override
  int get hashCode => Object.hash(ProverRunning, revision, applications);

  @override
  String toString() =>
      'ProverRunning(revision: $revision, applications: $applications)';
}

/// A finished run, and the facts it reached.
///
/// [revision] is the construction revision the run read. It is here so a
/// consumer can tell a current answer from a stale one *without this
/// provider watching the construction* — see [ProverNotifier].
class ProverReady extends ProverState {
  ProverReady({
    required this.revision,
    required this.database,
    required this.applications,
    required this.reachedFixpoint,
  });

  final int revision;

  /// Every fact the run derived, each carrying the derivation it was
  /// discovered with — the proof DAG, already stored.
  final FactDatabase database;

  /// The run's incidence closure — which points name which line — read
  /// off [database] once, on first use. What lets a consumer tell a
  /// parallel from an identity (`CarrierIndex.isTrivial`).
  ///
  /// Built here rather than taken from the engine: `Prover.incidence`
  /// is the angle side's and may trail the database after a stop, while
  /// this is the closure of exactly the facts this state publishes.
  late final CarrierIndex carriers = CarrierIndex.over(database.facts);

  /// Rule applications spent, cumulative across
  /// [ProverNotifier.proveMore] — so it is bounded by
  /// [proverApplicationBudget] only for a run that was never resumed.
  final int applications;

  /// Whether the engine reached quiescence. False means the budget ran
  /// out first, and [database] is a prefix of the fixpoint.
  final bool reachedFixpoint;

  /// The proof of [goal], or null when the run did not derive it.
  ///
  /// Null is the honest answer for two different situations the UI is
  /// right not to distinguish: the statement is false, or it is true and
  /// out of the DD core's reach. Neither is a proof.
  Proof? proofOf(Fact goal) =>
      database.contains(goal) ? Proof.of(goal, database) : null;

  @override
  bool operator ==(Object other) =>
      other is ProverReady &&
      other.revision == revision &&
      identical(other.database, database) &&
      other.applications == applications &&
      other.reachedFixpoint == reachedFixpoint;

  @override
  int get hashCode => Object.hash(
    ProverReady,
    revision,
    identityHashCode(database),
    applications,
    reachedFixpoint,
  );

  @override
  String toString() =>
      'ProverReady(revision: $revision, facts: ${database.length}, '
      'applications: $applications, reachedFixpoint: $reachedFixpoint)';
}

/// The document is outside what the prover can speak about.
///
/// Today that means one thing: a non-Euclidean absolute. The predicate
/// vocabulary is Euclidean, and `hypotheses` refuses rather than
/// approximating (PLAN §M-P1) — a CK document is a perfectly good
/// document about which DD has nothing to say, which is a state to
/// render, not an exception to throw at a panel.
class ProverRefused extends ProverState {
  const ProverRefused(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) =>
      other is ProverRefused && other.reason == reason;

  @override
  int get hashCode => Object.hash(ProverRefused, reason);

  @override
  String toString() => 'ProverRefused($reason)';
}

/// A question was asked, and here is the verdict.
///
/// [run] is the run the verdict came out of, when there was one — a
/// refutation needs none, because the filter settles it without the
/// prover being started at all. Carrying it means going back from an
/// answer to the derived list does not throw the run away.
class ProverAnswered extends ProverState {
  const ProverAnswered({
    required this.answer,
    required this.revision,
    this.run,
  });

  final ProverAnswer answer;

  /// The construction revision the verdict was reached at — the same
  /// staleness comparison [ProverReady.revision] carries.
  final int revision;

  final ProverReady? run;

  @override
  bool operator ==(Object other) =>
      other is ProverAnswered &&
      other.answer == answer &&
      other.revision == revision &&
      other.run == run;

  @override
  int get hashCode => Object.hash(ProverAnswered, answer, revision, run);

  @override
  String toString() => 'ProverAnswered($answer, revision: $revision)';
}

/// Runs the DD prover over the live construction, and holds what it
/// derived (PLAN §M-P4).
///
/// **This is the domain/Flutter boundary and nothing more.** Everything
/// it drives — `hypotheses`, `DiagramFilter`, `Prover`, `Proof` —
/// is pure Dart under `lib/domain/prover/`, unit-tested there; what the
/// application layer adds is a lifetime, a revision to compare against,
/// and a budget.
///
/// **On demand, never on every edit.** PLAN §M-P4 divides the labour
/// explicitly: the numeric probe is the always-on cheap path, DD
/// certifies and explains when asked. So [prove] is a method, not a
/// `build` — and this notifier deliberately does *not* watch
/// `constructionProvider`. A drag notifies once per frame; a panel that
/// emptied every frame would be worse than one marked stale, and a
/// re-run per frame would be worse still.
///
/// **Staleness is therefore the consumer's comparison.** A [ProverReady]
/// records the revision it read; a widget that already watches the
/// construction (every painter does) knows the current one. The
/// refinement this leaves on the table, named rather than built: a proof
/// is about the construction's *graph*, and only the filter's screen
/// reads positions, so a drag that moves no parent tie invalidates
/// strictly less than a revision bump says. Acting on that needs a
/// structural revision counter, which does not exist.
///
/// **`Isolate.run` is not here yet, and the measurement says it should
/// be.** PLAN §"The prover yields with a MessageChannel" states the rule
/// — export a job only when it is longer than the round trip
/// (0.05–0.09 ms) — and a real document's fixpoint measures 10 ms to
/// well past 13 s (Phase 145 notes). So the native arm clears that bar
/// by orders of magnitude, and chunking, which keeps frames alive, does
/// not make a 13-second answer arrive sooner. What stands between here
/// and there is the id-based fact transfer that keying facts by point
/// *identity* forces — the deferral M-P2b named for this consumer — and
/// it is a slice of its own, not a line in this provider.
@Riverpod(keepAlive: true, name: 'proverProvider')
class ProverNotifier extends _$ProverNotifier {
  /// Bumped per [prove] call, so a run whose result arrives after a
  /// newer one started drops its answer instead of clobbering it. The
  /// superseded run's remaining work is not cancelled — the engine has
  /// no cancellation and a real fixpoint is short — but its result never
  /// reaches the state.
  int _generation = 0;

  /// The engine behind the published [ProverReady], kept so an exhausted
  /// run can be resumed rather than restarted. Phase 140 built the
  /// resumable shape; this is a consumer using it for what it is for.
  Prover? _engine;

  /// Set by [stop], read once per pass through `stopWhen` — the hook
  /// `Prover.runChunked` already checks — and reset at the top of every
  /// run method, so a stop belongs to the run it interrupted and never
  /// to the next one.
  bool _cancelled = false;

  @override
  ProverState build() => const ProverIdle();

  /// Reads the construction, runs the prover over it, and publishes what
  /// it derived. Answers when the run is finished or superseded.
  ///
  /// A held run at this revision is **continued, not rebuilt** — [ask]'s
  /// guard, which this method shipped without (Phase 156): a ▶ on an
  /// incomplete run used to re-probe, re-seed and start from zero while
  /// the *Keep going* row below it resumed correctly. Restarting when
  /// the revision has moved stays right, and is what the guard's
  /// comparison keeps.
  ///
  /// [applicationBudget] overrides [proverApplicationBudget] for this
  /// call — a consumer that wants a quick first answer can ask for one,
  /// and [proveMore] picks up whatever is left either way.
  Future<void> prove({int? applicationBudget}) async {
    final generation = ++_generation;
    _cancelled = false;
    final snapshot = ref.read(constructionProvider);
    final objects = List.of(snapshot.construction.objects);
    final absolute = snapshot.construction.kernel.absolute;
    if (!absolute.isEuclidean) {
      state = const ProverRefused(
        'the predicate vocabulary is Euclidean; a document under a proper '
        'absolute needs the CK re-founding',
      );
      return;
    }
    final reusable =
        _engine != null && _heldRevision(state) == snapshot.revision;
    state = ProverRunning(
      snapshot.revision,
      applications: reusable ? _engine!.applications : 0,
    );
    // Synchronous, and deliberately before the first yield: `probe`
    // perturbs the live construction's roots and restores them
    // bit-exactly, so nothing may interleave with it.
    final engine = reusable
        ? _engine!
        : () {
            final filter = DiagramFilter.probe(objects, absolute: absolute);
            final database = FactDatabase();
            seedHypotheses(
              database,
              hypotheses(objects, absolute: absolute),
              filter,
            );
            return Prover(database: database, filter: filter);
          }();
    await engine.runChunked(
      chunkBudget: proverChunkBudget,
      maxApplications: applicationBudget ?? proverApplicationBudget,
      stopWhen: () => _cancelled,
      onPass: () => _reportProgress(generation, engine, snapshot.revision),
    );
    if (generation != _generation) return;
    _engine = engine;
    state = _readyFrom(engine, snapshot.revision);
  }

  /// Republishes the running state with the applications spent so far —
  /// `onPass`'s body, once per pass, so the panel can say how hard the
  /// run is working instead of freezing on `Deriving…`. Guarded the way
  /// the completion publish is: a superseded run's progress is dropped
  /// with its result.
  void _reportProgress(int generation, Prover engine, int revision) {
    if (generation != _generation) return;
    state = ProverRunning(revision, applications: engine.applications);
  }

  /// The construction revision [_engine] was built at, read off the
  /// published state — the two are only ever assigned together. Null
  /// when the state carries none, [ProverRunning] included: reusing the
  /// engine an in-flight run may itself be driving would interleave two
  /// `runChunked` loops over one engine.
  static int? _heldRevision(ProverState held) => switch (held) {
    ProverReady(:final revision) => revision,
    ProverAnswered(:final revision) => revision,
    _ => null,
  };

  /// Spends another [proverApplicationBudget] on the run already held,
  /// which is what a consumer offers when [ProverReady.reachedFixpoint]
  /// is false. A no-op unless an exhausted run is published — there is
  /// nothing to continue otherwise.
  Future<void> proveMore({int? applicationBudget}) async {
    final held = state;
    final engine = _engine;
    if (held is! ProverReady || engine == null || engine.isComplete) return;
    final generation = ++_generation;
    _cancelled = false;
    state = ProverRunning(held.revision, applications: held.applications);
    await engine.runChunked(
      chunkBudget: proverChunkBudget,
      maxApplications: applicationBudget ?? proverApplicationBudget,
      stopWhen: () => _cancelled,
      onPass: () => _reportProgress(generation, engine, held.revision),
    );
    if (generation != _generation) return;
    state = _readyFrom(engine, held.revision);
  }

  /// Asks whether [question] holds, and answers in the three shapes
  /// [ProverVerdict] names.
  ///
  /// **A refutation costs no run at all.** The filter settles it from
  /// the sampled configurations, so a false claim is answered before the
  /// engine starts — which matters most on exactly the documents where
  /// starting it is expensive.
  ///
  /// Otherwise the run is *goal-directed in its stopping, not in its
  /// search*: DD chains forward either way, but with a goal there is no
  /// need for quiescence, only for one fact. A held run at this revision
  /// is continued rather than restarted, and a run already complete is
  /// simply consulted.
  Future<void> ask(ProverQuestion question, {int? applicationBudget}) async {
    final generation = ++_generation;
    _cancelled = false;
    final snapshot = ref.read(constructionProvider);
    final objects = List.of(snapshot.construction.objects);
    final absolute = snapshot.construction.kernel.absolute;
    if (!absolute.isEuclidean) {
      state = const ProverRefused(
        'the predicate vocabulary is Euclidean; a document under a proper '
        'absolute needs the CK re-founding',
      );
      return;
    }

    final held = state;
    final reusable =
        _engine != null &&
        held is ProverReady &&
        held.revision == snapshot.revision;
    // Synchronous, and deliberately before the first yield: `probe`
    // perturbs the live construction's roots and restores them
    // bit-exactly, so nothing may interleave with it.
    final engine = reusable
        ? _engine!
        : () {
            final filter = DiagramFilter.probe(objects, absolute: absolute);
            final database = FactDatabase();
            seedHypotheses(
              database,
              hypotheses(objects, absolute: absolute),
              filter,
            );
            return Prover(database: database, filter: filter);
          }();

    if (!engine.filter.holds(question.canonical)) {
      _engine = engine;
      state = ProverAnswered(
        answer: ProverAnswer(
          question: question,
          verdict: ProverVerdict.refuted,
        ),
        revision: snapshot.revision,
        run: reusable ? held : null,
      );
      return;
    }

    state = ProverRunning(snapshot.revision, applications: engine.applications);
    await engine.runChunked(
      chunkBudget: proverChunkBudget,
      maxApplications: applicationBudget ?? proverApplicationBudget,
      stopWhen: () => _cancelled || _derived(engine, question) != null,
      onPass: () => _reportProgress(generation, engine, snapshot.revision),
    );
    if (generation != _generation) return;
    _engine = engine;
    state = ProverAnswered(
      answer: _answerFrom(engine, question),
      revision: snapshot.revision,
      run: _readyFrom(engine, snapshot.revision),
    );
  }

  /// Spends another budget on an [ProverVerdict.undecided] question.
  /// A no-op on any other state — the other three verdicts are settled.
  Future<void> askMore({int? applicationBudget}) async {
    final held = state;
    final engine = _engine;
    if (held is! ProverAnswered ||
        held.answer.verdict != ProverVerdict.undecided ||
        engine == null ||
        engine.isComplete) {
      return;
    }
    final question = held.answer.question;
    final generation = ++_generation;
    _cancelled = false;
    state = ProverRunning(held.revision, applications: engine.applications);
    await engine.runChunked(
      chunkBudget: proverChunkBudget,
      maxApplications: applicationBudget ?? proverApplicationBudget,
      stopWhen: () => _cancelled || _derived(engine, question) != null,
      onPass: () => _reportProgress(generation, engine, held.revision),
    );
    if (generation != _generation) return;
    state = ProverAnswered(
      answer: _answerFrom(engine, question),
      revision: held.revision,
      run: _readyFrom(engine, held.revision),
    );
  }

  /// The spelling of [question] the run holds, or null for none.
  ///
  /// Any spelling will do: they are one statement, and which points name
  /// a line is the prover's business (see [ProverQuestion]). "Holds"
  /// through [Prover.resolve], so an `eqangle` the angle side entails
  /// but DD never stores is an answer too, with its certificate.
  static Fact? _derived(Prover engine, ProverQuestion question) {
    for (final spelling in question.spellings) {
      final fact = Fact.of(spelling);
      if (engine.resolve(fact)) return fact;
    }
    return null;
  }

  ProverAnswer _answerFrom(Prover engine, ProverQuestion question) {
    final fact = _derived(engine, question);
    if (fact != null) {
      return ProverAnswer(
        question: question,
        verdict: ProverVerdict.proved,
        proof: Proof.of(fact, engine.database),
      );
    }
    return ProverAnswer(
      question: question,
      // A finished run that did not reach it has shown something: the
      // rules cannot get there. An unfinished one has shown nothing at
      // all about reachability, and saying "unprovable" there would be a
      // lie about the prover rather than a fact about the figure.
      verdict: engine.isComplete
          ? ProverVerdict.unproved
          : ProverVerdict.undecided,
    );
  }

  ProverReady _readyFrom(Prover engine, int revision) => ProverReady(
    revision: revision,
    database: engine.database,
    applications: engine.applications,
    reachedFixpoint: engine.isComplete,
  );

  /// Publishes [run] as the current state — how a consumer goes back
  /// from an answer to the list of everything the run found, without
  /// re-running anything.
  ///
  /// Ignored unless [run] is the run this notifier is actually holding:
  /// publishing someone else's database would leave [askMore] and
  /// [proveMore] pointed at a different engine from the one on screen.
  void showRun(ProverReady run) {
    if (_engine == null || !identical(_engine!.database, run.database)) return;
    state = run;
  }

  /// Asks the run in flight to stop at its next pass boundary; a no-op
  /// when nothing is running.
  ///
  /// **Cancellation is not supersession, and the two must not be
  /// collapsed**: [_generation] exists so a superseded run *drops* its
  /// result, and a stopped run must *publish* one — everything derived
  /// so far, in the identical shape a spent budget publishes
  /// (`ProverReady(reachedFixpoint: false)`, or an undecided answer),
  /// so *Keep going* resumes it with no second mechanism and no new arm
  /// on [ProverState]. Which is why this sets a flag the run reads
  /// rather than touching the state itself: the interrupted `runChunked`
  /// returns through its own publish path.
  void stop() {
    if (state is! ProverRunning) return;
    _cancelled = true;
  }

  /// Drops any held run, back to [ProverIdle]. File > New / Open, and
  /// what a consumer calls when a stale answer should stop being shown
  /// at all rather than being shown as stale.
  void clear() {
    _generation++;
    _engine = null;
    state = const ProverIdle();
  }
}
