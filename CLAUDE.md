# Claude Code Working Notes — regula

This file is auto-loaded into every Claude Code session for this project. **Read it first.**

## What this project is

Cross-platform (web / Android / iOS) dynamic geometry app written in Flutter. Construction-graph based: free points are the only mutable roots, every other object derives from its parents and recomputes when they change. See `docs/PLAN.md` for the full architecture and build order.

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
- **Save format carries a `version` field.** Bump it on any breaking schema change and add a migration.
- **No new public API in `domain/` without a test.** Especially `domain/math/` and `domain/construction/`.

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
- Property-based tests via `glados`; golden tests via `golden_toolkit` (tagged so they can be skipped on platforms where they're flaky).
- Riverpod: prefer `@riverpod`-annotated providers (code-gen) for type safety.

## What goes where

| Concern | Location |
|---|---|
| Pure geometry math | `lib/domain/math/` |
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
