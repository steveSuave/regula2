# Build TODO — V2 kernel track

Live checklist for the V2 phases described in `docs/PLAN.md`. Tick items as they land on `main` with `flutter analyze` clean and `flutter test` green.

Definition of done for each phase: code merged, tests passing, app runnable (chrome + one native target), `docs/TODO.md` updated, `docs/STATUS.md` entry written.

Rotation: this file holds open phases plus the most recent couple of completed ones. Fully-completed phase checklists move to `docs/archive/TODO-completed-phases.md`. V1's final checklist state is archived at `docs/archive/TODO-v1-final.md`.

Phase numbering starts at 100 to mark the V2 era (V1 ended at Phase 73). Prover (M-P) and 3D (M-3D) milestones get numbered phases when opened — see their outlines in `docs/PLAN.md`.

## Carried over from V1 (environment, not code)

- [ ] Android emulator smoke — needs an AVD + system image (`sdkmanager` download to approve)
- [ ] iOS simulator smoke + `flutter build ios` — blocked on complete Xcode install + CocoaPods
- [ ] Stretch from V1 Phase 19: hand-written SVG export (may slip forever)

## Phase 115 — Tracing III: degeneracy detection + complex detour

- [x] Singularity detection: starvation trigger (trial step under `detourTriggerStep` *and* tightest separation under `detourTriggerSeparation`), singular parameter extrapolated from the last two accepted steps' separations via the collapse law s = C·√(t*−t) (`estimateSingularParameter` — provably *undershoots* on near-misses, the bias that keeps detours homotopic to the real path)
- [x] Path deformation: semicircular `DetourArc` in complex `t` (safety-margined radius, shrink-to-fit with strict enclosure, bitwise-real exit), walked by the identical acceptance machinery with arc-scoped complex carriers (`TracedBranch.allowComplexCarriers` → `intersectionCandidates(complexCarriers:)`, realness gates only — the kernel is holomorphic throughout); orientation recorded as `detourOrientation`'s *odd* drag-direction rule — a fixed absolute half-plane provably swaps conjugates on a there-and-back drag (one net winding; the probe caught it), oddness makes it a bitwise identity
- [x] Canonical tests: line through tangency crosses with no jump, no swap, deterministic sides, endpoint = static solve; there-and-back identity; chord *and* perpendicular bisector of the conjugate pair stay real, defined lines across the crossing; near-misses trace through on the real axis (no detour) or starve cleanly — never a silent swap; singular endpoint starves and bails (no valid arc)
- [x] Property: detoured endpoint = real-path endpoint when no singularity is enclosed — a co-traced transverse pair rides another pair's detour to exactly its real-path endpoint, no swap at any observed step

## Phase 116 — Tracing integration: default drag resolution + perf gate

- [x] `drag_session.dart` drives `recomputeAlongPath` by default (`TracingFlags.dragTracing` defaults on; kept as the escape hatch for static-preview tests); branch identity held by `TracedBranch` between recomputes and **adopted** at every completed pass's end: `branchIndex` := the final step's `matchedIndex` (the canonical-order index of the tracked root), guarded against coasts, double-root ties and out-of-range indices — so static recomputes, mid-gesture bails and commits all re-select the traced branch
- [x] Save re-derives `branchIndex` from canonical order — falls out of pass-end adoption (the saved index *is* the canonical address of the tracked root; codec unchanged, round-trip pinned). The gesture's one command carries the net re-pointings (`MoveFreePointCommand.branchChanges`, new `Construction.setIntersectionBranch` primitive), so undo/redo replay traced identity exactly; rollback/cancel restore pre-drag indices. No existing jump-behaviour test needed loosening — none pinned commit-time relabeling (STATUS notes)
- [x] Debug overlay showing step counts: ⇧O (`AppAction.toggleTraceOverlay`) toggles a `TraceStatsOverlay` canvas chip — accepted/rejected/detours per traced frame, or "static bail" — fed by `DragSession.traceStats` through `ToolNotifier.lastTraceStats`, live mid-gesture via the construction revision
- [x] **Performance gate** (standing from here on): ≤ 8 ms kernel time per drag frame on a 100-object stress construction (VM); js/wasm numbers recorded — PASS on every target at ~1% of budget (ms/frame static→traced: VM 0.064→0.065, AOT 0.078→0.118, js 0.080→0.100, wasm 0.076→0.120; 1.00 trials/frame, checksums identical; adoption adds nothing measurable vs Phase 114)

