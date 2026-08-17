import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/construction/construction.dart';

part 'construction_provider.g.dart';

/// Immutable snapshot handle for the (mutable) [Construction].
///
/// The construction mutates in place, so watchers can't detect change by
/// comparing instances. [revision] increments on every construction
/// notification, giving Riverpod a value that *does* change — watch this
/// state and repaint whenever it does. Two states are equal only when they
/// hold the same construction instance at the same revision.
class ConstructionState {
  const ConstructionState(this.construction, this.revision);

  final Construction construction;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ConstructionState &&
      identical(other.construction, construction) &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(identityHashCode(construction), revision);
}

/// Owns the live [Construction] and bridges its pure-Dart listener API
/// into Riverpod: every construction mutation bumps [ConstructionState]'s
/// revision, so `ref.watch(constructionProvider)` rebuilds on each change.
///
/// Mutate the construction only through commands (via
/// `commandStackProvider`), with the drag-preview carve-out documented in
/// CLAUDE.md — both paths notify the construction, which lands here.
@Riverpod(keepAlive: true, name: 'constructionProvider')
class ConstructionNotifier extends _$ConstructionNotifier {
  /// The construction we are subscribed to. Mirrors `state.construction`,
  /// but lives outside `state` because the `onDispose` callback must not
  /// touch `state` (Riverpod forbids Ref use inside life-cycles).
  late Construction _construction;

  @override
  ConstructionState build() {
    _construction = Construction();
    _construction.addListener(_onConstructionChanged);
    ref.onDispose(() => _construction.removeListener(_onConstructionChanged));
    return ConstructionState(_construction, 0);
  }

  /// Swaps in a different construction (File > New / Open) and resets the
  /// revision. Providers that depend on the construction *instance*
  /// (e.g. `commandStackProvider`) rebuild; undo history starts fresh.
  void replace(Construction construction) {
    _construction.removeListener(_onConstructionChanged);
    _construction = construction;
    _construction.addListener(_onConstructionChanged);
    state = ConstructionState(_construction, 0);
  }

  void _onConstructionChanged() {
    state = ConstructionState(_construction, state.revision + 1);
  }
}
