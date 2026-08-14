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

- [ ] Generalize the tracing walk over an abstract drive: extract `recomputeAlongPath`'s controller (acceptance, collision refusal, detour) into a shared core; add `Construction.recomputeAlongParameterPath(id, from, to)` lerping a `PointOnObject.parameter` (real steps re-enter `recompute`, so host extent clamping behaves exactly as static; a clamped stretch cannot starve — position is constant there)
- [ ] Complex parameter evaluation for detours: `Complex.cos`/`sin` (hyperbolic identities, bitwise-real on the real axis), `PointOnObject.tracedPosition` (pass-internal, mirroring `FreePoint`'s), carrier chart forms continued holomorphically (line: affine in p; circle: cos/sin of complex angle); 1D odd detour orientation (`detourOrientation1D`)
- [ ] `_SlideDragSession` traces by default (same flag, static bail, per-frame identity chaining, branch adoption); `SetPointOnObjectParameterCommand` carries `branchChanges` like the move command
- [ ] Tests: Cinderella rig (slide C across D — no swap at any step, coast through exact coincidence, adoption + static reproduction, commit/undo/redo, codec round-trip); tangency slide detours and crosses; there-and-back identity on a parameter drive; complex trig units

## Phase 117 — Locus rewrite on tracing

- [ ] Revisit the detour orientation convention (decision deferred here, 2026-08-14): Phase 115 ships *reversal-identity* (`detourOrientation` odd in the drag direction — there-and-back restores branches), deviating from Cinderella's fixed-time orientation (back-and-forth alternates sides, honest monodromy). Chosen because the hybrid static/traced architecture erases monodromy state at every static touchpoint (commit/save/bail); once branch identity is durably continuation-carried (116/117), the alternation would survive and the choice reopens. Complete loci are unaffected either way — real double-root crossings have no branch point, so the figure-eight closes under both conventions. Switching = make the orientation constant + flip the there-and-back test to expect alternation.
- [ ] New `Locus.recompute`: adaptive sweep of the driver parameter via the tracing engine; keep density adaptation + polyline rendering
- [ ] Delete: tan-grid ray sampling, defined/undefined boundary bisection, branchIndex flipping, infinity tails (infinity now falls out of projection)
- [ ] Existing locus corpus is the spec: closed loci stay closed; figure-eights and conic loci compared point-set-wise with tolerance
- [ ] Goldens regenerated where the (better) curve differs; diffs reviewed in STATUS

## Phase 118 — Codec v2 + v1 migration

- [ ] `constructionFormatVersion = 2`; v1 decode path kept permanently (`branchIndex` documented as canonical-order seed)
- [ ] v2 hooks: homogeneous params (needed by five-point conic), per-file kernel flags (needed by M-CK)
- [ ] Migration corpus: directory of real v1 `.rgl` fixtures that must load and round-trip; kitchen-sink v1 file loads into identical geometry
- [ ] `version > 2` still throws

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
