// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'question_draft_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The question being built, or null while the builder is closed
/// (Phase 160, PLAN §"The question builder").
///
/// A provider for [selectionProvider]'s reason: the builder's bar and
/// the canvas share no ancestor worth threading it through, and a canvas
/// tap has to reach the draft. **Not the selection.** While a draft is
/// open a tap in select mode fills the next slot instead of selecting —
/// the slot is where the order comes from, and a selection that also
/// moved under every tap would re-target the next tool invisibly. The
/// selection is read once, when the builder opens, to seed the draft.
///
/// View state: never persisted, never undoable. Objects the draft holds
/// are pruned when they leave the construction, slot by slot, so a
/// deletion empties a slot rather than leaving a dangling reference, and
/// a document replaced wholesale empties every slot (its objects are new
/// instances, whatever their ids) and leaves the builder open.

@ProviderFor(QuestionDraftNotifier)
final questionDraftProvider = QuestionDraftNotifierProvider._();

/// The question being built, or null while the builder is closed
/// (Phase 160, PLAN §"The question builder").
///
/// A provider for [selectionProvider]'s reason: the builder's bar and
/// the canvas share no ancestor worth threading it through, and a canvas
/// tap has to reach the draft. **Not the selection.** While a draft is
/// open a tap in select mode fills the next slot instead of selecting —
/// the slot is where the order comes from, and a selection that also
/// moved under every tap would re-target the next tool invisibly. The
/// selection is read once, when the builder opens, to seed the draft.
///
/// View state: never persisted, never undoable. Objects the draft holds
/// are pruned when they leave the construction, slot by slot, so a
/// deletion empties a slot rather than leaving a dangling reference, and
/// a document replaced wholesale empties every slot (its objects are new
/// instances, whatever their ids) and leaves the builder open.
final class QuestionDraftNotifierProvider
    extends $NotifierProvider<QuestionDraftNotifier, QuestionDraft?> {
  /// The question being built, or null while the builder is closed
  /// (Phase 160, PLAN §"The question builder").
  ///
  /// A provider for [selectionProvider]'s reason: the builder's bar and
  /// the canvas share no ancestor worth threading it through, and a canvas
  /// tap has to reach the draft. **Not the selection.** While a draft is
  /// open a tap in select mode fills the next slot instead of selecting —
  /// the slot is where the order comes from, and a selection that also
  /// moved under every tap would re-target the next tool invisibly. The
  /// selection is read once, when the builder opens, to seed the draft.
  ///
  /// View state: never persisted, never undoable. Objects the draft holds
  /// are pruned when they leave the construction, slot by slot, so a
  /// deletion empties a slot rather than leaving a dangling reference, and
  /// a document replaced wholesale empties every slot (its objects are new
  /// instances, whatever their ids) and leaves the builder open.
  QuestionDraftNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'questionDraftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$questionDraftNotifierHash();

  @$internal
  @override
  QuestionDraftNotifier create() => QuestionDraftNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QuestionDraft? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QuestionDraft?>(value),
    );
  }
}

String _$questionDraftNotifierHash() =>
    r'38d6e81ba98820993a9a9e8286d7b7eba98cb12d';

/// The question being built, or null while the builder is closed
/// (Phase 160, PLAN §"The question builder").
///
/// A provider for [selectionProvider]'s reason: the builder's bar and
/// the canvas share no ancestor worth threading it through, and a canvas
/// tap has to reach the draft. **Not the selection.** While a draft is
/// open a tap in select mode fills the next slot instead of selecting —
/// the slot is where the order comes from, and a selection that also
/// moved under every tap would re-target the next tool invisibly. The
/// selection is read once, when the builder opens, to seed the draft.
///
/// View state: never persisted, never undoable. Objects the draft holds
/// are pruned when they leave the construction, slot by slot, so a
/// deletion empties a slot rather than leaving a dangling reference, and
/// a document replaced wholesale empties every slot (its objects are new
/// instances, whatever their ids) and leaves the builder open.

abstract class _$QuestionDraftNotifier extends $Notifier<QuestionDraft?> {
  QuestionDraft? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<QuestionDraft?, QuestionDraft?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<QuestionDraft?, QuestionDraft?>,
              QuestionDraft?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The check on the open draft once it is complete; null while the
/// builder is closed or the draft is not yet full.
///
/// Re-probed whenever the construction changes with a complete draft
/// open — a drag then pays a probe per frame, which is the price of the
/// verdict staying true of the figure on screen. Under a non-Euclidean
/// absolute the filter cannot speak (it throws, by design); the draft
/// is passed through unrefuted and the prover refuses it on *Ask* with
/// the reason it always gives.

@ProviderFor(draftCheck)
final draftCheckProvider = DraftCheckProvider._();

/// The check on the open draft once it is complete; null while the
/// builder is closed or the draft is not yet full.
///
/// Re-probed whenever the construction changes with a complete draft
/// open — a drag then pays a probe per frame, which is the price of the
/// verdict staying true of the figure on screen. Under a non-Euclidean
/// absolute the filter cannot speak (it throws, by design); the draft
/// is passed through unrefuted and the prover refuses it on *Ask* with
/// the reason it always gives.

final class DraftCheckProvider
    extends $FunctionalProvider<DraftCheck?, DraftCheck?, DraftCheck?>
    with $Provider<DraftCheck?> {
  /// The check on the open draft once it is complete; null while the
  /// builder is closed or the draft is not yet full.
  ///
  /// Re-probed whenever the construction changes with a complete draft
  /// open — a drag then pays a probe per frame, which is the price of the
  /// verdict staying true of the figure on screen. Under a non-Euclidean
  /// absolute the filter cannot speak (it throws, by design); the draft
  /// is passed through unrefuted and the prover refuses it on *Ask* with
  /// the reason it always gives.
  DraftCheckProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'draftCheckProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$draftCheckHash();

  @$internal
  @override
  $ProviderElement<DraftCheck?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DraftCheck? create(Ref ref) {
    return draftCheck(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DraftCheck? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DraftCheck?>(value),
    );
  }
}

String _$draftCheckHash() => r'4e0255627cef6c831c9930223e9b99fd8acf7608';
