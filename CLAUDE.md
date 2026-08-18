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

### V2 kernel invariants (see PLAN §Architecture)

- **Projective is canonical; affine is a view.** Every kind stores homogeneous state; `position`/`line`/`circle` are projections; `isDefined` means "real and finite after projection".
- **Domain code reads projective accessors only** (`projPoint` / `projLine` / `conic`). The affine getters exist for the painter, hit-tester, codec, and the chart reads PLAN §Parameterization sanctions.
- **One degeneracy convention: the projective value is total, the projection is nullable.** A projective accessor answers null only when a parent's is null or the value is the zero triple; "real?", "finite?", "a circle?" are the projection's questions. Stated in full on `GeoObject`, with its three sanctioned exceptions.
- **The old affine kernel is gone from `lib/` (Phase 121).** `intersections.dart`, `angle_bisector.dart`, `circle_relations.dart`, `harmonic.dart` and `tangents.dart` now live in `test/v1_oracle/`, where nothing shippable *can* import them. They are kept as the agreement oracle the projective kernels are specified against — don't extend them, don't "fix" them toward the new kernel, and don't move anything else in there just because it looks old: the test is "no `lib/` consumer *and* something in `test/` compares against it".
- **`Vec2`, `LineEq` and `CircleEq` are view structs, permanently.** They are what projective state *projects to* for the painter, hit-tester, codec and the chart reads of PLAN §Parameterization — not types anything computes geometry in. Reach them through `toVec2` / `toLineEq` / `toCircleEq`, which answer null where there is no real finite value. `LineEq`/`CircleEq` still throw on degenerate arguments; that is a programmer-error contract, so never construct one in a recompute without a guard.
- **Branch orderings are load-bearing.** New intersection functions must agree with the old orderings on real transverse cases (canonical order, circular points I/J filtered) — `test/v1_oracle/` is what that agreement is checked against, and it is permanent because v1 documents are. Tracing deliberately replaced per-frame *ordering* with continuation in Phases 116–117; the static canonical order it re-derives at each pass end did not change.

## Commands

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after touching freezed / json_serializable / riverpod_generator classes
flutter analyze
flutter test
flutter run -d chrome                                       # web smoke
flutter run -d <device-id>                                  # mobile smoke
```

CI gate: `flutter analyze && flutter test && flutter test --platform chrome test/web`.

**`test/web/` is the browser gate, and it exists because a green suite is not evidence about the renderer.** Web is the compile target (Phase 122), and the VM test harness uses a different `dart:ui` implementation. Phase 126d shipped a defect a user found in a browser with every test passing: `Path.combine(PathOperation.difference, rect, oval)` returns the rect *unbroken* on the web renderer when the oval is entirely contained, and the correct annulus on the VM. Anything whose correctness rests on the rasterizer rather than on our own arithmetic — path booleans, fill rules, blend modes, text metrics — belongs in `test/web/` behind `@TestOn('browser')`, which a plain `flutter test` skips. Prefer a formulation with no platform-dependent step at all (an even-odd fill needs no boolean op) and pin *that* on both.

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
| Affine chart types (`Vec2`/`LineEq`/`CircleEq`) + metric helpers | `lib/domain/math/` |
| V1's affine kernel, frozen as the agreement oracle | `test/v1_oracle/` |
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
