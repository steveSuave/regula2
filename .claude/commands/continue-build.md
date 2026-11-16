---
description: Resume work on the dynamic geometry app — read CLAUDE.md / PLAN.md / STATUS.md / TODO.md and propose the next concrete step
argument-hint: "[optional: focus area, e.g. 'phase 2', 'tests', 'fix lint']"
---

You are resuming work on the **regula** dynamic geometry Flutter app. A previous session has already done some of the work; your first job is to orient yourself, then propose a concrete next step before writing any code.

## Step 0 — Intents first

Read `intent/README.md` and the `intent.md` files it lists. It names the active intent and where to start; it overrides the steps below wherever they disagree (the steps below describe the old PLAN / TODO / STATUS method, which intent 001 replaces). An intent marked "draft, awaiting review" is shown to the user for acceptance before its `spec.md` is written, and no code is written before its `plan.md` is approved.

## Step 1 — Orient

Read the four durable artifacts in this order:

1. `CLAUDE.md` (repo root) — architectural invariants and conventions.
2. `docs/PLAN.md` — full architecture and build order.
3. `docs/STATUS.md` — newest entry first; that's where the previous session left off.
4. `docs/TODO.md` — live phase checklist; find the first unchecked item in the active phase.

Then, if a git repo exists, run `git status` and `git log -n 5 --oneline` to confirm the working tree state matches the STATUS entry. If they disagree, trust what's actually on disk and flag the discrepancy.

## Step 2 — Report

Give the user a short orientation, no more than ~10 lines:

- **Current phase:** which phase from `docs/TODO.md` is active.
- **Last session ended with:** one sentence from the latest STATUS entry.
- **Working tree:** clean / dirty / branch.
- **Open questions or gotchas** carried forward from the last STATUS entry, if any.

## Step 3 — Propose

Recommend the **single next concrete step** — usually the first unchecked item in the active phase — and describe what files you'd touch and what tests you'd add. If the user passed an argument (`$ARGUMENTS`), let it bias which step you propose. Wait for the user's confirmation before editing.

## Step 4 — Discipline

- Honour every invariant in `CLAUDE.md` (especially: `lib/domain/` must not import `package:flutter/*`).
- Commit on a phase branch (`phase-N-<slug>`), one commit per logical step.
- After landing the step: tick `docs/TODO.md`, and at session end, append a new entry to `docs/STATUS.md`.
- If the work would change scope or architecture, update `docs/PLAN.md` first.
- If a phase isn't represented in `docs/TODO.md`, add it before starting.

If any of those four files is missing, stop and tell the user — don't try to reconstruct them from memory.
