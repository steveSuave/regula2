I read the Cinderella page; `mmrc.iss.ac.cn/gex/` refused HTTPS (the site is HTTP-only and fetching upgrades), so I worked from the Chou–Gao–Zhang papers and the JGEX/Newclid literature instead. Here's the assessment.

## The one decision that drives everything

Cinderella's two headline properties — no jumping points, complete loci — are not features. They are consequences of a single representational choice: **the kernel computes in homogeneous coordinates over ℂ, and drags are resolved by analytic continuation along a path that detours through complex space to avoid degeneracies.** Their own claim is that no orientation-based heuristic can ever fix this; there's a proof. So this is a kernel rewrite or it's nothing.

Your kernel is `Vec2(double, double)` with `LineEq(a,b,c)` and `CircleEq(center, radius)`, and it returns `List<Vec2>` of length 0/1/2 with `isDefined` guards threaded through 60 object kinds. That is precisely the design complexification deletes. Under a projective complex kernel:

- line ∩ line is **always** exactly one point (possibly at infinity) — a cross product,
- line ∩ conic is **always** exactly two points (possibly complex, possibly coincident),
- conic ∩ conic is **always** four — found via the pencil `λA + μB`, solving `det = 0` (a cubic) for a degenerate member, splitting it into two lines, intersecting each with a conic.

`isDefined` stops being a graph property and becomes a *rendering* question ("is this point real and finite?"). All the degeneracy guards, the empty-list returns, the `branchIndex` clamping — they go away. `intersections.dart`, `line_eq.dart`, `circle_eq.dart` get replaced by roughly 3k lines of `Complex`, `ProjPoint`, `ProjLine`, `ConicMatrix`. Circles become conics through the circular points I=(1,i,0), J=(1,−i,0), which is also what gives you Cayley–Klein for free: pick a different fundamental conic and you get hyperbolic and elliptic geometry out of the same code. Cinderella ships non-Euclidean geometry as a near-freebie this way. Worth taking.

## What you'd reuse from regula

Of the 21k lines, roughly:

**Reuse ~as-is (~35–40%).** The entire UX shell, which is what you said you want to keep: toolbar (1.3k), the 83-action shortcut table + resolver + cheat sheet, attributes inspector, object tree, theme, export dialog, PNG export, file IO, label layout/declutter/obstacles, measure formatting, grid. Plus `command_stack` and the whole `Command` hierarchy — undo/redo is representation-agnostic. Plus `construction.dart` itself: insertion-order-is-topological-order, dependents map, single notification after the pass. That design is correct and survives verbatim.

**Adapt (~30%).** The 35 tool state machines keep their interaction logic (slot collection, either-order taps, structural dedupe) and change what they emit. The hit tester keeps its (priority, distance) ordering and gains conic distance + depth. The painter keeps its styling and gains conic→`Path` rendering. The codec keeps its shape, rewrites per-kind entries, bumps version.

**Rewrite (~30%), plus a lot of new.** All of `domain/math/`. Every `recompute` in the 60 `objects/` files — mechanical but broad.

Two pieces deserve special mention because they're the ones that get *simpler*:

- **`locus.dart` (704 lines)** is a hand-rolled approximation of complex tracing: boundary bisection, walking *through* a tangency by flipping `branchIndex`, infinity tails. That is you re-deriving continuation without the complex plane. With a real tracing kernel, most of it dissolves into "sweep the driver, let continuation keep branches consistent," and the figure-eight loci close for the right reason instead of by special case.
- **`point_coincidence.dart`** is already Cinderella's randomized theorem proving — perturb the shared free roots, keep coincidences that survive. You independently built the thing Cinderella uses to decide whether a theorem holds. It's also *exactly* the "construct numerical diagrams as models" component the deductive-database method needs to stay tractable. Keep it; it becomes the filter in front of the prover.

## What to borrow from JGEX

