/// Feature flags for the tracing engine (Phase 113).
///
/// Deliberately mutable process-global state: tracing hardened across
/// Phases 113–115 behind this switch, dark by default so the app never
/// depended on the unfinished engine; since Phase 116 traced drags are
/// the default and the switch remains as the escape hatch (tests
/// pinning static-preview behaviour, and a future debug setting).
abstract final class TracingFlags {
  /// When true (the default since Phase 116), a single-free-point drag
  /// preview resolves through `Construction.recomputeAlongPath` —
  /// branch identity carried by continuity — instead of a per-frame
  /// static solve. Read once per gesture (at `DragSession.start`), so a
  /// mid-gesture flip cannot mix resolution modes within one drag. The
  /// static-solve bail stands regardless: any failure inside a traced
  /// update falls back to `moveFreePoint` for that frame.
  static bool dragTracing = true;

  /// Trial budget per traced preview update — the `stepBudget` handed to
  /// `Construction.recomputeAlongPath` (Phase 114's adaptive controller;
  /// this replaced the fixed `dragSteps` substep count). A smooth
  /// one-pointer-event path resolves in a handful of trials; the budget
  /// only bites when the controller starves against a degeneracy, where
  /// exhaustion throws and the drag session bails to the static solve.
  static int dragStepBudget = 128;
}
