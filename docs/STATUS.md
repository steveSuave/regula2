# Status Log

Append-only journal of working sessions. Newest entries on top. Each entry should answer three questions in 5–15 lines: **what was done**, **what's next**, **gotchas / open questions**.

Write a fresh entry at the end of every session, before stopping. Do not edit older entries — if something turned out wrong, note it in the next entry.

Rotation: keep roughly the last 10 sessions here; move older entries to `docs/archive/` every 20–30 sessions. V1's log lives in `docs/archive/STATUS-sessions-01-88.md` and `STATUS-sessions-89-98.md`.

---

## Session 115 (V2 Session 17) — 2026-08-14

**Done**
- **Phase 116 (Tracing integration) complete** on `phase-116-tracing-integration`, four commits — traced drags are now the app's default behaviour:
- **Default on + branch adoption**: `TracingFlags.dragTracing` defaults true (kept as the escape hatch). `recomputeAlongPath` ends every *completed* pass by adopting the branch each trace followed: `branchIndex` := the final accepted step's `matchedIndex` — the final step ran at t = 1 on real carriers, so that *is* the canonical-order index of the tracked root, making save re-derivation free. Guards: no adoption on a coast (matchedIndex −1), a double root (separation ≤ `doubleRootEpsilon` — the tie broke arbitrarily), an out-of-range index (future 4-candidate carriers), or a throwing pass. Consequence: static recomputes now *reproduce* the traced branch — the drag session's bail heals to the adopted branch (tested: a frame crossing the canonical flip, then a forced-bail frame, stays on its conjugate side), and commit/save/reload sit where the trace left off.
- **Command capture**: new `Construction.setIntersectionBranch` primitive (re-point + recompute dependents); `MoveFreePointCommand.branchChanges` (`(id, from, to)` records, applied before the move so the closing `moveFreePoint` recomputes once over final indices) replays adoption under undo/redo. The session snapshots pre-drag indices of every downstream `IntersectionPoint` at start, restores them on rollback/cancel (indices before positions), and diffs them into the one command at `end()`; a zero-delta gesture with a net branch change still commits (a real re-pointing).
- **Debug overlay**: ⇧O (`AppAction.toggleTraceOverlay`, viewport section) toggles `TraceStatsOverlay` — a canvas chip showing the last traced frame's accepted/rejected/detours or "static bail", fed by `DragSession.traceStats` → `ToolNotifier.lastTraceStats`, repainting live through the construction revision each preview frame bumps.
- **Performance gate PASS** (`benchmark/run_tracing.sh`, 100-object stress, 48 branches, ms/frame static→traced): VM 0.064→0.065, AOT 0.078→0.118, js 0.080→0.100, wasm 0.076→0.120 — every target at ~1% of the 8 ms budget, 1.00 trials/frame, checksums identical; adoption is not measurable against Phase 114's numbers.
- Tests: adoption on the direction-anchor relabel rig (drag b past a: indices flip 0↔1 under motionless conjugate roots, static recompute then reproduces the traced side), no-adoption on the order-preserving tangency crossing and on a coasting final step; `setIntersectionBranch` units; command replay; session commit/undo/redo identity, cancel restore, bail-heals-to-adopted; codec round-trip of a committed traced drag; overlay widget test. No existing jump-behaviour test needed loosening — none pinned commit-time relabeling. Suite 2067 green, analyze clean, `flutter build web` compiles.

**Next**
- Phase 117 — locus rewrite on tracing: revisit the detour orientation convention first (decision recorded 2026-08-14, see TODO), then `Locus.recompute` as an adaptive tracing sweep, delete the 704-line special-case machinery, locus corpus as spec, goldens regenerated where the better curve differs.

**Gotchas**
- **Adoption is end-of-pass only and completed-pass only.** Mid-pass `branchIndex` is stale by design (identity lives in the slot); a throwing pass adopts nothing, so the bail's static solve re-selects by the *last adopted* index — that is what makes bail healing work. Don't adopt inside `traceArc` or on exception paths.
- **Rollback order is load-bearing** in `DragSession._rollback`: branch indices restore *before* `moveFreePoint`, so the rollback recompute re-selects the original branches. Same principle in `MoveFreePointCommand.apply`: branches first, then the move recomputes everything once.
- The double-root adoption guard reads `TracedBranch.separation` (min pairwise candidate distance at the last follow) — for 2-candidate sets that's exactly the tie distance; when 4-candidate conic∩conic carriers arrive (119–120) it goes conservative, which only ever *withholds* adoption. The `matchedIndex <= 1` guard is the other half of that future.
- Tests that want static previews must set `TracingFlags.dragTracing = false` **and restore true** in tearDown (the whole suite now runs traced by default — only `drag_session_tracing_test.dart` currently opts out per-test).
- A there-and-back gesture nets zero branch changes (reversal-identity, Phase 115) — the zero-delta-with-changes commit path exists for genuinely non-closing loops in the config space (crossing an odd number of canonical-flip surfaces); it is defensively coded but geometrically hard to rig, hence untested end to end.
- `ToolNotifier.lastTraceStats` is deliberately not provider state (like `_drag` itself): the overlay watches the construction and reads it imperatively. Don't lift it into `ActiveToolState` — it would rebuild the toolbar every preview frame.

---

## Session 114 (V2 Session 16) — 2026-08-14

**Done**
- **Phase 115 (Tracing III) complete** on `phase-115-complex-detour`, merged to `main`, three commits:
- **Singularity detection + arc planning** (`lib/domain/projective/tracing/singularity.dart`): starvation trigger = trial step < `detourTriggerStep` (1e-5) *and* tightest branch separation < `detourTriggerSeparation` (1e-3); `estimateSingularParameter` extrapolates t* from the last two accepted steps' separations via the collapse law s = C·√(t*−t) (s² linear — exact on tangencies; on a near-miss s² = C²((t−a)² + b²) it provably *undershoots* the closest approach while samples are farther than b, so planned arcs exit before the complex branch points — homotopy safety by construction, pinned in tests). `DetourArc.plan`: radius = 1.5× the estimated distance, shrunk to fit strictly inside the path, strict enclosure re-checked; exit is bitwise-exactly real (cos 0 = 1, sin 0 = 0).
- **Complex-carrier plumbing**: `FreePoint.tracedPosition` (complex homogeneous position, w ≡ 1, pass-internal only); `intersectionCandidates` gained `{complexCarriers}` which skips *only* the realness gates (the kernel is holomorphic by layer convention, so complex-carrier candidates are the analytic continuation of the real ones); wired through `TracedBranch.allowComplexCarriers`, arc-scoped (reset by seed/clear, never checkpointed) — real-axis tracing keeps Phase 114's static refusal bit-for-bit.
- **Detour in `recomputeAlongPath`**: on starvation, plan and walk the arc θ: π → 0 with the *identical* acceptance machinery (a whole-arc jump is self-refused: motion to either exit root ≥ entry separation/2, so refinement is forced without special-casing; collision refusal is live on the arc). Trials share the pass budget; mid-arc exhaustion restores the real entry state before throwing; resume at `step = arc.radius` (restarting from the remainder burned ~30 refusals halving down). Return record gained `detours` (Phase 116 overlay feed).
- **Orientation is the phase's recorded decision**: the toy probe caught that a fixed absolute half-plane swaps the conjugates on a there-and-back drag — the return pass parameterizes the reverse path, so its upper half-plane is the forward pass's lower one, and the round trip winds once around the branch point (monodromy). `detourOrientation` is an *odd* function of the drag direction (descending/leftward → upper); there-and-back now restores every branch bitwise.
- **Canonical tests** (in `recompute_along_path_test.dart` + `singularity_test.dart`, 27 new): tangency crossing (detours = 1, deterministic sides — the −i branch lands x < 0 on a downward drag, endpoint = static solve, per-step chordal motion < 0.3); there-and-back identity; chord *and* perpendicular bisector of the conjugate pair stay real defined lines at every observed step; the no-enclosure property via a co-traced transverse pair (r = 6 circle) riding the r = 3 pair's detour to exactly its real-path endpoint; near-miss ladder on a circle∩circle rig (δ ≥ 1e-8 traces through real, no detour; δ ≤ 1e-10 starves cleanly — bails, never silently swaps); singular endpoint (drag *onto* tangency) starves and bails. The Phase 114 starve toy survives as the insufficient-budget path (budget 40 exhausts before the trigger; default 128 crosses).
- Suite 2056 green, analyze clean, `flutter build web` compiles.

