# Status Log

Append-only journal of working sessions. Newest entries on top. Each entry should answer three questions in 5–15 lines: **what was done**, **what's next**, **gotchas / open questions**.

Write a fresh entry at the end of every session, before stopping. Do not edit older entries — if something turned out wrong, note it in the next entry.

Rotation: keep roughly the last 10 sessions here; move older entries to `docs/archive/` (e.g. `STATUS-sessions-01-88.md`) every 20–30 sessions. Sessions only need the newest 2–3 entries — don't read the archive unless hunting for old history.

---

## Session 98 — 2026-08-10

**Done**
- **Phase 73 — slope measurement of a line**, on `phase-73-slope-tool` (user request: GeoGebra-style slope readout, chiefly a quick parallelism check). PLAN Measurements sentence + build-order item 56 written first.
- `SlopeMeasurement` (`GeoMeasurement`; one `GeoLine` subject with the `AreaMeasurement` constructor kind-guard, so any concrete line kind — segments, rays, derived lines — measures alike through the carrier). Value = `direction.y / direction.x` (sign-invariant under the carrier's canonical orientation, so parent order never shows); undefined for vertical lines and while the subject is. Anchor derived from `parameterExtent` in the domain — segment midpoint, ray origin (either carrier orientation), `pointOnLine` for infinite carriers — mirroring `labelAnchor` without touching presentation.
- `SlopeTool`: stateless one-tap on the `AreaTool` model — topmost `GeoLine` from `hits` (so a point drawn on the line can't shadow it), everything else ignored, never the point ladder.
- Registration set: codec rows (+ kitchen-sink entry + ill-typed-subject `FormatException` case), `object_kind_label` 'Slope', Measure flyout row 4 + tooltip, `measureActive`, `AppAction.slopeTool` on `⇧ M` (slope is *m*), `main.dart` switch. Slope is dimensionless, so `labelText` formats it through the generic `GeoMeasurement` arm — 2 decimals default, Phase 72 `valueDecimals` row applies for free.
- 1613 tests green (+16: object units incl. vertical-undefined-recovers and both ray orientations, tool funnel incl. undefined-but-committed vertical, toolbar row + highlight, `⇧ M` end-to-end, codec round-trip + rejection), analyze clean.

**Next**
- No queued phase. Possible follow-up: a `slope(l)` text-calculation function (`objectFunctionNames`) — today a slope readout is referenced in texts by its own name (`{m}`), but a line can't be asked directly.

**Open questions / gotchas**
- A vertical line's slope is undefined (`isDefined` false → no label drawn), the codebase's degeneracy convention — GeoGebra shows `∞` instead. Revisit if users expect a visible marker.

## Session 97 — 2026-08-10

**Done**
- **Phase 72 — configurable measurement rounding** (user request: keep 2 decimals as the default, allow more). PLAN build-order item 55 + section notes written first.
- `ObjectAttributes.valueDecimals` (`int?`): decimal digits for the value part of a label — a measurement's value, a segment's shown length, an angle's degrees. `null` (the default) = kind default, 2 for lengths/areas and 1 for angles, i.e. exactly the pre-72 fixed counts — so no existing document or golden changes. Additive with a default → no save-format version bump (the codec's constructor-fallback rule).
- `measure_format.dart` formatters gain `{int? decimals}` with `defaultLengthDecimals`/`defaultAngleDecimals` constants; `labelText` threads the attribute through, so painter, hit rect, declutter and PNG export all agree for free.
- Inspector: Decimals preset row `0`–`5` under Show value, over segments + angles + measurements + expression texts with `{…}` slots (literal-only texts excluded via a new `ExpressionText.hasExpressions` — the row would be a silent no-op). The row shows each object's *effective* count (a fresh length highlights 2, a fresh angle 1); a tap writes an explicit value via one `ChangeAttributesCommand`.
- Text slots (follow-up request in-session): `formatComputedValue` and `TextTemplate.render` take `{int? decimals}` (null = 2; the `-0.00` guard generalized to every count — `-0` at zero decimals also normalizes), `ExpressionText.recompute` bakes `attributes.valueDecimals` into `renderedText`. Because the rendered string lives on the object, `Construction.setAttributes` gains its one carve-out from "attributes are display-only, nothing recomputes": it recomputes `GeoText`s — parents untouched, and nothing can derive from a text, so no cascade.
- 1597 tests green (+9: formatter overrides presentation + domain, `labelText` end-to-end at 4/0/1 decimals, text render + setAttributes re-render + `hasExpressions`, attributes default + round-trip), analyze clean.

**Next**
- No queued phase.

**Open questions / gotchas**
- The `setAttributes` recompute is deliberately `GeoText`-only — recomputing every kind would be near-free except `Locus`, whose sweep-and-restore sampling is expensive and mutates free points; don't widen it casually.
- There's no way back to "kind default" from the inspector once an explicit count is set (equivalent for lengths/texts at 2; an angle set to 1 is likewise identical in effect). An "Auto" chip could clear to null if ever wanted.

## Session 96 — 2026-08-05

**Done**
- **Phase 71 — polar line of a point w.r.t. a circle**, on `phase-71-polar-line` (user request; placement question answered: the row sits *above* Radical axis, directly below Tangents — the Lines flyout orders point+line tools → point+circle tools → the two-circle tool, and polar is point+circle). PLAN Lines-section sentence + build-order item 54 written first.
- Math: `polarLine(pole, CircleEq) → LineEq?` in `circle_relations.dart` — the line `(P − c)·(X − c) = r²`, null while the pole sits on the center. Glados-pinned: perpendicular to the center–pole join at the inverse point, carries the tangent points from outside, La Hire reciprocity (Q on polar of P ⇔ P on polar of Q).
- `PolarLine` (`GeoLine`; point + circle parents on the `TangentLine` model, no branch — the polar is single-valued; tangent at the pole when on the circle, still defined inside). `PolarLineTool` = `TangentTool`'s either-order two-slot collection (circle-flavored taps consumed before the point ladder) committing one line — bare `AddObjectCommand` for a reused point, `MacroCommand` when the ladder built the pole — plus `RadicalAxisTool`'s structural dedupe over identical point + circle instances (only reused points checked; a ladder-built point is new by construction).
- Registration: codec `PolarLine` entry + kitchen-sink round-trip (additive, no version bump), kind label 'Polar line', Lines flyout row + `linesActive` + group tooltip, `AppAction.polarLineTool`, chord `G ⇧ P` (`G P` stays reflect-about-point — the `G ⇧ A`/`G A` precedent), `main.dart` switch.
- Excluded from the transform whitelists like `TangentLine`/`RadicalAxisLine` (circle parent — not an all-`GeoPoint`-parents kind).
- 1589 tests green (+22: math canonical + 3 properties, object units incl. undefined-pole cascade via a line∩circle intersection, 7-test tool funnel, codec, toolbar row/order/highlight, `G ⇧ P` end-to-end), analyze clean.

**Next**
- No queued phase.

**Open questions / gotchas**
- `G ⇧ P` is the third shifted G chord (after `G ⇧ I`, `G ⇧ A`); the resolver's shift flag handles it, nothing new.
- The polar tool's dedupe runs on the *completing* tap only when the point slot holds a reused point — two polars over the same pair are impossible, but a hidden equivalent is not revealed (the `RadicalAxisTool` stance).

---

## Session 95 — 2026-08-05

**Done**
- **Phase 70 — circle by diameter + Lines flyout reorder**, on `phase-70-circle-by-diameter`. `DiameterCircle` (`GeoCircle`; two `GeoPoint` parents — the endpoints of a diameter; center = midpoint, radius = half distance; coincident endpoints give a zero-radius circle, the `CircleCenterPoint` stance). Rides `TwoPointTool` via a `buildDiameterCircle` tear-off — no new tool class. Circles flyout row 2 ('Circle by diameter (the two endpoints)', directly under center + rim), chord `G 2` (pairs with `G 3`'s three-point circle). Group highlight now splits on a `_twoPointCircleBuilders` set ({`buildCircle`, `buildDiameterCircle`}) in both the Points catch-all exclusion and the Circles check.
- Joins the transform + equivalence whitelists (all-`GeoPoint`-parents rule — a diameter maps to a diameter under any similarity). Codec/kind-label/kitchen-sink entries additive, no version bump.
- Lines flyout reorder (user request): Radical axis moves above Polygon (Polygon is now the last row). Safe for drive.js — verified it activates tools by shortcut only, never by Lines/Circles row index (the Phase 68 intersection-row move is precedent for mid-flyout shifts).
- 1567 tests green (+8: object units, codec kitchen sink, toolbar row + highlight + Lines order, `G 2` end-to-end, translated diameter circle), analyze clean.
- Answered the user's division-tool survey (no new tools recommended): harmonic division already exists (`G 4`, Phase 65); golden section is the segment-ratio dialog with `(sqrt(5)-1)/2` (Phase 69 expressions make it exact); geometric mean is not a fixed-ratio point (√(ab) depends on both lengths) but is now a 3-step classical construction — diameter circle over the joined segments + perpendicular + intersection.

**Next**
- No queued phase. If a one-tap geometric mean is ever wanted, it would be a new derived point kind (parents A, B, C collinear → altitude-foot construction), not a ratio preset.

**Open questions / gotchas**
- `G 2` is the first G chord on a digit that neighbors `G 3`/`G 4` semantically but not structurally — nothing shares state; the resolver handles digits like letters.
- The Circles flyout insertion shifted rows 2+ down by one; drive.js was audited (shortcut-driven, File-menu clicks only), but any *future* scripted flyout clicking must re-count.

---

## Session 94 — 2026-08-05

**Done**
- **Phase 67 — circle relations: Apollonius circle & radical axis**, on `phase-67-circle-relations`. Math first: new `math/circle_relations.dart` (the `harmonic.dart` precedent, not `circle_eq.dart` itself) — `radicalAxis` (null for concentric) and `apolloniusCircle` (null at ratio 1, non-positive or non-finite; center `(A − k²B)/(1 − k²)`, radius `k·|AB|/|1 − k²|`), glados-pinned: equal power on the axis, common chord of intersecting circles lies on it, circle points satisfy the ratio, internal/external division points on the circle, A↔B swap inverts the ratio.
- `ApolloniusCircle` (`ThreePointCircle` model; recompute feeds `|CA|/|CB|` straight to the helper — C on A/B degenerates to ratio 0/∞, rejected there) via `ThreePointTool` + `buildApolloniusCircle` tear-off, Circles flyout, `G ⇧ A` (`G A` stays the arc). Joins the transform + equivalence whitelists (twelfth rebuildable curve kind — distance ratios survive any similarity).
- `RadicalAxisLine` (`TwoLineBisectorLine` model minus the branch; identical-instance parents rejected) + `RadicalAxisTool` (`G X`) — the first "click two circles" tool: `PointAndLineTool` slots with `IntersectionTool`'s hit-only curve-tap rules, structural either-order dedupe (the axis is symmetric in its parents). Kept a dedicated class, not a builder-parameterized base, until a second two-circle consumer exists. Excluded from transforms like the other non-point-parent lines. Lines flyout row appended after Polygon.
- Codec/kind-label/kitchen-sink entries additive, no version bump; both flyout rows appended at the end so drive.js indices hold. 1559 tests green (+32), analyze clean. Merged to `main`.

**Next**
- No queued phase — Phases 65–67 (the EucliDraw-inspired batch from Session 89) are all done.

**Open questions / gotchas**
- `G X` is the first G chord whose second stroke is another leader key (`X` opens the macro chords) — the resolver consumes it inside the G chord fine, pinned by the widget test; nothing to do unless a future chord wants `X` as a leader mid-sequence.
- The radical-axis helper epsilon-guards only near-exact concentricity (`defaultEpsilon`), so nearly-concentric circles yield a well-defined but far-away axis — same conditioning stance as the harmonic conjugate's midpoint guard.
- `ThreePointTool` gives the Apollonius tool no structural dedupe (same as `ThreePointCircle` itself); fold in a `TriangleCircleTool`-style refusal if duplicate stacking ever annoys — note the order-sensitivity: only (A,B) swaps *with* C fixed give the same circle when the ratio inverts, so blanket permutation-refusal would be wrong.

---

## Session 93 — 2026-08-05

**Done**
- **Phase 66 — triangle circles: nine-point (Euler) circle & inscribed circle**, on `phase-66-triangle-circles`. Math first: `circumradius`/`inradius` in `triangle_centers.dart`, with glados properties pinning Euler's `|OI|² = R(R − 2r)` and the nine-point-through-side-midpoints fact before any object existed.
- `NinePointCircle` + `InscribedCircle` on a new shared abstract `TriangleCircle` base (the `TriangleCenterPoint` pattern: `vertex1..3`, `computeCircle` hook; `ThreePointCircle` deliberately left un-refactored onto it — different field names, codec untouched). Nine-point center computed via the Euler identity `H = A + B + C − 2O`, one circumcenter call per recompute.
- `TriangleCircleTool` (`TriangleCenterTool` shape, `.new` tear-off builders) with **structural** dedupe like the harmonic tool, but order-insensitive — the circles are symmetric in their vertices, so a vertex permutation still refuses; a different circle kind over the same triangle commits.
- Both kinds joined the transform whitelists (all five transforms — no reflect caveat for circles) and `equivalentExisting`; codec, kind labels, circles-flyout rows (appended after Sector, no index shifts), `G 9` and `G ⇧ I` chords (`_g` grew `_x`'s second-stroke shift flag — first shifted G chord).
- 1527 tests green (+26), analyze clean. Merged to `main`.

**Next**
- Phase 67 (Apollonius circle + radical axis: `radicalAxis`/`apolloniusCircle` math beside `CircleEq`, `ApolloniusCircle` via `ThreePointTool`, `RadicalAxisLine` + the first "click two circles" tool).

**Open questions / gotchas**
- Widget-test gotcha rediscovered: a flyout row can't be re-opened by tapping its *active* group icon — the deactivation double-tap detector swallows the single tap — so per-row tests each start from a fresh editor.
- Web smoke not re-run (domain + widget covered; both new rows appended at the flyout's end, so no drive.js index shifts — the Session 90 precedent).
- `ToolMenuRow` splits only a *trailing* parenthetical; the nine-point row is labeled 'Nine-point circle (Euler circle)' to fit that convention.

---

## Session 92 — 2026-08-05

**Done**
- **Phase 69 — expression-powered numeric dialogs + shortcut in the title**, on `phase-69-expression-dialogs` (user request, follow-on to the Session 91 gotcha). `_parseRatio` now parses the Phase 58 expression language over `EmptyExpressionEnv` — `sqrt(2)`, `pi/6`, `2^0.5`, pasted `×·÷`, and the old `a/b` fractions via the grammar's division — feeding every ratio/angle/length dialog; the angle dialogs inherit degrees-mode trig. Geometry accessors deliberately don't resolve: dialog values are baked at creation, a `dist(A,B)` ratio would go silently stale.
- Guards unchanged: unparseable/non-finite reads as cancel (`evaluateExpression` already nulls non-finite, so the dilation dialog's own `isFinite` check dropped out), zero ratio and non-positive lengths still cancel, side count stays integer-only.
- `_DialogTitle` — title left, dimmed `shortcutDisplayFor` right, the `ToolMenuRow` convention carried into all nine dialog-tools (`G R`, `G H`, `G T`, `G D`, `⇧ C`, `⇧ S`, `X G`, `G M`, `G E`) so the chord is learnable at the point of use.
- 1501 tests green, analyze clean. Merged to `main`.

**Next**
- Phase 66 (nine-point circle + inscribed circle), then Phase 67 (Apollonius circle + radical axis).

**Open questions / gotchas**
- Scientific notation ('1e3') was never supported by the old parser and still isn't — `e` is Euler's constant in the expression language; nobody has asked.
- The cheat sheet's Phase 64 text-calc section documents the expression language for `{…}` slots only; it doesn't mention the dialogs now speak the numeric subset. Add a line there if users don't discover it.

---

## Session 91 — 2026-08-05

**Done**
- **Phase 68 — dilate joins the Transform group**, on `phase-68-dilate-transform` (user request, out of order ahead of 66/67; PLAN updated first, build-order item 51). Follow-on to the session's design discussion: homothety can never be composed from the four isometries (they form a group, |k| ≠ 1 is unreachable), but Phase 24's rebuild-same-kind machinery only needs a *similarity*, so whole-object dilation rides it unchanged.
- `ObjectTransform.dilate` + `TransformObjectTool.dilate({newId, ratio})` — fifth named constructor, rotate model (dialog-baked ratio, transformee then center). All nine curve kinds rebuild; **no orientation caveats**: plane homothety is k·I, det k² > 0, so no `VertexAngle` arm swap and `Sector` is supported even at negative ratios. `equivalentExisting` compares `HomotheticPoint.ratio` exactly.
- `HomotheticPoint` unchanged (codec/labels/object tests untouched) — it's now the dilate transform's image-point kind, the `ReflectedPoint`/`RotatedPoint` role. This also resolves Session 90's homothetic-dedupe gotcha: dilate point mode dedupes via `equivalentExisting`, which the old `TwoPointTool` closure never did.
- Toolbar: Transform flyout += 'Dilate from point (object, then center)…'; the Points homothetic row is gone; 'Intersection of two curves' moved to row 2 (user request). `askDilationRatio` returns a bare double — non-finite *and zero* read as cancel; `G H` rewired, chord row listed with the other transforms.
- 1500 tests green, analyze clean. Merged to `main`.

**Next**
- Phase 66 (nine-point circle + inscribed circle: `circumradius`/inradius helpers in `triangle_centers.dart`, two `ThreePointCircle`-modeled `GeoCircle`s, transform-whitelist entries), then Phase 67.

**Open questions / gotchas**
- The Transform group is now closed over plane similarities by composition (spiral similarity = rotate ∘ dilate about one center); nothing further is *needed* there. Inversion is the one valuable non-similarity, and it cannot ride rebuild-same-kind (segments map to arcs) — its own phase with dedicated kinds if requested.
- `SegmentRatioPoint` still commits through the plain `TwoPointTool` closure with no dedupe (the surviving half of the Session 90 gotcha).
- Ratio dialogs still parse only decimals and one `a/b` fraction; swapping `_parseRatio` for the Phase 58 expression parser (numeric-only env — no geometry accessors, ratios are baked at creation) would allow `sqrt(2)` etc. in all three dialogs. Discussed and shelved pending a user go-ahead.

---

## Session 90 — 2026-08-05

**Done**
- **Phase 65 — derived points: projection, homothety, harmonic conjugate**, on `phase-65-derived-points` (merged the session-89 docs branch to `main` first). Three new `GeoPoint` kinds, so painter/hit-test/labels/naming came free; codec entries are additive, no version bump.
- `ProjectionPoint` (foot of the perpendicular via `LineEq.project`, modeled on `ReflectedPoint`), tool = `PointAndLineTool` + `buildProjectionPoint` tear-off, Points flyout, `G F`. The Points/Lines group highlight now splits on the builder — the one `PointAndLineTool` that builds a point.
- `HomotheticPoint` (finite `ratio` baked at creation, constructor-rejected otherwise; `ArgumentError` normalizes to `FormatException` in decode like `FixedRadiusCircle`). Ratio UX settled per the open question: numeric dialog, segment-ratio precedent (dialog-first closure over `TwoPointTool`, point then center), `G H`.
- New `math/harmonic.dart` `harmonicConjugate` (null when non-collinear / coincident base / C at midpoint), glados-tested: cross-ratio −1, conjugate collinear, involution. `HarmonicConjugatePoint` + dedicated `HarmonicConjugateTool` on `G 4`.
- **Key finding:** `dedupedDerivedPoint`'s numeric probe can *never* confirm a harmonic conjugate — perturbing the roots breaks collinearity, the candidate goes undefined, and the prober conservatively keeps duplicates. The tool dedupes **structurally** instead (identical parents, either base-pair order; `MultiPointTool.constructionObjects` exposes the search space). PLAN/TODO updated with the delta.
- 1491 tests green, analyze clean. Toolbar-test gotcha: flyout labels with a parenthetical render as *two* Text widgets — `find.text` must target the main label only.

**Next**
- Merge `phase-65-derived-points` into `main`, then Phase 66 (nine-point circle + inscribed circle: `circumradius`/inradius helpers in `triangle_centers.dart`, two `ThreePointCircle`-modeled `GeoCircle`s, transform-whitelist entries).

**Open questions / gotchas**
- Homothetic dedupe: `HomotheticPoint` taps go through the plain `TwoPointTool` (no dedupe), so running the same dialog+taps twice stacks a duplicate — same as `SegmentRatioPoint` today; fold both into a structural dedupe if it ever annoys.
- Web smoke not re-run this session (domain + widget covered; `drive.js` never clicks Points-flyout rows — it activates the point tool via the `P` shortcut and the macro section drives the Macros menu's row 1 — so the three inserted rows shift no scripted index).

---

## Session 89 — 2026-08-04

**Done**
- **Docs only — seven EucliDraw-inspired constructions registered as future phases** (user request, after a survey of EucliDraw's tool menus): projection point, homothetic point (dilation), harmonic 4th conjugate, nine-point (Euler) circle, inscribed circle, Apollonius circle, radical axis.
- `docs/TODO.md`: Phases 65–67 appended (grouped by machinery — derived points / triangle circles / circle relations), all boxes unticked.
- `docs/PLAN.md`: build-order items 48–50; new objects added to the Points / Lines / Circles subclass bullets; pure-math bullets extended (`triangle_centers.dart` circumradius + inradius, `CircleEq` radical axis + Apollonius, new `harmonic.dart`).
- No code changes; all seven are new concrete objects within existing sealed kinds, so painting/hit-testing/labels come free and no save-format version bump is needed.

**Next**
- Start Phase 65 — `ProjectionPoint` first: it's a thin object wrapper over the existing `LineEq.project`, with the tool on the `PointAndLineTool` base.

**Open questions / gotchas**
- Homothety ratio input UX: numeric prompt (the fixed-radius-circle precedent) vs. something drag-based — decide at Phase 65 implementation.
- Apollonius circle deliberately takes its ratio from a third clicked point C (`|CA|/|CB|`, circle through C) rather than numeric entry — matches the app's constructive style; revisit if numeric entry is ever wanted.
- Radical axis needs the first "click two circles" tool; model it on `PointAndLineTool` rather than widening `TwoLineOrThreePointTool`.

