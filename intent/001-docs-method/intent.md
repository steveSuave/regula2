# Intent: project-management files follow Anthropic's intent → spec → plan method

Author: SLevantis, drafted with Claude · Status: accepted 2026-11-23 (open questions settled by Claude on the user's delegation; see the end) · drafted 2026-11-17

## Problem

The repo's management files are one growing set for the whole project: an 827-line `docs/PLAN.md` (architecture plus every pinned decision), a phase checklist in `docs/TODO.md`, and an append-only `docs/STATUS.md`. Every session is told to read most of it. The unmerged branch `docs-intent-spec-plan` renamed these to INTENT / SPEC / PLAN, but only the names changed: its SPEC is still the old decision log and its INTENT is a product charter written after the fact.

Anthropic's published method (the AI-native SDLC playbook) is different in kind. Each change gets its own short `intent.md`, then a `spec.md` written from the accepted intent, then a `plan.md`, committed together in an `intent/` folder. `CLAUDE.md` is the only standing project-wide file and stays under a page.

## Proposed outcome

- Every change lives in `intent/<number>-<slug>/` as `intent.md`, `spec.md` and `plan.md`, in the playbook's formats:
  - `intent.md`: problem, proposed outcome, affected users and systems, constraints, open questions.
  - `spec.md`: numbered requirements, design, a table mapping each intent constraint to how it is met, open questions carried over, areas of concern.
  - `plan.md`: files that change, order of work, risks, proof. Updated in the same commit whenever the code departs from it; it also carries the change's progress and gotchas.
- The 827-line decision log is kept under an honest name, `docs/DECISIONS.md`, as the architecture record that code comments cite. It is read when a citation points at it, not at every session start.
- `docs/TODO.md` and `docs/STATUS.md` are frozen into `docs/archive/`. Open items in TODO become intents or are dropped, each named in this change's plan.
- `CLAUDE.md` is trimmed toward a page: what the project is, commands, invariants, conventions, and how to find the active intent.
- The `continue-build` command and the session start/end rules describe this method and nothing else.
- This restructure is on `main` before any other intent merges.

## Affected users and systems

- Every future Claude Code session (session start reads much less).
- `CLAUDE.md`, `.claude/commands/continue-build.md`, `README.md`, everything under `docs/`.
- About 130 `lib/`, `test/` and `benchmark/` files whose comments cite `PLAN §"…"` (comments only, no behaviour).
- Branch `docs-intent-spec-plan`: harvested, then deleted, not merged.

## Constraints

- No behaviour change: analyze clean and the full suite green before and after.
- The citation rewrite is mechanical and its own commit; file renames are their own commit so history follows the files.
- Every code citation must resolve to a heading that exists in `docs/DECISIONS.md`. The branch has two that do not (`"AR is a Z-module"`, `"Proofs must read"`); check `main` for the same.
- `docs/archive/` and old STATUS entries are left as written, with one header note saying which name meant what and when.
- Nothing worth keeping from the branch's `docs/INTENT.md` is lost: the product description, non-goals and quality bar move to `CLAUDE.md` or `README.md`.
- Build on `main`, not on `docs-intent-spec-plan`, so citations are rewritten once (`PLAN §` → `DECISIONS §`) and not twice.

## Open questions — settled 2026-11-23

The user delegated these ("choose what you would if you'd built it from scratch"). Each is reversible at spec review.

- **Freeze `STATUS.md`?** Yes. Progress and gotchas live in each change's `plan.md`.
- **Does `CLAUDE.md` fit a page with the kernel invariants?** Each invariant stays in `CLAUDE.md` as one line; its long explanation moves to `docs/DECISIONS.md`.
- **Retroactive intents for the kernel, Cayley–Klein and prover tracks?** No. This is paperwork only and changes nothing in the app. The archive is their history, `docs/DECISIONS.md` is their standing record, and it gains a one-page architecture map at its top so later intents have something to cite.
- **`intent/<number>-<slug>/` layout?** Kept.

Source: https://claude.com/resources/articles/the-ai-native-sdlc-playbook