**Next**
- Phase 116 — Tracing integration: `drag_session.dart` drives `recomputeAlongPath` by default, `TracedBranch` holds identity between recomputes, save re-derives `branchIndex` from canonical order (documented spec change), debug overlay (accepted/rejected/detours feed is ready), and the standing ≤ 8 ms perf gate on the 100-object stress construction.

**Gotchas**
- **The orientation rule must stay odd.** `detourOrientation` flips with the drag direction *on purpose*: keeping one absolute half-plane makes down-then-up wind once around the branch point and visibly exchange the two intersection objects (down-up-down would land p0 on the other side). Any future change must preserve oddness or record per-singularity orientations Cinderella-style. **Decision (user, 2026-08-14): keep reversal-identity for now; revisit at Phase 117** — Cinderella's fixed-time convention (back-and-forth alternates north/south) becomes viable only once branch identity is durably continuation-carried; today the hybrid architecture would erase the monodromy at every static touchpoint. Complete loci (figure-eight) don't depend on this: real double-root crossings have no branch point, so both conventions cross identically. Deferred item recorded in TODO Phase 117.
- A full tangency crossing costs ~90–95 trials of the 128 budget (creep in ~35, arc ~10, doubling ladder out ~28 accepts — the ladder is intrinsic: allowed motion grows as √(t−t*)). One crossing per preview path is safe; two would starve. Preview paths are per-pointer-event and the static bail heals, but Phase 116's perf work may want a higher budget or a cheaper re-expansion.
- The ambiguity floor: near-misses tighter than ~1e-10 (path-parameter scale) starve and bail rather than risking a detour that encloses the complex branch points — deliberate: a silent swap there would be wrong by ~1e-10 world units, a bail is honest. Don't "fix" the ultra-tight-near-miss test by loosening the trigger or estimate guards; the undershoot bias in `estimateSingularParameter` is load-bearing (tested) and keeps spurious detours homotopic.
- Landing *exactly* on a tangency (t* at the path end) cannot be detoured — the pass would have to finish at a complex parameter. `DetourArc.plan` refuses (`tStar < end` strict), the pass starves, bail recovers to the double root. Same for an exactly-tangent *seed* (separation 0 refuses every trial; samples never form).
- `complexCarriers` skips realness gates only during the arc. During real-t tracing a complex carrier (e.g. a line through a currently-complex intersection) still yields no candidates and the branch coasts — Phase 114 semantics preserved exactly. Cross-complex continuation for *chains* of complex objects is future work (117+/M-CK), not smuggled in here.
- Inside the arc the traced points are genuinely complex non-conjugates, so real dependents (chord, bisector) are momentarily complex/undefined — unobservable (onStep fires at real parameters only, one notify per pass), but don't add mid-arc observation hooks without accounting for it.
- `DetourArc.tAt(0)` is bitwise `exit` and exactly real, and `DragPath.evaluate` at a real Complex t reproduces `path.at` bitwise (same lerp arithmetic) — the pass ends real with zero imaginary parts, no cleanup pass needed. Don't reorder those expressions.

---

## Session 113 (V2 Session 15) — 2026-08-14

**Done**
- **Phase 114 (Tracing II) complete** on `phase-114-adaptive-tracing`, merged to `main`, three commits:
- **Adaptive step controller (Cinderella rule)**: `recomputeAlongPath` drops uniform substeps for accept/halve control — first trial attempts the whole path; a trial is accepted only if every traced root's chordal motion stayed under half its candidates' minimum pairwise separation at the previous accepted step; refusal restores the slots (`TracedBranch.checkpoint`/`restore`) and halves, acceptance doubles (path end reached bitwise-exactly). `TracedBranch` grew the bookkeeping (`follow` = match + motion/separation/matchedIndex, `coast` for candidate-free substeps, `seed` now takes the start candidates so the first trial is constrained). Budget exhaustion (`stepBudget`, default 128; flag `TracingFlags.dragStepBudget`, replaces `dragSteps`) throws `TraceStepBudgetException`; the drag session's existing catch-all bails static. Returns `(acceptedSteps, rejectedSteps)` — the Phase 116 overlay feed.
- **Collision refusal**: a trial is also refused when two distinct-seeded branches on the same ordered curve pair grab the same candidate. Exempt: pairs whose seeds coincide within `doubleRootEpsilon` ("married" — duplicate branch objects legitimately travel together) and grabs of coincident candidates (a double root — riding the touch point together is correct). Tested through a scripted `IntersectionPoint` subclass — real geometry only reaches the ambiguity via exact ties or coast re-acquisition, which adaptive steps can't hit reliably.
- **Glados** (`tracing_properties_test.dart`): secant / persistent-miss / near-tangency-approach families × random drags — no swaps at any accepted step, endpoint = static solve labels included, bounded trials, halving provably forced near tangency. The secant family immediately found a real soundness hole: **the sep/2 rule alone is unsound on RP¹** — a quarter-turn step matched each root to the other branch *through the point at infinity* with motions just under sep/2 (a swapped bijection, invisible to collision refusal too). Fixed with an absolute per-step motion cap (`_maxAcceptedMotion = 0.25` chordal); counterexample pinned as a deterministic toy.
- **Through-tangency is now a deterministic starve**: the allowed motion collapses with the separation, accepted steps Zeno toward the singular t, budget exhausts, throw, static bail (toy + drag-session tests pin it). Phase 115's detour replaces starvation with a traced crossing.
- **Benchmark reworked** (`traced adaptive`, reports trials/frame): smooth stress frames resolve in **1 trial** — ms/frame static→traced: VM 0.062→0.065, AOT 0.076→0.119, js 0.080→0.100, wasm 0.075→0.120; traced/static 1.0–1.6× (was 8–12× at 16 fixed substeps), ≤ 2% of the 8 ms gate, checksums identical everywhere.
- Suite 2029 green, analyze clean (also fixed a pre-existing `prefer_asserts_with_message` info on main), `flutter build web` compiles. TODO rotation: Phase 112 moved to archive.

**Next**
- Phase 115 — Tracing III: singularity detection (root separation under tolerance / step-controller starvation — the `TraceStepBudgetException` path is the hook), semicircular complex detour in `t` around the singular parameter (`DragPath.evaluate` is already holomorphic), fixed detour orientation recorded for determinism; canonical through-tangency tests then flip from "starves" to "crosses with no jump, no swap".

**Gotchas**
- **Don't weaken the motion cap.** `_maxAcceptedMotion = 0.25` is what closes the RP¹ through-infinity loophole the glados suite found — sep/2 alone accepts silent swaps on wide secant steps (pinned regression toy in `recompute_along_path_test.dart`). Legitimate through-infinity motion (line∩line under a parallel sweep) is not forbidden, it just refines.
- Through-tangency starvation is *deliberate* Phase 114 behaviour — don't "fix" it by raising the budget; the creep is Zeno and no budget crosses. The toy uses `stepBudget: 40` specifically to keep the creep far from the fp-noise zone around the strict inequality (margins shrink as s³ near the touch point); keep it small if you touch it.
- A starving frame costs ~budget × substep (~4–7 ms at 128 on the stress rig) before bailing — fine against the gate, but it's per-frame while the user sits on a degeneracy; 115's detour also removes this.
- Collision refusal is belt-and-braces by design: under the motion bounds a same-candidate grab is provably impossible when both previous roots were distinct candidates — the reachable paths are coast re-acquisition and matching ties, hence the scripted-double tests. Married pairs are computed once per pass at seed time.
- `TracedBranch.separation` is the candidate set's *min pairwise* distance — for two-candidate sets that's exactly the distance to the alternative; once conic∩conic carriers expose four real candidates (Phases 119–120) it's a conservative proxy (noted in `_collisionFree`).
- The drag session is unchanged except the flag rename: any `TraceStepBudgetException` inside a traced frame falls into the existing static bail; consecutive frames re-seed from the static solve, so tracing self-heals after a bailed frame.

