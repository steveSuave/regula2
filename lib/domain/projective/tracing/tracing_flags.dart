/// Feature flags for the tracing engine (Phase 113).
///
/// Deliberately mutable process-global state: tracing hardens across
/// Phases 113–116 behind this switch, dark by default, so the app never
/// depends on the unfinished engine while any session (or a debug
/// hook) can turn it on to exercise it end to end. Phase 116 makes
/// traced drags the default and retires the flag into a setting.
abstract final class TracingFlags {
  /// When true, a single-free-point drag preview resolves through
  /// `Construction.recomputeAlongPath` — branch identity carried by
  /// continuity — instead of a per-frame static solve. Read once per
  /// gesture (at `DragSession.start`), so a mid-gesture flip cannot mix
  /// resolution modes within one drag. The static-solve bail stands
  /// regardless: any failure inside a traced update falls back to
  /// `moveFreePoint` for that frame.
  static bool dragTracing = false;

  /// Trial budget per traced preview update — the `stepBudget` handed to
  /// `Construction.recomputeAlongPath` (Phase 114's adaptive controller;
  /// this replaced the fixed `dragSteps` substep count). A smooth
  /// one-pointer-event path resolves in a handful of trials; the budget
  /// only bites when the controller starves against a degeneracy, where
  /// exhaustion throws and the drag session bails to the static solve.
  static int dragStepBudget = 128;
}
