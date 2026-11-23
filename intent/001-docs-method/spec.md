# Spec: project-management files follow the intent → spec → plan method

Written 2026-11-23 from the accepted [intent](intent.md) · Status: approved 2026-11-23

## Requirements

1. **R1 — One folder per change.** Every change from 001 on lives in `intent/<number>-<slug>/` as `intent.md`, `spec.md`, `plan.md`, in the formats the intent lists. `intent/README.md` is the index: one row per intent with its status, plus a "Parked" list (R6).
2. **R2 — The decision log gets an honest name.** `docs/PLAN.md` becomes `docs/DECISIONS.md` by `git mv`, content unchanged apart from R3, R4 and its header paragraph.
3. **R3 — DECISIONS opens with a map.** A new first section, at most one page, names the standing subsystems (projective kernel, tracing/continuation, Cayley–Klein, prover, persistence, the V1 shell), gives each two or three sentences and the headings to read for it, and says where a space kernel attaches. It also carries the long form of the kernel invariants that `CLAUDE.md` keeps as one-liners.
4. **R4 — Every citation resolves.** Every `§"…"` and `§Word` in `lib/`, `test/` and `benchmark/` names text found in a heading or bold lead-in of `docs/DECISIONS.md`. A test enforces it.
5. **R5 — TODO and STATUS are frozen.** `docs/TODO.md` → `docs/archive/TODO-final.md`; `docs/STATUS.md` → `docs/archive/STATUS-sessions-176-186.md`. Both by `git mv`, content as written. `docs/archive/README.md` (new, short) says which name meant what and when.
6. **R6 — No open item is lost silently.** Each unticked box in `docs/TODO.md` is disposed of by name in `plan.md`: folded into an intent, parked in `intent/README.md` with its trigger, recorded in DECISIONS as a known limit, or dropped.
7. **R7 — `CLAUDE.md` is about a page.** What the project is, commands, invariants (one line each), conventions, the what-goes-where table, and how to find the active intent. Target: 70 lines or fewer.
8. **R8 — Session rules describe this method only.** `.claude/commands/continue-build.md` and the session start/end rules in `CLAUDE.md` mention no PLAN / TODO / STATUS.
9. **R9 — The superseded branch is harvested.** The product description, non-goals and quality bar from `docs-intent-spec-plan:docs/INTENT.md` land in `README.md` (product, users, non-goals) and `CLAUDE.md` (quality bar, where not already an invariant). The branch is then deleted, with the user's confirmation at that moment.
10. **R10 — No behaviour change.** `flutter analyze` clean and `flutter test` plus the browser gate green before and after, with the same test count plus the one new test.

## Design

### Layout after the change

```
CLAUDE.md                       about a page; points at intent/README.md
intent/README.md                index, parked list, where the next session starts
intent/NNN-slug/{intent,spec,plan}.md
docs/DECISIONS.md               architecture map + pinned decisions; read on citation
docs/EXPRESSIONS.md             unchanged
docs/V2-assessment.md           unchanged
docs/archive/                   README.md (new), PLAN-v1, old STATUS and TODO files
```

### Session start and end

- **Start:** `CLAUDE.md` (auto-loaded) → `intent/README.md` → the active intent's folder. `docs/DECISIONS.md` only when a citation or the map sends you there.
- **End:** commit; bring the active `plan.md` up to date (progress, gotchas, any departure from the plan); update the status row in `intent/README.md`.
- **Gates, unchanged in spirit:** an intent is accepted before its spec is written; a plan is approved before code.

### Citation rewrite

Measured on `intent-method` today:

