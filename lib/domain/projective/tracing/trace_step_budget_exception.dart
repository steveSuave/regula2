/// Thrown by `Construction.recomputeAlongPath` when the adaptive step
/// controller (Phase 114) exhausts its trial budget before reaching the
/// end of the path.
///
/// Budget exhaustion is *step starvation*: the Cinderella acceptance rule
/// shrinks steps toward zero as tracked roots approach a degeneracy (a
/// tangency collapses the candidate separation, so the allowed motion per
/// step collapses with it), and a path that crosses one can consume any
/// finite budget without crossing. This is the singularity signal Phase
/// 115 turns into a complex detour; until then, callers bail to a static
/// solve (the drag session already does — PLAN §Risks).
///
/// The construction is left mid-path: the dragged point sits at the last
/// trial position and traced slots have been cleared. Callers must
/// re-resolve statically (e.g. `moveFreePoint` to the intended target).
class TraceStepBudgetException implements Exception {
  const TraceStepBudgetException({required this.tReached, required this.trials});

  /// The path parameter of the last *accepted* step — how far along the
  /// path continuation got before starving.
  final double tReached;

  /// Trials spent (accepted + rejected) — equals the budget.
  final int trials;

  @override
  String toString() =>
      'TraceStepBudgetException: step controller starved at t = $tReached '
      'after $trials trials (degeneracy on the path?)';
}
