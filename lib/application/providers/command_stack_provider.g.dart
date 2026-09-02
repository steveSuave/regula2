// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'command_stack_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod wrapper around [CommandStack]: all user actions funnel through
/// [execute], and the UI watches the state for undo/redo button enablement.
///
/// Depends on the construction *instance* (not its revision), so the stack
/// survives every mutation but is rebuilt — history dropped — when
/// `constructionProvider.replace` swaps in a new construction. Undoing
/// commands against a construction they never touched would corrupt it.

@ProviderFor(CommandStackNotifier)
final commandStackProvider = CommandStackNotifierProvider._();

/// Riverpod wrapper around [CommandStack]: all user actions funnel through
/// [execute], and the UI watches the state for undo/redo button enablement.
///
/// Depends on the construction *instance* (not its revision), so the stack
/// survives every mutation but is rebuilt — history dropped — when
/// `constructionProvider.replace` swaps in a new construction. Undoing
/// commands against a construction they never touched would corrupt it.
final class CommandStackNotifierProvider
    extends $NotifierProvider<CommandStackNotifier, UndoRedoState> {
  /// Riverpod wrapper around [CommandStack]: all user actions funnel through
  /// [execute], and the UI watches the state for undo/redo button enablement.
  ///
  /// Depends on the construction *instance* (not its revision), so the stack
  /// survives every mutation but is rebuilt — history dropped — when
  /// `constructionProvider.replace` swaps in a new construction. Undoing
  /// commands against a construction they never touched would corrupt it.
  CommandStackNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commandStackProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commandStackNotifierHash();

  @$internal
  @override
  CommandStackNotifier create() => CommandStackNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UndoRedoState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UndoRedoState>(value),
    );
  }
}

String _$commandStackNotifierHash() =>
    r'c994ec334a92a4a062c08d17c1e04e61b08ac24a';

/// Riverpod wrapper around [CommandStack]: all user actions funnel through
/// [execute], and the UI watches the state for undo/redo button enablement.
///
/// Depends on the construction *instance* (not its revision), so the stack
/// survives every mutation but is rebuilt — history dropped — when
/// `constructionProvider.replace` swaps in a new construction. Undoing
/// commands against a construction they never touched would corrupt it.

abstract class _$CommandStackNotifier extends $Notifier<UndoRedoState> {
  UndoRedoState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UndoRedoState, UndoRedoState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UndoRedoState, UndoRedoState>,
              UndoRedoState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
