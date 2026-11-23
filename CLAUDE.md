# Claude Code Working Notes — regula2

Auto-loaded into every session. A dynamic geometry app for web, Android and iOS, in Flutter. The kernel is **complex projective**: homogeneous coordinates over ℂ, drags resolved by analytic continuation, so intersection points never jump and loci are complete. The construction is a DAG whose only mutable roots are free points. The repo carries regula's full history (V1 ends at tag `v1-final`).

## Session start and end

- **Start:** read `intent/README.md`, then the active intent's folder (`intent.md`, `spec.md`, `plan.md`). Propose the first concrete change before editing.
- **Gates:** an intent is accepted by the user before its `spec.md` is written; a `plan.md` is approved before code.
- **End:** commit (one commit per logical step); bring the active `plan.md` up to date, including its progress and gotchas and any departure from the plan; update the status row in `intent/README.md`.
- `docs/DECISIONS.md` is the architecture record that comments cite as `DECISIONS §"…"`. Read it when a citation or its map sends you there, not at session start. Change it in the same commit as the code that makes a decision true. `docs/archive/` is history; do not edit it.

## Invariants (do not violate)

- **`lib/domain/` must not import `package:flutter/*`.** Cross the boundary only via `lib/application/`.
- **Free points are the only directly-mutable objects**, and the `Construction` DAG is the single source of truth for rendering, hit testing, undo and save/load.
- **All user actions are reversible `Command`s.** One carve-out: drag preview frames mutate directly, and the gesture ends by emitting exactly one command (or rolling back on cancel).
- **The save format carries a `version`.** Bump `constructionFormatVersion` only for a change an older reader would misread, and add a migration; the encoder stamps the lowest version that reads back correctly. Version 1 is permanent and every file in `test/fixtures/` stays v1. (§"The version field is a requirement, not a build number")
- **No new public API in `domain/` without a test.**
- **The figure never lies.** Near-degenerate input gives real, faraway geometry; only exact degeneracy degenerates. When tracing cannot vouch for a frame it lags or bails to a static solve.

Kernel, long form in DECISIONS §Architecture:

- **Projective is canonical; affine is a view.** Domain code reads `projPoint` / `projLine` / `conic` only. `position` / `line` / `circle` are projections for the painter, hit-tester, codec and the chart reads §Parameterization sanctions.
- **The projective value is total, the projection is nullable.** A projective accessor is null only when a parent's is, or the value is the zero triple.
- **`Vec2`, `LineEq`, `CircleEq` are view structs.** Reach them through `toVec2` / `toLineEq` / `toCircleEq`. `LineEq` / `CircleEq` throw on degenerate arguments, so never construct one in a recompute without a guard.
- **Branch orderings are load-bearing.** Intersection functions agree with V1's canonical order on real transverse cases, with I and J filtered.
- **`test/v1_oracle/` is V1's affine kernel, frozen** as the oracle that agreement is checked against. Do not extend it, fix it, or move other code into it.

## Commands

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after touching freezed / json_serializable / riverpod_generator classes
flutter analyze && flutter test && flutter test --platform chrome test/web   # the CI gate
flutter run -d chrome
dart format lib test benchmark   # in its own commit when it would mix with a behaviour change
```

- **`main` is deployed.** `origin` is `github.com:steveSuave/regula2`; every push to `main` runs `ci.yml`, `benchmarks.yml` (informational) and `deploy.yml`, which publishes the wasm build to https://stevesuave.github.io/regula2/. Check `gh run list` after a merge.
- **`test/web/` is the browser gate.** A green VM suite is not evidence about the renderer: anything resting on the rasterizer (path booleans, fill rules, blend modes, text metrics) is tested there behind `@TestOn('browser')`. Prefer a formulation with no platform-dependent step.

## Conventions

- Files `snake_case.dart`, one non-trivial class each. `GeoObject` subclasses end in their kind (`Midpoint`, `PerpendicularLine`).
- Tests mirror the source layout as `<source>_test.dart`. Property tests via `glados`; goldens via `matchesGoldenFile`, tagged `golden`, excluded in CI, regenerated on macOS.
- Riverpod: `@riverpod`-annotated providers.

## What goes where

| Concern | Location |
|---|---|
| Projective kernel, tracing | `lib/domain/projective/` |
| Affine view structs, metric helpers | `lib/domain/math/` |
| Construction graph and objects | `lib/domain/construction/` |
| Tools; commands; prover | `lib/domain/tools/`, `commands/`, `prover/` |
| Providers; save/load | `lib/application/providers/`, `persistence/` |
| Canvas, painter, hit test; panels; theme; shortcuts | `lib/presentation/canvas/`, `panels/`, `theme/`, `shortcuts/` |
| App entry | `lib/main.dart` |
