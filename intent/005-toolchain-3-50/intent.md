# Intent: CI is green again on Flutter stable

Author: drafted by Claude · Status: draft, awaiting review · 2026-11-23

## Problem

`ci.yml` pulls Flutter `channel: stable`, which is now 3.50.1. The repo is developed on 3.47.2. On 3.50.1, `package:flutter/material.dart` is deprecated in favour of `package:material_ui/material_ui.dart`, the analyzer reports it as an info at each of the 43 files that import it, and `flutter analyze` exits non-zero on infos. So the CI workflow fails on every push to `main`, whatever the push contains. It was first seen on the merge of intent 001 (run 45197635026, 2026-11-23); the previous push, on 2026-09-05, was green.

Deploy and benchmarks do not run `flutter analyze` and still pass, so `main` keeps shipping, but with a red gate nothing tells a real failure from this one.

## Proposed outcome

- `flutter analyze`, `flutter test` and the browser gate are green both locally and in CI, on the same Flutter version.
- The local SDK is at CI's stable, per the rule in `docs/DECISIONS.md` §"Deferred decisions": the upgrade is due when CI's `stable` moves past the local SDK.

## Affected users and systems

- Every later intent: 002 requires all three workflows green before `regula2` is touched.
- 43 files in `lib/` and `test/` that import `package:flutter/material.dart`; `pubspec.yaml` if `material_ui` is a new dependency; goldens, which the last upgrade (Phase 187) moved.
- `.github/workflows/ci.yml`.

## Constraints

- No behaviour change in the app.
- The import change is mechanical and its own commit; any golden regeneration is its own commit.
- `lib/domain/` still imports nothing from Flutter.
- Read the Flutter 3.50 release notes and the `material_ui` migration guide before choosing; do not work from memory of earlier Flutter versions.

## Open questions

- Migrate the 43 imports to `material_ui` now, or pin CI to the local Flutter version and migrate later? Proposed: migrate, since pinning only defers it and DECISIONS already says CI's stable is the trigger.
- Should CI pin an exact Flutter version from now on, with upgrades as deliberate intents, so a release cannot turn the gate red on an unrelated push?
- Does this go before 002? Proposed: yes.
- What else did 3.48–3.50 deprecate or change that the analyzer has not yet flagged (renderer, wasm, text metrics)?
