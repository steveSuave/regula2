# Intent: CI is green again on Flutter stable

Author: drafted by Claude · Status: part 1 (the pin) done 2026-11-23 on the user's request to fix CI; part 2 (the migration) draft, awaiting review

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

Settled 2026-11-23, when the user asked for the CI failure to be fixed:

- **Pin or migrate?** Both, in that order. Part 1 pins all three workflows to Flutter 3.47.2, the version the tree is developed and tested on, which makes the gate green without touching the app. Part 2 is the upgrade itself.
- **Should CI pin an exact version from now on?** Yes, and deploy with it, so the build that ships is the build that was tested. Recorded in `docs/DECISIONS.md` §"Deferred decisions".

Open, for part 2:

- The migration is `dart fix --apply --code=migrate_design_widgets` plus `flutter pub add material_ui` (Flutter's guide: docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui). The types in `material_ui` are distinct classes from the SDK's. The suite calls `find.byTooltip` about 80 times, and whether `flutter_test`'s finder matches a `material_ui` `Tooltip` is not stated in the guide; it has to be tried.
- It needs the local SDK at 3.50.1 (`flutter upgrade` in `~/Code/flutter/flutter-upstream`), which changes the machine, not only the repo.
- What else 3.48–3.50 changed that the analyzer has not flagged (renderer, wasm, text metrics, goldens).
- When: before 002, or after the stereometry work starts? Nothing forces it while the pin holds; the in-framework library is deprecated in 3.50, not removed, and the guide gives no removal date.