The Chou–Gao–Zhang deductive database method (JAR 25(3), 2000): fix a predicate vocabulary — `coll`, `para`, `perp`, `cong`, `cyclic`, `eqangle`, `eqratio`, `midp`, `simtri`, `contri` — and a rule set (JGEX ~75 rules; AlphaGeometry's DD trims to ~20), then forward-chain to a fixpoint. The whole thing is tractable only because the numeric diagram acts as a model: you never attempt a deduction that isn't numerically true. That's the load-bearing trick, and you already have the diagram and the perturbation machinery.

For your congruent-points goal, the honest architecture is hybrid, not pure: numeric probe as the cheap filter (near-zero false negatives, it's what you run today), then DD to *certify and explain*. The UX payoff is large — instead of silently merging two points, you say "these coincide by Varignon's theorem" and show the deduction chain. JGEX's distinctive contribution beyond the proving is the **visually dynamic proof presentation**, and that's the part worth stealing outright, because a proof you can watch replay on the figure is what makes this a product rather than a research artifact.

Bundle the full-angle method as a second engine (cheap, complements DD on angle-chase problems). **Skip Wu's method and Gröbner bases initially** — complete but they produce unreadable proofs and want exact rational polynomial arithmetic, which in Dart means hand-rolling over `BigInt`. Bad effort/reward for v1. The area method (Chou–Gao–Zhang) is the better third engine if you want one: readable proofs, elimination on constructive statements, arithmetic-light.

Licensing: Cinderella is proprietary — take the mathematics from the published papers (Richter-Gebert & Kortenkamp; Richter-Gebert's *Perspectives on Projective Geometry*), not code. JGEX is open Java; AlphaGeometry's DDAR and Newclid are open Python. Those are legitimate rule-set sources.

## Flutter/Dart-specific difficulty

- **No complex type.** Write your own; Dart has operator overloading so it reads fine. The problem is allocation: every complex op allocates, and tracing does thousands of steps × dozens of objects × complex arithmetic per drag frame. Plan for `Float64List` struct-of-arrays in the tracing inner loop from the start, not as a later optimization.
- **No isolates on web.** This is your real cross-platform constraint given you ship to Chrome. The prover and heavy tracing want to be off the UI thread; `Isolate.run` covers mobile/desktop, web gets nothing. Either make the prover cooperatively chunked (yield to the event loop between fixpoint rounds) or plumb a real Web Worker. Decide this before writing the prover, because it dictates whether the engine is written as a straight-line algorithm or a resumable state machine. Benchmark dart2wasm vs dart2js early — numeric throughput differs meaningfully.
- **3D rendering is easier than it sounds.** Flutter's `Canvas` is 2D, but DGS 3D is wireframe with depth cueing, not textured meshes. Project yourself with a 4×4 camera and paint with `CustomPainter`, painter's-algorithm sorted. You already have viewport rotation from Phase 43; this is an extension of that, not a new rendering stack. Don't reach for `flutter_gpu`/`flutter_scene`.

## On the 3D UX

Your binding instinct is fine (alt-scroll orbit, ctrl-alt-scroll for z), but input binding isn't the hard part. The hard part is that **a 2D click doesn't determine a 3D point.** The established answer is CAD workplanes / GeoGebra's approach: a click casts a ray, snaps to existing objects if it can, and otherwise lands on the current construction plane; a modifier lifts it off that plane. Your ctrl-alt-scroll maps naturally onto "raise/lower off the plane."

Two scoping recommendations. First, keep 2D as the z=0 degenerate case of one kernel, but expose it as a *mode* with a locked camera and plane-constrained construction, so none of your existing one-tap tool UX gets taxed by 3D generality. Second, bound the 3D object taxonomy hard: point, line, plane, sphere, circle-as-plane∩sphere, conic-in-a-plane, polyhedra. Explicitly exclude general quadric ∩ quadric — that's a quartic space curve and it will eat a phase on its own for almost no user value.

## Rough effort

You're proposing four research-grade subsystems, not one. Ordered by payoff-per-risk:

1. **Complex projective kernel + conics + conic∩conic** — highest payoff, highest reuse, and it's what makes conic/conic intersections a one-liner instead of a special case.
2. **Tracing/continuation** — hardest per line. Adaptive step control (roots must move less than half their pairwise separation), root matching between steps, degeneracy detection, complex detour. Fiddly, needs heavy property testing, and robustness is a long tail. Budget generously.
3. **Port the 60 objects + 35 tools onto the new kernel** — broad and mechanical.
4. **DD prover + rules + proof replay UI** — self-contained, independent of 1–3, and the piece where your existing numeric probing gives you a real head start.
5. **3D last** — biggest new surface, most UX design, least leverage from what exists.

Total: on the order of 15–20k new lines against your 21k base, so call it 1.5–2× the effort that's already gone into regula. The reuse story is genuinely good — but the reuse is concentrated in the shell and the graph, and essentially none of it is in the math.

**Sources:** [Cinderella theoretical background](https://doc.cinderella.de/tiki-index.php?page=theoretical+background) · [Geometry Expert / JGEX](http://www.mmrc.iss.ac.cn/gex/) · [An Introduction to Java Geometry Expert](http://www.mmrc.iss.ac.cn/~xgao/paper/jgex.pdf) · [A Deductive Database Approach to Automated Geometry Theorem Proving and Discovering](https://www.semanticscholar.org/paper/A-Deductive-Database-Approach-to-Automated-Geometry-Chou-Gao/0b65b286e0be01972d67da0f7ab7dc01ad46f40a) · [Visually Dynamic Presentation of Proofs in Plane Geometry](https://link.springer.com/article/10.1007/s10817-009-9163-4) · [Newclid: A User-Friendly Replacement for AlphaGeometry](https://arxiv.org/pdf/2411.11938) · [Towards a geometry deductive database prover](https://link.springer.com/article/10.1007/s10472-023-09839-0)
