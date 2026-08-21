// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proof_highlight_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The objects one proof step is talking about (PLAN §M-P4).
///
/// A provider rather than widget state because it crosses two widgets
/// that share no ancestor worth threading it through: the proof panel
/// says which step is being read, the canvas draws the emphasis. That
/// is [selectionProvider]'s shape, and for the same reason.
///
/// **Not the selection, and deliberately a separate set.** The user may
/// have a selection while reading a proof, and the two mean different
/// things — one is what a command would act on, the other is what a
/// sentence is about. Folding them together would make a proof step
/// silently retarget the next tool, which is the kind of invisible
/// re-addressing this codebase keeps writing reports about.
///
/// View state: never persisted, never undoable, and cleared whenever the
/// reader stops looking at a step.

@ProviderFor(ProofHighlightNotifier)
final proofHighlightProvider = ProofHighlightNotifierProvider._();

/// The objects one proof step is talking about (PLAN §M-P4).
///
/// A provider rather than widget state because it crosses two widgets
/// that share no ancestor worth threading it through: the proof panel
/// says which step is being read, the canvas draws the emphasis. That
/// is [selectionProvider]'s shape, and for the same reason.
///
/// **Not the selection, and deliberately a separate set.** The user may
/// have a selection while reading a proof, and the two mean different
/// things — one is what a command would act on, the other is what a
/// sentence is about. Folding them together would make a proof step
/// silently retarget the next tool, which is the kind of invisible
/// re-addressing this codebase keeps writing reports about.
///
/// View state: never persisted, never undoable, and cleared whenever the
/// reader stops looking at a step.
final class ProofHighlightNotifierProvider
    extends $NotifierProvider<ProofHighlightNotifier, Set<String>> {
  /// The objects one proof step is talking about (PLAN §M-P4).
  ///
  /// A provider rather than widget state because it crosses two widgets
  /// that share no ancestor worth threading it through: the proof panel
  /// says which step is being read, the canvas draws the emphasis. That
  /// is [selectionProvider]'s shape, and for the same reason.
  ///
  /// **Not the selection, and deliberately a separate set.** The user may
  /// have a selection while reading a proof, and the two mean different
  /// things — one is what a command would act on, the other is what a
  /// sentence is about. Folding them together would make a proof step
  /// silently retarget the next tool, which is the kind of invisible
  /// re-addressing this codebase keeps writing reports about.
  ///
  /// View state: never persisted, never undoable, and cleared whenever the
  /// reader stops looking at a step.
  ProofHighlightNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proofHighlightProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proofHighlightNotifierHash();

  @$internal
  @override
  ProofHighlightNotifier create() => ProofHighlightNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$proofHighlightNotifierHash() =>
    r'08caf922e5a11fff2f8f26fc4ba053d12d02e6af';

/// The objects one proof step is talking about (PLAN §M-P4).
///
/// A provider rather than widget state because it crosses two widgets
/// that share no ancestor worth threading it through: the proof panel
/// says which step is being read, the canvas draws the emphasis. That
/// is [selectionProvider]'s shape, and for the same reason.
///
/// **Not the selection, and deliberately a separate set.** The user may
/// have a selection while reading a proof, and the two mean different
/// things — one is what a command would act on, the other is what a
/// sentence is about. Folding them together would make a proof step
/// silently retarget the next tool, which is the kind of invisible
/// re-addressing this codebase keeps writing reports about.
///
/// View state: never persisted, never undoable, and cleared whenever the
/// reader stops looking at a step.

abstract class _$ProofHighlightNotifier extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
