# Claude Code Working Notes — regula2

This file is auto-loaded into every Claude Code session for this project. **Read it first.**

## What this project is

V2 of regula: a cross-platform (web / Android / iOS) dynamic geometry app written in Flutter, being migrated from a numeric affine kernel to a **complex projective kernel** (homogeneous coordinates over ℂ, drags resolved by analytic continuation) — Cinderella-class behaviour: no jumping intersection points, complete loci. Construction-graph based: free points are the only mutable roots, every other object derives from its parents and recomputes when they change. See `docs/PLAN.md` for the V2 architecture and migration strategy; `docs/archive/PLAN-v1.md` documents the surviving V1 design. The repo carries regula's full git history (branch point tagged `v1-final`), so `git blame`/`bisect` trace surviving lines to their original phase commits.

## Session start

1. Read `docs/PLAN.md` — architecture & decisions, read-mostly.
2. Read the newest 2–3 entries of `docs/STATUS.md` — that's where the previous session left off. Don't read the whole file or `docs/archive/` unless hunting for old history.
3. Read `docs/TODO.md` — open phases plus the most recent couple of completed ones; older completed phases live in `docs/archive/`.
4. Propose the first concrete change before editing anything.

## Session end

1. Commit work-in-progress on the current phase branch (one commit per logical step).
2. Tick boxes in `docs/TODO.md` for items that fully landed (analyze clean + tests green).
3. Append a new entry to `docs/STATUS.md`: date, what was done, what's next, gotchas.
4. Rotation (occasional): if `docs/STATUS.md` exceeds ~15 sessions or `docs/TODO.md` accumulates fully-completed phases, move the old material to `docs/archive/` per the notes in each file's header.

## Architectural invariants (do not violate)

- **`lib/domain/` must not import `package:flutter/*`.** That layer is pure Dart, unit-testable in isolation. Cross the boundary only via `lib/application/` (Riverpod providers).
- **Free points are the only directly-mutable objects.** Every other object is derived and recomputes from its parents.
- **The `Construction` DAG is the single source of truth.** Rendering, hit testing, undo/redo, and save/load all read from it.
- **All user actions are reversible `Command`s.** No direct mutation of the construction outside a command, with one carve-out: drag *preview* frames mutate directly, and the gesture must end by emitting exactly one command capturing start → end (or rolling the preview back on cancel). One command per drag gesture, never per frame.
- **Save format carries a `version` field.** Bump `constructionFormatVersion` on any change an older reader would *misread*, and add a migration. Additive keys an older reader safely skips (it lands on the defaults the file meant) do not bump it. The encoder stamps the lowest version that reads the document back correctly, not the newest it knows — see PLAN §"The version field is a requirement, not a build number". Version 1 is permanent; `test/fixtures/` is its corpus and every file there must stay v1.
- **No new public API in `domain/` without a test.** Especially `domain/math/`, `domain/projective/`, and `domain/construction/`.

### V2 kernel invariants (migration era — see PLAN §Migration strategy)

- **Projective is canonical; affine is a view.** Migrated objects store homogeneous state; `position`/`line`/`circle` are projections; `isDefined` means "real and finite after projection".
- **New domain code reads projective accessors only** (`projPoint` / `projLine` / `conic`). The affine getters exist for the painter, hit-tester, codec, and unmigrated objects.
- **No new consumers of `lib/domain/math/intersections.dart`.** It is legacy, deleted in Phase 121.
- **Branch orderings are load-bearing.** New intersection functions must agree with the old orderings on real transverse cases (canonical order, circular points I/J filtered) until tracing deliberately replaces per-frame ordering with continuation in Phases 116–117. Don't "fix" branch-ordering tests before then.

## Commands

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after touching freezed / json_serializable / riverpod_generator classes
flutter analyze
flutter test
flutter run -d chrome                                       # web smoke
flutter run -d <device-id>                                  # mobile smoke
```

CI gate: `flutter analyze && flutter test`.

## Conventions

- File naming: `snake_case.dart`. One non-trivial class per file.
- Class naming: `GeoObject` subclasses end in their kind (`Midpoint`, `IntersectionPoint`, `PerpendicularLine`).
- Tests mirror source layout under `test/`. Test file: `<source>_test.dart`.
- Property-based tests via `glados`; golden tests via bare `matchesGoldenFile` (tagged `golden`, excluded in CI, regenerate on macOS).
- Riverpod: prefer `@riverpod`-annotated providers (code-gen) for type safety.
- Formatting: `dart format lib test benchmark` is the norm — the tree was migrated to the tall style in Phase 120c. Earlier sessions banned it because the pending migration made every diff unreadable; that reason is gone. Keep formatting in its own commit when it would otherwise mix with a behaviour change. Generated `*.g.dart` needs none (build_runner already emits tall style).

## What goes where

| Concern | Location |
|---|---|
| Projective kernel (Complex, ProjPoint, ConicMatrix, tracing) | `lib/domain/projective/` |
| Legacy affine math (frozen; shrinking) | `lib/domain/math/` |
| Construction graph & objects | `lib/domain/construction/` |
| Tool state machines | `lib/domain/tools/` |
| Reversible commands | `lib/domain/commands/` |
| Riverpod providers | `lib/application/providers/` |
| Save / Load | `lib/application/persistence/` |
| Canvas, painter, hit test | `lib/presentation/canvas/` |
| Toolbar / inspector / object tree | `lib/presentation/panels/` |
| Theme | `lib/presentation/theme/` |
| Keyboard shortcuts | `lib/presentation/shortcuts/` |
| App entry | `lib/main.dart` |

## When in doubt

- Scope or approach changes → update `docs/PLAN.md` first, then code.
- Phase missing from `docs/TODO.md` → add it before starting.
- Session getting long or context feels heavy → end cleanly, write STATUS, start fresh next time.