| Form | Count | Rewrite |
|---|---|---|
| `PLAN §"…"` (25 distinct headings) and `PLAN §Word` (5 distinct) | 94 occurrences | `DECISIONS §…` |
| `PLAN` split from its `§` by a line break | 13 | same, rejoined only if the line stays within 80 columns |
| Bare `PLAN` in a comment ("see PLAN", `PLAN "Export"`, "per PLAN") | about 60 | `DECISIONS` |
| `docs/PLAN.md` | 3 in code, plus README, workflows | `docs/DECISIONS.md` |
| `docs/STATUS.md`, `docs/TODO.md` in code comments | 4 | the archive path |

124 files in `lib/`, `test/` and `benchmark/` are touched, comments only. `PLAN-v1` and anything under `docs/archive/` are excluded. The rewrite is a script with an explicit check that every changed line is a comment line.

Two citations do not resolve today and are fixed by hand in the same commit:

- `"AR is a Z-module"` (`test/domain/prover/angle_chase_test.dart:84`): the heading spells it `ℤ`. The citation changes to `"AR is a ℤ-module"`.
- `"Proofs must read"` (`lib/domain/prover/angle_chase.dart:10`, `arithmetic_chase.dart:7`): no such heading. The text it means is two bold-led paragraphs under §"The prover against a real benchmark" ("A proof obligation, carried from the start" and "naming the facts is not yet reading"). They are not adjacent, so a new heading would have swallowed the paragraphs between them; the two citations now name the section and quote the paragraph's lead-in instead. DECISIONS is not changed for this.
- `§Migration` (4 sites, found during the rewrite): the Migration section was folded into §Architecture when Phase 121 finished, and the canonical-order rule these cite is item 4 there. They now read `§Architecture`.

### The citation test

`test/docs/decision_citations_test.dart`, plain Dart: collect every `DECISIONS §"…"` and `DECISIONS §Word` from `lib/`, `test/`, `benchmark/` (comment markers and line breaks normalised), and assert each is a substring of some heading line of `docs/DECISIONS.md` or of a bold lead-in there (that is how the file labels `M-P4`, "compile target" and similar decisions inside a section). It checks every `§` citation, with or without the `DECISIONS` prefix, since chained citations drop it. It fails with the file and line of the dangling citation.

### `CLAUDE.md`

Kept: project description (three lines), session start/end (R8 form), the six architectural invariants, the six kernel invariants as one line each with `DECISIONS §` pointers, commands and the CI gate, the deploy fact, the `test/web/` rule in two lines, conventions, the what-goes-where table. Moved to DECISIONS: the long forms of the kernel invariants and the Phase 126d rasterizer story. Dropped: rotation rules, "when in doubt" items that name PLAN or TODO.

## Intent constraints → how each is met

| Constraint | Met by |
|---|---|
| No behaviour change | R10; the rewrite script refuses non-comment lines |
| Citation rewrite mechanical and its own commit; renames their own commit | Plan steps 2 and 3 are separate commits |
| Every citation resolves; check `main` for the two dangling ones | R4; both are present on `main` too and fixed as above |
| Archive and old STATUS entries left as written, one header note | R5; the note is `docs/archive/README.md`, so no archived file is edited |
| Nothing worth keeping from the branch's INTENT.md is lost | R9 |
| Build on `main`, rewrite citations once | Work is on `intent-method`, which is `main` plus `intent/` |
| Restructure on `main` before any other intent merges | Plan's last step; 002–004 stay unstarted until then |

## Open questions carried over

None from the intent. One new: the outcome checklists in the branch's INTENT.md (O1–O6) are not carried, since ticked outcomes are history and the unticked ones are intents 003/004 or parked. Say so at review if the checklist is wanted in `README.md`.

## Areas of concern

- **A 124-file comment diff is unreviewable by eye.** Mitigation: the script's comment-only check, `dart format` producing no change, and analyze plus the suite before and after.
- **Merging to `main` deploys.** The build is byte-identical in behaviour, but the three workflows still run; they are checked after the merge.
- **`CLAUDE.md` at 70 lines loses context sessions used to get for free.** The one-line invariants are the mitigation; if a session trips on a moved explanation, it comes back.
