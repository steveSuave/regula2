# regula2

A cross-platform (web, Android, iOS) dynamic geometry app built with Flutter.

**Live at <https://stevesuave.github.io/regula2/>** — every push to `main` builds
`flutter build web --wasm --release` and publishes it to GitHub Pages.

Construct points, lines, circles, conics and derived objects (intersections,
midpoints, perpendiculars, triangle centers, transforms, loci, macros, …) on an
interactive canvas. Drag a free point and every dependent object updates
instantly: the construction is a DAG in which free points are the only mutable
roots and everything else recomputes from its parents. Every user action is a
reversible command, so the whole history undoes and redoes.

## What "V2" means

This is the second version of **regula**, a Flutter dynamic geometry app whose
kernel computed in ordinary real affine coordinates — `Vec2`, line equations,
circle equations, with epsilon bands deciding when a construction was degenerate.
That version reached ~39 object kinds and ~42 tools, and hit the ceiling the
representation imposes: intersection points that jump to the other branch when a
drag passes a degeneracy, loci that break into pieces at their crossings, and
special cases (parallels, tangencies, points at infinity) handled by hand rather
than by the algebra.

V2 replaces the kernel: **homogeneous coordinates over ℂ, with drags resolved by
analytic continuation** along a path that detours through complex space around
degeneracies — the approach Cinderella established. Under it,

- line ∩ line is *always* exactly one point (possibly at infinity) — a cross product,
- line ∩ conic is *always* exactly two (possibly complex, possibly coincident),
- conic ∩ conic is *always* four, via the pencil `λA + μB`,
- circles become conics through the circular points I = (1, i, 0) and J = (1, −i, 0),
  which also yields Cayley–Klein hyperbolic and elliptic geometry nearly for free,
- being "defined" stops being a property of the construction graph and becomes a
  rendering question: is this value real and finite after projection?

The old repository is private, but nothing here depends on it: this repo carries
the complete V1 git history (the branch point is tagged `v1-final`), V1's
surviving architecture is documented in `docs/archive/PLAN-v1.md`, its affine
kernel is preserved under `test/v1_oracle/` as the agreement oracle the new
kernel is specified against, and the assessment that motivated the rewrite is
`docs/V2-assessment.md`.

## Features

Construction:

- **Points** — free, derived, and constrained points glued to a line, circle,
  arc, or general conic
- **Lines** — line, segment, ray, perpendicular, parallel, angle and
  perpendicular bisectors, tangents, polar, radical axis
- **Circles** — center + rim point, by diameter, by radius, through three points,
  compass (transferred radius), arc, sector, nine-point, inscribed, Apollonius
- **Conics** — through five points, parabola from focus and directrix, ellipse and
  hyperbola from their foci, or from a given eccentricity
- **Intersections** — of any pair of the above, with branch identity preserved
  across drags rather than re-sorted per frame
- **Triangle centers** — circumcenter, incenter, centroid, orthocenter, and the
  circles that go with them
- **Angles** at a vertex or between two lines, including angles of a given size
- **Transformations** — reflection about a line or a point, rotation, translation,
  dilation, applied to points and to whole curves
- **Polygons and shape macros** — triangle, quadrilateral and regular-polygon presets
- **Loci** — traced by the continuation engine, so they follow their curve through
  crossings instead of stopping at them

Document and workspace:

- **Non-Euclidean documents** — switch the whole construction between Euclidean,
  hyperbolic and elliptic geometry from the geometry menu; the absolute is sized to
  your figure, and the switch is an undoable edit like any other
- **Measurements and live text** — distance, area, slope, and text objects with
  `{…}` expression slots that evaluate against the construction as it moves
  (language reference in `docs/EXPRESSIONS.md`)
- **Full undo/redo** over a reversible command stack; one command per drag gesture
- **Object tree, attributes inspector, and keyboard shortcuts**
- **Save/load** to `.rgl` (versioned JSON, with migrations for older documents) and
  **PNG export**
- **Light/dark theme**

In progress: a JGEX-style deductive-database theorem prover with visually replayed
proofs (the predicate vocabulary and its numeric diagram filter have landed), and,
after it, 3D. See `docs/PLAN.md` and `docs/TODO.md`.

## Getting started

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome     # or -d <device-id> for Android/iOS
```

Run the checks — this is also the CI gate:

```sh
flutter analyze
flutter test
flutter test --platform chrome test/web
```

`test/web/` holds the tests whose correctness rests on the browser's rasterizer
rather than on our own arithmetic; a plain `flutter test` skips them.

## Project layout

| Concern | Location |
|---|---|
| Projective kernel (Complex, ProjPoint, ConicMatrix, tracing) | `lib/domain/projective/` |
| Affine chart types and metric helpers | `lib/domain/math/` |
| Construction graph and objects | `lib/domain/construction/` |
| Tool state machines, reversible commands | `lib/domain/tools/`, `lib/domain/commands/` |
| Theorem prover | `lib/domain/prover/` |
| Riverpod providers, save/load | `lib/application/` |
| Canvas, painter, hit test, panels, theme | `lib/presentation/` |

`lib/domain/` is pure Dart — it never imports `package:flutter/*` — and is unit
tested in isolation; the boundary is crossed only through `lib/application/`.

Architecture and decisions live in `docs/PLAN.md`, the phase-by-phase roadmap in
`docs/TODO.md`, and the session log in `docs/STATUS.md`. `CLAUDE.md` states the
invariants any change has to keep.
