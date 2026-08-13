# Build TODO — V2 kernel track

Live checklist for the V2 phases described in `docs/PLAN.md`. Tick items as they land on `main` with `flutter analyze` clean and `flutter test` green.

Definition of done for each phase: code merged, tests passing, app runnable (chrome + one native target), `docs/TODO.md` updated, `docs/STATUS.md` entry written.

Rotation: this file holds open phases plus the most recent couple of completed ones. Fully-completed phase checklists move to `docs/archive/TODO-completed-phases.md`. V1's final checklist state is archived at `docs/archive/TODO-v1-final.md`.

Phase numbering starts at 100 to mark the V2 era (V1 ended at Phase 73). Prover (M-P) and 3D (M-3D) milestones get numbered phases when opened — see their outlines in `docs/PLAN.md`.

## Carried over from V1 (environment, not code)

- [ ] Android emulator smoke — needs an AVD + system image (`sdkmanager` download to approve)
- [ ] iOS simulator smoke + `flutter build ios` — blocked on complete Xcode install + CocoaPods
- [ ] Stretch from V1 Phase 19: hand-written SVG export (may slip forever)

## Phase 110 — `IntersectionPoint` v2 + tangency family

- [x] `IntersectionPoint`: candidates always 2 or 4; `branchIndex` indexes canonical order with I/J filtered; `candidateCount` = real-candidate count (locus walker contract until 117)
- [x] Migrate: `TangentLine` (polar-based, always 2), `PolarLine`, `RadicalAxisLine` (line through the two non-I/J common points — now a one-liner via `radicalAxisOf`), `AngleBisectorLine`, `TwoLineBisectorLine` (old ordering guarantee kept, anchored to affine orientations)
- [x] `point_resolution.dart` snap-to-intersection re-pointed at real candidates
- [x] All existing branch-ordering tests stay green; glados: intersection points incident to both parents always (in ℂ); tangency = double root

## Phase 111 — `PointOnObject` + parameterization on projective carriers

- [x] Decision recorded in PLAN: parameters stay real in the affine chart (arc-length on real lines, angle on real circles — gluing is a UI concept on the rendered curve); general real conics via stereographic parameterization; hyperbola-at-infinity as clamped extents
- [x] Migrate: `PointOnObject` (stores the lifted chart evaluation; chart-less carriers → undefined). The other two items on this line were already done when the phase opened: `Arc`/`Sector` extents stayed affine metadata in Phase 109, `TriangleCenterPoint` migrated in Phase 107
- [x] Glados: `pointAt(parameterAt(p))` projections stable; glued point stays on carrier under parent perturbation

## Phase 112 — Object batch 4: consumers

- [ ] Migrate: `VertexAngle`, `LineAngle`, `Polygon`, `DistanceMeasurement`, `LengthMeasurement`, `AreaMeasurement`, `SlopeMeasurement` (slope through infinity renders "—"), `ExpressionText`
- [ ] `Locus` deliberately untouched (rewritten in 117)
- [ ] Grep gate: no object file imports `intersections.dart` except `locus.dart`; every concrete kind except `Locus` reads projective accessors

## Phase 113 — SPIKE 3 / Tracing I: scaffolding

- [ ] `lib/domain/projective/tracing/`: `DragPath` (real `t∈[0,1]`, complexifiable), `TracedBranch` slots on intersection-bearing objects, `Construction.recomputeAlongPath` (fixed-step naive), SoA `Float64List` buffers per the Phase 101 decision
- [ ] Feature flag so `drag_session.dart` can opt in; static-solve bail always available
- [ ] Toy-harness tests: line dragged across a circle with fixed steps → continuous root histories; endpoint agrees with static solve up to branch labels
- [ ] STATUS records whether SoA meets the frame-budget estimate on js/wasm (feeds 122)

## Phase 114 — Tracing II: adaptive step control + root matching

- [ ] Step controller (Cinderella rule): accept a step only if every root moved less than half its minimum pairwise separation at the previous step; else halve
- [ ] Nearest-neighbour root matching with collision refusal; per-drag step budget with graceful bail to static solve (flagged in debug overlay)
- [ ] Glados: random constructions × random smooth drags → no branch swaps; endpoint = static solve modulo matching; bounded step counts; adversarial near-tangency paths force halving and still match

## Phase 115 — Tracing III: degeneracy detection + complex detour

- [ ] Singularity detection: root separation under tolerance / step-controller starvation
- [ ] Path deformation: semicircular detour in complex `t` around the singular parameter; fixed detour orientation recorded (determinism)
- [ ] Canonical tests: drag a line through tangency with a circle → intersection points go complex and return with no jump, no swap; bisector continuity across degenerate crossings
- [ ] Property: detoured endpoint = real-path endpoint when no singularity is enclosed

## Phase 116 — Tracing integration: default drag resolution + perf gate

- [ ] `drag_session.dart` drives `recomputeAlongPath` by default; branch identity held by `TracedBranch` between recomputes
- [ ] Save re-derives `branchIndex` from canonical order; jump-behaviour tests updated (documented spec change, STATUS notes)
- [ ] Debug overlay showing step counts
- [ ] **Performance gate** (standing from here on): ≤ 8 ms kernel time per drag frame on a 100-object stress construction (VM); js/wasm numbers recorded

## Phase 117 — Locus rewrite on tracing

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
