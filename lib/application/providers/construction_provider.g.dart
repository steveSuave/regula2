// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'construction_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the live [Construction] and bridges its pure-Dart listener API
/// into Riverpod: every construction mutation bumps [ConstructionState]'s
/// revision, so `ref.watch(constructionProvider)` rebuilds on each change.
///
/// Mutate the construction only through commands (via
/// `commandStackProvider`), with the drag-preview carve-out documented in
/// CLAUDE.md — both paths notify the construction, which lands here.

@ProviderFor(ConstructionNotifier)
final constructionProvider = ConstructionNotifierProvider._();

/// Owns the live [Construction] and bridges its pure-Dart listener API
/// into Riverpod: every construction mutation bumps [ConstructionState]'s
/// revision, so `ref.watch(constructionProvider)` rebuilds on each change.
///
/// Mutate the construction only through commands (via
/// `commandStackProvider`), with the drag-preview carve-out documented in
/// CLAUDE.md — both paths notify the construction, which lands here.
final class ConstructionNotifierProvider
    extends $NotifierProvider<ConstructionNotifier, ConstructionState> {
  /// Owns the live [Construction] and bridges its pure-Dart listener API
  /// into Riverpod: every construction mutation bumps [ConstructionState]'s
  /// revision, so `ref.watch(constructionProvider)` rebuilds on each change.
  ///
  /// Mutate the construction only through commands (via
  /// `commandStackProvider`), with the drag-preview carve-out documented in
  /// CLAUDE.md — both paths notify the construction, which lands here.
  ConstructionNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'constructionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$constructionNotifierHash();

  @$internal
  @override
  ConstructionNotifier create() => ConstructionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConstructionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConstructionState>(value),
    );
  }
}

String _$constructionNotifierHash() =>
    r'55fa1f7a17b89a6b9a81ca0c59bfffadaa86f61b';

/// Owns the live [Construction] and bridges its pure-Dart listener API
/// into Riverpod: every construction mutation bumps [ConstructionState]'s
/// revision, so `ref.watch(constructionProvider)` rebuilds on each change.
///
/// Mutate the construction only through commands (via
/// `commandStackProvider`), with the drag-preview carve-out documented in
/// CLAUDE.md — both paths notify the construction, which lands here.

abstract class _$ConstructionNotifier extends $Notifier<ConstructionState> {
  ConstructionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ConstructionState, ConstructionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConstructionState, ConstructionState>,
              ConstructionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