## Phase 116b — Tracing integration II: constrained-point drags

Found by the Cinderella no-jump demo (C, D on a line, equal circles around each, E = circle∩circle): dragging a `PointOnObject` ran the static per-frame solve — tracing only drove free-point drags — so E jumped when C crossed D (canonical circle∩circle order flips with the directed center line). The roots never approach each other in that example; only the labels flip, so real-axis continuation suffices there, but tangency slides need the detour too.

- [x] Generalize the tracing walk over an abstract drive: `_traceAlong` (acceptance, collision refusal, detour, adoption) shared by `recomputeAlongPath` and the new `Construction.recomputeAlongParameterPath(id, from, to)` lerping a `PointOnObject.parameter` (real steps re-enter `recompute`, so host extent clamping behaves exactly as static; a clamped stretch cannot starve — position is constant there)
- [x] Complex parameter evaluation for detours: `Complex.cos`/`sin` (hyperbolic identities, bitwise-real on the real axis), `PointOnObject.tracedPosition` (pass-internal, mirroring `FreePoint`'s), carrier chart forms continued holomorphically (line: affine in p; circle: cos/sin of complex angle); 1D odd detour orientation (`detourOrientation1D`)
- [x] `_SlideDragSession` traces by default (same flag, static bail, per-frame identity chaining, branch adoption via the shared `_BranchSnapshot`); `SetPointOnObjectParameterCommand` carries `branchChanges` like the move command
- [x] Two engine fixes the demo forced (see STATUS): **gesture-scoped seed memory** (`seedMemory` on both trace entry points, session-owned) re-seeds an intersection undefined at a pass boundary from the previous pass's roots, bridging exact-degeneracy frames; **coast-entry refusal** (`TracedBranch.hasCandidates`) — a match→coast transition on a trial wider than 1e-5 of the path is refused, closing a latent Phase 114 hole where a wide trial landing exactly on a carrier degeneracy froze the slot on a stale root and starved the pass
- [x] Tests: Cinderella rig at engine and session level (no swap at any step, coast through exact coincidence, seed-memory bridging + no-memory discriminator, adoption + static reproduction, commit/undo/redo, cancel, static-relabel discriminator); tangency slides detour and cross on line *and* circle carriers; there-and-back identity on a parameter drive; complex trig units + glados; `hasCandidates` round-trip; perf gate re-run unchanged (PASS ~1% all targets)

## Phase 117 — Locus rewrite on tracing

- [x] New `Locus.recompute`: traced walk over the tracing engine per defined run of a sampleCount-cell canonical scan (the scan is bitwise the old grids — intersection-free chains return it directly); shared acceptance rules extracted to `trace_acceptance.dart`; folds swap at the walk's last *confident* state and reverse (the 39c parity + closure/trim contract kept verbatim); crossings detour in complex sweep parameter (defensive until conic∩conic carriers, 119–120); full lines sweep RP¹ cyclically, splitting the wrap when the chain is undefined at driver-infinity
- [x] Deleted: tan-grid ray sampling (the tan substitution survives as the drive's density profile), 48-step boundary bisection + ladders (the walk's Zeno-in accepted steps are the ladder, fenced from the ε-tangent zone by the acceptance rule), branchIndex flipping (never mutated at all now), infinity tails (the domain edge evaluates at the carrier's direction point, w = 0 — infinity falls out of projection; a reversed positioning prefix with a divergent-tail trim replaces the 39e decay ladder)
- [x] Existing locus corpus passed **unchanged** (closed loci, figure-eight, doc-1 trimming, both fixture documents); the only test edit is the parabola fixture's coreSamples pin (core = the scan's focus-window slice now). Two engine finds fixed on the way: `TracedBranch.setBalance` (the raw chordal metric is the world-origin angle metric — silent far-out branch swaps; identity default keeps drags bitwise) and an index-flip consistency guard for the matched-motion blind spot (locus walk only; audit the drag engine in 121/122)
- [x] Goldens regenerated (locus scene light/dark): visually identical, subpixel sample placement only — reviewed in STATUS Session 117

## Phase 117b — Tracing degeneracy robustness (from two user documents)

Opened 2026-08-15 from `apatitos-topos.rgl` and `locus-miss-2.json`: dragging a free point in the first froze the app in Chrome, and its locus drew the wrong sheet over a third of the sweep. Both are engine gaps, not locus gaps — see PLAN §"Root collisions: seen, measured, walked around".

- [x] **Collisions can no longer hide inside an accepted step**: `collisionStepLimit` caps the next step by the extrapolated distance to the collision, in both walks. Without it a *transversal* crossing (separation vanishing linearly — the second intersection of a line drawn through a point already on the curve) dips to zero and recovers inside one scan cell with both endpoints comfortably separated, so nothing starves and nearest matching keeps the canonical index instead of the analytic branch
- [x] **The collision parameter is measured, not extrapolated**: `locateSeparationMinimum` brackets and ternary-searches the separation profile; its depth *relative to its shoulders* is also the crossing/near-miss discriminator (`SeparationMinimum.isCollision`, an absolute *and* a relative floor). A measured near-miss now suppresses the detour outright — strictly stronger than the undershoot heuristic it gates, which still stands in when no bracket exists
- [x] **Detour arcs must leave the real axis**: angular steps capped at `maxDetourArcStep` (π/4). A one-trial semicircle continues from the arc's real entry straight to its real exit — the very step across the collision the detour exists to prevent, and indistinguishable to the acceptance rule
- [x] **Structural double roots never seed**: candidates coincident within `doubleRootEpsilon` at seed time (`TangentLine ∩ the circle it touches`) have no branch identity to hold, and seeding one made the Cinderella bound refuse every trial — the whole pass starved and bailed on *every frame of every drag* in that document
- [x] **Loci are held back during a tracing pass** and settled once at its end: a locus is a DAG leaf, so no acceptance decision reads one, while recomputing one is a full traced sweep. This is what turned the starving frames into a freeze — a bailing frame paid ~130 locus sweeps
- [x] One more latent bug the rigs found: a detour that flips the matched index left `_prevMatched` stale, so the Phase 117 relabel-consistency guard refused *every* trial past the arc exit and the walk stalled there until its budget ran out. Hidden until now because exits happened to land inside the re-entry floor, where the guard is skipped. Re-baselined after an arc, exactly as the fold swap does
- [x] Tests: `apatitos-topos.rgl` as a corpus fixture (traced circumcentre rides one straight line, both crossings included); unit tests for `collisionStepLimit`, `locateSeparationMinimum` and `SeparationMinimum.isCollision`; a transversal-crossing locus rig pinned by the Thales-circle invariant at four scan densities, with a companion test that the *canonical* scan disagrees; a structural-double-root drag rig; a locus-deferral count on both the completing and the bailing path
- [x] Perf gate re-run **with a locus in the stress construction** — the Phase 116 gate never covered one. `benchmark/tracing_bench.dart` grew a second scenario (the documents' own shape: a chord through the driver, so the sweep meets a transversal crossing twice a turn). PASS on every target: ms/frame static→traced VM 0.89→0.94, AOT 1.52→1.60, js 1.30→1.38, wasm 1.34→1.40 — 12–20% of the 8 ms budget, and traced/static is now ≈1.05× because the locus settles once per pass instead of once per trial
- [x] Locus goldens regenerated (light + dark): visually identical, 10 px of antialiasing from adaptive step placement

## Phase 117c — Field instrumentation for the tracing engine

Opened 2026-08-15: the 117b user reported both documents *still* slow and then wedged in Chrome, with the locus shape now correct. Nothing in the domain layer reproduces it — on the VM `apatitos-topos.rgl` sliding D means 0.5 ms/frame and `locus-miss-2.json` dragging C over a 41×41 grid of positions peaks at 13 ms. So the phase is not a fix for a known defect; it is the instrument that says where the cost is on the reporter's machine. See PLAN §"The engine says what it costs".

- [x] `TraceDiagnostics` (`lib/domain/projective/tracing/`, pure Dart, sink-based so `domain/` stays Flutter-free): per-frame wall time, the locus sweep's share, and counters for trials, detours, folds, separation probes and **chain solves** — the unit a slow frame is actually made of. Frames nest by depth, so entry points can be instrumented without knowing their callers
- [x] Instrumented: both walks (accept/reject/detour), `_measureCollision`/`locateSeparationMinimum` probes, `Locus.recompute` (its own frame when nothing else opened one, so a sweep from a load, a command or an undo is recorded too), `_recomputeAffected` and the sweep's `driveReal`/`_driveComplex`, and both drag sessions' `update` as the frame boundary
- [x] **Stall reports from inside a running frame**: the walks call `checkpoint` from their inner loops; once a frame overruns it prints where it is, every second, until it finishes. The only instrumentation that survives the reported symptom, which is a frame that never returns
- [x] Armed in debug **and profile** builds: on the web those are different compilers (DDC vs optimized dart2js), so comparing the same reproduction across them is what separates a kernel cost from a debug-compiler cost. Disarmed in release
- [x] Surfaced: the trace overlay (⇧O) grew a cost line — ms, locus ms, chain solves; Ctrl/⌘⇧O opens a copyable report (totals, slowest frames, the last 40) and mirrors it to the console
- [x] **Measured waste found and removed**: `locateSeparationMinimum` refined every confirmed collision to the floating-point floor, ~205 chain solves per crossing, on every frame — more than half of `apatitos-topos.rgl`'s 742. The floor is only needed to settle *whether* it is a collision; once a probe is below `doubleRootEpsilon` that is closed and the parameter only has to centre an arc. Relaxed stopping rule → 442 solves/frame, goldens bit-identical
- [x] Tests: `TraceDiagnostics` (nesting, arm/disarm, streaming, stall rate limit, lazy detail, history cap, report); `Construction.nameOf`; two new `locateSeparationMinimum` contracts — a confirmed collision stops early (probe count is the contract), a near-miss still refines to the floor
- [x] **Answered by the reporter's numbers**: `locus-miss-2.json` dragging C in `flutter run -d chrome` is a median **106 ms/frame, worst 178 ms, 100% inside `Locus.recompute`** — ~870 chain solves at **~200 µs each**. The same sweep is 5.6 µs/solve on the VM and **8.3 on dart2js -O4**. It is the debug web compiler, by a factor of ~25; there is no kernel defect behind this report
- [x] `benchmark/locus_docs_bench.dart` + `run_locus_docs.sh`: both reported documents inlined and swept on VM / AOT / dart2js / dart2wasm, so the claim above is reproducible and stays honest as the engine changes
- [x] A debug web build says so once at startup, naming `--profile` — this cost two sessions of hunting a freeze that was not there
- [x] Checked and rejected: a coarse locus preview during drags. 128 → 16 samples only takes 504 → 349 solves (the walk is adaptive; the scan is ~15% of a sweep), so it trades real fidelity for ~30%

## Phase 117d — A locus may lag the pointer

Opened 2026-08-15, straight off 117c's answer. Profile mode fixed the reporter's session and nothing structural: a preview frame still cost 500–900 chain solves with no defence against those solves being slow. See PLAN §"A locus may lag the pointer".

- [x] `LocusRefresh` (`lib/domain/construction/`): a scoped `previewing` flag plus a duty-cycle rule — during a preview a locus re-sweeps only once it has been idle at least as long as its own last sweep took (`maxShare`, default 0.5). No wall-clock constant in the rule, so it is self-tuning across machines, documents and compilers
- [x] Sound because a locus is a DAG leaf: nothing may take one as a parent, so no recompute and no acceptance decision can read a stale sample. Skipping is invisible to the graph
- [x] Both drag sessions scope their preview frame; the gesture's command runs *outside* it, so the committed, undone, redone and saved states are never stale
- [x] Measured on `locus-miss-2.json`: at 60 Hz with a healthy sweep **299/300 frames still sweep** (no behaviour change); with frames arriving as fast as they are served, mean frame cost 2.09 ms → 0.01 ms and the locus coalesces instead of the gesture dying
- [x] Tests: the policy (never-swept, duty cycle, share 1 = old behaviour, clamping, scope nesting and restore-on-throw) and the integration — previews coalesce, the command leaves the locus current and equal to a cold sweep, a cancel restores the start, share 1 is bit-identical to the old path
- [ ] Later, if a document ever needs it: the honest remaining lever is per-solve cost (allocation in the complex kernel), not the sweep's shape. Phase 122

## Phase 118 — Codec v2 + v1 migration

- [x] `constructionFormatVersion = 2` + `minimumConstructionFormatVersion = 1`; v1 decode path kept permanently. v1 needs no *rewriting* — v2 only adds, so the migration is the defaults the new readers fall back to; `branchIndex` documented at the codec as a canonical-order **seed**, not an identity (Phase 116 adoption re-derives it at every traced pass end, and a v1 file was written by a build that had nothing else)
- [x] **The stamp is a requirement, not a build number** (PLAN §"The version field is a requirement…"): `encodeDocument` writes `requiredFormatVersion(document)` — the lowest version that reads the document back *correctly*. A document using nothing from v2 is written byte-identically to a v1 save and still opens in a v1 build; what earns a bump is misreading (a skipped `kernel` block draws the wrong geometry), not novelty (a skipped `rotation` key lands on the default the file meant). CLAUDE.md's invariant amended to match
- [x] v2 hook — **per-file kernel flags** (M-CK): a top-level `kernel` block carrying the fundamental conic, `DocumentKernel` on `DecodedDocument`. `euclidean`/`hyperbolic`/`elliptic` are reserved *names*, not free strings; the two this build cannot honour are **refused, not approximated** (drawing a hyperbolic document in Euclidean geometry is exactly the failure the stamp was bought to prevent). Omitted from the file while default, which is what keeps ordinary documents at v1
- [x] v2 hook — **homogeneous params** (Phase 120): one settled wire shape for a `ProjPoint`, a `ProjLine` or a conic's six entries — `{"h": [[re,im], …]}`, each component a pair even when real, so nothing downstream has to guess whether a bare number was real. The map wrapper is what makes such a param self-identifying to the version rule. `encodeHomogeneousParam` / `homogeneousParam`, `FormatException` on every malformed shape
- [x] Migration corpus (`test/application/persistence/v1_migration_corpus_test.dart`): every document under `test/fixtures/` — five real user files plus `v1/kitchen-sink-v1.json`, a frozen encode of the kitchen sink at the Phase 117 encoder — must be v1, must load with every written object present and wired, and must survive decode → encode → decode with identical geometry object for object. Data-driven, so another user document enrols itself; the version assertion is what stops a v2 file quietly ending the coverage. The kitchen-sink file is pinned against the live builder, not just against itself
- [x] `version > 2` still throws (naming the newest understood); `version < 1` now throws too

## Phase 119 — Conic rendering + hit-testing

- [ ] Painter: classify conic (ellipse / parabola / hyperbola / degenerate line pair); viewport-clipped parametric sampling → `Path` (reuse locus polyline machinery); styled like circles; degenerate conics render as their line pair
- [ ] Hit-tester: conic distance via seeded Newton on the closest-point condition (coarse-sample seed); (priority, distance) contract kept
- [ ] Goldens: each conic class × light/dark; circles render identically to before (regression goldens)
- [ ] Property: distance ≈ 0 on-curve, monotone off-curve

## Phase 120 — Five-point conic: object + tool (payoff demo)

- [ ] `FivePointConic` object (conic-from-five-points from Phase 104)
- [ ] `ConicTool` (`MultiPointTool`, 5 slots) + toolbar row + shortcut + inspector + object-tree label + codec entries — the template checklist for shell additions
- [ ] Intersection tool accepts conics (conic∩line, conic∩conic already total)
- [ ] Tests: tool flow widget test; codec round-trip; painter golden; glados — conic passes through its five parents; degenerate five-point sets give the right degenerate conic

## Phase 121 — Old kernel deletion + convention unification

- [ ] Revisit the detour orientation convention (deferred from 117 → here, user decision 2026-08-14): Phase 115 ships *reversal-identity* (`detourOrientation` odd in the drag direction — there-and-back restores branches), deviating from Cinderella's fixed-time orientation (back-and-forth alternates sides, honest monodromy). Reopens only once branch identity is durably continuation-carried — commit/save/bail are still static touchpoints through 117–120, so the alternation could not survive them yet. Complete loci are unaffected either way — real double-root crossings have no branch point, so the figure-eight closes under both conventions. Switching = make the orientation constant + flip the there-and-back test to expect alternation.
- [ ] Delete `lib/domain/math/intersections.dart`; demote `LineEq`/`CircleEq` to presentation view structs (remove throwing construction paths from domain flows)
- [ ] One degeneracy convention everywhere: projective value total; projection nullable
- [ ] Remove lift-default dead code where every kind now overrides
- [ ] `point_coincidence.dart` re-pointed at projected positions (probe stays sound — it only reads positions)
- [ ] Grep gates recorded in CLAUDE.md; PLAN's migration-contract section replaced by the final architecture description

## Phase 122 — Performance hardening + compile-target finalization

- [ ] Tracing inner loop fully on SoA `Float64List` (no boxed `Complex` in the hot loop)
- [ ] Benchmark suite runnable in CI (informational job)
- [ ] Final dart2js-vs-dart2wasm decision executed (Pages deploy switched if wasm wins, per 101/113 numbers)
- [ ] Drag budget re-measured and recorded as the standing gate
