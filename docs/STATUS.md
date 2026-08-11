# Status Log

Append-only journal of working sessions. Newest entries on top. Each entry should answer three questions in 5–15 lines: **what was done**, **what's next**, **gotchas / open questions**.

Write a fresh entry at the end of every session, before stopping. Do not edit older entries — if something turned out wrong, note it in the next entry.

Rotation: keep roughly the last 10 sessions here; move older entries to `docs/archive/` every 20–30 sessions. V1's log lives in `docs/archive/STATUS-sessions-01-88.md` and `STATUS-sessions-89-98.md`.

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
