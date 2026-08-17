import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'construction_provider.dart';

part 'selection_provider.g.dart';

/// The set of selected object ids.
///
/// Selection is presentation state, not construction state — it is not
/// undoable and never persisted. The notifier listens to the construction
/// and prunes ids whose objects were deleted (or vanished wholesale via
/// `constructionProvider.replace`), so watchers never see a stale id.
@Riverpod(keepAlive: true, name: 'selectionProvider')
class SelectionNotifier extends _$SelectionNotifier {
  @override
  Set<String> build() {
    ref.listen(constructionProvider, (_, next) {
      final pruned = <String>{
        for (final id in state)
          if (next.construction.contains(id)) id,
      };
      if (pruned.length != state.length) {
        state = pruned;
      }
    });
    return const {};
  }

  /// Selects exactly [id] (plain click).
  void select(String id) => state = {id};

  /// Adds [id] to, or removes it from, the selection (shift-click).
  void toggle(String id) => state = state.contains(id)
      ? {
          for (final other in state)
            if (other != id) other,
        }
      : {...state, id};

  /// Replaces the selection with [ids] (rubber band); [additive] unions
  /// instead (shift + rubber band). An empty non-additive call clears.
  void selectMany(Iterable<String> ids, {bool additive = false}) =>
      state = additive ? {...state, ...ids} : {...ids};

  /// Selects every object currently in the construction (Ctrl/Cmd+A).
  void selectAll() => state = {
    for (final object in ref.read(constructionProvider).construction.objects)
      object.id,
  };

  void clear() => state = const {};

  /// Set semantics, so re-selecting the already-current selection (or a
  /// prune that removes nothing) does not repaint watchers.
  @override
  bool updateShouldNotify(Set<String> previous, Set<String> next) =>
      previous.length != next.length || !previous.containsAll(next);
}
