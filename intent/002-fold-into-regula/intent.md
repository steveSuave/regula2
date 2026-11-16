# Intent: regula2 becomes regula again

Author: SLevantis, drafted with Claude · Status: draft, awaiting review · 2026-11-17

## Problem

The app was forked into a second repository, `steveSuave/regula2`, when the V2 kernel work started. The "2" was never meant to be part of the name, and the original `steveSuave/regula` still serves the old V1 build at https://stevesuave.github.io/regula/. There are now two repos and two live sites for one app.

## Proposed outcome

- `steveSuave/regula` holds the current code, as a continuation of its own history, and https://stevesuave.github.io/regula/ serves the current app.
- The name "regula2" is gone from the product, the README, `CLAUDE.md` and the live docs.
- `steveSuave/regula2` is archived, and its Pages site redirects to the new URL.
- The local checkout is the directory `regula`, with `origin` pointing at `steveSuave/regula`.

## Decisions already made (2026-11-16)

- Fast-forward push into `regula`; no force push, no repo rename.
- `regula` becomes public.
- `regula2` is archived with a redirect, not deleted.
- The V1 app does not stay live. It remains recoverable from tag `v1-final`.

## Affected users and systems

- Anyone with the old `/regula2/` link or bookmark (gets a redirect).
- Anyone using the V1 site at `/regula/` (gets V2; V1 documents open in it).
- GitHub: both repos, their Pages settings, the three workflows (`ci.yml`, `benchmarks.yml`, `deploy.yml`).
- In the tree: the `--base-href "/regula2/"` in `.github/workflows/deploy.yml`, and 44 mentions of "regula2" across 16 files (README, `CLAUDE.md`, docs, `benchmark/comparator/`, `test/corpus/newclid_translation.dart`).
- Local: the two checkouts under `~/Code/var/`, and Claude's per-project memory folder, which is keyed by the directory path.

## Constraints

- Nothing is lost. Verified on 2026-11-16, re-verify before pushing:
  - `regula`'s `main` is commit `7ef44db`, the same commit as tag `v1-final` here, and an ancestor of this repo's `main`.
  - All 78 remote branches of `regula` are contained in this repo's `main`.
  - `regula` has no issues, pull requests, releases or Actions secrets.
  - The local `regula` checkout is clean, with no stashes and no unpushed branches.
- Tags `v0.2` and `v1-final` are pushed with `main`.
- The site at `/regula/` is confirmed to serve the new build, with all three workflows green, before `regula2` is touched.
- Making a repo public and archiving one are outward-facing: each is confirmed with the user at the moment it is done.
- History files (`docs/archive/`, old status entries) keep the old name.
- Runs after intent 001, so the renamed docs are the restructured ones.

## Open questions

- Do the 34 remote phase branches of `regula2` get pushed to `regula`, or only `main` and tags? Proposed: only `main` and tags, since every branch is merged.
- What happens to the old local checkout: deleted, or kept aside as `regula-v1`?
- Browsers that visited the V1 site may hold its cached service worker; check that a returning visitor gets the new build.
- Does the redirect on `regula2` also need a `404.html` so deep links redirect too?
