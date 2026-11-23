# Spec: CI is green again on Flutter stable

Status: drafted 2026-11-23 after a throwaway trial of the migration (below). Awaiting approval with `plan.md`.

## Requirements

1. The tree builds and passes `flutter analyze` (no issues), `flutter test` and `flutter test --platform chrome test/web` on Flutter 3.50.1.
2. No `lib/` or `test/` file imports `package:flutter/material.dart`; they import `package:material_ui/material_ui.dart`.
3. `material_ui` is a declared dependency in `pubspec.yaml`.
4. All three workflows (`ci.yml`, `deploy.yml`, `benchmarks.yml`) pin `flutter-version: 3.50.1`.
5. The local SDK is 3.50.1, so local and CI agree.
6. No behaviour change in the app. `lib/domain/` still imports nothing from Flutter.
7. `docs/DECISIONS.md` §"Deferred decisions" records the upgrade, as Phase 187's entry did for 3.47.2.

## Design

### What the trial showed (2026-11-23, local SDK upgraded to 3.50.1)

| Step | Result |
|---|---|
| Baseline on 3.50.1, before any change | 43 infos (all `deprecated_member_use` on the import); 3555 tests pass |
| `flutter pub add material_ui` (`^1.11.1`) | one line in `pubspec.yaml`, lockfile changes |
| `dart fix --apply --code=migrate_design_widgets` | 43 files, one import line each |
| `dart fix --apply --code=directives_ordering` | 36 files; the new import sorts differently, so the fix is needed or the analyzer reports 36 infos |
| `flutter analyze` | no issues |
| `flutter test` | 3555 pass; **`find.byTooltip` still matches `material_ui`'s `Tooltip`**, the open question from the intent |
| `flutter test --tags golden` | pass; no golden moved |
| `flutter test --platform chrome test/web` | 15 pass |
| `flutter build web --wasm --release` | builds |
| `dart format --set-exit-if-changed` | clean |

The trial diff (45 files, +82/−53) is not on the branch; it was reverted so the real commits follow an approved plan. It was only a size probe.

### Shape of the change

Three mechanical things, each its own commit: the pin bump in the workflows, the dependency plus import migration, and the import re-sort. No golden regeneration is expected, and none is planned unless CI's Linux run disagrees with the local macOS one (goldens are excluded from CI, so CI cannot disagree).

### Local SDK

Upgraded in place with `flutter upgrade` in `~/Code/flutter/flutter-upstream`. That checkout carried a modified `pubspec.lock` (Flutter's own tool packages); it was stashed as `pre-3.50 upgrade pubspec.lock drift` rather than forced, and can be dropped.

## Intent constraints → how each is met

| Constraint | How |
|---|---|
| No behaviour change | The diff is imports and one dependency; the trial passed the whole suite and goldens unchanged |
| Import change mechanical and its own commit; golden regeneration its own commit | Commit 2 is only `dart fix` output; commit 3 holds the re-sort; no golden commit unless needed |
| `lib/domain/` imports nothing from Flutter | The fix touched no `lib/domain/` file in the trial; verified by grep in the plan's proof |
| Read the release notes and migration guide, do not work from memory | The migration followed docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui as the intent cites; 3.48–3.50 release notes are read in plan step 1 |

## Open questions carried over

- **3.48–3.50 changes the analyzer does not flag** (renderer, wasm, text metrics): the trial's green browser gate, goldens and wasm build are the evidence so far. The release-notes read in plan step 1 can still overturn that.
- **`flutter/cupertino.dart`** is not imported anywhere, so the Cupertino half of the guide does not apply.

## Areas of concern

- **Two copies of material types.** `material_ui` types are distinct classes from the SDK's. Any third-party package whose public API takes SDK `ThemeData`, `Color` schemes or similar would not accept ours. The trial's green suite suggests none of our dependencies does; the app's runtime behaviour (theme toggle, dialogs) is covered by the widget tests but is worth one look in a real browser.
- **`uses-material-design: true`** and the tree-shaken icon font: the wasm build still produced the shrunken `MaterialIcons` asset, so icons ship.
- **The pin rule from 2026-11-23.** An upgrade is an intent, and the PR's CI run is its evidence. So the final proof is a green CI run on the branch before merge.
