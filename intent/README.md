# Intents

One folder per change, following Anthropic's AI-native SDLC playbook: `intent.md` (what is asked for), then `spec.md` (what was decided), then `plan.md` (how it is built and proved). The user reviews and accepts an intent before its spec is written.

| # | Intent | Status | Depends on |
|---|---|---|---|
| 001 | [Docs follow the intent → spec → plan method](001-docs-method/intent.md) | draft, awaiting review | — |
| 002 | [regula2 becomes regula again](002-fold-into-regula/intent.md) | draft, awaiting review | 001 |
| 003 | [Prover is experimental, off by default](003-prover-flag/intent.md) | draft, awaiting review | 002 (so it ships to the final URL) |
| 004 | [Stereometry](004-stereometry/intent.md) | draft, awaiting review | 001; after 003 |

## Where the next session starts ("continue")

Written 2026-11-17 on branch `intent-method`, which is `main` plus this folder. Nothing here is on `main` yet.

1. The user reviews the four intents and corrects them.
2. Intent 001 goes first: write its `spec.md` and `plan.md`, do the restructure on this branch, and merge to `main`. The user requires the restructure before anything merges.
3. Then 002, 003, 004 in order, each through spec and plan before code.

Until 001 lands, `CLAUDE.md` and `docs/` on this branch still describe the old method (PLAN / TODO / STATUS). Where they disagree with this folder, this folder is current. The branch `docs-intent-spec-plan` is superseded by intent 001 and is not to be merged.
