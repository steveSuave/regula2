# Build TODO — V2 kernel track

Live checklist for the V2 phases described in `docs/PLAN.md`. Tick items as they land on `main` with `flutter analyze` clean and `flutter test` green.

Definition of done for each phase: code merged, tests passing, app runnable (chrome + one native target), `docs/TODO.md` updated, `docs/STATUS.md` entry written.

Rotation: this file holds open phases plus the most recent couple of completed ones. Fully-completed phase checklists move to `docs/archive/TODO-completed-phases.md`. V1's final checklist state is archived at `docs/archive/TODO-v1-final.md`.

Phase numbering starts at 100 to mark the V2 era (V1 ended at Phase 73). Prover (M-P) and 3D (M-3D) milestones get numbered phases when opened — see their outlines in `docs/PLAN.md`.

## Carried over from V1 (environment, not code)

- [ ] Android emulator smoke — needs an AVD + system image (`sdkmanager` download to approve)
- [ ] iOS simulator smoke + `flutter build ios` — blocked on complete Xcode install + CocoaPods
- [ ] Stretch from V1 Phase 19: hand-written SVG export (may slip forever)

## Phase 114 — Tracing II: adaptive step control + root matching

- [x] Step controller (Cinderella rule): accept a step only if every root moved less than half its minimum pairwise separation at the previous step; else halve — plus an absolute per-step motion cap (0.25 chordal) the glados suite proved necessary: sep/2 alone is unsound on RP¹ (a wide step can swap branches *through the point at infinity* with motions just under the bound)
- [x] Nearest-neighbour root matching with collision refusal (married-seed and coincident-double-root exemptions); per-pass step budget (`stepBudget`, default 128; `TracingFlags.dragStepBudget`) with graceful bail to static solve — exhaustion throws `TraceStepBudgetException`, the drag session bails; `recomputeAlongPath` returns accepted/rejected counts as the Phase 116 debug-overlay feed (the overlay itself is 116's item)
- [x] Glados: random constructions × random smooth drags → no branch swaps; endpoint = static solve modulo matching; bounded step counts; adversarial near-tangency paths force halving and still match

## Phase 115 — Tracing III: degeneracy detection + complex detour

- [x] Singularity detection: starvation trigger (trial step under `detourTriggerStep` *and* tightest separation under `detourTriggerSeparation`), singular parameter extrapolated from the last two accepted steps' separations via the collapse law s = C·√(t*−t) (`estimateSingularParameter` — provably *undershoots* on near-misses, the bias that keeps detours homotopic to the real path)
- [x] Path deformation: semicircular `DetourArc` in complex `t` (safety-margined radius, shrink-to-fit with strict enclosure, bitwise-real exit), walked by the identical acceptance machinery with arc-scoped complex carriers (`TracedBranch.allowComplexCarriers` → `intersectionCandidates(complexCarriers:)`, realness gates only — the kernel is holomorphic throughout); orientation recorded as `detourOrientation`'s *odd* drag-direction rule — a fixed absolute half-plane provably swaps conjugates on a there-and-back drag (one net winding; the probe caught it), oddness makes it a bitwise identity
- [x] Canonical tests: line through tangency crosses with no jump, no swap, deterministic sides, endpoint = static solve; there-and-back identity; chord *and* perpendicular bisector of the conjugate pair stay real, defined lines across the crossing; near-misses trace through on the real axis (no detour) or starve cleanly — never a silent swap; singular endpoint starves and bails (no valid arc)
- [x] Property: detoured endpoint = real-path endpoint when no singularity is enclosed — a co-traced transverse pair rides another pair's detour to exactly its real-path endpoint, no swap at any observed step

## Phase 116 — Tracing integration: default drag resolution + perf gate

- [ ] `drag_session.dart` drives `recomputeAlongPath` by default; branch identity held by `TracedBranch` between recomputes
- [ ] Save re-derives `branchIndex` from canonical order; jump-behaviour tests updated (documented spec change, STATUS notes)
- [ ] Debug overlay showing step counts
- [ ] **Performance gate** (standing from here on): ≤ 8 ms kernel time per drag frame on a 100-object stress construction (VM); js/wasm numbers recorded

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
