import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'proof_highlight_provider.g.dart';

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
@Riverpod(keepAlive: true, name: 'proofHighlightProvider')
class ProofHighlightNotifier extends _$ProofHighlightNotifier {
  @override
  Set<String> build() => const {};

  /// Emphasizes exactly [ids] — a step at a time, so this replaces
  /// rather than accumulates.
  void show(Iterable<String> ids) {
    final next = ids.toSet();
    if (next.length == state.length && next.every(state.contains)) return;
    state = next;
  }

  void clear() {
    // The proof panel schedules this from its `dispose`, and a panel can
    // be torn down together with its container — an app closing, a test
    // ending — in which case there is nothing left to clear.
    if (!ref.mounted) return;
    if (state.isEmpty) return;
    state = const {};
  }
}
