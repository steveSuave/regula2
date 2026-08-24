import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/construction/geo_object.dart';
import '../../domain/prover/diagram_filter.dart';
import '../../domain/prover/question_draft.dart';
import '../../domain/prover/question_template.dart';
import '../../domain/prover/questions.dart';
import 'construction_provider.dart';
import 'selection_provider.dart';

part 'question_draft_provider.g.dart';

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
@Riverpod(keepAlive: true, name: 'questionDraftProvider')
class QuestionDraftNotifier extends _$QuestionDraftNotifier {
  @override
  QuestionDraft? build() {
    ref.listen(constructionProvider, (_, next) {
      final draft = state;
      if (draft == null) return;
      var pruned = draft;
      for (var i = 0; i < draft.values.length; i++) {
        final value = draft.values[i];
        if (value == null) continue;
        final live = value.objects.every(
          (object) => identical(next.construction.byId(object.id), object),
        );
        if (!live) pruned = pruned.clear(i);
      }
      if (!identical(pruned, draft)) state = pruned;
    });
    return null;
  }

  /// Opens the builder on [template], seeded from the selection in
  /// construction order.
  void open(QuestionTemplate template) {
    final selectedIds = ref.read(selectionProvider);
    final objects = ref.read(constructionProvider).construction.objects;
    state = QuestionDraft.seeded(template, [
      for (final object in objects)
        if (selectedIds.contains(object.id)) object,
    ]);
  }

  void close() => state = null;

  /// The tap gesture, routed from the canvas: [object] into the next
  /// open slot. A no-op while closed, or when the slot refuses it.
  void tap(GeoObject object) {
    final draft = state;
    if (draft == null) return;
    final next = draft.tap(object);
    if (!identical(next, draft)) state = next;
  }

  /// [object] into slot [index] — the correction path, and the way a
  /// dropdown fills a slot the figure makes hard to hit.
  void put(int index, GeoObject object) {
    final next = state?.put(index, object);
    if (next != null) state = next;
  }

  void clearSlot(int index) {
    final draft = state;
    if (draft == null) return;
    state = draft.clear(index);
  }
}

/// What a complete draft spells, and whether the figure already denies
/// it — the verdict before *OK* (PLAN §"The question builder").
class DraftCheck {
  const DraftCheck({required this.question, required this.refuted});

  /// Null for a complete draft that names no statement.
  final ProverQuestion? question;

  /// True when the numeric filter refutes [question] — false in some
  /// perturbation of the figure — which costs no prover run. The user
  /// who fills eight slots into a false statement learns it here, not
  /// after a run.
  final bool refuted;
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
@riverpod
DraftCheck? draftCheck(Ref ref) {
  final draft = ref.watch(questionDraftProvider);
  if (draft == null || !draft.isComplete) return null;
  final snapshot = ref.watch(constructionProvider);
  final objects = List.of(snapshot.construction.objects);
  final question = draft.question(objects);
  if (question == null) return const DraftCheck(question: null, refuted: false);
  final absolute = snapshot.construction.kernel.absolute;
  if (!absolute.isEuclidean) {
    return DraftCheck(question: question, refuted: false);
  }
  final filter = DiagramFilter.probe(objects, absolute: absolute);
  return DraftCheck(
    question: question,
    refuted: !filter.holds(question.canonical),
  );
}
