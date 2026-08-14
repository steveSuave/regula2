/// Thrown by `Construction.recomputeAlongPath` when the adaptive step
/// controller (Phase 114) exhausts its trial budget before reaching the
/// end of the path.
///
/// Budget exhaustion is *step starvation*: the Cinderella acceptance rule
/// shrinks steps toward zero as tracked roots approach a degeneracy (a
/// tangency collapses the candidate separation, so the allowed motion per
/// step collapses with it), and a path that crosses one can consume any
/// finite budget without crossing. Since Phase 115 starvation first
/// attempts a complex detour around the singularity; this throw remains
/// for the cases no detour resolves — the samples don't extrapolate to a
/// singular parameter, the singularity sits at or past the path's end
/// (the pass would have to finish at a complex parameter), or the detour
/// arc itself exhausts the budget. Callers bail to a static solve (the
/// drag session does — PLAN §Risks).
///
/// The construction is left mid-path but *real*: the dragged point sits
/// at the last trial position (or back at the arc entry after a failed
/// detour) and traced slots have been cleared. Callers must re-resolve
/// statically (e.g. `moveFreePoint` to the intended target).
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
