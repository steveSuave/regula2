# Plan: project-management files follow the intent → spec → plan method

Written 2026-11-23 from [spec](spec.md) · Status: approved 2026-11-23; done bar step 10 · Branch: `intent-method`

## Files that change

| File | Change |
|---|---|
| `docs/PLAN.md` → `docs/DECISIONS.md` | `git mv`; then new header, architecture map, moved invariant explanations, `#### Proofs must read` heading |
| `docs/TODO.md` → `docs/archive/TODO-final.md` | `git mv`, untouched |
| `docs/STATUS.md` → `docs/archive/STATUS-sessions-176-186.md` | `git mv`, untouched |
| `docs/archive/README.md` | new: which name meant what, and when |
| 124 files under `lib/`, `test/`, `benchmark/` | comments only: `PLAN` → `DECISIONS` |
| `.github/workflows/deploy.yml`, `benchmarks.yml` | one comment each |
| `test/docs/decision_citations_test.dart` | new |
| `CLAUDE.md` | rewritten to about a page |
| `README.md` | doc pointers; product, users and non-goals from the superseded branch |
| `.claude/commands/continue-build.md` | rewritten for this method |
| `intent/README.md` | status rows, parked list, next-session note |

## Order of work (one commit each)

1. **Baseline.** `flutter analyze`, `flutter test`, `flutter test --platform chrome test/web`. Record the counts here.
2. **Renames.** The three `git mv`s and `docs/archive/README.md`. Nothing else, so history follows the files.
3. **Citation rewrite.** Script from the scratchpad (not committed): rewrite per the spec's table, refuse any non-comment line, list what it changed. Fix the dangling citations. Run `dart format lib test benchmark` and confirm it changes nothing.
4. **Citation test.** Add `test/docs/decision_citations_test.dart`; confirm it fails when a citation is broken on purpose, then passes.
5. **DECISIONS header and map.** New header paragraph, the one-page map, the long-form kernel invariants.
6. **`CLAUDE.md`, `README.md`, `continue-build.md`.** Including the harvest from `docs-intent-spec-plan:docs/INTENT.md`.
7. **TODO dispositions** (table below) into `intent/README.md` and DECISIONS.
8. **Gates again**, same three commands; counts match step 1 plus one test.
9. **Merge to `main`**, push, check `gh run list` for the three workflows.
10. **Delete `docs-intent-spec-plan`** after confirming with the user. It is local only.

## Open TODO boxes and where each goes

| Item (`docs/TODO.md`) | Disposition |
|---|---|
| Android emulator smoke; iOS simulator smoke and `flutter build ios` | Parked. Trigger: intent 004's first milestone, which requires a phone |
| Hand-written SVG export | Dropped ("may slip forever" since V1 Phase 19) |
| Phase 186 carried prover items (`readFact` on `eqangle`, the re-glance on old zeros, `regular_hexagon#2`) | Parked under the prover, which 003 puts behind a flag |
| Phase 176, the Newclid comparison | Parked. Trigger: Newclid ships past 3.0.1 or fixes either crash class |
| Phase 154, the proof sheet seen on a narrow window | Folded into intent 003's proof, which must check the phone layout anyway |
| Phase 137, compat edge for `TangentLine` on a chartless carrier | Not work. Confirmed present under its DECISIONS heading as a known limit, added there if not |
| Phase 132d, chain members glued to a conic inside traced passes | Same: a known limit under its DECISIONS heading |

## Risks

- **The script touches code.** It refuses any line that is not a `//`, `///` or `#` comment, and analyze plus the suite run after.
- **A citation form the grep missed.** The new test only checks `DECISIONS §` forms; a final `grep -rnw PLAN lib test benchmark` must return only `PLAN-v1` hits.
- **Goldens.** Untouched; golden tests are not in the gate and no rendering code changes.
- **Deploy on merge.** Checked in step 9.

## Proof

- Baseline and final gate counts recorded below, differing by exactly the one new test.
- `grep -rnw PLAN lib test benchmark .github CLAUDE.md README.md` returns nothing but `PLAN-v1`.
- The citation test passes, and was seen to fail on a deliberately broken citation.
- `wc -l CLAUDE.md` is 70 or fewer.
- `git log --follow docs/DECISIONS.md` reaches the old PLAN history.
- The three workflows are green on `main` after the merge.

## Progress and gotchas

- 2026-11-23: intent accepted, spec and plan drafted. Nothing restructured yet.
- 2026-11-23: plan approved ("carry on"). Baseline: analyze clean, 3554 tests, 15 browser tests.
- Step 2 done (`7f5d3d7`).
- Step 3 done: 199 comment lines in 126 files (124 Dart, `run_corpus.sh`, `benchmark/comparator/README.md`, two workflows), no line refused, `dart format` changed nothing. `prover_provider.g.dart` changed with its source's doc comment, so a rebuild reproduces it.
- Departures from the plan, spec updated in the same commit: no `#### Proofs must read` heading (the two paragraphs are not adjacent; the citations were repointed); four `§Migration` citations found dangling and repointed to `§Architecture`; the test also accepts bold lead-ins and checks `§` citations without the `DECISIONS` prefix.
- Gotcha: 13 rewritten comment lines are now 81–84 columns (`DECISIONS` is five letters longer). There is no line-length lint and `dart format` does not wrap comments; left as they are.
- Gotcha: `docs/STATUS.md` and `docs/TODO.md` references in four code comments now point into `docs/archive/`.
- Steps 4–7 done. The map's citations were checked against the headings by hand (the test reads Dart files only).
- Departure: the kernel invariants' long form was already §Architecture's five numbered points, so nothing moved into DECISIONS for them. What `CLAUDE.md` dropped and DECISIONS did not have is now there: §"A green suite is not evidence about the renderer" and §"Known limits, carried from the old checklist".
- `CLAUDE.md` is 58 lines. It gained one invariant from the superseded branch's quality bar ("The figure never lies").
- New convention, not in the spec: work branches are named `intent-NNN-<slug>` (in `continue-build.md`).
- Step 8 done: analyze clean, 3555 tests (baseline plus the citation test), 15 browser tests.
- Step 9 done: merged as `057a4ca` and pushed. Deploy and Benchmarks green. **CI failed, at `flutter analyze`, for a reason outside this change:** CI's Flutter stable is now 3.50.1, which deprecates `package:flutter/material.dart` (43 infos, and analyze exits non-zero). Local is 3.47.2, where analyze is clean. Drafted as intent 005.
- Step 10 open: deleting `docs-intent-spec-plan` waits for the user's go-ahead.