---

## Session 112 (V2 Session 14) — 2026-08-14

**Done**
- **Phase 113 (SPIKE 3 / Tracing I) complete** on `phase-113-tracing-scaffolding`, three commits:
- **`lib/domain/projective/tracing/`**: `DragPath` (endpoint-exact chart lerp `at(t)`; `evaluate(Complex t)` is the same interpolation continued *holomorphically*, w ≡ 1 — the shape Phase 115's detour needs), `TracedBranch` (per-`IntersectionPoint` slot, SoA `Float64List` storage per Phase 101; `nearestIndexAmong` = argmin of the scale-invariant chordal measure `|p×c|²/(|p|²|c|²)`, works on complex candidates), `Construction.recomputeAlongPath` (uniform substeps; seeds slots from current `projPoint`, clears them before returning; one notification; `onStep` observation hook).
- **Tracked recompute**: while its slot is active, `IntersectionPoint.recompute` follows the candidate nearest the tracked root instead of `candidates[branchIndex]`; empty-candidate steps keep the slot and resume matching. `branchIndex` is *never* mutated by a pass — the tracked value persists only until the next static recompute, and consecutive passes chain identity by seeding from what the last one left behind. Commit/save/undo stay fully static until Phase 116 owns those semantics; rollback is therefore exact.
- **Exclusions**: locus-chain intersection points are never seeded (the sweep-and-restore recompute would drag a tracked root along the sweep and break the flip machinery — moot in 117 when loci ride tracing); nothing seedable collapses the pass to one static solve at the path end.
- **Feature flag**: `TracingFlags.dragTracing` (default off, `dragSteps` 16), captured once per gesture in `DragSession.start`; traced previews apply to single-free-point drags only (rigid translations move several roots at once). The static-solve bail ships as promised: any failure inside a traced frame falls back to `moveFreePoint` (tested by forcing `dragSteps = 0`).
- **Toy harness** (`test/domain/projective/tracing/`): secant sweep (continuous histories, no swap, endpoint = static solve labels included, identity chained across two consecutive paths), persistent miss (conjugate roots tracked through the complex domain, labels preserved), through-tangency (histories continuous at fixed-step resolution — crossing step ~√(6h) — endpoint in the static candidate set up to labels). The drag-session test pins a real discriminator: dragging a line endpoint *past* the other flips the canonical conjugate order while the roots sit still — static previews relabel, traced previews hold each branch on its side.
- **Frame budget measured** (`benchmark/tracing_bench.dart` + `run_tracing.sh`, 100-object stress construction, 48 tracked branches, 16 substeps/frame, best of 5, ms/frame): VM 0.46, AOT 0.88, dart2js 0.62, dart2wasm 0.85 — **all ≤ 12% of the 8 ms Phase 116 gate** with the boxed engine and naive fixed steps; checksums identical on all targets. The SoA hot-loop rewrite (122) has enormous headroom.
- `dart:typed_data` added to the domain layer-rule allowlist (the SoA decision). Suite 2010 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-113-tracing-scaffolding`; then Phase 114 — Tracing II: adaptive step control (accept a step only if every root moved less than half its minimum pairwise separation, else halve), nearest-neighbour matching with *collision refusal*, per-drag step budget with graceful bail, glados over random constructions × random smooth drags.

**Gotchas**
- The tangency handoff is a genuine nearest-neighbour **tie**: the conjugate→real split is symmetric around the touch point, so both branches can grab the same root crossing it. Collision refusal (114) mitigates; only the complex detour (115) resolves it deterministically. The toy tests deliberately assert set-agreement, not labels, through tangency — don't "fix" them early.
- After a pass, `_point` = tracked root but `branchIndex` is untouched, so the object is out of sync with canonical addressing until the next static recompute. Deliberate: it keeps rollback exact and every jump-behaviour test green. Adoption/persistence is Phase 116 (with save re-derivation).
- The traced/static frame ratio is ~8–12×, not 16×: `moveFreePoint` re-derives `transitiveDependentsOf` per call while the traced pass hoists it across substeps. Don't read the ~30–55 µs substep as a solver regression.
- `DragPath.at` uses the two-product lerp form `start·(1−t) + end·t` specifically for bitwise-exact endpoints (`at(1) == end`); the drag session's preview/commit consistency relies on it. Don't "simplify" to `start + t·delta`.
- The locus-chain exclusion set is rebuilt on every `recomputeAlongPath` call (O(Σ chain lengths) per preview frame). Fine at current scales; dies with Phase 117 anyway.
- `benchmark/tracing_bench.dart` imports domain code only — keep it (and everything under `lib/domain/`) Flutter-free or the js/wasm benchmark targets break.

---

## Session 111 (V2 Session 13) — 2026-08-13

**Done**
- Merged `phase-111-point-on-object` to `main`.
- **Phase 112 complete** on `phase-112-consumers` — the consumer kinds are the *metric boundary*: they read the parents' projective accessors and project into the chart themselves, because their outputs (angles, lengths, areas, outlines, rendered text) are chart quantities by definition (M-CK later re-founds measurement on cross-ratios at exactly this boundary).
- **Migrated**: `VertexAngle`, `Polygon`, `DistanceMeasurement` (parent `projPoint` → `toVec2`), `LengthMeasurement`, `AreaMeasurement` (subject `conic` → `toCircleEq`), `ExpressionText` via `text_evaluator.dart` (all point/circle accessors; at-infinity or line-pair references render `?`), `LineAngle` (vertex = projective meet; `intersections.dart` import dropped), `SlopeMeasurement`.
- **V2 semantics changes** (tests updated, all documented in kind docs):
  1. `SlopeMeasurement`: a vertical carrier reports `double.infinity` and stays *defined* — rendered `—` by `formatLength`'s new non-finite guard; undefined only without a chart carrier (ℓ∞, complex). The slope tool test now expects a defined infinite commit.
  2. `LineAngle`: V1's absolute 1e-9 direction band is gone — nearly-parallel-but-crossing carriers mark their genuine tiny wedge (the old "falls back +1/+1 while parallel" test actually exercised near-*coincident* lines through the origin; it now tests exact coincidence, plus a new test pinning the tiny-wedge behaviour).
  3. `VertexAngle` deliberately stays undefined for an arm at infinity: a point at infinity is a direction *without a sign*, so a signed wedge there would break rescaling invariance — don't "improve" it.
- **Grep gate exceeded**: zero `intersections.dart` importers remain in `lib/` (the gate allowed `locus.dart`, which never imported it directly) — Phase 121's deletion is test-side only. Remaining affine reads in object files are the documented `orientedAlong` anchor derivations (`_v1Direction`-style), extent metadata, and §Parameterization chart reads.
- New per-kind Phase 112 tests: at-infinity/complex/line-pair parents → undefined, rescaling-invariance glados (VertexAngle measure, LineAngle legacy fold, DistanceMeasurement value/anchor, LengthMeasurement circumference), evaluator accessors, `formatLength` non-finite. Suite 1989 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-112-consumers`; then Phase 113 — SPIKE 3 / Tracing I: scaffolding (`lib/domain/projective/tracing/`, `DragPath`, `TracedBranch`, `Construction.recomputeAlongPath`, SoA buffers per Phase 101, feature flag + static-solve bail, toy-harness tests). Budget generously per PLAN — hardest phase per line.

**Gotchas**
- `SlopeMeasurement.value == double.infinity` flows into `ExpressionText` arithmetic via bare-name sugar and renders `Infinity` in templates (pre-existing `toStringAsFixed` behaviour, same as a `{1/0}` expression) — only the *label* path renders `—`. Revisit if users hit it.
- The consumer kinds now go undefined at ~1e9 relative magnitude (the `toVec2` at-infinity cutoff) where V1 had no ceiling — same wall as `Midpoint.position` (session 108 note); harmless for measurements, and the right realness gate once tracing complexifies parents' stored values (the actual payoff of this phase).
- `formatLength` renders any non-finite as `—`, NaN included — that's load-bearing for slope; don't "tighten" it to infinities only without checking.
- The `LineAngle` legacy acute fold (null signs) is orientation-free, so it tolerates un-anchored carriers (stubs); the signed wedge does not — sign conventions need the kinds' anchored `line` projections, like `TwoLineBisectorLine`.

---

## Session 110 (V2 Session 12) — 2026-08-13

**Done**
- Merged `phase-110-intersection-tangency` to `main`.
- **Phase 111 complete** on `phase-111-point-on-object`, two commits:
- **PLAN §Parameterization pinned** (new subsection beside the two early-pinned decisions): carrier parameters stay *real, in the affine chart* — signed arc-length on lines (through the `orientedAlong` anchor), polar angle on circles; tracing (113+) continues homogeneous *values*, never parameters; general real conics get stereographic parameterization when Phases 119/120 need it (rational → polynomial in homogeneous coordinates; ellipses close up, parabolas touch infinity once, hyperbolas twice); hyperbola branches are clamped real extents, no gluing through infinity; projective/complex parameters rejected.
- **`PointOnObject` migrated**: stores the homogeneous lift of the chart evaluation, `projPoint` override + `position` reading `x.re/y.re` directly (`w` exactly 1 until tracing — no `toVec2` at-infinity cutoff, which locus sweeps along diverging line arms rely on; pinned by a 1e12-parameter test). The `line`/`circle` reads in `recompute` are the *sanctioned chart reads* of §Parameterization, not bridge leftovers. Chart-less carriers (ℓ∞, complex, degenerate line-pair conic) → undefined with `projPoint` null, consistent with the Phase 110 realness gate. New glados: rescaling invariance through the object graph (line + circle hosts), `pointAt(parameterAt(p))` round-trip stability, glued point stays projectively incident under parent perturbation.
- **TODO correction**: Phase 111's migrate line listed `Arc`/`Sector` extents and `TriangleCenterPoint`, but both landed earlier (extents stayed affine metadata in Phase 109; `TriangleCenterPoint` migrated in Phase 107) — checklist annotated, only `PointOnObject` actually migrated this phase. TODO rotation: completed Phases 108/109 moved to archive.
- Suite 1972 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-111-point-on-object`; then Phase 112 — object batch 4: consumers (`VertexAngle`, `LineAngle`, `Polygon`, the measurement kinds, `ExpressionText`); `Locus` deliberately untouched until 117; grep gate: no object file imports `intersections.dart` except `locus.dart`.

**Gotchas**
- `PointOnObject.position` deliberately does NOT go through `toVec2()` — the stored lift has `w` exactly 1 and reads back totally at any magnitude. Switching it to `toVec2()` would impose the ~1e9 relative at-infinity cutoff and break locus infinity tails; don't "simplify" it (same trap as `FreePoint.position`, session 106).
- The stereographic-conic and hyperbola-extent parts of §Parameterization are *decision only* — no code exists until conics become carriers (Phases 119/120). `PointOnObject` still rejects non-line/circle parents.
- `PointOnObject.recompute` reading `curve.line`/`curve.circle` is sanctioned by PLAN §Parameterization (parameters are chart quantities; projections carry the orientation anchor). The Phase 112 grep gate should treat it as the documented exception alongside painter/hit-tester/codec.

**Done**
- **Phase 110 complete** on `phase-110-intersection-tangency`, three commits:
- **`IntersectionPoint` migrated** to projective candidates: `intersectionCandidates(curve1, curve2)` (public, shared with snap-to-intersection) — line∩line one `meet` (empty on coincident carriers), line∩conic two via `intersectLineConic` (line role by type), conic∩conic four via `intersectConicConic` with I/J filtered (new `isCircularPoint`, kernel). `branchIndex` addresses canonical order; `projPoint` = tracked candidate (complex conjugate mates through a miss, real-at-infinity for parallel lines); `candidateCount` = *distinct* real finite candidates (double root counts once — the locus walker contract). New `doubleRootEpsilon = 1e-6` classification tolerance: candidates real within it snap exactly real (`_realSnapped`) — replaces V1's world-unit tangency band with a root-noise-sized relative one (the `provoleas2.json` constructed tangency carries Im ≈ 6.6e-9 from rounding; a genuine miss grows as √|miss| and stays complex).
- **Polar-structure kinds migrated**: `PolarLine` = `A·p` verbatim (pole at center → ℓ∞ carrier, `line` null); `TangentLine` polar-based (touch points = polar ∩ conic, carrier = polar *of the touch point* — La Hire puts it through the pole; V1 left/right branch order re-derived affinely; complex conjugate carriers from inside); `RadicalAxisLine` on new `circles.dart` kernel `radicalAxisOf` = the pencil member `b.xx·A − a.xx·B` (exact for circle-shaped inputs; concentric → ℓ∞; coincident → zero triple; degenerate line-conic input → its own line, the flattening limit).
- **Bisector kinds migrated** on new holomorphic `euclidean.dart` kernels `angleBisectorOf` / `twoLineBisectorOf` (principal-√ unitization, V1's sum-vs-diff conditioning mirrored exactly). Internal/external selection is a *ray* concept, not projective: `AngleBisectorLine` feeds chart-canonical (w = 1) representatives; `TwoLineBisectorLine` anchors representatives to the affine orientations first (`.near` factory re-pointed off `intersections.dart`). V1's parallel band gone: nearly parallel lines bisect to the genuine mid-parallel.
- **Two standing rules pinned this phase** (both in `intersectionCandidates`' doc):
  1. **Ordering re-anchor**: `intersectLineConic` orders along the *representative's* direction, but no kind contract pins stored carrier signs (a join through a chart-normalized parent flips) — the line∩conic pair is re-ordered along the parent's oriented affine `line.direction`, exactly as `orientedAlong` re-anchors projections. Pinned by a stub test with a deliberately flipped representative.
  2. **Realness gate**: static intersection-shaped operations (`intersectionCandidates`, `TangentLine`'s polar construction) consume only *real* carriers. A complex carrier still passes through real points — an undefined intersection's bisector passes through its real vertex, which sat on the very conic being intersected — and mining it fabricates real geometry V1 left undefined (the locus-miss phantom: G popped up at B/626-land inside the |AD| < |AB| gap). Cross-complex continuation belongs to tracing (Phase 113+).
- `point_resolution.dart`'s `nearestIntersectionBranch` re-pointed at `intersectionCandidates` (canonical index = `branchIndex`, real candidates only, no throwaway probe objects).
- Locus goldens regenerated (2 px antialiasing shift from ~1e-10 kernel-arithmetic differences); suite 1962 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-110-intersection-tangency`; then Phase 111 — `PointOnObject` + parameterization on projective carriers (decision to record in PLAN first: parameters stay real in the affine chart; stereographic parameterization for general conics; hyperbola branches as clamped extents).

**Gotchas**
- `doubleRootEpsilon` (1e-6) is a third kind of tolerance: classification of *solver root coincidence* (tangency doubles, concentric I/J tilt ~1e-8). It never enters computed values. Don't tighten it below ~1e-7: double roots are inherently √machine-eps ≈ 1e-8 accurate.
- The realness gate means an `IntersectionPoint` chain member reading a complex parent yields **no candidates** (`projPoint` null), not a stored complex value — only intersections of *real* carriers store their complex misses. Phase 113+ revisits when continuation owns complex paths; don't "fix" the gate away before then.
- `radicalAxisOf` relies on the circle constructors' *exact* coefficient shape (`xx == yy` bitwise, `xy == 0`) — every Phase 109 constructor and `ConicMatrix.lift` emit it; a future constructor that doesn't will silently leave quadratic residue in the axis.
- V1 epsilon bands removed this phase (all documented in kind docs): line∩circle tangency band (|d−r| ≤ 1e-9 world), `PolarLine`'s pole-on-center guard, `RadicalAxisLine`'s concentricity guard, `TwoLineBisectorLine`'s parallel gate. Near-degenerate configs now produce genuine faraway geometry; exact degeneracy carries ℓ∞ (or zero → undefined). The V1-agreement glados tests skip 1e-3-relative margins around the old boundaries, per the Phase 102 convention.
- `TwoLineBisectorLine`'s parallel-degeneracy is *naturally* total: with parallel carriers one branch's direction vanishes and the other joins the meet-at-infinity with itself — both exact zero triples. No guard needed; don't add one.

---

## Session 108 (V2 Session 10) — 2026-08-13

**Done**
- **Phase 109 complete** on `phase-109-circles-as-conics`: `lib/domain/projective/circles.dart` — circle constructions as conics, all polynomial/holomorphic in homogeneous inputs: `pointCircleAt` (isotropic line pair), `circleWithRadius`, `circleThrough`, `compassCircleOf`, `diameterCircleOf` (bilinear `(X−p)·(X−q)` form), `circumcircleOf` (classical determinant, minors expansion), `apolloniusCircleOf` (`|PA|²|CB|² = |PB|²|CA|²`). Plus `ConicMatrix.poleOf` (adjugate·line; pole of ℓ∞ = center, exact for lifted circles).
- Migrated the circle kinds to stored `ConicMatrix`: `CircleCenterPoint`, `CompassCircle`, `DiameterCircle`, `FixedRadiusCircle` (`circle` pairs the projected center with its exact stored radius), `ThreePointCircle`, `ApolloniusCircle`, `TriangleCircle` base + `NinePointCircle` (circumcircle of the side midpoints, natively projective) + `InscribedCircle` (rides along project→incenter→lift, like Phase 107's `Incenter`), `Arc`/`Sector` carriers (angular extents stay affine metadata off the projection), `CircleCenter` (pole of ℓ∞). **V2 semantics**: collinear parents / equidistant Apollonius C now carry the degenerate line-pair conic (`conic` non-null, `circle` null, `isDefined` false) instead of no value; at-infinity parents give double-ℓ∞ / Thales-limit pairs.
- `toCircleEq` reworked twice, both deliberate: (1) center/radius arithmetic from **raw-entry ratios** (not chart-normalized entries), keeping integer centers/radii bit-exact — the pre-existing `expect(radius, 5)`-grade tests pass untouched; (2) the circle-shape check is judged against the **quadratic block's own scale**, not the full matrix norm — a whole-matrix relative check rejected genuine circles beyond |center| ≈ √(1/eps) ≈ 6e4 and broke the `locus-miss.json` infinity-tail regression (Thales circle over A and a driver running to infinity). Degenerate line-conics are no risk: the constructors produce their vanishing quadratic entries exactly.
- New `StubProjectiveCircle` in `test/projective_stubs.dart`; per-kind glados (rescaling invariance through the object graph, I/J membership, midpoint incidence) + V2-semantics tests; bridge test updated for the sanctioned collinear-conic change. Suite 1919 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-109-circles-as-conics`; then Phase 110 — `IntersectionPoint` v2 (candidates always 2 or 4, `branchIndex` on canonical order with I/J filtered) + tangency family (`TangentLine`, `PolarLine`, `RadicalAxisLine`, bisector lines), `point_resolution.dart` re-pointed at real candidates.

**Gotchas**
- TODO's Phase 109 line said "`CircleCenterPoint` from polar structure" — the polar-structure kind is `CircleCenter` (the center *point*); `CircleCenterPoint` is the circle from center + rim. Fixed in the ticked checklist.
- `toCircleEq`'s huge-circle acceptance means near-collinear `ThreePointCircle` configurations now produce enormous circles where V1's `circumcenter` epsilon might have nulled slightly earlier; the exactly-degenerate cases are exact zeros from the constructors, so tests stay deterministic. Same for `ApolloniusCircle`: V1's `1 − ratio²` epsilon band is gone — near-equidistant C gives a very large circle (continuity across the bisector; only exact equidistance degenerates).
- `Sector`'s start/end-on-center guard is now relative (`ProjPoint.closeTo`, 1e-9) where V1 compared `Vec2`s exactly — same policy shift as Phase 107's coincidence guards, pinned by a test.
- `Midpoint.position` (and every migrated point's `toVec2`) reads at-infinity beyond ~1e9 relative — the Sector/Arc chains in the locus fixture die there (t ≈ 4e9), comfortably past the tail-convergence threshold; V1 had no cutoff at all. If a future fixture needs more range, that cutoff is the next wall.
- `circumcircleOf` with one point at infinity is the line pair (line through the finite two, ℓ∞) — three of the conic's five defining points (it, I, J) sit on ℓ∞, so ℓ∞ is a component. Handy for tests; don't "fix" it to a null.

---

## Session 107 (V2 Session 9) — 2026-08-13

**Done**
- **Phase 108 complete** on `phase-108-transforms`: `lib/domain/projective/proj_transform.dart` — 3×3 complex `ProjTransform` (apply to point `M·p`, line `adj(M)ᵀ·l`, conic congruence `adj(M)ᵀ·A·adj(M)` — all via the adjugate, so division-free and holomorphic; `compose`, `adjugate`-as-inverse, `closeTo`/`isReal`/`normalized`/`scaledBy` per the layer conventions). Euclidean constructors polynomial in their homogeneous inputs: `translation`, `translationTaking` (bilinear in two points), `rotation`, `reflection` (`(a²+b²)I − 2nlᵀ`), `pointReflection`, `homothety`.
- Migrated the eight transform-point kinds: `ReflectedPoint`, `CentralReflectionPoint`, `RotatedPoint`, `TranslatedPoint`, `HomotheticPoint` (each = named `ProjTransform` applied to projective parents), `ProjectionPoint` (meet with `perpendicularThrough` — foot from a generic infinite point is the carrier's direction), `SegmentRatioPoint` (new kernel `lerpOf`, `midpointOf` generalized), `HarmonicConjugatePoint` (new kernel `harmonicConjugateOf`: `D = (C×B)ᵢA + (C×A)ᵢB` at the join's largest coordinate — division-free cross-ratio; **V2 semantics change**: C at the midpoint now conjugates to the join's point at infinity, marked as such, instead of going undefined).
- New glados generators `similarity` / `projTransform`; kernel suites for transform∘adjugate = id, join/conic covariance, `evaluate` scaling by det², I/J fixed by direct similarities and swapped by reflections; per-kind rescaling-invariance + at-infinity tests. Pre-existing suite passed untouched; 1861 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-108-transforms`; then Phase 109 — object batch 3: circles as conics (all circle kinds store `ConicMatrix`; `CircleCenterPoint` from polar structure; `circle` getter becomes projection; three collinear points → degenerate line-conic).

**Gotchas**
- `applyToLine`/`applyToConic` recompute `adjugate` per call (cheap, 9 entries). If a kind ever applies one map to many objects, hoist the transform — but don't cache inside `ProjTransform`; it's immutable-by-convention like the rest of the layer.
- `ProjTransform.reflection` of the line at infinity is the exact zero matrix (a = b = 0), not merely singular — reflection across ℓ∞ has no Euclidean meaning. Isotropic axes (a² + b² = 0, complex) give singular-but-nonzero maps.
- `harmonicConjugateOf` is total but only *meaningful* for C on line AB; the object gates collinearity with relative `isIncidentTo` (V1 used absolute world units — identical at test scales, divergent far from unit scale, same deliberate policy as Phase 107's coincidence guards). Coincident base pairs must be guarded with `closeTo` *before* calling (rescaled duplicates leave nonzero join residue — same gotcha as `carrierThrough`).
- `lerpOf(p, q, t)` with an endpoint at infinity degenerates to the zero triple exactly at the weight that selects the infinite endpoint's complement (t = 0 for q infinite) — `SegmentRatioPoint` nulls there. Bilinear-form artifact, documented in the kernel.
- The transform kinds null on `image.isZero` (exact zero triples from degenerate maps); near-zero noise triples can't arise for real parent configurations, so no `closeTo` guards are needed in these recomputes.

---

## Session 106 (V2 Session 8) — 2026-08-12

**Done**
- **Phase 107 complete** on `phase-107-incidence-core`: the incidence core stores homogeneous state. New kernel file `lib/domain/projective/euclidean.dart` (`directionOf`, `normalDirectionOf` = the I,J conjugate, `parallelThrough`/`perpendicularThrough`, `midpointOf`, `centroidOf`, `perpendicularBisectorOf` — all multilinear/holomorphic, zero-triple propagation) with its own unit + glados suite.
- Migrated: `FreePoint` (stores its lift; `position` reads `.re` back exactly at any magnitude), `LineThroughTwoPoints`/`Segment`/`Ray` on a shared `carrierThrough` join (segments/rays additionally require drawable endpoints — carrier nulled too; only the infinite line gains infinite-parent semantics), `ParallelLine`/`PerpendicularLine` via a projective `carrierFrom` hook on `RelativeLine`, `PerpendicularBisectorLine`, `Midpoint`, and `TriangleCenterPoint` + `Centroid`/`Orthocenter`/`Circumcenter` (centroid trilinear; ortho/circumcenter as meets of altitudes/bisectors — collinear vertices now land at infinity, marked as such). `Incenter` rode along on the migrated base (project → `tc.incenter` → lift): semantically unchanged, not "migrated".
- `orientedAlong` in `geo_object.dart` re-anchors V1 line orientations at projection time (p1→p2, reference direction) — branch orderings and parameter extents stay bit-compatible in direction. Pre-existing suite passed **untouched**; with the new per-kind glados (complex-rescaling invariance via `test/projective_stubs.dart` stubs) and V2-semantics tests the suite is 1801 green, analyze clean, `flutter build web` compiles.

**Next**
- Merge `phase-107-incidence-core`; then Phase 108 — `proj_transform.dart` (3×3 complex matrix; apply to point/line/conic) and the transform-point kinds (`ReflectedPoint`, `RotatedPoint`, `HarmonicConjugatePoint` via cross-ratio, …).

**Gotchas**
- `join(p, p.scaledBy(k))` is only *algebraically* zero — floating point leaves a tiny nonzero triple. Coincidence is filtered by the `closeTo` guards in `carrierThrough`/`PerpendicularBisectorLine`; only exact duplicates cancel bitwise. Don't rely on `isZero` for rescaled duplicates.
- Prefix-imported extensions still participate in *implicit* extension resolution: importing both `test/domain/math/generators.dart` and `test/domain/projective/generators.dart` (even `as pg`) makes `any.vec2` ambiguous. In files needing both, build the complex scalar from `any.coordinate` instead.
- `FreePoint.position` reads the stored lift's `.re` directly (w is exactly 1). Don't "simplify" it to `toVec2()!` — the relative `isFinite` check calls coordinates beyond ~1e9 "at infinity" and the `!` would throw.
- Coincidence guards are now *relative* (`ProjPoint.closeTo`, eps 1e-9) where V1 used absolute 1e-9 world units — identical at test scales, divergent far from unit scale. Deliberate; the layer's eps policy is relative.
- The migrated-kind contract for the undefined-projective-view bridge test still holds because degenerate *inputs* null the carrier; but migrated kinds can now expose a non-null `projPoint`/`projLine` while `isDefined` is false (points at infinity) — that is the intended reading, don't "fix" it back.

---

## Session 105 (V2 Session 7) — 2026-08-12

**Done**
- **Phase 106 complete** on `phase-106-bridge`: lift-from-affine projective bridge in the abstract kinds — `GeoPoint.projPoint` (`[x,y,1]`), `GeoLine.projLine` (coefficient-wise), `GeoCircle.conic` (`ConicMatrix.lift`), each null exactly while the affine view is; kind-level docs rewritten to the migrated reading (`isDefined` = "real and finite after projection"). Zero behaviour change: the pre-existing 1754 tests pass untouched.
- `buildKitchenSink()`/`geometryOf()` extracted verbatim from the codec test into shared `test/kitchen_sink.dart` (domain-only imports); the new `geo_object_bridge_test.dart` loops it as the every-concrete-kind registry — lift∘project agrees with each affine view, plus null propagation on degenerate line/circle/point instances. Suite 1756 green, analyze clean.
- PLAN §Migration now pins the standing rule in-document: **new domain code reads the projective accessors only**; affine getters exist for painter, hit-tester, codec, and unmigrated `recompute()` bodies.
- TODO rotation: completed Phases 100–104 moved to `docs/archive/TODO-completed-phases.md` (105/106 remain as the recent-completed pair).

**Next**
- Merge `phase-106-bridge`; then Phase 107 — object batch 1 (incidence core): migrate `FreePoint`, `Midpoint`, `LineThroughTwoPoints`, `Segment`, `Ray`, `ParallelLine`, `PerpendicularLine`/`PerpendicularBisectorLine` (conjugate directions w.r.t. I,J), `Centroid`, `Orthocenter`, circumcenter-as-point to stored homogeneous state.

**Gotchas**
- `LineEq`'s constructor renormalizes to a unit normal and `ProjLine.toLineEq` may flip orientation (chart normalization divides by the largest-magnitude coordinate, sign included) — compare projected lines with `closeTo` (orientation-blind), never by coefficients.
- The kitchen sink is the de-facto kind registry for exhaustive tests: the codec encoder throws `UnsupportedError` for a kind missing from it, so new kinds must be added there (the codec test enforces this; the bridge test rides the same guarantee).
- No web smoke this session — zero-behaviour-change phase; the suite (incl. widget tests) is the evidence.

---

## Session 104 (V2 Session 6) — 2026-08-12

**Done**
- **Phase 105 complete** on `phase-105-conic-conic`: production `intersectConicConic` in `lib/domain/projective/conic_intersection.dart` on the proper types, per the Spike-2 recipe; the Cardano cubic moved to `cubic.dart` (`solveCubic`/`solveQuadratic` public, tested); `tolerances.dart` rewritten as the layer's single documented eps policy (relative predicate tolerance vs named kernel cutoffs on balanced unit-Frobenius data). `pencil.dart` and its raw `CVec3`/`CMat3` deleted; `benchmark/pencil_stress.dart` re-pointed at the production API.
- **Translation balancing closes the Spike-2 far-offset gap**: centroid (mean of the conics' adjugate poles of ℓ∞) → origin before `diag(σ,σ,1)` + Frobenius. Unit circles at offset 1e6 now solve to 1.2e-10 ≈ one ulp of the answer (prototype: 2.9e-5); ≤ 5e-48 through offset 1e4. Regression bounds tightened ~1000×.
- **Canonical ordering implemented and glados-pinned**: real finite first in V1 `intersectCircleCircle` order (left of the directed center line; swapping arguments reverses), then real-infinite, then non-real by a rescaling-invariant Hermitian measure — conjugate mates negative-first, so circles end […, J, I]. Ordering is invariant under complex rescaling of either input (tested).
- Coincident conics (within `coincidentConicEpsilon` = 1e-13) report no discrete intersection; degenerate inputs (line pairs, double lines) work as pencil members. Full suite 1754 green, analyze clean.

**Next**
- Merge `phase-105-conic-conic`; then Phase 106: bridge layer in the abstract kinds (`GeoPoint.projPoint` / `GeoLine.projLine` / `GeoCircle.conic` lift-from-affine defaults, zero behaviour change, exhaustive lift-agreement test over the codec's kind registry).

**Gotchas**
- The non-real ordering key must stay Hermitian (largest of Im(x̄y), Im(x̄w), Im(ȳw), norm-scaled). A key read off chart-normalized imaginary parts flips with which coordinate `normalized` divides by — noise-driven when two coordinates tie in magnitude (I/J!). This is classification, not kernel math, so Hermitian is allowed here (nowhere else).
- Far-offset accuracy is now representation-limited, not solver-limited: beyond offset ~1e8 (unit radius) `ConicMatrix.lift` itself loses r² below ulp(cx²) and the input *is* a point circle. Phase 109's stored conics inherit this; if it ever matters, store conics pre-translated.
- `coincidentConicEpsilon` sits at 1e-13 deliberately below the near-identical stress family — circles δ = 1e-12 apart must still solve (they do, to 1e-8 incidence); don't raise it toward `projectiveEpsilon`.
- Double roots (tangencies) are inherently ~sqrt(machine-eps) accurate and the joint-Newton polish is rightly skipped there (singular normal equations, and a double line's gradient is exactly zero). Don't tighten the 1e-6 tangency test bounds.
- Pencil cubic coefficients come from interpolating det(A+λB) at λ ∈ {0, ±1, ∞} — same absolute accuracy as column-substitution at unit Frobenius, much less code.

---

## Session 103 (V2 Session 5) — 2026-08-12

**Done**
- **Phase 104 complete** on `phase-104-conic-matrix`: `lib/domain/projective/conic_matrix.dart` — symmetric 3×3 complex `ConicMatrix` (`evaluate` = pᵀAp, `polarLine`, `containsPoint`, `closeTo`, `isReal`, `rank`, `normalized`, `scaledBy`), lift from `CircleEq`, `linePair`, `throughFivePoints` (complex Gauss–Jordan on chart-normalized points, null on rank < 5), `toCircleEq` projection (added ahead of Phase 109's `circle` getter — small, tested), and the circular points `circularPointI`/`J` as constants.
- `intersectLineConic` on the proper types: always 2 `ProjPoint`s via the Spike-2 span trick; canonical order = increasing parameter along the representative's `(b, −a)` direction, so `ProjLine.lift` of a V1 `LineEq` orders exactly like V1 `intersectLineCircle` (flipping the representative flips the order — V1 semantics); conjugate pairs pinned by ascending Im of the chart parameter.
- 33 new tests (units + glados): I/J ⇔ circle shape, five-point recovery of circles, rank on line pairs/double lines, V1 agreement in positions *and order* on transverse + constructed-tangent + miss cases, rescaling invariance of every predicate and of the intersection point set. Full suite 1749 green, analyze clean.

**Next**
- Phase 105: production `intersectConicConic` on `ConicMatrix`/`ProjPoint` per the Spike-2 recipe, adding the missing *translation* part of balancing (centroid → origin) and the single documented tolerance policy; promote the stress corpus to regression tests; re-point `pencil.dart` at the proper types (its raw `CVec3`/`CMat3` and `pencil_test.dart`'s five-point Gaussian helper survive until then, deliberately).

**Gotchas**
- `ConicMatrix.closeTo` computes the 2×2 minors of the coefficient 6-vectors directly (Lagrange identity). Don't "simplify" it to the Cauchy–Schwarz difference `‖A‖²‖B‖² − |⟨A,B⟩|²` — that cancels catastrophically and can't resolve residuals below ~1e-16 relative, i.e. it breaks at the default eps² = 1e-18.
- `rank` is relative to the Frobenius norm, so a tiny circle far from the origin classifies as a point circle (|det| = r² drowns against ‖A‖³ ~ |center|⁶). Real conditioning, not a bug — the translation-balancing gap Phase 105 closes. The rank-3 glados test is deliberately restricted to `smallCircle` scales.
- Canonical intersection order is a property of the line's *representative*, not the line: scaling by a negative/complex factor can permute the pair. Compare point sets, not indices, after rescaling.

---

## Session 102 (V2 Session 4) — 2026-08-12

**Done**
- **Phase 103 complete** on `phase-103-proj-types`: `lib/domain/projective/proj_point.dart` + `proj_line.dart` — homogeneous `[x:y:w]` / `[a:b:c]` over boxed `Complex`, cross-product `join`/`meet`, bilinear incidence, chart normalization (divide by largest-magnitude coordinate — removes scale *and* phase, making `isReal` scale-invariant), relative predicates (`closeTo`, `isIncidentTo`, `isReal`, `isFinite`), `lift` from `Vec2`/`LineEq`, total projections `toVec2()`/`toLineEq()` (null = complex or at infinity — the rendering question). Zero triples fail every predicate and propagate instead of throwing; NaN likewise.
- `lib/domain/projective/tolerances.dart`: provisional shared `projectiveEpsilon = 1e-9` (relative, sine-like measure) — Phase 105 consolidates the layer policy here.
- 47 new tests (units + glados: duality, incidence, rescaling invariance of every predicate/projection, parallels meeting at `[d.x, d.y, 0]`, lift∘project = id). Full suite 1716 green, analyze clean.

**Next**
- Phase 104: `ConicMatrix` + circular points I/J + `intersectLineConic` (canonical ordering compatible with V1 `intersectLineCircle`). The pencil prototype's `intersectLineConic` and its span trick are the reference; conic-from-five-points replaces the test-only Gaussian helper in `pencil_test.dart`.

**Gotchas**
- `ProjPoint`/`ProjLine` `==` is exact component equality; projective equality is `closeTo`. Don't compare homogeneous values with `==` in geometry code.
- All predicates are *relative* (residual vs the triples' norms), so eps values are dimensionless — don't reuse them as world-space distances.
- The pencil prototype still runs on raw `CVec3`/`CMat3`; it gets re-pointed at the proper types in Phase 105, not before.

---

## Session 101 (V2 Session 3) — 2026-08-12

**Done**
- **Phase 102 (SPIKE 2) complete** on `phase-102-pencil-spike`: `lib/domain/projective/pencil.dart` — conic∩conic via degenerate pencil members, prototype-quality but fully tested (23 tests: cubic solver units + glados, split recovery, line∩conic vs V1, circle pairs vs V1 `intersectCircleCircle`, five-point conics through 4 shared points, random-conic incidence, stress-corpus regression bounds).
- `benchmark/pencil_stress.dart` measures the corpus; bounds pinned in `pencil_test.dart` with ~100× margin.

**The stability recipe (Phase 105 implements to this)**
1. **Balance coordinates** with `S = diag(σ,σ,1)`, σ = max(linear/quadratic, √(constant/quadratic)) entry ratios over both matrices; then unit-Frobenius normalize. Frobenius alone is NOT enough — without balancing, 10⁶-scale circles collapse entirely; with it, scale extremes 10^±8 sit at machine precision.
2. **Cubic** det(A+λB): Cardano on the depressed form, larger resolvent root, one Newton polish per root on the original cubic; degree drop → quadratic → linear.
3. **Member choice is the heart of the recipe.** Candidates = 3 Cardano roots + cluster-robust extras: the triple-root center −c₂/(3c₃) and the two derivative roots (≈ double roots) — these are well-conditioned exactly where root clusters make individual Cardano roots garbage (near-identical conics → near-triple root with ∛machine-eps error). Filter |det(member)| ≤ 1e-8 (unit Frobenius), then score = rank2Signature / (√|det| + 1e-16), where rank2Signature = max |diag(adjugate)|. The √det penalty prefers the most *accurately degenerate* member (simple well-separated root → det ~ machine eps) — without it, near-tangency picks the near-double point-circle member and loses 8 digits.
4. **Split** rank-2 via adjugate (`adj = −ppᵀ` → p from largest diagonal, then `C + M_p = 2hgᵀ` rank 1 → lines = max row/col); rank-1 → double line from the largest row.
5. **Line∩conic**: span the line by `l×e_i, l×e_j` (i, j avoiding the largest component of l — guarantees independence), homogeneous quadratic, cancellation-free root pairs (q:a), (c:q).
6. **Polish** each point: one joint Newton step onto both conics (minimal-norm along both gradients, bilinear 2×2 normal equations), skipped near tangency (singular system).

**Achieved tolerances (unit-circle-scale configs)**: transverse ~1e-16 incidence; near-tangent ε→1e-12: incidence ≤ 2e-16, point error ≤ 1.2e-11; just-missing: conjugate pair with |Im| = √ε ± machine noise; near-identical circles (near-triple root): worst incidence 8e-11, worst point error 1.7e-7 at δ=1e-6; concentric → I,J doubled with ~1e-8 tilt.

**Known gap for Phase 105**: balancing has no *translation* part — small circles far from the origin lose digits quadratically in the offset (1e2 → 8.5e-13, 1e4 → 8.6e-9, 1e6 → 2.9e-5 and the points' imaginary contamination starts failing realness checks). Recipe: conjugate by a translation taking the configuration centroid to the origin before scaling. Pinned as bounds in the far-offset stress test.

**Next**
- Merge `phase-102-pencil-spike`; then Phase 103: `ProjPoint`/`ProjLine` (join/meet, incidence, normalization, lift/project) — the pencil prototype's raw `CVec3`/`CMat3` get proper types in 103/104 and the pencil is productionized against them in 105.

**Gotchas**
- The five-point-conic helper in `pencil_test.dart` (real Gaussian elimination) is test-only scaffolding; Phase 104's conic-from-five-points is the real one.
- `dotVec`/`quadForm` are bilinear, NOT Hermitian — deliberate (holomorphy is what analytic continuation needs). Don't "fix" them to conjugate.
- Glados comparison tests skip 1e-3-relative margins around V1's tangency/concentricity classification boundaries — V1's epsilon semantics, not pencil weakness.

---

## Session 100 (V2 Session 2) — 2026-08-12

**Done**
- **Phase 101 (SPIKE 1) complete** on `phase-101-complex-spike`.
- `lib/domain/projective/complex.dart`: immutable `Complex` — `+ - * /` (Smith division), `conj`, `abs`/`abs2`, `arg` in (−π, π], numerically stable principal `sqrt` (branch cut on the negative real axis, `sqrt(-x) = +i·sqrt(x)`), `polar`, hybrid abs/rel `isRealWithin(eps)` and `closeTo`. Division by zero yields non-finite components, never throws. 33 tests: glados field axioms up to eps, conjugation/modulus identities, branch cut pinned on both sides of the cut.
- `benchmark/complex_bench.dart` + `run_all.sh` + `wasm_driver.mjs`: quadratic + cubic (Cardano) complex root solving, three styles — boxed `Complex`, `(double,double)` records, fully inlined SoA scalar doubles — identical LCG coefficient streams, checksums cross-check all styles on all targets.

**Benchmark table** (ns/solve, best of 5, M-series mac; node for js/wasm):

| target | quad boxed | quad records | quad SoA | cubic boxed | cubic SoA |
|---|---|---|---|---|---|
| VM JIT | 35.9 | 41.4 | 26.4 | 128.1 | 86.3 |
| AOT exe | 36.7 | 29.4 | 26.0 | 118.0 | 86.2 |
| dart2js -O4 | 52.0 | 50.0 | 40.0 | 155.0 | 90.0 |
| dart2wasm | 30.0 | 41.7 | 19.4 | 114.0 | 83.1 |

**Decisions recorded (SPIKE 1 exit)**
- **No allocation cliff**: boxed `Complex` is only 1.3–1.7× slower than SoA even on dart2js — the feared js-allocation catastrophe does not materialize. So: **boxed `Complex` is the API type everywhere** (kernel Phases 103–112 use it freely); worst-case cubic at ~155 ns/solve supports ~50k solves/ms-frame-budget, ample for static solves.
- **SoA policy confirmed for the tracing inner loop** (Phases 113–116): fully inlined scalar-double math over `Float64List` buffers — consistently fastest on every target (up to 1.7×). **Records rejected** as the hot-loop shape: inconsistent (faster than boxed on AOT, *slower* on VM/wasm — likely boxing differences).
- **SoA API shape**: no tuple-returning helpers in the hot loop; roots live in parallel `re[]`/`im[]` `Float64List`s, intermediate values are pairs of local doubles, formulas inlined (quadratic/cubic solvers in `complex_bench.dart` are the reference implementations, checksum-verified against boxed).
- **Web compile-target policy**: wasm beats js on every workload (19–83 vs 40–90 ns) and even beats VM JIT. Preliminary call: **dart2wasm is the intended web target**; final decision executes in Phase 122 (per PLAN, after tracing exists to benchmark end-to-end).

**Next**
- Merge `phase-101-complex-spike` to `main`, then Phase 102 (SPIKE 2): conic∩conic pencil prototype — complex cubic solver (reuse the benchmark's Cardano, productionized), degenerate-member split, glados vs V1 `intersectCircleCircle` ground truth.

**Gotchas**
- `benchmark/` imports `package:regula/domain/projective/complex.dart` — pure Dart, compiles standalone with `dart compile`; keep it Flutter-free or the js/wasm targets break.
- dart2wasm's generated `.mjs` loader API (compile/instantiate/invoke) has changed across SDK versions; `wasm_driver.mjs` matches SDK 3.11 — revisit if the SDK is upgraded.
- Records benchmark kept in the harness deliberately as a canary: if a future SDK makes records reliably fast, the SoA inlining tax could be revisited.

---

## Session 99 (V2 Session 1) — 2026-08-10

**Done**
- **Phase 100 — repo seeded.** regula2 created by history-preserving `git clone` of regula (457 commits; branch point `7ef44db` tagged `v1-final`; `origin` remote removed so the repo is independent — `git blame`/`bisect` work across the V1/V2 boundary).
- The V2 assessment archived as `docs/V2-assessment.md` (it was untracked in regula).
- Docs reset for V2: old PLAN/STATUS/TODO rotated to `docs/archive/` (`PLAN-v1.md`, `STATUS-sessions-89-98.md`, `TODO-v1-final.md`); new `docs/PLAN.md` (projective-canonical/affine-as-view migration strategy, kernel-track table, M-CK/M-P/M-3D milestone outlines, risks, reuse contract) and `docs/TODO.md` (Phases 100–122 checklists). `CLAUDE.md` gained the V2 kernel invariants; `README.md` gained the V2 statement.
- Deferred decisions recorded in PLAN: package stays `regula` for now (174 `package:regula/` imports); no GitHub remote yet, CI workflows ride along until one is added.

**Next**
- Phase 101 (SPIKE 1): `Complex` type + benchmark harness — boxed vs `Float64List` SoA on VM/dart2js/dart2wasm; exit with the compile-target policy and the SoA API shape recorded here.

**Gotchas**
- Verification of the seeded tree passed: `flutter analyze` clean; 1587 tests + 26 goldens green; `flutter run -d web-server` serves HTTP 200; `git blame` on `construction.dart` traces to the original "Phase 2: Construction DAG" commit.
- `~/.config/git/ignore` has a global `cl-*` pattern — that's why the assessment was untracked in regula; it's archived here as `docs/V2-assessment.md` (no `cl-` prefix) to dodge it.
- Branch-ordering tests are load-bearing: the canonical-order compatibility rule in PLAN §Migration exists so they stay green until Phases 116–117 deliberately change dynamic behaviour. Don't "fix" them earlier.
