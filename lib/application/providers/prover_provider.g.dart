// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prover_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(ProverNotifier)
final proverProvider = ProverNotifierProvider._();

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
final class ProverNotifierProvider
    extends $NotifierProvider<ProverNotifier, ProverState> {
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
  ProverNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proverNotifierHash();

  @$internal
  @override
  ProverNotifier create() => ProverNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProverState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProverState>(value),
    );
  }
}

String _$proverNotifierHash() => r'56dd9d39d59fd1c4b5d834d5e2f57be50b60717e';

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

abstract class _$ProverNotifier extends $Notifier<ProverState> {
  ProverState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ProverState, ProverState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProverState, ProverState>,
              ProverState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
