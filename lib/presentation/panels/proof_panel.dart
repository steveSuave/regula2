/// The proof panel: what the prover derived, and why (PLAN §M-P4).
///
/// Two levels, because a proof needs a goal before it can be a proof.
/// The panel lists the statements the run *derived* — a hypothesis is
/// not news, it is what the figure was built to be — and picking one
/// shows the numbered steps that reach it.
///
/// **Rendered from `Proof.steps`, never from `Proof.render()`.** That is
/// Session 157's note taken literally: the walk's post-order is the
/// reading, and a panel that re-sorted or re-derived it would be saying
/// something different from the certificate `verify()` checks.
///
/// As in `intersection_report.dart`, the parts worth testing are pure
/// functions that take no [BuildContext] — which statements are offered
/// as goals, how a step reads — because *what it says* should not need a
/// widget tree to read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/construction_provider.dart';
import '../../application/providers/proof_highlight_provider.dart';
import '../../application/providers/prover_provider.dart';
import '../../application/providers/selection_provider.dart';
import '../../domain/prover/fact.dart';
import '../../domain/prover/fact_database.dart';
import '../../domain/prover/proof.dart';

/// The statements worth offering as goals: what the run *derived*.
///
/// Givens are excluded on purpose. A hypothesis is what the
/// construction was built to guarantee — "M is the midpoint of AB" is
/// not a result, it is the figure — and a list that opened with thirty
/// of them would bury the three statements the prover actually found.
/// They are still in the proofs, above the steps that use them, which is
/// where a reader wants them.
///
/// When [selectedIds] is non-empty the list narrows to statements
/// mentioning at least one selected object. *At least one*, not all: a
/// user who selects two points is asking what relates them, and the
/// interesting answer usually names a third.
///
/// Order is the database's own — first-derived first — which keeps the
/// panel reproducible for the same reason a printed proof is.
List<Fact> provableGoals(
  FactDatabase database, {
  Set<String> selectedIds = const {},
}) => [
  for (final fact in database.facts)
    if (!(database.derivationOf(fact)?.isHypothesis ?? true))
      if (selectedIds.isEmpty ||
          fact.points.any((point) => selectedIds.contains(point.id)))
        fact,
];

/// The reason column for one step: `given`, or the rule and the steps it
/// cites.
///
/// The rule keeps its own name — the panel does not carry a display-name
/// table for the twenty-three DD rules, because a second spelling of a
/// rule's name is a thing that drifts from the rule set and then lies
/// about which rule ran. Underscores become spaces, which is mechanical
/// and cannot drift.
String stepReason(ProofStep step) => step.isGiven
    ? 'given'
    : '${step.rule!.replaceAll('_', ' ')} '
          'from ${step.premiseSteps.map((n) => '[$n]').join(', ')}';

/// Whether a finished run still describes the construction in front of
/// the user.
///
/// The prover provider deliberately does not watch the construction (a
/// drag notifies per frame), so this comparison is the consumer's job —
/// and this panel already watches it. Conservative by revision: a drag
/// that moves no parent tie invalidates strictly less than this says,
/// which is the refinement Phase 145 named and did not build.
bool isStale(ProverState state, int revision) =>
    state is ProverReady && state.revision != revision;

/// Side panel showing what the prover derived, and the proof of whichever
/// statement is picked.
class ProofPanel extends ConsumerStatefulWidget {
  const ProofPanel({super.key});

  static const double panelWidth = 300;

  @override
  ConsumerState<ProofPanel> createState() => _ProofPanelState();
}

class _ProofPanelState extends ConsumerState<ProofPanel> {
  /// The statement whose proof is open, or null while the goal list is.
  ///
  /// Held against the *fact*, not an index: the list narrows with the
  /// selection, and an index would silently retarget when it did.
  Fact? _goal;

  /// The step number whose objects are emphasized on the figure, or null
  /// when none is. Local state, mirrored into `proofHighlightProvider`
  /// for the canvas to read — the number is this panel's business, the
  /// ids are the canvas's.
  int? _readingStep;

  /// Captured at init because `dispose` may not touch `ref` — the same
  /// constraint `ConstructionNotifier` records for its own life-cycle.
  /// Read eagerly in [initState]: a `late final` initializer would run
  /// for the first time inside `dispose` on a panel nobody touched,
  /// which is the very moment `ref` is unavailable.
  late final ProofHighlightNotifier _highlight;

  @override
  void initState() {
    super.initState();
    _highlight = ref.read(proofHighlightProvider.notifier);
  }

  @override
  void dispose() {
    // The emphasis belongs to a panel that is being read; the canvas
    // outlives this one and must not be left pulsing at a step nobody
    // is looking at. Scheduled rather than called: a provider may not be
    // modified inside a life-cycle, and this *is* one.
    final highlight = _highlight;
    WidgetsBinding.instance.addPostFrameCallback((_) => highlight.clear());
    super.dispose();
  }

