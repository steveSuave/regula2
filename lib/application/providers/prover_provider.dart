import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/prover/diagram_filter.dart';
import '../../domain/prover/fact.dart';
import '../../domain/prover/fact_database.dart';
import '../../domain/prover/hypotheses.dart';
import '../../domain/prover/proof.dart';
import '../../domain/prover/rule_engine.dart';
import 'construction_provider.dart';

part 'prover_provider.g.dart';

/// Rule applications per chunk between event-loop yields.
///
/// Phase 140 measured the resumable shape's overhead flat from 1 000 to
/// 500 000 applications per step, so the low end costs nothing and keeps
/// the largest single uninterruptible slice small. Real documents reach
/// quiescence inside one chunk — the Varignon fixpoint is 44
/// applications — which is the point: the budget is about the
/// pathological document, not the common one.
const int proverChunkBudget = 1000;

/// The ceiling on one [ProverNotifier.prove] call, in rule applications.
///
/// **Quiescence is not something a real document owes**, and that is a
/// measurement rather than a caution: `test/fixtures/provoleas2.json`
/// (27 objects, 23 hypotheses) is still deriving after 200 000
/// applications — the `eqangle` join blowup Session 156 named as
/// structural and had not yet seen materialize. So a UI consumer needs a
/// ceiling, and exhaustion is a reported *state*, not a failure:
/// everything derived so far is a fixpoint prefix, and the engine
/// resumes exactly where it stopped ([ProverNotifier.proveMore]).
///
/// **30 000 is ~2 s in the regime where the cap actually binds.** On that
/// same blowup rig an application costs ~65 µs on the VM; documents that
/// reach quiescence do it in hundreds of applications and never see this
/// number. It stays counted in applications rather than milliseconds for
/// the Phase 139/140 reason — a run's outcome must be a function of the
/// document, not of the machine — with the honest caveat recorded in the
/// Phase 145 notes: an application's cost is *not* flat on the real rule
/// set (65 µs to 2.3 ms across the fixtures), because the join
/// enumeration that yields no candidate is not charged as one. The cap
/// bounds work in the engine's own unit; the wall-clock it buys is
/// document-dependent.
const int proverApplicationBudget = 30000;

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
  const ProverRunning(this.revision);

  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ProverRunning && other.revision == revision;

  @override
  int get hashCode => Object.hash(ProverRunning, revision);

  @override
  String toString() => 'ProverRunning(revision: $revision)';
}

/// A finished run, and the facts it reached.
///
/// [revision] is the construction revision the run read. It is here so a
/// consumer can tell a current answer from a stale one *without this
/// provider watching the construction* — see [ProverNotifier].
class ProverReady extends ProverState {
  const ProverReady({
    required this.revision,
    required this.database,
    required this.applications,
    required this.reachedFixpoint,
  });

  final int revision;

  /// Every fact the run derived, each carrying the derivation it was
  /// discovered with — the proof DAG, already stored.
  final FactDatabase database;

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

/// Runs the DD prover over the live construction, and holds what it
/// derived (PLAN §M-P4).
///
/// **This is the domain/Flutter boundary and nothing more.** Everything
/// it drives — `hypotheses`, `DiagramFilter`, `ProverEngine`, `Proof` —
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
  ProverEngine? _engine;

  @override
  ProverState build() => const ProverIdle();

  /// Reads the construction, runs the prover over it, and publishes what
  /// it derived. Answers when the run is finished or superseded.
  ///
  /// [applicationBudget] overrides [proverApplicationBudget] for this
  /// call — a consumer that wants a quick first answer can ask for one,
  /// and [proveMore] picks up whatever is left either way.
  Future<void> prove({int? applicationBudget}) async {
    final generation = ++_generation;
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
    state = ProverRunning(snapshot.revision);
    // Synchronous, and deliberately before the first yield: `probe`
    // perturbs the live construction's roots and restores them
    // bit-exactly, so nothing may interleave with it.
    final filter = DiagramFilter.probe(objects, absolute: absolute);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(objects, absolute: absolute), filter);
    final engine = ProverEngine(database: database, filter: filter);
    await engine.runChunked(
      chunkBudget: proverChunkBudget,
      maxApplications: applicationBudget ?? proverApplicationBudget,
    );
    if (generation != _generation) return;
    _engine = engine;
    state = _readyFrom(engine, snapshot.revision);
  }

  /// Spends another [proverApplicationBudget] on the run already held,
  /// which is what a consumer offers when [ProverReady.reachedFixpoint]
  /// is false. A no-op unless an exhausted run is published — there is
  /// nothing to continue otherwise.
  Future<void> proveMore({int? applicationBudget}) async {
    final held = state;
    final engine = _engine;
    if (held is! ProverReady || engine == null || engine.isComplete) return;
    final generation = ++_generation;
    state = ProverRunning(held.revision);
    await engine.runChunked(
      chunkBudget: proverChunkBudget,
      maxApplications: applicationBudget ?? proverApplicationBudget,
    );
    if (generation != _generation) return;
    state = _readyFrom(engine, held.revision);
  }

  ProverReady _readyFrom(ProverEngine engine, int revision) => ProverReady(
    revision: revision,
    database: engine.database,
    applications: engine.applications,
    reachedFixpoint: engine.isComplete,
  );

  /// Drops any held run, back to [ProverIdle]. File > New / Open, and
  /// what a consumer calls when a stale answer should stop being shown
  /// at all rather than being shown as stale.
  void clear() {
    _generation++;
    _engine = null;
    state = const ProverIdle();
  }
}
