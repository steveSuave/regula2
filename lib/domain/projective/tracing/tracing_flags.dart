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

  /// Pins the trial budget per traced preview update, overriding the
  /// per-gesture derivation below. Null — the default — derives it from
  /// the construction with [dragStepBudgetFor]. Set it to hold a
  /// specific budget (tests pinning a walk's behaviour at a known
  /// number, a future debug setting); zero makes every traced frame bail
  /// to the static solve, which is how the bail path is exercised.
  static int? dragStepBudget;

  /// The trial budget a traced pass gets when [dragStepBudget] does not
  /// pin one: an amount of *work* divided by what one trial of this
  /// construction costs (Phase 139; PLAN §"The step budget is an amount
  /// of work, not a number of trials").
  ///
  /// [objectsPerTrial] is how many objects the pass recomputes on every
  /// trial — the dragged point's transitive dependents, less any `Locus`
  /// among them, which Phase 117b settles once per pass rather than once
  /// per trial. A trial's cost is flat *per such object* across a 32×
  /// range of graph sizes (`benchmark/drag_budget_bench.dart`) — 0.33 µs
  /// on the VM, 0.45 dart2js, 0.52 dart2wasm, 0.64 AOT — so dividing a
  /// fixed work quota by the count bounds the marginal cost of a
  /// *starving* frame at ~4 ms (VM) to ~7.8 ms (AOT) on any
  /// construction, where a constant trial count let it grow without
  /// bound with the graph. Those are today's worst case, not a new one:
  /// the quota is pinned to the gate rig's shipped budget.
  ///
  /// Deterministic on purpose: a wall-clock deadline would bound the
  /// same quantity more directly and would make which root a point holds
  /// depend on the machine. See PLAN for that rejection, and for why the
  /// clamps are where they are.
  static int dragStepBudgetFor(int objectsPerTrial) =>
      (dragStepBudgetWork ~/ (objectsPerTrial < 1 ? 1 : objectsPerTrial)).clamp(
        dragStepBudgetMin,
        dragStepBudgetMax,
      );

  /// The work quota [dragStepBudgetFor] divides, in object-recomputes.
  ///
  /// 12288 is the constant this replaced, restated: the 100-object
  /// stress construction the Phase 116 drag-frame gate is defined on has
  /// 96 objects downstream of its dragged point, and 128 × 96 = 12288.
  /// The gate rig's budget is therefore unchanged, and the recalibration
  /// is visible as one.
  static const int dragStepBudgetWork = 12288;

  /// The floor, and it is the previous constant: no construction gets
  /// less budget than it did, so graphs past the ~96-object crossover
  /// behave exactly as before. Their starving frames still cost time
  /// linear in the graph and still have too few trials to finish a
  /// detour — a pre-existing limit, named in PLAN, whose fix is to
  /// decline the detour rather than to raise the number.
  static const int dragStepBudgetMin = 128;

  /// The ceiling, and it costs no capability: past roughly 500 trials a
  /// starving frame stops making progress (its cost flattens while the
  /// counter runs), so this bounds the small-graph case — four objects
  /// downstream would otherwise be handed 3072 trials — without capping
  /// anything a walk can use.
  static const int dragStepBudgetMax = 2048;
}
