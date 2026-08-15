# regula2 — V2 Plan: Complex Projective Kernel

## Context

regula2 is the V2 of regula, seeded from the full V1 repo (history preserved; the branch point is tagged `v1-final`, regula commit `7ef44db`). V1's architecture — construction DAG, command-pattern undo, tool state machines, the whole presentation shell — is documented in `docs/archive/PLAN-v1.md` and survives largely intact; **this document describes only what changes and why.**

The driver is the assessment in `docs/V2-assessment.md`: Cinderella-class behaviour — no jumping intersection points under drags, complete loci — is not a set of features but the consequence of one representational choice. **The kernel computes in homogeneous coordinates over ℂ, and drags are resolved by analytic continuation along a path that detours through complex space around degeneracies.** No orientation heuristic patched onto an affine kernel can deliver this (there's a proof); V1's `locus.dart` (704 lines of hand-rolled boundary bisection, branch flipping, and infinity tails) and its `branchIndex` clamping are what approximating it numerically costs. Under a projective complex kernel:

- line ∩ line is **always** exactly one point (possibly at infinity) — a cross product,
- line ∩ conic is **always** exactly two points (possibly complex, possibly coincident),
- conic ∩ conic is **always** four — via the pencil `λA + μB`,
- `isDefined` stops being a graph property and becomes a *rendering* question: "is this point real and finite?",
- circles become conics through the circular points I=(1,i,0), J=(1,−i,0), which also unlocks Cayley–Klein non-Euclidean geometries nearly free.

Beyond the kernel, the V2 scope (in payoff-per-risk order) is: tracing/continuation engine, port of the ~39 object kinds and ~42 tools, a JGEX-style deductive-database prover with visually replayed proofs, and — last — 3D. The kernel track is planned phase-by-phase in `docs/TODO.md` (Phases 100–122); prover and 3D are milestone outlines below, opened as numbered phases when their time comes.

Mathematics sources: Richter-Gebert & Kortenkamp's published papers and *Perspectives on Projective Geometry* (Cinderella itself is proprietary — take the math, never code); Chou–Gao–Zhang for the deductive database and area methods; JGEX (open Java), AlphaGeometry DDAR / Newclid (open Python) for rule sets.

## Migration strategy: projective-canonical, affine-as-view

The kernel boundary in V1 is narrow (`vec2.dart` + `line_eq.dart` + `circle_eq.dart` + `intersections.dart`, ~380 lines) but its conventions are wide: 39 object kinds consume nullable affine views (`GeoPoint.position`, `GeoLine.line`, `GeoCircle.circle`), the painter/hit-tester/codec/tools consume the same views, `IntersectionPoint.branchIndex` and the locus walker depend on the deterministic branch orderings documented in `intersections.dart`, and 33k lines of tests encode all of it. A big-bang rewrite means weeks of red; instead:

1. **The new kernel lives beside the old one** in `lib/domain/projective/` — `Complex`, `ProjPoint`, `ProjLine`, `ConicMatrix`, total intersection functions, and later the tracing engine. `lib/domain/math/` is untouched until Phase 121.
2. **The bridge lives in the abstract kind layer** (`geo_object.dart`): `GeoPoint.projPoint` / `GeoLine.projLine` / `GeoCircle.conic` nullable getters with **lift-from-affine defaults** (`[x,y,1]`, `[a,b,c]`, circle→conic). A *migrated* concrete class stores homogeneous state, overrides the projective getter, and reimplements the affine getter as a projection — `isDefined` keeps its signature but its meaning becomes "real and finite after projection", the rendering question. An *unmigrated* class keeps its old affine `recompute()` verbatim and reads affine views of parents (which may already be migrated). Standing rule from Phase 106 on: **new domain code reads the projective accessors only** (`projPoint` / `projLine` / `conic`); the affine getters exist for the painter, hit-tester, codec, and unmigrated `recompute()` bodies. Any object can migrate in any order with zero broken intermediate states: a migrated child reading an unmigrated parent gets a lifted real finite value (correct — the old kernel can't produce anything else), and an unmigrated child reading a migrated parent goes undefined exactly when the projection is null, matching its old semantics.
3. **Painter, hit-tester, codec, and tools keep consuming affine views throughout the migration.** `Vec2` survives permanently as the rendering/UI coordinate type; `LineEq`/`CircleEq` end up demoted to presentation view structs.
4. **Branch ordering is preserved statically, then deliberately broken dynamically.** The new intersection functions return roots in a canonical order defined to agree with the old ordering on real transverse cases (line∩conic by parameter along the line; circle∩circle real roots by sign against the directed center line; the circular points I, J filtered out of `branchIndex` addressing) — so the branch-ordering tests stay green and saved files stay meaningful. Once tracing lands (Phase 116), branch identity *during a drag* is held by continuation (root matching), not per-frame re-sorting; tests that encode jump behaviour are updated then, with explicit STATUS notes — those jumps are the bug V2 exists to fix. On save, `branchIndex` is re-derived as the canonical-order index of the tracked root.
5. **Migration order is roots-upward by mathematical family:** incidence core → transforms-as-projective-maps → circles-as-conics → intersection/tangency → parameterized objects → consumers. Each batch is a phase; each phase ends analyze-clean, suite-green, app-runnable.

Rejected alternatives: an affine-canonical bridge (projective computed lazily from affine) can't hold continuation state or complex values; a parallel `objects2/` fork doubles the shell's dispatch surface and abandons the tests-as-spec property.

### Two decisions pinned early (see docs/V2-assessment.md "Flutter/Dart-specific difficulty")

- **Numeric throughput / compile target (Phase 101).** Dart has no complex type; every boxed complex op allocates, and tracing runs thousands of steps × dozens of objects per drag frame. The tracing inner loop is planned on `Float64List` struct-of-arrays from the start, and dart2js vs dart2wasm is benchmarked before any kernel code depends on the answer.
- **Web threading (before any prover code, M-P0).** No isolates on web. The prover engine is written as a resumable state machine with an explicit work queue from day one — cooperatively chunked on web, `Isolate.run`-wrapped on native, Worker-portable later. A straight-line fixpoint loop cannot be retrofitted.

### Parameterization (pinned in Phase 111)

**Carrier parameters stay real, read in the affine chart.** A constrained point's parameter (`PointOnObject.parameter`, arc/sector angular extents, segment/ray parameter extents, locus sweep variables) remains a real number against the carrier's *projected* affine view: signed arc-length along the oriented direction for lines (the `orientedAlong` anchor keeps direction V1-compatible), polar angle for circles. The parameter is a UI and persistence quantity — it is what a drag gesture sets, what the codec stores, and what extent clamping compares — so it must be real, invariant under rescaling of the carrier's homogeneous state, and meaningful to the user. Complexification happens on the *value* path only: tracing (Phase 113+) continues the constrained point's homogeneous coordinates along the drag path; it never continues a carrier parameter. When the carrier's projection is undefined (complex or fully at infinity), the constrained point has no chart to evaluate in and goes undefined with it.

- **Lines**: signed arc-length from `pointOnLine` along `direction` — unchanged. Bounded hosts (segments, rays, arcs, sectors) clamp into their extents on every recompute; gluing a point to the drawn extent is a UI concept on the rendered curve, not projective structure.
- **Circles**: polar angle — unchanged.
- **General real conics** (needed by Phase 119 rendering and Phase 120 five-point conics): stereographic parameterization — project from a chosen real point on the conic; rational in t, so evaluation is polynomial in homogeneous coordinates. Ellipses close up (t ∈ ℝ ∪ {∞}, one glue point), parabolas touch infinity once, hyperbolas twice.
- **Hyperbola at infinity**: no gluing through the asymptotic parameter values — each branch is a clamped real extent, like a segment. The UI never walks a parameter across infinity.

Rejected: projective parameters (RP¹ homogeneous pairs) or complex parameters. They make extent clamping, drag-to-parameter mapping, and persistence ambiguous for no payoff — analytic continuation operates on object values along the drag path, not on carrier parameters. (Clarified in Phase 116b: a traced *parameter drag* interpolates the real stored parameter, and a detour evaluates the dragged point's chart form at a complex path parameter strictly inside one pass — the value-path continuation above, never a complex parameter type: the stored parameter, clamping and persistence stay real throughout.)

### Locus on tracing (pinned in Phase 117)

`Locus.recompute` stays a sweep-and-restore over the fixed [chain], but the per-sample machinery of Phases 39b–f (uniform grid walked statically, defined↔undefined boundary bisection, `branchIndex` flipping, infinity tails) is replaced by the tracing engine. The design:

- **Sweep domain.** One real sweep parameter `u` per host: circle hosts sweep the angle (full turn cyclic, or the `angularExtent` bounded); segment hosts sweep the `parameterExtent`; a ray sweeps `φ ∈ [0, π/2]` with `t = origin + halfSpan·tan φ`; a full line sweeps `φ ∈ [−π/2, π/2]` with `t = center + halfSpan·tan φ`, **cyclically** — the domain is RP¹, `tan` is π-periodic, and a run may wrap through the driver's point at infinity (the Cinderella projective-driver semantics; before 117 the two grid edges were separate open ends). The tan substitution is the density profile the old grids encoded; the grids themselves are gone.
- **Drive.** The sweep drives the driver's homogeneous value directly (the `tracedPosition` mutation, now sanctioned for locus sweeps): interior real `u` lifts the chart evaluation with `w` exactly 1 (bitwise-identical to the static sweep); the bitwise domain edge of a ray/line host evaluates to the carrier's direction point (`w = 0`) — a fully projective chain takes its genuine value at driver-infinity, a chart-reading chain member goes undefined there, both honest ("infinity falls out of projection"; the tails' subpixel ladder is deleted). Complex `u` (detour arcs only) mirrors the chart ops over `Complex`, per the 116b convention. The stored `parameter` is untouched and restored bit-exactly with one chain recompute at the end.
- **Structure discovery.** A `sampleCount`-cell static scan (slots inactive — canonical branches, the old uniform sweep) still finds the defined runs, grouped cyclically on circle and full-line hosts. Each run is then *walked* by the tracing engine: chain `IntersectionPoint`s seeded from the run's start state, the shared acceptance rule (motion < min(sep/2, cap), collision refusal, coast-entry refusal), trial spans capped at one scan cell so polyline density never falls below the scan's.
- **Singularities met by the walk.** On starvation the singular `u*` is estimated (collapse law) and classified by a static probe past it: still defined → a **crossing** — a `DetourArc` in complex `u` continues the branch through it (the old machinery re-sorted canonically here and drew a kink; the traced curve is the fix the corpus goldens get regenerated for); undefined → a **fold** — the real curve turns: the walk Zenos in (its accepted steps are the old boundary ladder, stopped by the acceptance rule exactly at the kernel's epsilon-tangent zone, which fences the Phase 39d phantom), swaps each starving slot to its other candidate (the real-curve continuation through the coalescence — no complex machinery needed, and `branchIndex` is never touched), reverses direction, and continues.
- **Termination keeps the Phase 39c contract verbatim**: a parity set tracks outstanding fold swaps; a walk that returns to the original assignment *and* geometrically rejoins its start closes (figure-eights, tangency-bounded circles); any open termination — a genuine end reached while swapped, budget/segment caps — trims back to the last original-assignment sample. Never wrong ink.
- **What this deletes** from `locus.dart`: `_refineBoundary` (48-step bisection + ladder), `_infinityTail`, the tan sample grids, all `branchIndex` mutation and its restore bookkeeping. What it keeps: chain computation, cyclic run grouping, the trim rule, `coreSamples` (defined recorded positions inside the focus window).

Consequences the corpus tests are updated for (point-set-wise comparisons per the phase contract): interior crossings trace smoothly instead of kinking; full-line loci may connect through the driver's infinity (fewer components, limits touched exactly or asymptotically to ~1e-5 of the domain via coast-entry refinement); sample lists are adaptive, not grid-aligned (they already weren't after 39b).

### Root collisions: seen, measured, walked around (pinned in Phase 117b)

Two user documents (`apatitos-topos.rgl`, `locus-miss-2.json`) exposed three gaps in the 114–117 engine. All three are properties of *how a collision is detected and crossed*, not of the geometry, so they are pinned here rather than left as engine folklore.

- **A collision must never hide inside an accepted step.** The Cinderella bound compares a root's motion against the separation at the step's *start*, so it only ever sees a step's endpoints. Where two roots pass through each other **transversally** — separation vanishing *linearly*, the signature of a line drawn through a point that already lies on the curve being intersected (the "second intersection of `CD` with the circle `D` is on" — the commonest construction in the corpus) — the separation can dip to zero and recover inside one step while both endpoints stay comfortably separated and every root moves only a little. Nothing starves, no fold or crossing is classified, and nearest matching quietly keeps the *canonical index* rather than the analytic branch. The step is therefore capped by the extrapolated distance to the next collision (`collisionStepLimit`), which forces every collision to a step *end*, where refinement localizes it. The cap is self-scaling — a separation that is large, or shrinking slowly, extrapolates far ahead and throttles nothing.
- **The collision's parameter is measured, not extrapolated.** `estimateSingularParameter` fits the `s ∝ √(t*−t)` law of a transverse tangency, where it is exact and its near-miss *undershoot* is load-bearing (an undershot arc stays homotopic to the real path). On the linear law it undershoots by a factor that refinement does not improve, so the planned arc hugs the collision instead of clearing it — the detour then exits *nearer* the singularity than it entered and picks the wrong sheet on the way out. So when a detour is about to be planned, the walk brackets and ternary-searches the separation profile directly (`locateSeparationMinimum`): law-agnostic, a bounded handful of evaluations once per singularity. Its *depth relative to its shoulders* is also the crossing/near-miss discriminator the extrapolation cannot provide — a genuine zero bottoms out at solver noise, a miss keeps a finite fraction — so a miss falls back to the extrapolated estimate and its guarantee unchanged.
- **A detour arc must actually leave the real axis.** An arc's two endpoints are its real entry and exit, so a walk that accepts the whole semicircle in one trial has continued from one real parameter straight to the other — exactly the step across the collision the detour exists to prevent, and the acceptance rule cannot tell the difference (near a collision, both roots move little). Arc steps are capped at `π/4`, four minimum.

Two further rules follow from the same documents, about work the engine should not be doing:

- **Structural double roots never seed.** A point built as `TangentLine ∩ the circle it touches` has its two candidates coincident *by construction*, at every position of every parent. There is no second branch to hold identity against and no step size could separate the matches, so seeding it made the Cinderella bound refuse every trial: the controller halved to nothing and the whole pass starved and bailed — on every frame of every drag in the document. Slots whose candidates coincide within `doubleRootEpsilon` at seed time are left to resolve canonically (exact, when the candidates coincide) and the pass's other slots keep tracing.
- **Loci are held back during a tracing pass.** A locus is a DAG leaf — nothing may take one as a parent — so no acceptance decision can read one, while recomputing one is a whole traced sweep of its own. The walk recomputes the rest of the graph per trial and settles the loci once, at whatever state the pass ends on. This is what made the starving frames above *freeze* rather than merely stutter: a bailing frame paid `stepBudget` (~130) full locus sweeps before giving up. The Phase 116 performance gate never covered a construction carrying a locus; it should.

### The engine says what it costs (pinned in Phase 117c)

Both 117b documents came back still slow, and nothing in the domain layer reproduced it: on the VM every frame of both is well under a millisecond. That is the actual finding — not "it is fixed", but "the cost is not where we can see it", and an engine that cannot be asked what a frame cost cannot answer that question from a user's machine.

- **Frames are recorded, and a slow one reports itself.** `TraceDiagnostics` (pure Dart, armed in debug *and profile* builds) records per drag frame: wall time, the locus sweep's share of it, and counts of accepted/rejected trials, detours, folds, separation probes and — the unit that actually matters — **chain solves**, one recompute of the affected subgraph. Trials are not the currency: on `apatitos-topos.rgl` a frame ran 200 walk trials and **742 chain solves**, because a starving step that measures a collision spends probes nobody was counting.
- **A stall reports from inside itself.** A frame that never returns never ends, so the walks call `TraceDiagnostics.checkpoint` from their inner loops: once a frame overruns, it prints where it is and how far along, every second, until it finishes. This is the only instrumentation that survives the symptom being reported — a wedged tab.
- **Debug web is a different compiler, not a flag.** `flutter run -d chrome` is DDC; profile and release are optimized dart2js, which the perf gate measures at ~1.5× the VM. So "is this the kernel or the debug compiler?" is settled by running the same reproduction in both and diffing these numbers — which is why the recorder is armed in profile too.
- **Refine to the question being asked, not to the floating-point floor.** `locateSeparationMinimum` drove its ternary search to 1e-15 so that a *tight near-miss* could not be misread as a collision. But that precision is only needed to settle the **verdict**; once a probe has been below `doubleRootEpsilon` the verdict is closed for good and all the parameter is still for is centring an arc whose radius is a fraction of the same distance. Relaxing the stopping rule at that moment (`_collisionResolution`, 1e-4 relative) took a crossing from ~205 probes to ~35 and the document's frame from 742 chain solves to 442, with the goldens bit-identical. A near-miss still pays the floor, because that is the case the floor was bought for.

## Kernel track (Phases 100–122)

Full checklists live in `docs/TODO.md`. The arc, with the three de-risking spikes marked:

| Phases | Arc |
|---|---|
| 100 | Seed repo, docs reset (this bootstrap) |
| 101–102 | **SPIKE 1** `Complex` + js/wasm/SoA benchmark · **SPIKE 2** conic∩conic pencil stability prototype |
| 103–105 | `ProjPoint`/`ProjLine` (join/meet) · `ConicMatrix` + circular points + line∩conic · conic∩conic production |
| 106 | Bridge layer in the abstract kinds (zero behaviour change) |
| 107–112 | Object migration batches: incidence core → transforms → circles-as-conics → intersection/tangency → `PointOnObject`/parameterization → consumers |
| 113–116 | **SPIKE 3** tracing scaffolding · adaptive steps + root matching · degeneracy detection + complex detour · integration + performance gate (≤ 8 ms kernel time per drag frame on a 100-object stress construction) |
| 117 | Locus rewrite on tracing (the 704-line special-case machine dissolves) |
| 118 | Codec v2 + permanent v1 loader |
| 119–120 | Conic rendering + hit-testing · five-point conic object + tool (the payoff demo) |
| 121–122 | Old kernel deletion + degeneracy-convention unification · performance hardening + compile-target finalization |

## Milestone outlines

Opened as numbered phases when started; each then gets its own PLAN section. Key decisions are recorded now so they don't get re-litigated.

### M-CK — Cayley–Klein non-Euclidean geometries (optional; unlocked after Phase 121)

The fundamental conic becomes a per-construction setting: Euclidean = the degenerate conic {I, J}; hyperbolic = unit circle (Beltrami–Klein); elliptic = imaginary unit conic. *Measurement* is where geometry lives — distance and angle become cross-ratio logarithms against the fundamental conic, so measurements and angle objects switch on the ambient setting while incidence objects need **zero changes** (the payoff of Phases 103–110). Perpendicularity = conjugacy w.r.t. the fundamental conic — Phase 107's I,J formulation generalizes verbatim. UI is a construction-level mode with disc-boundary rendering for hyperbolic; persisted via the Phase 118 codec hook. Scope guard: no Poincaré model-switching in v1 of this milestone.

### M-P — Deductive-database prover

Independent of the kernel track; can start any time after Phase 112 (it consumes projected positions only).

- **M-P0 — threading decision.** Benchmark cooperative chunking (yield between fixpoint rounds) vs a Web Worker on dart2js/dart2wasm, reusing the Phase 101 harness; `Isolate.run` on native either way. The engine is a resumable state machine regardless (see pinned decisions above).
- **M-P1 — predicates + numeric filter.** Predicates `coll / para / perp / cong / cyclic / eqangle / eqratio / midp / simtri / contri` with numeric evaluators over the diagram's projected positions. Generalize `point_coincidence.dart`'s perturbation probe (V1 already built Cinderella's randomized theorem test) from "same position" to "predicate survives perturbation" — the model filter that keeps forward chaining tractable: never attempt a deduction that isn't numerically true.
- **M-P2 — forward chaining.** Fact database keyed by canonical predicate forms (eqangle/eqratio canonicalization is the fiddly part — take Newclid's canonical forms); ~20-rule DD core from the open DDAR/Newclid sources (rules, not code); fixpoint to quiescence; every derived fact records (rule, premises) so the proof DAG is free. **Wu's method and Gröbner bases are skipped permanently** — unreadable proofs, exact rational arithmetic over `BigInt`, bad effort/reward.
- **M-P3 — full-angle engine.** Second engine for angle-chase problems, a peer behind one `Prover` facade, same fact DB and numeric filter.
- **M-P4 — proof replay UI.** The product: a proof panel (step list) with on-figure animated highlighting per step, reusing painter selection styling and the label system. Point-merge UX says "these coincide by Varignon's theorem" with a *Show why* replay instead of silently merging. The numeric probe stays the always-on cheap path; DD certifies and explains on demand.
- **M-P5 — area method (optional).** Third engine, readable proofs; only if M-P2/3 leave explanatory gaps.

### M-3D (last)

- **M-3D0 — decision record, written before any code.** Taxonomy bounded hard: point / line / plane / sphere / circle-as-plane∩sphere / conic-in-a-plane / polyhedra; **general quadric∩quadric excluded permanently** (a quartic space curve — a phase of effort for almost no user value). 2D remains the default *mode*: locked camera, plane-constrained construction, zero tax on the existing one-tap tool UX. Rendering is wireframe `CustomPainter` with painter's-algorithm depth sorting and depth cueing — no `flutter_gpu`/`flutter_scene`. Tracing is *not* generalized to 3D initially; the bounded taxonomy keeps static intersections simple.
- **M-3D1 — camera.** 4×4 camera; alt-scroll orbit, ctrl-alt-scroll z-dolly — an extension of the existing viewport rotation (V1 Phase 43). Camera lives in presentation; domain stays frame-free.
- **M-3D2 — 3D kernel types + workplane model.** `ProjPoint3`/`Plane`/`Sphere` (real-first; complexify only where a total-intersection payoff exists), reusing `Complex` and the SoA patterns; `Workplane` as a construction-level current-plane object. 3D objects are new `Geo*3` kinds beside the 2D ones, dispatched by the same painter/hit-tester switches.
- **M-3D3 — placement UX.** A 2D click doesn't determine a 3D point: click = ray cast → snap to existing object → else land on the current workplane; a modifier lifts off-plane (maps onto ctrl-alt-scroll raise/lower). Extends the `point_resolution.dart` ladder — ray-snap slots in where snap-to-intersection sits today.
- **M-3D4 — taxonomy objects + tools + codec v3.** Conic-in-plane reuses `ConicMatrix` in plane coordinates — the 2D kernel is the 3D kernel's chart.
- **M-3D5 — depth-aware presentation.** Depth-sorted painting; hit-testing gains depth as the tiebreaker after (priority, distance); goldens per camera preset.

## Risks & de-risking

Three spikes are scheduled first in their tracks, each killing the biggest unknown before architecture hardens on it:

1. **Phase 101** — complex-arithmetic throughput and compile target. Risk: allocation kills drag frames on dart2js. Killed by benchmarking boxed vs SoA on VM/js/wasm up front.
2. **Phase 102** — conic∩conic numerical stability in doubles. Risk: the pencil/cubic/degenerate-split route is numerically treacherous. Killed by prototyping against ground truth (V1 `intersectCircleCircle`, conics through constructed points) and recording the normalization / root-choice / polishing recipe before Phase 105 productionizes it.
3. **Phase 113** — continuation robustness. Risk: the tracing long tail (root-matching failures, step starvation) — the assessment's "hardest per line, budget generously". Contained by proving the skeleton on toys behind a feature flag with a graceful static-solve bail that ships in every phase, so tracing hardens incrementally (114–116) without the app ever depending on an unfinished engine.

Standing risks: test-suite coupling to old branch orderings (mitigated by the canonical-order compatibility rule; dynamic-behaviour breaks quarantined to Phases 116–117 with STATUS notes); parameterization at infinity (pinned — see §Parameterization: parameters stay real in the affine chart; stereographic parameterization for general conics; hyperbola branches as clamped extents); scope creep from CK/prover/3D (milestone-gated; never started mid-kernel-track).

## Reuse contract — what does NOT change

Future sessions must not churn these; they are the V2 dividend (see `docs/archive/PLAN-v1.md` for their design):

- **`construction.dart`** — insertion-order-is-topological-order, dependents map, recompute pass, single notification. Verbatim; gains only `recomputeAlongPath` (Phase 113).
- **Command hierarchy + `command_stack.dart`** — undo/redo is representation-agnostic. Verbatim.
- **Tool architecture** — tools never mutate; sealed `ToolResult` emitting `Command`s; `MultiPointTool` collect→commit; `drag_session.dart` as the sanctioned preview exception; the `point_resolution.dart` ladder's priority order.
- **Presentation shell** — toolbar, attributes inspector, object tree, shortcut system (85 actions / 91 bindings / cheat sheet), the `AppAction` switch in `main.dart`, theme, export, file IO, label layout/declutter, grid. Extended with new arms per new kind; never restructured.
- **Painter / hit-tester contracts** — per-kind switch on the abstract kinds; (priority, distance) lexicographic hit ordering. They gain conic arms; the contracts stand.
- **Codec shape** — insertion-ordered `{version, viewport, flags, objects:[{id, type, parents, params, attributes}]}`; version bumps are additive with permanent old-version loaders.
- **Docs & process** — PLAN/STATUS/TODO/archive rotation, CLAUDE.md session protocol, branch-per-phase, analyze-clean + tests-green definition of done, goldens tag-excluded in CI.
- **`Vec2`** — permanent as the rendering/UI coordinate type; `LineEq`/`CircleEq` become presentation view structs after Phase 121.

## Deferred decisions

- **Package / app rename.** `pubspec.yaml` name stays `regula` (174 files import `package:regula/…`); renaming to `regula2` plus Android/iOS bundle-id changes is a mechanical later change, to be done in one dedicated commit if/when the app ships under a new identity.
- **GitHub remote / CI / Pages.** The repo currently has no remote. `.github/workflows/` came along from V1 and will work as-is when a remote is added; the Pages deploy target may switch to wasm per the Phase 101/122 benchmarks.
