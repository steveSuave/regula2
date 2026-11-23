# Intent: stereometry — construct, cut and measure solids, on a phone

Author: SLevantis, drafted with Claude · Status: draft, awaiting review · 2026-11-17

## Problem

The app is planar. People who teach or solve stereometry problems (pyramids, prisms, cross-sections, dihedral angles, distances between skew lines) cannot use it, and the tools that can do this are either desktop-bound or hard to learn. This is the direction the app develops in next.

## Proposed outcome

Someone can build a textbook stereometry figure on a phone, turn it around, cut it with a plane, and read off the angles, distances, areas and volumes the problem asks for. The readings stay correct while they drag.

**3D is a view of every document, not a separate kind of document.**
- Every figure already lies on the base plane of one space. A single 2D/3D button unlocks the camera; with it off, the app is exactly today's app.
- The existing 2D tools work in the *active plane*: the base plane by default, or any plane or face the user taps. There is no parallel set of "3D versions" of circle, perpendicular, midpoint or intersection.
- In 3D view, one finger on empty canvas orbits and two fingers pan and zoom. Tapping and dragging objects is unchanged. A selected point has a handle that lifts it off its plane.
- The picture reads like a textbook: parallel projection by default, hidden edges dashed, faces translucent, preset views.

**What the first version covers.**
- Objects: points in space, lines and segments, planes (three points, or a line and a point), spheres.
- Constructions: perpendicular from a point to a plane, plane perpendicular to a line, parallels through a point, line ∩ plane, plane ∩ plane, line ∩ line when coplanar, line ∩ sphere, plane ∩ sphere as a circle.
- Solids in one gesture: prism and pyramid by pulling a base polygon up, cube, regular tetrahedron; cone and cylinder after that.
- Cross-sections: a plane cutting a solid gives a polygon that can be measured and built on.
- Measurements: angle between lines (skew included), between a line and a plane, dihedral angle; distance from a point to a plane and between skew lines; area; volume.

**Milestones, each usable on a phone when it lands.**
1. 3D view and camera; existing documents can be orbited.
2. Space kernel, points, lines, planes, the active plane.
3. Solids, cross-sections, dashed hidden edges.
4. Measurements.
5. Spheres, cones, cylinders.

Each milestone gets its own `spec.md` and `plan.md` under this intent, or its own intent if it grows.

## Affected users and systems

- Teachers, students and problem-setters working on solid geometry; existing 2D users, who must notice nothing.
- A new space kernel beside `lib/domain/projective/`; new object kinds in `lib/domain/construction/`; tools; the viewport, painter and hit-tester in `lib/presentation/canvas/`; the save format.

## Constraints

- **Phone is required for the first and every version.** No gesture exists only on mouse or keyboard.
- **2D costs nothing.** With 3D off, every existing document renders and behaves as it does today, and existing goldens are unchanged.
- **Mathematically robust.** Real projective 3-space: points and planes as dual homogeneous quadruples, lines in Plücker coordinates, so join and meet are uniform and coplanar-versus-skew is one test. Geometry inside a plane runs on the existing complex 2D kernel in that plane's coordinates. The figure never lies: skew lines have no intersection point, and only exact degeneracy degenerates.
- **Open to later extension** (calculus: graphs of z = f(x, y), space curves, surfaces). The kind taxonomy, painter, depth ordering and hit-testing accept sampled curves and surfaces as a category, though none ship now.
- **Standing project rules hold**: `lib/domain/` stays free of Flutter imports; every action is one undoable command; the save format is versioned and every v1 document stays readable; no new domain API without a test; anything resting on the rasterizer is tested in a browser.
- **Carried non-goals**: no general quadric ∩ quadric; no GPU rendering stack (`CustomPainter` with depth sorting).
- The prover stays planar (see intent 003).

## Acceptance fixtures

- Pyramid OABCD, square base of side a, equilateral lateral faces: ∠OAC = 45°, base-to-face dihedral = arctan √2 ≈ 54.7356°, face-to-face dihedral = arccos(−1/3) ≈ 109.4712°, stable under a drag of a base vertex.
- A cube cut by a plane through three points on its edges: the section polygon, its side count and its area.

## Open questions

- How exactly does the lift handle work on touch, and how does the user see which plane is active?
- One finger on empty canvas pans today in 2D. Is switching that to orbit in 3D view acceptable, or confusing?
- Hidden-edge dashing is straightforward for convex solids. What is the rule for non-convex figures and for edges hidden by a sphere?
- Branch identity for line ∩ sphere: a pinned ordering rule first; is continuation (as in 2D) needed later?
- Does tracing run inside a non-base plane's chart in the first version, or only static solves there?
- Which save-format version carries 3D, and what does an older reader do with it?
- Perspective projection: optional later, or never?
- The unmerged branch `m-3d-planning` holds an earlier decision record (Phases 190–196). It is input only. It excluded line ∩ line in space, deferred off-plane free points, and used alt-scroll for the camera; this intent reverses all three.
