# Plan: CI is green again on Flutter stable

Status: approved 2026-11-23; steps 1–6 done, post-merge checks and the site look remain. Branch `intent-005-toolchain-3-50`.

## Files that change

- `.github/workflows/ci.yml`, `deploy.yml`, `benchmarks.yml`: `flutter-version: 3.47.2` → `3.50.1`.
- `pubspec.yaml`, `pubspec.lock`: `material_ui: ^1.11.1`.
- 43 files in `lib/` and `test/`: the import line.
- The same files again for import ordering.
- `docs/DECISIONS.md` §"Deferred decisions": the upgrade entry.
- `intent/README.md`, this plan.

## Order of work (one commit each)

1. Read the Flutter 3.48, 3.49 and 3.50 release notes for anything the analyzer misses; note findings under Progress.
2. `flutter pub add material_ui`, then `dart fix --apply --code=migrate_design_widgets`. Commit: dependency and imports only.
3. `dart fix --apply --code=directives_ordering`. Commit: ordering only.
4. Bump the three workflow pins to 3.50.1.
5. Update DECISIONS (toolchain entry: 3.50.1 / its Dart version, why `material_ui`, the `find.byTooltip` result, the pin held).
6. Push the branch, wait for CI, check `gh run list`. Merge to `main` only when green; then check the deploy run.
7. Update this plan and the README row; delete the branch.

## Risks

- A release-note item the trial did not exercise (text metrics, wasm) turns up in step 1. Mitigation: the browser gate and wasm build already passed; a finding becomes a gotcha or a follow-up intent, not a silent change.
- CI's Linux runner behaves differently from local macOS. Mitigation: that is what step 6 is for; goldens are excluded from CI anyway.
- `flutter pub add` resolves a newer `material_ui` than `^1.11.1` by the time of the real run. Mitigation: accept the resolver's choice, re-run the proof.

## Proof

- Locally on 3.50.1: `flutter analyze` (no issues), `flutter test`, `flutter test --platform chrome test/web`, `flutter test --tags golden`, `flutter build web --wasm --release`, `dart format --set-exit-if-changed lib test benchmark`.
- `grep -rn "package:flutter/material.dart" lib test` finds nothing; `grep -rn "package:flutter" lib/domain` finds nothing.
- A green `ci.yml` on the branch, then green `ci.yml`, `deploy.yml`, `benchmarks.yml` after the merge.
- A look at the deployed site once (theme toggle, a dialog, toolbar tooltips), since `material_ui` types are new at runtime.

## Progress and gotchas

- 2026-11-23: trial done and reverted (all green, see spec). Local SDK is already 3.50.1.
- The SDK checkout's own `pubspec.lock` drift is in `git stash` there; harmless to drop.
- Step 1 was partial: only the 3.50.0 notes were found; 3.48, 3.49 and 3.50.1 notes were not. 3.50.0 mentions soft-hyphen rendering, WidgetSpan RTL order and web text-paint fixes; none showed up in the suite, goldens or browser gate. The notes say "Dart 3.13"; the SDK actually reports Dart 3.14.0.
- Steps 2–5 landed as planned, one commit each. CI runs only on `main` pushes and pull requests, so the branch needed PR #2 to get its run: green in 5m.
- Local proof on 3.50.1 matched the trial: analyze clean, 3555 + 15 tests, 32 goldens, wasm build, format clean, no `flutter/material.dart` import left, nothing from `package:flutter` in `lib/domain`.
