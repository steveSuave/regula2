---
description: Resume work on the dynamic geometry app — read intent/README.md and the active intent, then propose the next concrete step
argument-hint: "[optional: an intent number or a focus, e.g. '003', 'tests']"
---

You are resuming work on the **regula** dynamic geometry Flutter app. Orient yourself, then propose a concrete next step before writing any code.

## Step 1 — Orient

1. `CLAUDE.md` is already loaded: invariants, commands, conventions.
2. Read `intent/README.md`. It lists every intent with its status, the parked items, and where the next session starts.
3. Read the active intent's folder: `intent.md`, then `spec.md` and `plan.md` if they exist. The plan's "Progress and gotchas" section is where the previous session left off.
4. Run `git status` and `git log -n 5 --oneline`. If they disagree with the plan's progress, trust what is on disk and say so.

Do not read `docs/DECISIONS.md` or `docs/archive/` at session start. Go to DECISIONS when a comment's `DECISIONS §"…"` citation or its map sends you there.

## Step 2 — Report

No more than about ten lines:

- **Active intent** and its status (draft, accepted, spec drafted, plan approved, in progress).
- **Last session ended with:** one sentence from the plan's progress section.
- **Working tree:** clean or dirty, and the branch.
- **Open questions or gotchas** carried in the intent, spec or plan.

## Step 3 — Propose

Recommend the single next step. Which one depends on where the intent stands:

- **Intent is a draft:** show it to the user for acceptance and corrections. Do not write the spec yet.
- **Intent accepted, no spec:** write `spec.md` (numbered requirements, design, a table mapping each intent constraint to how it is met, open questions carried over, areas of concern), then `plan.md` (files that change, order of work, risks, proof). Ask for approval of the plan.
- **Plan approved:** the next unfinished step in the plan's order of work. Say which files you would touch and which tests you would add.

If the user passed an argument (`$ARGUMENTS`), let it choose the intent or bias the step.

## Step 4 — Discipline

- Honour every invariant in `CLAUDE.md`.
- Work on a branch named for the intent (`intent-NNN-<slug>`), one commit per logical step.
- When the code departs from the plan, update `plan.md` in the same commit.
- A decision that binds future changes goes into `docs/DECISIONS.md` in the commit that makes it true.
- At session end: update the plan's progress and gotchas, and the status row in `intent/README.md`.
- A new change starts as a new `intent/<number>-<slug>/intent.md`, not as code.

If `intent/README.md` is missing, stop and tell the user.