  /// Emphasizes [step]'s objects on the figure, or clears the emphasis
  /// when the step already being read is tapped again — a highlight the
  /// user cannot turn off is one they have to close the panel to escape.
  void _readStep(ProofStep step) {
    if (_readingStep == step.number) {
      setState(() => _readingStep = null);
      _highlight.clear();
      return;
    }
    setState(() => _readingStep = step.number);
    _highlight.show(step.fact.points.map((point) => point.id));
  }

  /// Back to the goal list, or to a different goal: either way no step
  /// is being read any more.
  void _stopReading() {
    _readingStep = null;
    _highlight.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Watched for the staleness comparison the provider does not make.
    final revision = ref.watch(constructionProvider).revision;
    final state = ref.watch(proverProvider);
    final selectedIds = ref.watch(selectionProvider);
    final theme = Theme.of(context);

    // No width of its own: the docked call site sizes it to
    // [ProofPanel.panelWidth] and the compact one puts it in a sheet, as
    // the object tree already does between its panel and its drawer.
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme, state, revision),
          const Divider(height: 1),
          Expanded(child: _body(theme, state, selectedIds)),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, ProverState state, int revision) {
    final running = state is ProverRunning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _goal == null ? 'Proof' : 'Why',
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (_goal != null)
            IconButton(
              tooltip: 'Back to the list',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _goal = null;
                _stopReading();
              }),
            ),
          IconButton(
            tooltip: isStale(state, revision)
                ? 'The figure changed — prove again'
                : 'Prove',
            icon: running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isStale(state, revision) ? Icons.refresh : Icons.play_arrow,
                  ),
            onPressed: running ? null : _prove,
          ),
        ],
      ),
    );
  }

  Future<void> _prove() async {
    setState(() {
      _goal = null;
      _stopReading();
    });
    await ref.read(proverProvider.notifier).prove();
  }

  Widget _body(ThemeData theme, ProverState state, Set<String> selectedIds) {
    switch (state) {
      case ProverIdle():
        return _note(
          theme,
          'Nothing proved yet. The prover reads the construction and '
          'derives what follows from it — press play to run it.',
        );
      case ProverRunning():
        return _note(theme, 'Deriving…');
      case ProverRefused(:final reason):
        return _note(theme, reason);
      case ProverReady():
        // A held goal outlives a re-run only if the new run reached it
        // too; otherwise the list is the honest place to be.
        final goal = _goal;
        if (goal != null && state.database.contains(goal)) {
          return _proof(theme, Proof.of(goal, state.database));
        }
        return _goals(theme, state, selectedIds);
    }
  }

  Widget _goals(ThemeData theme, ProverReady state, Set<String> selectedIds) {
    final goals = provableGoals(state.database, selectedIds: selectedIds);
    if (goals.isEmpty) {
      return _note(
        theme,
        selectedIds.isEmpty
            ? 'The prover found nothing beyond what the construction '
                  'already says.'
            : 'Nothing derived about the selection. Clear it to see '
                  'everything the prover found.',
      );
    }
    return ListView(
      // Distinct storage keys, so the two lists keep their own scroll
      // offsets: opening a proof must start at step [1], and coming back
      // must land where the reader left the list.
      key: const PageStorageKey<String>('proof-goals'),
      children: [
        for (final goal in goals)
          ListTile(
            dense: true,
            title: Text(describeFact(goal), style: theme.textTheme.bodyMedium),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => setState(() {
              _goal = goal;
              _stopReading();
            }),
          ),
        if (!state.reachedFixpoint) _continueTile(theme, state),
      ],
    );
  }

  /// The budget ran out, and the exhausted state is actionable — that is
  /// what `proveMore` is for. Saying so beats an unexplained short list:
  /// a real document can outrun the budget (Phase 145 measured one that
  /// does), and "nothing more was found" would be a different claim.
  Widget _continueTile(ThemeData theme, ProverReady state) => ListTile(
    dense: true,
    leading: const Icon(Icons.more_horiz, size: 18),
    title: Text(
      'Stopped after ${state.applications} steps — there may be more',
      style: theme.textTheme.bodySmall,
    ),
    subtitle: const Text('Keep going'),
    onTap: () => ref.read(proverProvider.notifier).proveMore(),
  );

  Widget _proof(ThemeData theme, Proof proof) => ListView(
    key: const PageStorageKey<String>('proof-steps'),
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          describeFact(proof.goal),
          style: theme.textTheme.titleSmall,
        ),
      ),
      for (final step in proof.steps)
        InkWell(
          // Tapping a step points at what it is about. The row keeps the
          // panel's plain look rather than becoming a ListTile: a proof
          // is read as a numbered list, and rows that look tappable read
          // as a menu.
          onTap: () => _readStep(step),
          child: Container(
            color: _readingStep == step.number
                ? theme.colorScheme.secondaryContainer
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '[${step.number}]',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        describeFact(step.fact),
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        stepReason(step),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _note(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
