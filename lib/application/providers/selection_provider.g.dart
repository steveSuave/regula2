// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The set of selected object ids.
///
/// Selection is presentation state, not construction state — it is not
/// undoable and never persisted. The notifier listens to the construction
/// and prunes ids whose objects were deleted (or vanished wholesale via
/// `constructionProvider.replace`), so watchers never see a stale id.

@ProviderFor(SelectionNotifier)
final selectionProvider = SelectionNotifierProvider._();

/// The set of selected object ids.
///
/// Selection is presentation state, not construction state — it is not
/// undoable and never persisted. The notifier listens to the construction
/// and prunes ids whose objects were deleted (or vanished wholesale via
/// `constructionProvider.replace`), so watchers never see a stale id.
final class SelectionNotifierProvider
    extends $NotifierProvider<SelectionNotifier, Set<String>> {
  /// The set of selected object ids.
  ///
  /// Selection is presentation state, not construction state — it is not
  /// undoable and never persisted. The notifier listens to the construction
  /// and prunes ids whose objects were deleted (or vanished wholesale via
  /// `constructionProvider.replace`), so watchers never see a stale id.
  SelectionNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectionNotifierHash();

  @$internal
  @override
  SelectionNotifier create() => SelectionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$selectionNotifierHash() => r'fc835c0ab1dbc2d2b9f571ccfd99cdb8416386d1';

/// The set of selected object ids.
///
/// Selection is presentation state, not construction state — it is not
/// undoable and never persisted. The notifier listens to the construction
/// and prunes ids whose objects were deleted (or vanished wholesale via
/// `constructionProvider.replace`), so watchers never see a stale id.

abstract class _$SelectionNotifier extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
