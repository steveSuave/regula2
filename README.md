# regula2

A cross-platform (web, Android, iOS) dynamic geometry app built with Flutter —
the V2 of [regula](https://github.com/steveSuave/regula), migrating the kernel to
**homogeneous coordinates over ℂ** with drags resolved by analytic continuation
(Cinderella-style): intersection points that never jump, loci that close, conics
as first-class objects, and — down the road — a geometry theorem prover with
replayable proofs and 3D. The full V1 git history is carried in this repo (branch
point tagged `v1-final`); the roadmap lives in `docs/PLAN.md` and `docs/TODO.md`,
and the assessment that motivated the rewrite in `docs/V2-assessment.md`.

Construct points, lines, circles, and derived objects (intersections, midpoints,
perpendiculars, triangle centers, transforms, macros, …) on an interactive canvas.
Drag a free point and every dependent object updates instantly — the whole
construction is a DAG where free points are the only mutable roots and everything
else recomputes from its parents.

## Features

- Construction tools: points, lines, segments, rays, circles, arcs/sectors, angles,
  intersections, and common triangle centers
- Transformations: reflection, rotation, translation, dilation
- Shape macros (triangle, quadrilateral, and regular-polygon presets)
- Full undo/redo via a reversible command stack
- Object tree, attributes inspector, and keyboard shortcuts
- Save/load to local JSON, PNG export
- Light/dark theme

## Getting started

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome     # or -d <device-id> for Android/iOS
```

Run the checks:

```sh
flutter analyze
flutter test
```

## Project layout

Architecture, conventions, and build history live in `docs/PLAN.md`, `docs/STATUS.md`,
and `docs/TODO.md`. See `CLAUDE.md` for the working invariants (domain/application/
presentation layering, command pattern, etc.).

## Demo deployment
V1 remains usable at: https://stevesuave.github.io/regula/ (regula2 has no remote/deployment yet).
