# Status Log

Append-only journal of working sessions. Newest entries on top. Each entry should answer three questions in 5–15 lines: **what was done**, **what's next**, **gotchas / open questions**.

Write a fresh entry at the end of every session, before stopping. Do not edit older entries — if something turned out wrong, note it in the next entry.

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

## Session 88 — 2026-08-03

**Done**
- **Bugfix: shortcuts went dead after renaming an object in the inspector** (user report), on `fix-shortcuts-dead-after-rename`. Root cause: leaving a text field (Enter's default `unfocus()`, or the name editor being rebuilt under a new `ValueKey` while focused) drops primary focus onto the enclosing *FocusScope*, and a scope's children are off the key-event dispatch path — so `AppShortcuts` stopped seeing keys until the next canvas click (whose pointer-down `refocus` was the only revival).
- Fix at the shortcut layer, covering every text field at once: `_AppShortcutsState` listens to `FocusManager` and reclaims focus whenever the primary focus lands on a scope that is an ancestor of its node (focus fell on "nothing"). Foreign scopes (dialogs) are not ancestors and are left alone; the canvas `refocus` stays as belt-and-braces.
- Tests: two regressions in `editor_shortcuts_test.dart` — rename committed with Enter, and leaving the field unchanged; both then expect `P` to activate the point tool with no canvas click. 1456 green, analyze clean.

**Next**
- Merge `fix-shortcuts-dead-after-rename` into main after review.

**Open questions / gotchas**
- The reclaim check is `primary is FocusScopeNode && ancestors.contains(primary)` — if a nested FocusScope is ever introduced *inside* the editor around a panel, focus dropped onto that scope would also be reclaimed (correct today, worth re-checking then).

---

## Session 87 — 2026-08-01

**Done**
- **Phase 64 — cheat sheet documents the text-calculation language** (user request), on `phase-64-cheat-sheet-text-calc`. New `ShortcutSection.textCalc` ("Text calculations (G E, then {…})") rendered from display-only rows: the `{…}` slot idea with an example, the eight geometry accessors, bare-name sugar, operators (pasted `×·÷` included), the numeric functions (trig in degrees), `pi`/`e` shadowing, and the `?` undefined marker.
- `GestureRow`/`gestureRows` generalized to `InfoRow`/`infoRows` — the display-only row concept now covers gestures *and* language reference, no new render path in `cheat_sheet.dart`.
- Tests: the existing every-section render loop picks the new section up automatically; a spot check finds `dist(A, B)`; a new registry pin walks `objectFunctionNames` / `numericFunctionNames` / `constantNames` and asserts each is mentioned in the section, so adding an accessor without documenting it fails the suite. 1454 green, analyze clean.

**Next**
- Candidate cheat-sheet gaps spotted while in there (not yet done, need user's pick): canvas move/select gestures are undocumented — shift-tap toggle, empty-canvas rubber-band (shift adds), long-press as touch shift-tap, label dragging (40 px leash) and text body drags; numeric dialogs accepting fractions (`5/2`); double-tap on the active toolbar tool deactivating it.

**Open questions / gotchas**
- The registry pin is substring-based (`contains`) — cheap and adequate as a "did you mention it" tripwire, not a semantic check.
- Two rows now display `?` (app-level toggle, undefined marker) — fine, different sections; no test counts `?` occurrences.

---

## Session 86 — 2026-08-01

**Done**
- **Phase 62 — angles show their value, not their name, by default** (user request), on `phase-62-angle-value-default`. One-site change in the `_nameObjectsIn` auto-name funnel: `GeoAngle` joins the `hideLabel` group (like lines/circles, the Greek name still allocates and shows in the tree/inspector) and additionally gets `showValue: true` — a fresh angle's canvas label is just its measure (`90.0°`). Both remain plain per-object attributes, so the inspector toggles flip either back at will.
- Existing saves are unaffected: the funnel only touches unnamed, visible objects at creation time, and attributes are baked into the object (undo/redo safe, no re-derivation).
- Test: commit a `VertexAngle` through the funnel, expect name `α`, `labelVisible` false, `showValue` true. 1450 green, analyze clean.
- **Phase 63 — angle labels on the bisector, past the arc** (user follow-up: the value sat behind/inside the marker; decided against a bigger fixed offset — direction-blind — and against growing the global default — points/segments are correctly snug), on `phase-63-angle-label-bisector`. New `labelBaseTopLeft(object, viewport, textSize)` in `label_layout.dart`: the screen point the `(labelDx, labelDy)` nudge is measured from. Angles center the text on the wedge bisector at `angleMarkerRadius + 4 + support(text box along bisector)` — the support term keeps the box's near *edge* clear of the arc even for wide values on a horizontal bisector; other kinds keep `worldToScreen(labelAnchor)` exactly.
- The three placement sites all route through the helper so they can't drift: painter `_drawLabel`, `labelScreenRect` (label-drag hit rect), and the declutter scene's `LabelBox.anchor` (recovered as `rect.topLeft − offset` since only the rect knows the text size there). Fresh angles bake `labelDx/labelDy: 0` in the funnel; dragging an angle label still works as a nudge relative to the moving bisector base.
- Tests: bisector-centering/clearance/radius-tracking/nudge units in `label_layout_test.dart`, funnel test extended; `measures_light/dark` goldens regenerated — the diff was exactly the value text moving off the right-angle square. 1453 green, analyze clean.

**Next**
- No queued phase.

**Open questions / gotchas**
- Hidden macro-scaffolding angles (none exist today) would skip the funnel case entirely — they'd keep `showValue: false`, which is the right dormant state anyway.
- Old saves with angles keep their baked (6, −18) offset, so their labels land at bisector base + that small skew — mild, self-heals if the user drags the label. No migration felt worth it.
- A dragged angle label follows the wedge as the angle changes (the base moves, the nudge is relative) — segment-midpoint precedent, deliberate.

---

## Session 85 — 2026-08-01

**Done**
- **Phase 61 — rotation-preserving Fit + compass size tweak** (user feedback on 60/43), on `phase-61-rotation-preserving-fit`. PLAN updated first with the decided triad: **compass** levels without moving, **Fit** frames without leveling, **Reset** stays the full home (origin / 100 % / level) — user asked "same for Reset?", answered no: zoom-to-100 % already keeps the angle, Reset's role is the canonical view.
- `visibleWorldBounds` / `fittedViewport` gain optional `rotation`: bounds are taken in the rotated view frame (`include` rotates contributions by +θ; a circle's disc rotates as its *center* ± r — rotating box corners would misplace the box), the state comes from `CanvasViewport.pinning` (bounds center → canvas center), which reduces exactly to the old pan solve at θ = 0 (cos 0 / sin 0 are exact). `_fitConstruction` passes the live angle; PNG export's fit framing still exports unrotated (default 0).
- Compass chip slimmed on feedback ("slightly smaller"): needle 36 → 30 px, padding 14/10 → 12/8, readout labelLarge → labelMedium.
- Tests: 3 new fit units (π/2 pair scales by canvas height, arbitrary angle centers the extremes on canvas, rotated disc keeps the 60 × 60 box) + the fit/reset widget test wanders off rotated and pins the kept angle; the final Reset assertion now also proves Reset clears rotation. 1449 green (26 goldens), analyze clean.

**Next**
- No queued phase.

**Open questions / gotchas**
- Fit under rotation frames the *rotated* AABB of the world AABB contributions per kind — for long diagonal constructions this is tighter than fitting the world box, not looser; no known caveat.
- Memory nuance recorded: the large-visual-defaults preference is about content, not chrome (36 px chip icon was too big, 30 px settled).

---

## Session 84 — 2026-08-01

**Done**
- **Phase 60 — compass relocation** (user feedback: the app-bar compass was too easy to miss), on `phase-60-compass-corner`. PLAN updated first: the compass moves to a **floating chip on the canvas's top-right corner** — the map-app convention, larger and on the content it levels.
- `_compassButton` (app-bar `IconButton`) → `_compassChip`: a `Positioned` (12 px inset) in the canvas `Stack`, mounted *before* `RegionPickOverlay` so an export pick still owns the surface. Elevated `Material` chip (`surfaceContainerHigh`, radius 16), 36 px needle in `primary` at `−rotation`, **live signed-degrees readout** under it (previously tooltip-only; tooltip now just "Straighten the view"). All 43b behaviors kept: mounted only while rotated, click levels about the canvas center keeping pan/zoom, own `Consumer` on a rotation select. Key `compass-button` unchanged.
- Leaving the app bar retires the conditional icon-row mount — web-smoke icon indexing is now rotation-independent by construction.
- Compass widget test extended: chip rect pinned to the canvas top-right insets, `29°` readout at 0.5 rad, level-view absence and center-pivot leveling as before. 1446 tests green (26 goldens), analyze clean.

**Next**
- No queued phase.

**Open questions / gotchas**
- The session opened with "can we make viewport rotation undoable?" — cancelled by the user before any code. Design sketch if it returns: an application-layer `SetViewportCommand` (before/after `ViewportState` snapshots + injected setter, construction argument unused) on the shared `CommandStack`, emitted once per settled rotation interaction; PLAN's Phase 43 bullet still says "not undoable (viewport precedent)".
- The chip overlaps canvas content in the top-right corner while rotated (it's an overlay by design); at very small canvas widths it stays 12 px off the inspector edge — no width gate was added.

---

## Session 83 — 2026-07-31

**Done**
- **Phase 43b — desktop rotation bindings** (user feedback: "make trackpad work, ideally also for web"), on `phase-43b-desktop-rotation`, merged to `main`. PLAN updated first with the key finding: browsers never expose the trackpad rotate gesture (only Safari's non-standard `GestureEvent`), so web rotation must be a synthetic binding.
- **Alt/Option + scroll rotates about the cursor** — linear 0.003 rad/px (≈17°/notch) through the same pointer-signal plumbing as Ctrl-zoom, so mouse wheels and trackpad two-finger swipes both drive it. Shift was rejected as the modifier: browsers convert Shift+wheel to horizontal deltas.
- **Quiet-period settle**: wheel streams have no end event, so 250 ms after the last rotate event the shared `TwistGate.settled` snap runs about the last cursor position (`_settleRotationAbout(focal)` extracted from the touch path; timer cancelled on new events, nav-gesture start, dispose).
- **Compass chip**: app-bar button mounted only while rotated (own `Consumer` over a rotation select — twist frames rebuild one button, not the screen; conditional mount keeps drive.js icon indexing intact at level view), needle turns with the content, tooltip shows signed degrees, click levels about the canvas center keeping pan/zoom — the previously-missing way back to straight without Reset/Fit.
- **Native trackpad twist** (macOS, non-shipping): the `TwistGate` also mounts while a `Listener` pan-zoom pointer is active. The widget test via `TestGesture.panZoom*` confirmed the recognizer counts a pan-zoom as two pointers and folds its rotation into `details.rotation` — no nav-entry changes needed.
- Cheat-sheet `Alt/Option + scroll` gesture row. 1446 tests green (26 goldens), analyze clean.

**Next**
- No queued phase.

**Open questions / gotchas**
- Alt+scroll on Firefox/Linux natively means history-nav; the web engine's `preventDefault` on canvas wheel events should suppress it — verify in the next real-browser smoke run.
- The wheel settle is time-based (250 ms), so a very slow continuous Alt+scroll near level can snap mid-stream between notches; harmless (the next notch re-rotates from 0) but worth knowing.
- A fix rode along: Session 82's TODO edit had accidentally swallowed the "## Phase 44 — Line clipping modes" header, folding 44's items into 43b's section; restored.

---

## Session 82 — 2026-07-31

**Done**
- **Phase 43 — viewport rotation (two-finger twist), complete.** Five commits on `phase-43-viewport-rotation`, merged to `main`:
  1. `ViewportState.rotation` (radians, CCW on screen) + generalized `CanvasViewport` transforms — rotation composes in the y-up frame *before* the flip, so `pan` keeps its world-point-at-origin meaning; `pinning` gains the term; `zoomedAbout`/`pannedByScreen`/`panBy`/`zoomBy`/nav-baseline preserve it; Reset and File > New clear it, zoom-to-100 % keeps it, Fit emits 0.
  2. Twist gesture: pure `TwistGate` per navigation gesture — arms past 0.1 rad with a rebaseline (no jump), settles a release within 2° back to exactly 0 (normalized to (−π, π], about the last focal). Touch-only v1, gated on the Listener's first-pointer kind. **Gotcha found by test: Flutter's `details.rotation` is a raw atan2 difference that leaps by 2π when the finger line crosses ±π — the gate unwraps successive samples.**
  3. Painter: new `worldToScreenAngle`/`worldToScreenDirection` helpers replace the bare `-angle` negations (arcs, sectors, angle markers, right-angle square); grid/axes/ticks become world segments over the visible world quad's AABB — at rotation 0 this reduces exactly to the old lines, all 24 pre-43 goldens byte-identical. Infinite lines/rays were already screen-space-safe; labels stay upright.
  4. Band select: `objectsContainedIn(within, cardinalAngle:)` — screen-space inclusive containment, circle extremes along the band frame's cardinals (−rotation).
  5. Persistence + export: additive `rotation` viewport key (absent → 0, no bump); current-view *and region* framings carry rotation, fit exports unrotated. Rotated-scene golden ×2 themes; twist cheat-sheet gesture row.
- 1442 tests green (26 goldens included), analyze clean.

**Next**
- No queued phase. Candidate follow-ups: a desktop binding for rotation (explicitly out of v1 scope), web smoke re-run on a release build if any pixel-level doubt arises (widget + golden coverage was deemed sufficient — drive.js has no touch-twist driver).

**Open questions / gotchas**
- `TwistGate` rebaselines at arming, so twisting deliberately and hand-twisting back to the exact start leaves ~0.1 rad of view angle (inside the snap only if within 2°). Accepted trade-off vs. a visible 5.7° jump at arming.
- The rotation snap-back pivots about the gesture's last focal; a nav gesture that never updated (down-up with no move) settles about the canvas origin instead — harmless, nothing rotated.
- `_branchExtremes`' cardinal set is *not* symmetric in the sign of the frame angle ({−θ + kπ/2} ≠ {θ + kπ/2}); the canvas passes `−viewport.state.rotation` — don't "simplify" the sign away.

---

## Session 81 — 2026-07-31

**Done**
- User request: construction files now use a **`.rgl` extension** instead of `.json`. Content is unchanged (still plain indented JSON); only the dialogs changed in `file_io.dart`: save offers `construction.rgl` and allows only `rgl`; open accepts both `rgl` and `json` so pre-rename files stay openable (`_saveExtensions` / `_openExtensions` split).
- Updated the two filename references in `file_menu_test.dart`. 1411 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) remains the queued phase.

**Open questions / gotchas**
- No OS file-type registration was added for `.rgl` — double-clicking a file won't launch the app; open-from-dialog only.

---

## Session 80 — 2026-07-31

**Done**
- Bug fix (user report): **circles vanished on phones at high zoom** while part of the rim should still be on screen. Cause: the painter handed `drawCircle`/`drawArc` the full screen-space radius; past a few thousand px, mobile GPU backends (Impeller / fp16 paths) silently drop circle-oval primitives — desktop tolerates it, so it only showed on mobile. Straight lines never had the problem (the infinite-line far-endpoint strategy relies on that).
- Fix: new `large_radius_arc.dart` — past `largeRadiusThreshold` (2048 px) circles/arcs/sectors are drawn as sampled polylines covering only the angular window that can reach the canvas (tangent-cone bound from the padded canvas's bounding circle), so every vertex stays near the viewport. Sagitta ≤ 0.05 px, capped at 4096 segments. Stroke, dash, halo, sector radii and fills all routed; a viewport deep inside a huge disc fills the whole canvas rect, a fully off-screen circle draws nothing.
- Tests: `large_radius_arc_test.dart` (window cases incl. rim-far-but-center-near, overlap wraparound/negative sweep, sagitta walk) + painter smoke test at 500k px radius over four pan regimes. 1411 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) remains the queued phase.

**Open questions / gotchas**
- The huge-radius sector stroke draws disjoint contours (arc pieces + two radii), so its dash phase differs from the small-radius closed walk — invisible at these sizes.
- `arcWindowOverlap` returns pieces in the *arc's* frame (not the window's) — the sector fill walk depends on that ordering; don't "simplify" it back.

---

## Session 79 — 2026-07-23

**Done**
- User request: tool flyout rows now render their parenthesized explanation ("Ray (origin, then direction)") as a **second, smaller dimmed line under the tool name** instead of inline. Done centrally in `ToolMenuRow` (toolbar.dart): a regex splits the existing `Name (explanation)…` label convention — no call-site changes, so main.dart's Text/Hide-Delete/grid groups got the treatment for free. The trailing `…` of dialog tools stays on the name line; explanation uses `bodySmall` + `onSurfaceVariant`.
- Tests that tapped full labels updated to tap the name-only first line (toolbar_test, geometry_canvas_test). 1397 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) remains the queued phase.

**Open questions / gotchas**
- The label strings still carry the parentheses as the source of truth; `ToolMenuRow` is the only splitter. If a future label needs literal parens in the *name*, the convention breaks — restructure `ToolItem` to separate name/description fields then.

---

## Session 78 — 2026-07-22

**Done**
- Phase 59 (user request): **two-stage cancel mid-tool**. With a multi-input tool armed (midpoint after its first tap), there was no way to drop just the pending input — undo also popped the last committed command, Esc also left the tool. Now Esc and Ctrl+Z both consume the pending input first (tool stays active, previews clear, stack untouched) and only act at app level — deactivate / undo — on a second press.
- Mechanism: new `Tool.hasPartialInput` getter (true exactly while `reset()` would discard collected input; implemented across the hierarchy, single-shot tools hardwire false), consulted in `main.dart`'s `_handleShortcut` before `resetInProgress()` vs the old behavior. Esc got its own `AppAction.cancelOrReturnToMoveSelect` so `V` remains a *direct* switch to move/select — the two keys shared an action before.
- Tests: `has_partial_input_test.dart` (lifecycle across `MultiPointTool` / `TwoLineOrThreePointTool` / slot tools / single-shot), an end-to-end widget test of both two-stage flows, resolver expectation updated. 1394 green, analyze clean.
- Follow-up (same session, user request): the app-bar undo **button** now two-stages exactly like the shortcut — both land in one `_undo()` funnel. The button enables while a tool holds pending input even on an empty stack (the first press has work to do), via a narrow `hasPartialInput` select that flips only on arm/disarm, so the scaffold still doesn't rebuild per collected tap. The old canvas test pinning the one-press collateral behavior updated to the two-press contract. 1396 green.

**Next**
- Phase 43 (viewport rotation) remains the queued phase.
- Touch has no Esc: a cancel-pending gesture for mobile (re-tapping the active tool's own toolbar button was floated) is the natural follow-up if users ask.

**Open questions / gotchas**
- (resolved same session, see follow-up above) The toolbar undo button initially went straight to the stack; it now shares the shortcut's two-stage funnel.

---

## Session 77 — 2026-07-22

**Done**
- User request: a dedicated **Move/select button** leads the toolbar (`Icons.near_me` cursor arrow, key `move-select-button`) — one tap calls `toolProvider.deactivate()`. On touch there is no Esc key and the double-tap-to-deselect gesture is clumsy (it fights the flyout's opening tap), so this is the primary mobile path back to move mode, GeoGebra-style.
- The button is primary-tinted exactly while `tool == null` — the highlight is derivable state, so Esc, `V`, and double-clicking an active group highlight it automatically with no new wiring. Tooltip carries the keys (`Esc or V`) since the button has no flyout rows to show them in.
- +1 widget test (highlight swap tool↔move, one-tap deactivation). 1387 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) remains the queued phase.

**Open questions / gotchas**
- The double-tap-to-deselect affordance on group icons stays — desktop users may have the habit — but the Move button is now the advertised path; if double-tap's gesture-arena delay on the active group's opening tap ever annoys, it can be dropped without losing deselect.

---

## Session 76 — 2026-07-22

**Done**
- Phase 58 (user request, design agreed up front): the **combined text & calculation tool**. One `Text…` row (first in the Text & labels group, `G E`) — tap the canvas, type content in a dialog, get an `ExpressionText` on the canvas; `{…}` slots evaluate live (`perimeter = {dist(A,B)+dist(B,C)+dist(C,A)} cm`) and re-render as the referenced geometry drags. Tapping an existing text (its label rect counts) re-opens the dialog pre-filled and replaces it in one undo step.
- Expression engine (`domain/math/expression.dart`, net-new): recursive-descent parser + evaluator. `+ − * / ^` (unary minus below `^`: `-2^2 = −4`), `pi`/`e`, sqrt/trig/abs/round/floor/ceil/min/max — trig in **degrees** so it composes with `angle()`. Typed math symbols (`× · ÷ −`) normalize at the tokenizer. Parse throws only `ExpressionFormatException`; evaluation never throws — anything unknown/degenerate/non-finite is null, rendered `?`.
- Geometry binding (`construction/text_template.dart` + `text_evaluator.dart`): accessors `dist/len/angle/area/radius/perimeter/x/y` (len/area follow the Length/AreaMeasurement semantics for arcs/sectors) plus bare-name sugar (segment → length, measurement → value, angle → degrees). Function names and arities validate at parse time, so the dialog's inline errors are specific.
- `GeoText` is the eighth sealed kind (`renderedText` + fixed `anchor`); `ExpressionText` binds names → instances once at creation (renames never break values; the source string goes stale until the next edit — accepted v1). Rides the label machinery wholesale: painter/hit-tester/label/declutter/fit/naming/tree/codec switch cases added, plus the three non-compiler-flagged sites (body drag disabled in `DragSession.start`, canvas label-rect tap loop, auto-namer `hideLabel` group). Codec type is additive — no version bump.
- Tool seam: additive `ToolInput.text`; the canvas pre-gates `TextTool` like `DeleteTool` (dialog is presentation, tool stays pure), re-checks after the async gap, and the tool itself quietly `ToolIgnored`s stale references. Editing = delete + re-add under one `MacroCommand`, same id and attributes — texts are not referenceable, so the cascade is always just the text.
- Tests: parser (incl. glados fuzz + random-AST round-trip), template, evaluator (incl. the bare-`e`-vs-`len(e)` pin), object recompute/cascade through a live `Construction`, codec round-trip + tampered-parents rejection, tool unit tests, end-to-end flow widget tests (create/cancel/validation-error/edit/undo, `G E`). 1377 green, analyze clean, web release build compiles.
- Follow-up (same session, user request): `docs/EXPRESSIONS.md` documents the complete expression language — operators/constants, every geometry accessor with its per-kind semantics (len/area mirror the measurement tools by design), the bare-name shorthand table, the numeric function list, degree conventions, and the `?` degradation rules. Linked from PLAN's `expression.dart` bullet; keep it in lockstep with the registry when functions are added.
- Follow-up (same session, user feedback: stroke width / line style are irrelevant to texts, and the composed label confuses the expression): the inspector's stroke-width and line-style rows now exclude texts **and measurements** — both are pure label text (the label pass reads font size and color only), so the rows were silent no-ops all along; measurements just went unreported since Phase 38. The show-label toggle also hides on text selections, because `labelText` now renders a text's content bare and never composes `name = content` — the content is user prose that can itself contain `=` (`a = AB = 5.00` read as a bogus chained equation). A text's name lives in the tree and inspector only. +2 tests, 1386 green.
- Follow-up (same session, user feedback: "dragging seems weird — why only a small radius?"): the v1 label-drag repositioning and its 40 px caption clamp are gone for texts. Body-dragging a text now moves its **world anchor** freely — mutable `ExpressionText.anchor`, `Construction.moveTextAnchor` (no dependents to recompute: texts aren't referenceable), `MoveTextAnchorCommand` (one per gesture, the free-point contract), `_TextAnchorDragSession` (total-delta preview, rollback on end/cancel, no grid snap — annotation, not geometry), and the canvas label loop routes `GeoText` grabs to the body drag. Referenced geometry provably stays put; caption offsets untouched. +7 tests, 1384 green.

**Next**
- Phase 43 (viewport rotation) remains the queued phase.
- Text follow-ups if users ask: named/referenceable calculations (dependency chains between texts), numeric integrals (the function registry is table-driven for exactly this).

**Open questions / gotchas**
- Renaming a referenced object does **not** rewrite a text's stored source string — values keep tracking (bound by instance), but the edit dialog shows the old name until re-resolved on OK. Rewriting source on rename needs an AST printer; deferred.
- `pi` and `e` shadow bare references to objects so named (the lowercase auto-pool contains `e`); accessor arguments are always object names, so `len(e)` still reaches the object. Pinned by test.
- A text's body drag moves its **anchor**, not its free-point ancestors — those are the *referenced* geometry, and a rigid translate would move the figure. Don't "simplify" `_TextAnchorDragSession` into the translate path.

---

## Session 75 — 2026-07-21

**Done**
- Phase 57 (user bug report, `parallelogram-double-point.json`): the parallelogram macro no longer stacks a duplicate on an existing point. The reported case is Varignon's theorem — macro over three side-midpoints of a quadrilateral lands its fourth corner *identically* (not approximately) on the fourth midpoint — so it was never a floating-point problem and no structural check could see it (different kind, different parents).
- `lib/domain/tools/point_coincidence.dart`: `coincidentExistingPoint` decides "same point" probabilistically — tolerance screen at the current configuration, then the coincidence must survive 3 random perturbations of every mutable root (FreePoint positions + PointOnObject parameters) either point depends on, recomputing carriers construction-wide plus the candidate's private ancestor chain. Roots restored bit-exactly afterward. Any uncertainty (undefined under probe, out of tolerance) keeps the new point: a duplicate is clutter, a wrong merge corrupts drag semantics.
- `MultiPointTool.dedupedDerivedPoint` (snapshot of `ToolInput.objects` per collected input) + `ParallelogramMacroTool` wiring: a reused corner drops the hidden parallels entirely, so the commit is just the 4 visible segments. Accidental coincidences (a stray free point parked exactly on the corner) still create the independent derived corner — pinned by test.
- Tests: 8 helper cases (incl. bit-exact restoration and a verbatim replay of the reported file's geometry) + 2 macro-level cases. 1284 green, analyze clean.

- Rollout (same session, user request "fix it everywhere possible"): every tool that derives a point which can pre-exist now dedups — square (both corners), kite, right/isosceles trapezium, equilateral triangle, regular polygon (chained vertices continue from whichever instance survived), midpoint tool (either order + circle-center on a center-point circle), triangle centers, angle-by-size (marker still added, wired to the reused arm), intersection tool (numeric refusal atop its structural check). `commitCollected` now returns `ToolResult`: an all-deduped product refuses the completing tap (`ToolIgnored`, last vertex dropped, rest stays armed — the IntersectionTool convention; ToolIgnored skips the revision bump, and un-cleared collection means no stale preview). 12 new tests (double-stamp per macro; medians-crossing-as-centroid for both centroid and intersection tools), 1297 green.
- NOT wired, deliberately: rectangle/rhombus D, trapezium D, right/isosceles triangle third corner, fixed-length B — each depends on a `PointOnObject` parameter created in the same commit, a fresh DOF no existing point can identically track, so dedup provably can never fire there. Don't "complete" the rollout with dead code.

**Next**
- Phase 43 (viewport rotation) still queued; text tool expected.
- Duplicate *segments* (re-stamping also re-adds sides over existing ones) are the analogous next cleanup if users hit it — points were the reported problem.

**Open questions / gotchas**
- The probe mutates live `FreePoint.position` / `PointOnObject.parameter` directly (bypassing `Construction` so no listeners fire) and restores before returning — safe only because it runs synchronously inside commit; don't lift it anywhere async.
- Probe recomputes skip angles/polygons/measurements/loci deliberately (nothing point-valued reads them; restoring carrier inputs bit-exactly means they were never stale — and `Locus.recompute` is too expensive to run 4×).
- Tolerances: screen/survive at `1e-6·max(1,‖p‖)` relative, perturbation at `0.03·max(1,·)` — identical points agree to ~1e-12 relative, accidental ones separate by ~0.03, orders of magnitude on both sides. Don't tighten the perturbation "to be safe": too small and near-tangency (quadratic) separations dip under tolerance.

---

## Session 74 — 2026-07-21

**Done**
- Phase 56 (user request): name-points and declutter regrouped under one **Text & labels** app-bar flyout (`Icons.text_fields`, right after the toolbar cluster). Rows show their shortcuts (`G M`, `⇧ F`) via `ToolMenuRow`; the icon tints primary while the naming tool is active and a double-click deselects — the `_hideDeleteGroup` construction verbatim. Declutter is the group's one-shot row (fires immediately, never tints); naming re-opens the dialog. The standalone `abc` toolbar button and the wand view-cluster button are gone — each action keeps exactly one home, and the group is the declared landing spot for the anticipated text and calculation tools.
- Rationale (discussed with the user first): both actions operate on the drawing's *text* — semantically one concern — and grouping now, at two rows, avoids moving buttons again when the text tool lands. If declutter turns out to be pressed constantly mid-session rather than as a finishing touch, the fix is auto-declutter-after-transform, not un-grouping.
- Tests re-routed: `toolbar_test.dart` name-points group opens the dialog via menu row and pins the tint on `Icons.text_fields` (plus double-click must open neither menu nor dialog); `name_points_flow_test.dart` activates through the group. 1274 green, analyze clean.
- Ad-hoc Playwright smoke on a fresh release build: menu screenshot shows both rows with shortcut hints; clicking the declutter *row* moved overlapped label A (6,−18) → (20,−9.5), left clean B, one Ctrl+Z restored both, zero console errors — **ADHOC PASS**. drive.js untouched (it indexes File from the left and theme/delete from the right; the group sits between).

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- User expects a **text tool** and possibly a **calculation tool** soon — both belong in this group when they arrive.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- `_activateNamePointsTool` is `Future<void> Function()` fed into `PopupMenuButton<VoidCallback>` — valid Dart (void-returning function types accept any return), and the dialog opens fine after the menu closes; don't "fix" it into an awaited call inside `onSelected`.
- The leftover 8321 server from Session 72/73 was finally killed this session; smoke runs start their own or reuse knowingly.

---

## Session 73 — 2026-07-21

**Done**
- Phase 55 (user request): a one-shot **Declutter labels** action — wand button in the app bar after Reset view, `⇧ F` — that moves every overlapped label (names, values, measurements) to the clearest nearby spot. One batch `ChangeAttributesCommand` rewriting `labelDx`/`labelDy` for the moved objects only, so a single undo restores every label; nothing to move is a silent no-op.
- `label_declutter.dart` (pure `dart:ui`, no Flutter framework): greedy insertion-order solver. Scene primitives `Capsule` / `RectObstacle` / `LabelBox`; scoring = label-on-label 4× area + ink 2× (own ink at half weight) + off-canvas 8×; ~50 candidates per label (current, default, 16 directions × 3 gaps with the box *beside* the anchor), radially clamped to the manual drag's `labelOffsetMaxPx` 40 (user-confirmed choice: stay in the drag radius, least-bad in dense spots rather than far-away labels). Keep/move thresholds (8 px² each) so clean labels and deliberate manual placements never churn.
- Capsule overlap deliberately deviates from naive clipped-length × width: it multiplies the clipped centerline by a penetration depth read off the span's midpoint, so the *default* placement grazing its own stroke edge-on scores ~0 — otherwise every clean segment label would move.
- `label_obstacles.dart`: `buildDeclutterScene` mirrors `GeometryPainter._drawObject` per kind (point dots → rects; segments/rays/lines honoring `lineClip` → capsules; circles/arcs/sectors/loci → chord runs; polygons → edges; angle markers → square edges or ≤ 30°-step spokes + rim so the reflex side stays free; measurements label-only). Label rects come from `labelScreenRect`, so the solver can't disagree with the painter. Offsets persist as the existing additive JSON fields — no format bump.
- Tests: 12 solver + 4 builder cases (see TODO). 1274 green, analyze clean.
- Ad-hoc Playwright smoke on the fresh release build (8321 server reused): segment A→B via `S`, `G M` + Enter renames the endpoints (allocator freed/reused letters → bottom point ends up **C** with its label lying across the stroke), `⇧ F` moved C's offset (6,−18) → (20,−9.5) leaving the clean labels alone, one Ctrl+Z restored all three saved-doc offsets exactly, zero console errors — **ADHOC PASS** (screenshot-verified: label clear of the stroke).

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- Possible declutter follow-ups if requested: leader lines for dense areas (would relax the 40 px radius), auto-declutter after transforms.

**Open questions / gotchas**
- The segment tool auto-names new endpoints; `G M` alphabet mode then *re-allocates* (a tap frees the old letter for the next tap) — surprised the smoke script, which asserted on A/B while the points ended up C/A. Emergent from the Phase 53 single-rule allocator, already test-pinned there.
- Declutter scores against the *current viewport*: offsets are screen-px and zoom-independent, so a layout decluttered when zoomed-out may overlap again after zooming — by design (press `⇧ F` again); nothing re-solves automatically.

---

## Session 72 — 2026-07-21

**Done**
- Phase 53 (user request, C.a.R-inspired): sequential point-naming tool. A one-field dialog (`G M`, or the tool's button) drives the mode: empty → alphabet from A, single Latin letter → alphabet from that offset (case picks the pool), a word → its characters one tap at a time. Each accepted tap is one `ChangeAttributesCommand` (`name` + `labelVisible: true`); non-point taps consume nothing.
- Placement (user feedback, after first landing in the Points flyout): the tool gets its own `abc` button closing the toolbar's tools cluster — a single-action tool doesn't earn a one-row flyout and doesn't belong under the hide/delete trash can. One click opens the dialog; active tint + double-click deselect mirror the `_ToolGroup` affordances; `pointsActive` no longer claims the tool. drive.js survives untouched: it only indexes the File icon from the left and theme/delete from the right.
- Alphabet mode is stateless — each tap takes the first free name from the live used-name set via the new `nextNameFrom` allocator (round 0 scans start…Z, later rounds `A1…Z1, A2…` like `nextAutoName`), so used names are skipped and undo re-offers freed letters. String mode holds a cursor and *evicts* a clashing holder (`evictedName`, Phase 27 rule) in the same command; exhausted taps are ignored. Dialog validation (repeated chars / spaces) keeps it open with an inline error — a deliberate deviation from the numeric dialogs' garbage-reads-as-cancel.
- `NamePointsHint` chip (new canvas overlay surface, bottom-left, `IgnorePointer`): shows "Next name: X" / "All letters assigned" while the tool is active — the sequence's only forward-looking feedback.
- Tests: `nextNameFrom` group, `name_points_tool_test.dart` (both modes, skip/evict, exhaustion, re-tap, undo, reset), toolbar dialog + button-tint + double-click-deselect cases, `G M` resolver, `name_points_flow_test.dart` (canvas taps + chip + one undo per tap). 1257 green, analyze clean. Web smoke re-run on a fresh release build after the placement move: **SMOKE PASS** (drive.js untouched). Ad-hoc Playwright: G M → "MID" spells the points, saved doc carries the names, alphabet re-tap renames M→A, one Ctrl+Z steps back one tap, zero console errors — **ADHOC PASS**.

- `phase-53-name-points` merged into `main` (fast-forward).
- Phase 54 (user request): object labels are large by default — `ObjectAttributes.labelFontSize` default 12.0 → 16.0, the inspector's 'L' preset. Documents always serialize the field explicitly, so existing saves keep their sizes; only pre-Phase-28 saves (no field) ride the decode fallback up — cosmetic, no version bump. Six goldens regenerated (measures / measurements / decorations × light/dark; everything else byte-identical), inspector undo test re-pinned to 16. 1257 green, analyze clean, release-build **SMOKE PASS** (larger labels don't disturb drive.js's blob detection).
- Phase 54 follow-ups (user request): `angleMarkerRadius` default 20.0 → 28.0, also the 'L' preset; axis tick numbers 10 → 12 px (the canvas's smallest text); and the axes/grid popup rows now show their shortcuts as trailing text via `ToolMenuRow` (⇧X / ⇧G / Ctrl⌘⇧G) instead of the cheat sheet being their only home. The two hit-tester wedge tests derived world geometry from "default radius 20 px" — they now pin 20 explicitly on their angles instead of leaning on the default. Angle-bearing goldens regenerated (angles / markers / measures × light/dark).

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- `resetInProgress()` fires on *every* undo/redo and restarts a partial naming string (the cursor is the one deviation from the back-to-initial-after-commit tool contract). Accepted for v1: eviction makes re-tapping in order idempotent and the hint chip shows the restart. If it grates, the fix is tracking letter→point assignments, not keeping the cursor across resets.
- In alphabet mode a re-tap gives the point the *next* free letter and frees its old one for the following tap — the emergent single-rule behavior, test-pinned; any "ignore re-taps" nicety belongs in the UI layer.
- Port 8321 had a leftover server from an earlier session; it serves `build/web` from disk so the fresh build was what got smoked (verified via Last-Modified).

---

## Session 71 — 2026-07-20

**Done**
- Phase 52 (user request): foldable object-tree groups. Each group header grows a leading chevron (its own `IconButton` tap target, so folding never selects) that folds the group's rows away; the header and dividers stay, a trailing count stands in for the hidden rows, and select-by-kind (tap / shift-tap / long-press) keeps acting on the whole folded group.
- Groups start folded (follow-up user request): a fresh panel is a compact per-kind overview and expanding is opting into detail. Expansion is view state like the search query — an `_expanded` set in the panel state, reset when the panel closes, never persisted.
- An active search overrides folding — a match inside a folded group must not read as "no matches" — and disables the chevron while it's forcing everything open; clearing the query restores the folds.
- Tests: default-folded overview / expand-refold / folded-header select / search-override cases; existing row-level tests now expand their group first through the chevron, the way the user does. 1216 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- Folds don't persist across panel close/reopen (deliberate, matching the search query). If that grates in practice, the natural home for remembered folds is a UI-state provider, not the save format.
- The chevron is disabled rather than hidden during search so the header layout doesn't shift; it shows the expanded glyph then, since the search forces every match visible.

---

## Session 70 — 2026-07-20

**Done**
- Phase 51 (user request): equal-length congruence ticks on segments. New `ObjectAttributes.tickMarks` (int, default 0, additive JSON field — no version bump): the painter draws that many short strokes perpendicular to the segment, centered as a group on its midpoint (10 px long, 5 px apart, logical pixels, zoom-invariant), always solid even on dashed segments, with the object's paint so the selection-halo pass widens them like the stroke.
- Inspector: 'Equal marks' preset row (– / 1 / 2 / 3) via the existing `_PresetSelector`, offered only while a segment is selected and targeting the segment slice of a mixed selection.
- Tests: painter tick geometry (perpendicularity, group centering, spacing, dashed-stroke case, degenerate-segment guard), inspector scoping + one-command-per-tap + undo, `tickMarks: 2` in the kitchen-sink codec round-trip, decorations golden scene gains two ticked segments (regenerated light+dark). 1214 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- Ticks are segments-only by design; the natural extensions if asked are arc ticks (same notation for equal arcs, perpendicular to the rim at the arc midpoint) and per-side ticks on polygons — the attribute and painter helper generalize.
- A degenerate (coincident-endpoint) segment paints nothing at all — the tick guard exists so the helper never divides by a zero screen length if that upstream skip ever changes.

---

## Session 69 — 2026-07-20

**Done**
- Phase 50 (user request): the measure tools understand partial circles. New `LengthMeasurement` over one circular subject — circle circumference (2πr, anchored at the top of the rim), arc length (r·sweep, arc midpoint), sector perimeter (2r + r·sweep, rim midpoint; a wedge is a closed region, so both radii count). New `DistanceTool` subclasses `TwoPointTool`: a *first* tap whose topmost hit is a `GeoCircle` commits the length in one command; everything else (point taps, gluing, crossings, free points) is the unchanged two-point flow. Replaces the `buildDistance` tear-off wiring in toolbar/main.
- `AreaMeasurement` no longer reports the whole parent circle for an `Arc`/`Sector` subject (both are `GeoCircle`s, so the area tool already accepted them — silently measuring πr² of the carrier): a sector now measures its wedge (½r²θ) and an arc the circular segment its chord cuts off (½r²(θ − sinθ)), each anchored at the true centroid on the extent bisector with guarded θ→0 limits.
- Codec: additive `LengthMeasurement` kind, no version bump. Kind label 'Length'; menu/cheat-sheet rows reworded. Distance-tool tests moved out of `area_tool_test.dart` into a proper `distance_tool_test.dart`. Measurements golden scene gains the circumference label (regenerated light+dark). 1208 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- Deliberate trade-off: a first distance-tool tap on a bare circle used to glue a `PointOnObject`; now it measures. Workaround: create the point first (point tool), then measure from it — points always outrank curves under the tap.
- Sector "length" = full perimeter (2r + arc), not just the rim — draw an `Arc` to measure a rim alone. Polygon perimeter would be the natural next extension of `LengthMeasurement` if asked.
- A sector's area anchor is the wedge centroid, so the area and (rim-anchored) length labels never stack; on a plain circle area sits at the center and circumference at the top of the rim.

---

## Session 68 — 2026-07-20

**Done**
- Bug fix (user report, `inter2.json`): the Session 64 duplicate-intersection refusal didn't cover the two-line bisector when its parent segments *share a defining endpoint*. Segments a = AB, b = AC off vertex A, bisector of the wedge — intersecting the bisector with a parent still stacked a new point on A, because `_derivedIncident` only recognized an `IntersectionPoint` of exactly the parent pair as the crossing, and here no such point exists: the crossing *is* A.
- Generalized the Phase 44b rule: a point [`structurallyIncident`] on **both** parent lines of a `TwoLineBisectorLine` is on the bisector — distinct lines cross at most once (coincident parents leave the bisector undefined), so such a point is the crossing. Recurses through the shared predicate, so the `IntersectionPoint` case, a shared defining endpoint, and deeper chains all count. Line clipping mode 2 inherits the improvement for free (a visible shared vertex now clips the bisector).
- `inter2.json` kept verbatim in `test/fixtures/` with a codec-loaded regression replaying the taps that produced the stacked points (refused now; fails without the fix, stash-verified, along with new incidence + tool unit tests). 1193 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- The three-point `AngleBisectorLine` needed no change: its vertex is already an on-carrier defining point, and the vertex-shared-with-a-segment-endpoint case was already covered.
- The user's document still contains the stacked D and E from before the fix — the fix prevents creating new stacks, it doesn't delete existing ones.

---

## Session 67 — 2026-07-18

**Done**
- Phase 49 (user request, small polish): object tree group headers are now visually separated — a `Divider` between groups (none above the first) and the header text restyled to `primary` color + `w600`. Label text/casing untouched so the widget tests' `find.text('Points')` finders keep working. The `noRows` flag became a `visibleGroups` list feeding both the empty-state check and the divider indexing.
- Snap to grid gets a shortcut: `AppAction.toggleSnapToGrid` on `Ctrl/⌘ ⇧ G` — the primary-modifier escalation of `⇧G` (show/hide grid) — wired to the existing `DocumentSettingsNotifier.toggleSnapToGrid`. Cheat sheet lists it automatically from the table; the grid popup item is unchanged (menu items don't show shortcut hints, consistent with axes/grid).
- New editor-shortcut test: Ctrl variant toggles `snapToGrid` on, Meta variant back off, `showGrid`/`showAxes` untouched. 1190 green, analyze clean.
- Tagged `v0.2`.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- The `?`-cheat-sheet's viewport section grew a row; no layout issues at default sizes, but nobody re-checked phone-width overlay scrolling this session.

---

## Session 66 — 2026-07-18

**Done**
- Follow-up to Session 65 (user request): the same extent clamping for `Segment` and `Ray`. New API on `GeoLine`: `parameterExtent` (`(min, max)` in the carrier's arc-length parameterization, null bound = unbounded side, null = whole carrier; Segment spans its endpoints ordered, Ray is bounded at its origin and open past `through`) and `clampParameter` — the line siblings of `angularExtent`/`clampAngle`.
- `PointOnObject` clamps line parameters at creation and (effectively, without mutating the stored parameter) on recompute; the slide drag clamps every frame via a per-kind clamp switch. A segment that shrinks past the point carries it on its endpoint and gives it back.
- `Locus`: a Segment host sweeps only its span (uniform, endpoints included, all samples core, gapless sweeps skip the walk); a Ray host sweeps `[origin, ∞)` on a tan grid anchored at the origin (first sample exactly on it, halfSpan as density scale, baked `center` unused); infinity tails now gated per-side to genuinely unbounded edges (`_infiniteEdges`), `_boundedSweep` replaces the circle-host special cases in core/early-return.
- **Semantic change, deliberate**: `locus3.json` (parabola) regression test rewritten. Phase 39f swept a *segment-hosted* driver over the whole carrier projectively (full parabola); with points now confined to their hosts that behavior is unreachable (the clamped chain flattens beyond the extent), and today's user request explicitly wants bounded loci. The fixture now asserts the parabola piece between the endpoint images, (1, −2) → (1, 2). Full-parabola workflow: host the driver on the *line* through B and C. Infinite-line hosts keep the full 39f projective sweep + tails (locus-miss.json still green).
- Tests: Segment/Ray/LineThroughTwoPoints extent + clamp, PointOnObject near/shrink on segment and ray, segment slide-drag clamp, segment- and ray-host locus domains. 1189 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- If the user misses the full parabola from segment-hosted drivers, the answer is "drive on a line, not a segment" — or a future toggle; do not silently revert the clamp.
- Intersection points remain unclipped to segment/ray/arc extents (deferred as before) — only constrained points clamp.
- Ray extent orientation is derived per-recompute from origin/through carrier parameters, so it survives any future carrier canonicalization.

---

## Session 65 — 2026-07-18

**Done**
- Bug fix (user report): a `PointOnObject` hosted on an `Arc`/`Sector` slid the full 360° of the carrier, and a locus driven by such a point traced the whole turn. Root cause was threefold: the slide drag re-projects onto the carrier circle, `PointOnObject` never clamps its polar angle, and `Locus` sweeps every `GeoCircle` host one full turn.
- New API on `GeoCircle`: `angularExtent` (`(start, sweep)` CCW span, null = whole turn; `Arc` normalizes its signed sweep, `Sector` exposes its wedge, both null while undefined) and `clampAngle` (identity for full circles, else snaps outside angles to the angularly nearer extent endpoint, via new `angularDistance` in `angle_geometry.dart`).
- `PointOnObject`: `near()` clamps the tap's angle; `recompute()` clamps the *effective* angle without mutating `parameter` — a wedge that shrinks past the point carries it on its rim end and gives it back when it grows again.
- `_SlideDragSession`: clamps each frame's parameter (point stops at the branch ends, reverses immediately) and takes the grab offset from the clamped parameter; committed command carries the clamped value.
- `Locus`: bounded hosts sweep only their extent (endpoints included, `sampleCount` uniform steps), treated non-cyclically — no 0/2π wrap merging in `_runs`, infinity tails now gated to line hosts. Painter closes a gapless circle-host locus into a loop only when `angularExtent == null`.
- Tests: `angularDistance` (glados), Arc/Sector `angularExtent`+`clampAngle`, full-circle passthrough, sector-hosted `near`/shrink-restore, sector slide-drag clamp, sector-host locus domain. 1180 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- Segments/rays still constrain to their infinite carrier line (deferred as before) — only the circle kinds got extent clamping; do segments next if the same complaint comes in.
- Intersection points on arcs/sectors remain unclipped to the extent (the pre-existing deferred-clipping caveat, untouched).
- A gappy bounded-host locus run touching a domain edge gets a null gap on that side, like a line host's infinity edge — genuine end, no refinement ladder there (the arc endpoint is a domain edge, not a defined↔undefined boundary).

---

## Session 64 — 2026-07-18

**Done**
- Bug fix (user report): two crossing segments + their `IntersectionPoint`, then their angle bisector — intersecting the bisector with one of the segments stacked a *new* point on the existing crossing instead of reusing it. Cause: `IntersectionTool` committed unconditionally, and the bisector's only crossing with either segment *is* the existing vertex.
- Extracted the structural-incidence rules out of `line_clip.dart` into a shared public predicate `structurallyIncident(curve, point)` (`domain/construction/incidence.dart`): hosted `PointOnObject`s, `IntersectionPoint` parents, on-carrier defining points (now also covering `Segment` and the circle kinds — `onCircle`, three-point circle, arc points, sector `start`), plus the Phase 44b derived theorems (two-line bisector ∋ parents' crossing, perpendicular bisector ∋ pair's midpoint). Zero-epsilon as before; mere coincidence is still not incidence. `lineClipSpan` mode 2 now rides the shared predicate (behavior unchanged — defining points are found via the objects scan, valid since parents always live in the construction).
- `IntersectionTool`: before committing, a visible defined point structurally incident on *both* curves and classified (by the same nearest-branch probe the tap uses) onto the chosen branch means the intersection already exists → tap refused like the transform tool's duplicate image, first curve stays armed. Covers both bisector modes (`TwoLineBisectorLine` via the derived theorem, `AngleBisectorLine` via its vertex), the same-pair-twice duplicate, and two curves sharing a defining point. Per-branch: the other branch of a line×circle pair still commits. Hidden points don't block.
- Tests: new `incidence_test.dart` (6), 4 new + 1 reworked in `intersection_tool_test.dart`. 1170 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- The dedupe is structural only — a `FreePoint` merely dragged onto the crossing doesn't block a new intersection point (by design, same zero-epsilon rule as line clipping).
- Candidate extensions to `structurallyIncident` deliberately left out to keep `lineClipSpan` behavior identical: `Midpoint`/`SegmentRatioPoint` on the segment/line of the same pair. Adding them would slightly change mode-2 ray clamping when endpoints are hidden.
- The point tool was never affected: at the crossing the existing point outranks curves in the hit order (rung 1 of the resolution ladder).

---

## Session 63 — 2026-07-18

**Done**
- User request: GeoGebra-style "Midpoint or Center" — the midpoint tool now emits a circle's center when the first tap lands on a circle-valued object. New derived point `CircleCenter` (`domain/construction/objects/circle_center.dart`, parent: any `GeoCircle`; arcs/sectors yield the *carrier* circle's center). Not to be confused with the pre-existing `CircleCenterPoint`, which is the circle built from center + rim point.
- New `MidpointTool extends TwoPointTool` (`domain/tools/midpoint_tool.dart`): first tap whose *topmost* hit is a `GeoCircle` → commits `AddObjectCommand(CircleCenter)` in one step; everything else falls through to the normal two-point midpoint flow. The shortcut only fires with nothing collected, so a circle tap as the *second* input still glues a `PointOnObject` parent as before. A point sitting on the circle still wins the tap (points outrank curves in the hit order).
- Wiring: toolbar menu row + `M` shortcut label renamed "Midpoint or center"; `buildMidpoint` removed from `toolbar.dart` (the builder now lives inside `MidpointTool`; the Points-group catch-all in `pointsActive` still matches it as a `TwoPointTool`). Codec: `CircleCenter` encode/decode (no params, parent index 0) + kitchen-sink coverage. Kind label: "Circle center". Painter/hit-test/naming needed no changes — all generic over `GeoPoint`.
- Tests: `circle_center_test.dart` (4), `midpoint_tool_test.dart` (5: point-point unchanged, circle → center, arc carrier center, point-over-circle priority, second-tap glue). 1159 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- A first tap on a circle-line *crossing* where the circle ranks topmost now creates the center, not an intersection-snap midpoint parent. Deemed the right trade — tap the crossing with a point already collected (or use the intersection tool) if the crossing is wanted.
- Tapping the same circle twice makes two coincident centers (GeoGebra does the same); no dedup.
- No web smoke — flows are pinned by tool unit tests + toolbar/canvas widget tests.

---

## Session 62 — 2026-07-18

**Done**
- Bug fix (user report): half-circle sector + segment over its diameter → no point creatable on the segment. Cause: the hit tester ranks the sector (circle priority) above the segment and hits it on its straight radius edges, and `resolvePoint` rung 3 glued to the ranked-best curve unconditionally — `PointOnObject.near` on a `Sector` projects onto the *carrier circle*, so the point teleported out to the arc.
- Fix in `point_resolution.dart` rung 3: glue to the ranked-best curve **whose glued position stays within `snapThreshold` of the tap**; curves whose hit target is wider than their analytic carrier (a sector's straight edges) fall through to the next candidate, and if none qualifies, to the grid-snapped `FreePoint` rung. `snapThreshold == 0` (legacy inputs) keeps the old always-glue behavior, same degradation contract as rung 2.
- Only sectors change in practice: for lines, circles, arcs, clipped lines and rays the projection distance is ≤ the hit distance, so the check always passes.
- Tests: 4 new in `point_resolution_test.dart` (segment-under-diameter regression, bare straight-edge tap → free point, near-arc tap still glues, legacy threshold-0 pin). 1150 green, analyze clean.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- A tap on a sector's straight edge with nothing underneath now makes a *free* point at the tap (was: a point flung to the arc). A point constrained to the radius edge would need a new parameterization — not worth it unless requested.
- No web smoke — domain-only change, exact scenario pinned by unit tests.

---

## Session 61 — 2026-07-18

**Done**
- User request in two steps: surface the hide tool in the app bar, then group it with delete "like the rest of the tools". Landed as one **hide/delete flyout group** (`hide-delete-group`, `main.dart`) replacing the delete `IconButton`: rows Hide (`H`), Show/Hide (`⇧H` — its first pointer affordance) and Delete (`Del` hint), rendered by the toolbar's row widget (`_ItemRow` made public as `ToolMenuRow`). Group icon stays `delete_outline`, tints `colorScheme.primary` while any of `DeleteTool`/`VisibilityTool` is active, double-click deactivates (the `_ToolGroup` pattern — recognizer mounted only while active).
- Act-on-selection semantics unchanged: Hide/Delete still act on the current selection at activation (one undo step; hide keeps the selection, delete runs the cascade confirmation). The old press-again-to-toggle-off is retired with the buttons — re-picking a menu item just re-arms; leaving is double-click / Esc / `V`. `_activateShowHideTool` extracted so the `⇧H` shortcut and the menu share one path.
- The group lives in `main.dart`, not `GeometryToolbar`: its items act on the selection at activation, which the toolbar's pure tool factories deliberately can't.
- Tests: new `hide_tool_flow_test.dart` (6 flows incl. tint + double-click + Show/Hide item); `delete_tool_flow_test.dart` reworked for menu activation and double-click deactivation; `app_bar_layout_test.dart`'s scroll-to-delete now goes through the flyout. 1146 green, analyze clean.
- Also landed just before this entry (separate commits `9c1322a`, `325cce6`): polygon macro order change and the polygon tool's move to the Lines group.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- The Delete row shows `Del` as its shortcut hint, but `Del` only deletes the selection — it doesn't arm the tap tool. The row's act-on-selection path matches `Del` exactly when a selection exists, so the hint reads true in practice; revisit if it confuses.
- No web smoke this session — app-bar-only change, covered by the widget suites; run one before the next release-facing phase.

---

## Session 60 — 2026-07-17

**Done**
- **Phase 47 complete** on `phase-47-unified-app-bar`, merged to `main` — user feedback on the Phase 42 split: the app bar must not re-arrange on small windows (compact variant moved the loose icons into a `more_vert` overflow and pinned delete/undo/redo); it should stay identical and scroll **in its entirety**, object tree through redo.
- Retired the compact chrome wholesale: `compactChrome`/`_wideChromeMinWidth`/`_compactBarHeight`, the title-slot-only toolbar and the overflow menu are gone from `main.dart`. The whole bar is now one `_appBarRow` in the AppBar title slot (`automaticallyImplyLeading: false`, `titleSpacing: 0`) inside a horizontal `SingleChildScrollView`; `ConstrainedBox(minWidth: bar width)` + `IntrinsicWidth` let the `Spacer` right-align the action cluster while it fits and collapse to zero exactly when scrolling starts — desktop renders as before, narrow windows scroll the unchanged row. A lone `SizedBox.shrink()` in `actions` suppresses Material's implicit end-drawer button.
- `compactPanels` (drawers vs docked, drawer-opening tree button, selection-gated style button) untouched.
- Tests: `compact_layout_test.dart` → `app_bar_layout_test.dart` (phone: full cluster present + scroll-to-tap delete at the far end; tablet portrait: same bar over docked panels; desktop: `maxScrollExtent == 0`, cluster right-aligned). `toolbar_test`'s flyout `scrollUntilVisible` calls now pass `find.byType(Scrollable).last` — the bar is a second Scrollable and the default lookup threw "Too many elements".
- 1141 tests green (suite went 12 → 11 in the renamed file), analyze clean, web SMOKE PASS on a fresh release build (drive.js untouched — wide icon order is unchanged). Ad-hoc Playwright: 400×800 wheel + CDP touch-drag scroll the bar end to end; 1280×800 looks byte-identical to the old wide chrome and the wheel is inert there.
- Follow-up in the same session: the unified bar read as "fatter" on mobile (56-px default vs the old 48). `toolbarHeight` now rides the `compactPanels` gate — 48 px on phones, default elsewhere; content identical. Tests re-pinned (phone 48, desktop `kToolbarHeight`), 1141 green, slim bar confirmed on the release build at 400×800.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by several phases — push when convenient.

**Open questions / gotchas**
- Mouse-only desktop users in a narrow window can't drag-scroll the bar (Flutter's default drag devices exclude mice); trackpad/wheel horizontal scroll works. Same behavior as the old compact toolbar strip, so no regression — revisit if it grates.
- `wide_window.dart` (1280×800) is still required in `EditorScreen` suites: at flutter_test's 800×600 default the trailing bar buttons sit off-screen and taps would need a scroll first.

---

## Session 59b — 2026-07-17

**Done**
- **Phase 39f complete** on `phase-39f-projective-line-sweep` (3 commits incl. docs), merged to `main` — user feedback on 39e: a parabola locus (`locus3.json`, E on a square's side, G = midpoint of E and the perpendicular's crossing with the far side's carrier — analytically x = y²/4) "also stops early before infinity".
- The trace *diverges* at driver-infinity, so no finite tail can complete it: the bounded sweep window itself was the defect — third user report against it (Session 55 chevrons, 39e touch, this). Decision: line hosts now sweep **projectively** (Cinderella's driver semantics) — `t = center + halfSpan·tan(φ)`, φ cell-centered uniform over (−π/2, π/2). Whole carrier covered; `center`/`halfSpan` keep their persisted values as the sampling **focus** (half the samples within one view-width); no codec change, old documents just stop truncating.
- `_infinityTail` rungs now start at `max(2·halfSpan, |edge − center|)`: from the ≈80·halfSpan projective edge, a 2·halfSpan first rung barely moves the driver, increments *grow* toward the doubling regime and the decay test spuriously rejected (caught by the doc-1 fixture before the fix landed).
- Unbounded arms would explode zoom-to-fit and throw labels off-view, so `GeoLocus` gained **`coreSamples`** (defined uniform positions inside the focus; default all defined samples): consumed by `fit_viewport`, `label_anchor`, `tool/locus_render.dart`. Band selection deliberately stays whole-samples — a diverging locus is line-like and, like lines, never band-selects.
- Test churn, all deliberate: identity-trace re-pinned to the tan grid; the 39c cut-window U-curve now *closes* (no cut exists) and is re-pinned as the projective-coverage test — open-walk trimming stays pinned by the doc-1-shaped fixture; tangency-sampled pins relaxed 1e-6 → 1e-3 (the old bound was an artifact of the uniform grid hitting the tangency parameter exactly; the dive stops at the two-candidate epsilon edge ~1e-4 away). Locus goldens regenerated after visual review — indistinguishable. `goldens/failures/` untracked + gitignored (accidentally committed in 39b).
- 1142 tests green (4 new: parabola fixture regression, fit + 2 anchor stub pins), analyze clean, doc 1 still touches line b, web SMOKE PASS on a fresh release build.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by Phases 44, 44b, 39e, 39f — push when convenient.

**Open questions / gotchas**
- In-focus sampling density is ~0.64× the old window grid (tan′ spreads samples); boundary ladders compensate at gaps. If a real document shows faceting, bump the default `sampleCount` — it's per-locus and persisted.
- The far tan-grid chords double in parameter per sample; a trace that curves at 10–80 view-widths out will facet when zoomed out that far. Baked sampling can't be zoom-adaptive — accepted, Cinderella shows similar artifacts.
- The two projective ends of a line host are NOT joined through infinity even when both converge to the *same* point (they'd render as two strokes meeting there, not a closed loop); no user document has hit this.

## Session 59 — 2026-07-17

**Done**
- **Phase 39e complete** on `phase-39e-locus-infinity-limit` (3 commits incl. docs), merged to `main` — user feedback on 39d: doc 1's first locus stroke "should be touching the AC line" but stops short.
- Diagnosis first, analytic: in doc 1 the traced G has constant height ±|AB|/2 and G_x → A_x like |AB|²/(4t) as driver D → ±∞ (the Thales circle over AD flattens onto the perpendicular through A — line b, through A and C), so each stroke's far end has a *finite limit on line b*; the baked sweep window cut it |AB|²/(4·t_edge) ≈ 10.7 world units short — exactly the ~22 px gap in the user's ~2× screenshot. Cinderella's projective driver sweeps through infinity and touches the limit; the Session 55 "window edges cut line-host traces, not a defect" note was wrong for converging traces.
- Fix: `_infinityTail` — window-edge open ends grow samples at geometrically doubling driver distances (start 2·halfSpan, cap 10⁹), accepted all-or-nothing on increment decay (each ≤ 0.95 × previous; t^−p convergence gives ratio 2^−p, divergence ≥ 1), so diverging traces keep the window cut bit-exact and nothing leaks into merely-defined regions past the edge. `_trace`'s uniform-list early return is now circle-host-only so fully-defined line sweeps also route through the walk.
- Razor's edge found by the scaled unit fixture (r = 3): deep in the ladder, double-precision position noise (~parameter × ε; G_x visibly quantizes to 0.0 near t ≈ 10⁸) overtakes the true increments and one noise uptick rejected a genuinely converging tail. Hence the **converged stop**: increment ≤ 10⁻⁶ × trace extent accepts the tail immediately — remaining gap same order, far subpixel, and reached long before the noise regime.
- Tests: doc-1-shaped unit fixture asserts far ends within 10⁻³ of (0, ±1.5); fixture regression asserts a sample within 0.01 of the infinity limit on line b per stroke (both stash-verified to fail without the fix); identity-trace and U-curve pins unchanged. 1138 green, analyze clean, goldens byte-identical, render of doc 1 shows both strokes touching line b, web SMOKE PASS on a fresh release build (change is domain-internal; drive.js untouched).

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by Phases 44, 44b and 39e — push when convenient.

**Open questions / gotchas**
- The tail's chord faceting decays with the increments (doc 1's tail is exactly straight — constant G_y), but a trace that *curves* while converging would show doubling-length chords near the window edge; PLAN records ×√2 rungs as the densification fallback if a document ever shows it.
- The two strokes' infinity limits differ (upper sheet vs lower sheet), so they stay separate components — nothing to join through infinity here; a construction whose both window ends converge to the *same* point would still render as two strokes meeting there, not a closed loop.
- A leftover `python3 -m http.server 8321` from an earlier session is still serving `build/web` (reads from disk per request, so fresh builds are picked up); my own server bind failed harmlessly. Kill PID if the port is ever needed.

## Session 58b — 2026-07-16

**Done**
- **Phase 44b complete** on `phase-44b-derived-incidence` (3 commits incl. docs), merged to `main` — user feedback on 44: in `provoleas2.json` the two-line bisector and the tangent "have more than one point but do not clip".
- Diagnosis first (codec-loaded probe over the document): two distinct causes. The bisector `i` passes through K (structural — K parents `i`) *and* L = f ∩ h, but L's parents are f and h — a genuine gap: every bisector branch provably passes through its parent lines' crossing. The tangent `k` is different: its apparent points (O, N, L, S) lie on it only because the tangent *coincides with line NO in this figure* — the theorem the construction demonstrates — so no construction tie exists at all.
- Fix per user decision ("structural extension, keep the epsilon test out"): `lineClipSpan` gains **derived incidences** — `IntersectionPoint` of exactly a `TwoLineBisectorLine`'s two parent lines, `Midpoint` of exactly a `PerpendicularBisectorLine`'s two parent points, both order-blind (`_derivedIncident`/`_samePair`). Coincidence-by-figure stays excluded; the tangent clips once its tangency point exists (intersect it with its circle — the document's hidden twin tangent `l` already clips N→P that way, pinned in-fixture).
- `provoleas2.json` kept verbatim in `test/fixtures/` with a codec-to-span regression (bisector clips K↔L — fails without the rules, stash-verified; tangent stays infinite; twin clips). PLAN's Phase 44 passage records the derived-incidence rule and the deliberately short v1 list.
- 1138 tests green (9 new), analyze clean, goldens untouched, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched). No browser ad-hoc this time — the change is helper-internal; the Phase 44 ad-hoc already proved the inspector→painter wiring and the fixture regression drives the real codec.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by Phases 44 + 44b — push when convenient.

**Open questions / gotchas**
- The derived-incidence list is deliberately short: `SegmentRatioPoint`/`Midpoint` over a `LineThroughTwoPoints`' defining pair and `Incenter` on an `AngleBisectorLine`'s triple are also true theorems, recorded in PLAN as candidates when a real construction wants them (a ratio point beyond the pair *would* extend a mode-2 span).
- If a user reports "the tangent still doesn't clip", the answer is in PLAN: coincidence-by-theorem is not incidence — create the tangency point (intersection tool on tangent + circle; it's a 1-candidate intersection, so either branch lands on it).

## Session 58 — 2026-07-16

**Done**
- **Phase 44 complete** on `phase-44-line-clip` (5 commits incl. docs), merged to `main` — Cinderella-style line clipping, one of the two remaining queued phases.
- `ObjectAttributes.lineClip` (0 infinite / 1 defining pair / 2 incident-point span; additive, no version bump) + pure `lineClipSpan(objects, line)` in `domain/construction/line_clip.dart` returning world endpoints (signature takes the objects iterable, not a `Construction` — the hit tester holds no construction). Structural incidence, visible + defined points only; per-kind on-carrier defining points (line/ray pairs, `RelativeLine.through`, `AngleBisectorLine.vertex`, `TangentLine.point`; perpendicular-bisector and two-line-bisector contribute none); ray mode 2 keeps the origin and clamps the far end at the outermost incident point strictly ahead; `Segment` ignores the attribute entirely.
- Painter strokes exactly the span (halo + dash included; `lineClip == 0` guard skips the O(objects) scan) and `CanvasHitTester._distanceTo` clamps to the same span, so taps on the invisible carrier stretch miss. Carriers stay infinite for intersection math — pinned by test. Inspector "Extent" ∞/D/P `_PresetSelector` row over the clippable slice (lines + rays, not segments/points); D offered only while a `LineThroughTwoPoints` is selected.
- 1129 tests green (36 new) + 24 goldens (new `clips` scene ×2 themes; the 22 existing verified byte-identical *before* regenerating), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched). Ad-hoc Playwright: L + two taps, select, inspector P segment → far-carrier ink clears, span stays, saved document carries `lineClip: 2`, one Ctrl+Z restores the infinite carrier — **ADHOC PASS**.

**Next**
- Phase 43 (viewport rotation) is the last queued phase.
- `main` is ahead of `origin/main` by this phase — push when convenient.

**Open questions / gotchas**
- Mode 1 is deliberately visibility-blind (hiding a defining point doesn't un-clip) while mode 2 counts visible points only — per PLAN, but the asymmetry may surprise; watch for feedback.
- Band selection (`objectsInRect`) still never takes lines/rays, clipped or not — a mode-2 line *looks* like a segment but won't band-select. Not in the phase spec; revisit if reported.
- A clipped line's span endpoint usually coincides with a visible point, so a tap at the clip edge selects the *point* (priority), exactly like tapping a segment end — the hit-tester test documents this.
- The painter/hit-tester span scan is O(objects) per clipped line per frame/tap — fine at realistic sizes (Phase 40 precedent); revisit only if a document full of clipped lines drags.

## Session 57 — 2026-07-16

**Done**
- **Phase 39d complete** on `phase-39d-locus-epsilon-zone`, merged to `main` — user feedback on 39c: doc 1 still drew "a diagonal extension that is not part of the proper locus" off each stroke.
- Root cause (pinned by probe *before* touching code): Session 56's belief that "G's tangency limit is A / the tangency position" was wrong — those were the artifacts. G converges smoothly to a *finite interior limit* (the bisector's limit direction at the tangency is 45° to AB ⇒ G → A + (AD̂ ± perp)·|AB|/2); only within ~1e-11 grid steps of the boundary does F's `candidateCount` drop 2 → 1 — the intersection math's epsilon-*tolerance* zone, where a fabricated tangent (F ≈ D) collapses the bisector and throws G onto exactly A / B. The 48-deep bisection landed ~2⁻⁴⁸ inside that zone, so the ladder's last rung drew one long diagonal from the true limit to the garbage point.
- Fix: at a tangency, `_refineBoundary` re-bisects toward the edge of the culprit's **two-candidate region** (the true discriminant-zero point) instead of the defined↔undefined edge. On the coalescing point itself the tolerance zone was harmless (its stand-in *is* the limit), which is why the figure-eight and the closed-circle fixtures never showed it — both still pass with their 1e-6 tangency tolerances, and the locus golden is byte-identical.
- The doc-1-shaped unit test had *encoded the garbage as the expected limit* (`dive reaches A`); it now asserts convergence to (±1.5, ±1.5) and rejects any sample near A.
- User request: both problem documents moved verbatim from `~/Documents/geometry/regula/` into `test/fixtures/` with a codec-to-samples regression test (`locus_fixture_regression_test.dart`): doc 1 = two single-sided strokes reaching the analytic limits, no sample within 30 units of A/B (fails without the fix — the spike even crosses AB, tripping the one-side assertion); doc 2 = one closed gapless figure-eight. `tool/locus_render.dart` committed as a document→SVG eyeballing utility (recreated ad hoc three sessions running).
- 1097 tests green, analyze clean, all 22 goldens byte-identical; both fixtures re-rendered clean (doc 1 = two straight strokes, no diagonals; doc 2 = closed eight).

**Next**
- Phases 43 (viewport rotation) and 44 (line clipping) remain; either can go next.
- `main` is ahead of `origin/main` by Phases 37–39d — push when convenient.

**Open questions / gotchas**
- `candidateCount == 1` is not only "at a tangency": it is the *signature of the tolerance zone* — positions computed there are stand-ins, trustworthy only on the coalescing intersection itself, never downstream of it. Any future sampling near boundaries should stay inside the two-candidate region.
- The re-bisection assumes the culprit's 2-candidate predicate is monotone across [tIn, tOut] like definedness; if the uniform grid ever lands *inside* the tolerance zone (tIn itself 1-candidate), the ladder degenerates to tIn — harmless duplicates, no spike.

## Session 56 — 2026-07-16

**Done**
- **Phase 39c complete** on `phase-39c-locus-continuation-scope` (2 commits incl. docs), merged to `main` — user feedback on 39b: doc 1's locus grew "a lot more lines that are unexpected" while doc 2's figure-eight was right.
- Diagnosis: the 39b walk output was continuous and Cinderella-faithful, but its open-walk flipped sheets (mirror strokes + dives) trace positions that the app's deterministic-branch *dragging* can never reach — phantom curves to the user. Worse, a probe showed most of the phantom ink came from a genuine bug: a non-closing walk left its culprit flip in place, so the *next* run's walk traced under the leaked branch (the global restore only runs after all runs).
- Scope rule: flipped sheets survive **only when the walk closes** — parity back to original *and* geometric rejoin (`_closes`, endpoints within 5 % of trace extent; a closed-parity geometric miss means a downstream branch-ordering swap and demotes to open). Non-closing exits trim to the last original-assignment sample and restore outstanding flips. Doc 1 = branch-fixed strokes + refined dives to their tangency limits (one limit is A, the other side's is the tangency position itself); doc 2 = closed eight, untouched; full-circle/ellipse closed walks untouched (locus golden byte-identical).
- Continuity-tracking downstream intersections (to keep swap-affected closed walks closed instead of demoting them) deliberately deferred — PLAN records it; the closure guard keeps such walks safely open.
- 1095 tests green (U-curve fixture re-pinned to the trimmed expectation; new doc-1-shaped tangent+bisector fixture asserting two single-sheet components on *opposite* sides of AB — it fails without the flip-restore, verified by stash-run). Analyze clean. Web smoke on a fresh release build: **SMOKE PASS**; ad-hoc locus flow: **ADHOC PASS**. Both user documents re-verified by probe + render.

**Next**
- Phases 43 (viewport rotation) and 44 (line clipping) remain; either can go next.
- `main` is ahead of `origin/main` by Phases 37–39c — push when convenient.

**Open questions / gotchas**
- The walk's `open()` exit is the only place flips are undone mid-recompute; any future exit path added to `_walk` must go through it (the doc-1 regression test is the tripwire — its opposite-sides assertion exists precisely because per-component assertions can't see a leaked mirror sheet).
- If a user ever reports a figure-eight-style locus that "lost its second half" after 39c, it's likely a closed-parity walk failing the geometric closure guard (downstream ordering swap) — that's the deferred continuity-tracking case; the construction would be the fixture to build it against.
- Session cwd trap: an earlier `cd tool/web_smoke && …; cd ..` left the shell in `tool/`, making later relative paths (`NODE_PATH`, `cp`) silently wrong — prefer absolute paths in multi-step shell commands.

## Session 55 — 2026-07-16

**Done**
- **Phase 39b complete** on `phase-39b-locus-fidelity` (2 commits incl. docs), merged to `main` — locus fidelity, from two user problem documents (`locus-miss.json`: "straight line smaller than what the point traces"; `locus-miss-2.json`: "half the figure-eight, with a small hole").
- Diagnosis first (temporary probe test, deleted): the sweep machinery was exact — samples matched a ground-truth `setPointOnObjectParameter` sweep to 0.0 — so all three symptoms were sampling/rendering/semantics: (1) runs split at the circle-host 0/2π wrap, (2) ~31 world units truncated at tangency boundaries (traced point moves like √ε there; uniform step was 27 units), (3) the missing half belongs to the other intersection branch.
- Fixes, all inside `Locus.recompute`'s private sweep: cyclic run grouping (rotate the uniform sweep to start at a gap); boundary bisection + geometrically clustered ladder samples; and **linkage continuation** — a boundary whose culprit is a chain `IntersectionPoint` with coalescing candidates reverses the sweep and flips that branch (Cinderella's complex-tracing behavior, real arithmetic, sweep-scoped), closing the walk when the branch assignment returns to the original (first sample repeated) and bailing to open components on mid-walk undefineds or past an 8-segment budget.
- `IntersectionPoint.branchIndex` is now mutable under the `driver.parameter` restore contract (flipped only inside a sweep, restored before recompute returns — safe for loci sharing chain members); new public `candidateCount` getter is the coalescence signal. Drag and save semantics unchanged: deterministic persisted branch, no new persisted state; a fully-defined full-turn circle host emits the exact old uniform list, so the painter's close rule and the other goldens stayed byte-identical.
- 1094 tests green (5 new/rewritten in `locus_test.dart`), analyze clean, locus golden regenerated (the arch now closes into a half-height ellipse through its tangencies). Web smoke on a fresh release build: **SMOKE PASS**, zero console errors; the Phase 39 ad-hoc Playwright locus flow re-run: **ADHOC PASS**. Both user documents verified by probe + rendered SVG: doc 2 = one closed 105-sample figure-eight (no seam), doc 1 = two symmetric U-components walking through their tangencies onto the second parallel line.

**Next**
- Phases 43 (viewport rotation) and 44 (line clipping) remain; either can go next.
- `main` is ahead of `origin/main` by Phases 37–39b — push when convenient.

**Open questions / gotchas**
- Two razor's-edge lessons baked into `_refineBoundary`: probe candidate-count half a grid step *inside* the run (at the bisected boundary the epsilon-tolerant intersection math says "tangent, 1 candidate", and the uniform grid can land exactly on a tangency), and scan for the culprit at the undefined *uniform* sample (just past the bisected boundary an intersection can linger epsilon-defined while a downstream member — doc 1's angle bisector with a degenerating arm — is already undefined, misattributing the gap).
- A flipping locus costs ~3–5× the plain sweep per upstream drag frame (uniform pass + 48 bisections per boundary + the walk re-evaluating each segment). Fine in testing; if a deep chain drags noticeably, cache the uniform pass positions for the walk's first segment.
- The continuation deliberately flips only the *culprit* intersection per boundary and re-uses the boundaries detected under the original assignment; exotic cases (different culprit under a flipped assignment, simultaneous coalescences) truncate to open components — never wrong ink.
- Window edges still cut line-host traces (doc 1's chevrons stop at ±halfSpan) — that's the documented baked-window behavior, not a defect; recreate the locus in a wider view for a wider window.

## Session 54 — 2026-07-16

**Done**
- **Phase 39 complete** on `phase-39-locus` (4 commits incl. docs), merged to `main` — the locus kind, closing the 37–39 queue.
- `GeoLocus` seventh sealed kind (`samples: List<Vec2?>?`, nulls = gaps, null list = undefined host); `Locus` validates traced-depends-on-driver by a constructor parent walk (also rejects `traced == driver`), exposes the sweep `chain` as an unmodifiable getter, and recomputes by sweep-and-restore: save `driver.parameter`, per sample set + recompute the chain in topo order + record `traced.position`, restore bit-exactly. Circle hosts sweep one full turn (painter closes the loop when gapless); line hosts sweep `[center ± halfSpan]` baked at creation.
- 15 compiler-surfaced kind switches: painter polyline per non-null run (dash-capable, length-1 runs skipped), hit at the lines tier over consecutive sample segments, band = all non-null samples contained (none → never), fit/anchor over non-null samples (all-gap anchor falls back to the origin), lowercase naming pool with `labelVisible: false`, tree group "Loci", codec `'Locus'` with absent-param defaults (128/0/100, new `_optionalDoubleParam`). `IntersectionPoint`'s guard tightened to lines/circles-only so locus parents fail as `ArgumentError` → codec `FormatException`.
- `LocusTool` (`⇧L`, Measure row 3): tap 1 slot-consults a `PointOnObject` from the whole hit set (never the point ladder), tap 2 any point whose parent walk reaches the driver; one `AddObjectCommand`, driver haloed. New additive `ToolInput.viewExtent` (canvas passes `screenToWorldLength(width)`) bakes the line-host window: center = tap-time parameter, halfSpan = visible world width, fallback 100.
- 1092 tests green (42 new) + 22 goldens (new `locus` scene ×2 themes — gap-bearing half-height arch + dashed closed loop — the 20 existing byte-identical before regenerating), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors, drive.js untouched. Ad-hoc Playwright: segment + glued driver + midpoint, `⇧L` + two taps ink a view-spanning trace; saved doc carries `Locus` (driver parent 0, `sampleCount 128`, tap-time `center 450`/`halfSpan 1000`), auto-named `b` label-hidden; one Ctrl+Z empties.

**Next**
- Phases 43 (viewport rotation) and 44 (line clipping) are the remaining queued phases; either can go next.
- `main` is ahead of `origin/main` by several phases (37–39) — push when convenient.

**Open questions / gotchas**
- Painter/hit-tester locus tests drive a private `_StubLocus extends GeoLocus` with hand-picked samples (kinds are open below the sealed root) — a handy pattern for future kind tests; the painter run-count test records `drawPath` calls via a `noSuchMethod` canvas stub and asserts loop closure with `computeMetrics().single.isClosed`.
- A locus recompute costs `sampleCount × chain-length` member recomputes per upstream drag frame (PLAN's documented perf note, 128 default). Fine in the ad-hoc browser check; revisit with adaptive sampling only if a deep chain drags noticeably.
- The locus hit path ignores the circle-host closing segment (samples only); the gap it leaves is one sample-spacing wide, well under any usable threshold.
- `Locus.center`/`halfSpan` are persisted for circle hosts too (unused there) — harmless, keeps the codec uniform.

## Session 53 — 2026-07-16

**Done**
- **Phase 38 complete** on `phase-38-measurements` (6 commits incl. docs), merged to `main` — distance + area measurements, the sixth sealed kind and the seventh (Measure) toolbar group.
- `polygonSignedArea` (shoelace, positive CCW; |shoelace| for self-intersecting loops, bowtie pinned) in new `domain/math/polygon_math.dart`; `GeoMeasurement` sealed kind (`value` + `anchor`, undefined with the parents); `DistanceMeasurement` (|ab|, midpoint anchor) and `AreaMeasurement` (constructor-enforced `GeoPolygon || GeoCircle` subject — ill-typed saves normalize to `FormatException` via the decode loop; |shoelace| / πr², vertex-average / center anchor).
- All kind switches swept (15 compiler-surfaced sites): measurements get hit priority 4 (polygons drop to 5, anchor distance + band-by-anchor), painter draws nothing — the text rides `labelText`, which now always composes a value part for measurements (`a = 5.00` named, bare `5.00` otherwise; `AreaMeasurement` through `formatArea`); naming joins the lowercase pool but **keeps `labelVisible: true`** (unlike lines/circles/polygons — the text is the object); tree group "Measurements"; kind labels Distance/Area; codec entries with empty params + `any(0)` subject.
- Tools: distance = `TwoPointTool` + `buildDistance` tear-off (`D`; Points catch-all excludes it), `AreaTool` = dedicated stateless one-tap class consulting `hit`/`extraHits` for the topmost polygon/circle, never the point ladder (`⇧D`). Measure flyout (icon `straighten`) after Macros. The canvas tap handler checks measurement `labelScreenRect`s before geometry (label-drag precedent), so text dragged off its anchor stays tappable; the text drag itself rides the generic label drag unchanged.
- 1058 tests green (54 new) + 20 goldens (new `measurements` scene ×2 themes; the 18 existing verified byte-identical *before* regenerating), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors, drive.js untouched (14 detected icons; the ≥10 check absorbed the new group). Ad-hoc Playwright: `D` + two taps and `⇧D` inside an `X V` polygon render text ink and save `DistanceMeasurement` + `AreaMeasurement` (area subject = the polygon; auto-names `A B a C D E b c` — shared lowercase pool, labels shown), three Ctrl+Z empty.
- Session 44's re-measure note resolved: a new widget test pins wide chrome at the exact 980-px floor (leading tree icon hit-testable with the Measure group aboard); the compact strip test re-counted to seven groups.

**Next**
- Phase 39 (locus) closes the 37–39 queue; Phases 43 (viewport rotation) and 44 (line clipping) can still slot anywhere.
- `main` is ahead of `origin/main` by this phase — push when convenient.

**Open questions / gotchas**
- An `AreaMeasurement` over an `Arc`/`Sector` subject passes the `GeoCircle` constructor test and reports the full **carrier-disc** πr² — and `AreaTool` will consume a tapped arc/sector. Documented at the class; if it reads as a bug in practice, exclude arcs at the tool (the `fillables` `!Arc` precedent).
- The measurement text-rect promotion runs only in the no-tool selection path of `_handleTap`; tool taps (incl. `DeleteTool`) see measurements by anchor distance only — deleting a far-dragged text needs a tap at its anchor or tree selection.
- The measurement label-drag canvas test needed a 40-px move: 30 px sits under the scale recognizer's ~36-px pan slop (the older label test's 42-px diagonal cleared it silently). Future canvas drag tests should budget ≥ 40 px.
- drive.js survived untouched this time, but the Measure group shifted the whole wide cluster left another 48 px — the next app-bar/toolbar icon will re-roll the popup-side dice again (standing Session 43/50 gotcha).

## Session 52 — 2026-07-16

**Done**
- **Phase 37 complete** on `phase-37-polygon` (4 commits incl. docs), merged to `main` — `GeoPolygon` fifth sealed kind + `Polygon` (first variable-arity object) + `PolygonTool` + circle/polygon fill.
- `GeoPolygon.polygonVertices` (null while any vertex is undefined; collinear/self-intersecting stays defined); `Polygon` enforces ≥ 3 vertices, `parents => vertices`, vertex list copied unmodifiable. Codec `'Polygon'` decodes variable arity over `parents.length` (< 3 → the constructor's `ArgumentError` → `FormatException`; no version bump).
- All eight documented kind switches + six more the compiler surfaced (constructor guards in `IntersectionPoint`/`PointOnObject`, tap-ignored arms in `point_and_line_tool`/`transform_object_tool`, codec-test `geometryOf`). Hit tester: interior = distance 0 at new lowest priority 4 (even-odd ray cast), outside = min clamped edge distance, band = every vertex contained.
- Painter `_drawFill` gains polygon + `GeoCircle` filled-disc cases; `Arc` deliberately skips fill (wedge vs circular segment is ambiguous) via an explicit break arm, and the inspector's `fillables` matches (`GeoAngle || GeoPolygon || (GeoCircle && !Arc)`).
- `PolygonTool` over `MultiPointTool` (onInput fully overridden): ladder taps, closes on re-tapping vertex 1 once ≥ 3 collected, other collected-vertex taps ignored; existing vertices matched by hit identity, private new ones by tap distance ≤ `snapThreshold`; one `MacroCommand`, `fillAlpha: 0.25` baked. Macros flyout row 1 ("Polygons & shape macros"), `X V`, auto-name joins the lowercase pool with `labelVisible: false`.
- 1004 tests green (22 new), 18 goldens (new `polygons` scene ×2 themes, 16 existing byte-identical), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — the smoke's macro section drives Square via `X S`). Ad-hoc Playwright: `X V` + 3 taps + close tap fills the interior, saved doc = `3×FreePoint + Polygon` (fillAlpha 0.25, names `A B C` / `a`), one Ctrl+Z empties.

**Next**
- Phase 38 (distance + area measurements) heads the queue — it consumes `GeoPolygon` (`AreaMeasurement`) and adds the seventh **Measure** toolbar group (re-measure `_wideChromeMinWidth = 980` per the Session 44 note); then Phase 39 (locus). 43–44 can still slot anywhere.

**Open questions / gotchas**
- Dragging a polygon body drags the rigid union of *all* vertex ancestors (the generic no-tool path) — fine, but a polygon over glued/derived vertices moves only their free ancestors, which can distort; same rule as every derived curve, just more visible on a filled region.
- With snapping/hit thresholds at 0 (never in the real canvas), a *new* first vertex can't be re-tapped to close — the close test matches by distance ≤ `snapThreshold`. Existing-point first vertices close by identity regardless.
- `PolygonTool.pointCount` is a vestigial 3 (`MultiPointTool` requires it; the overridden `onInput` never consults it) — documented at the override.
- The `Sector` import in `attributes_inspector.dart` became `Arc` (sectors now qualify through the `GeoCircle && !Arc` test) — anyone grepping for the old fillables shape should read the Phase 37 comment there.

## Session 51 — 2026-07-16

**Done**
- **Phase 45 complete** on `phase-45-snap-to-grid` (3 commits incl. docs), merged to `main` — snap to grid, riding Phase 36's adaptive step.
- `DocumentSettings.snapToGrid` (default false, `toggleSnapToGrid`) — same contract as the other flags: not undoable, persisted via an additive `"snapToGrid"` codec key (absent → false, no version bump), File > New resets; deliberately independent of `showGrid`. Third checked item in the grid popup + compact overflow; menu-only, no shortcut.
- Pure `snapToGrid(Vec2, step)` in new `domain/math/grid_snap.dart` (componentwise round-to-nearest; step ≤ 0 / non-finite passes through — 0 is the wire format for "off"; glados idempotence + half-step bound).
- Additive `ToolInput.gridSnapStep`: the canvas passes `gridStep(scale)` while the toggle is on (`gridStep` stays presentation-side; domain only sees the resolved number). Grid rounding is the resolution ladder's **last** rung — only rung 4's `FreePoint` quantizes; point reuse, curve gluing and crossing snaps always win and glued positions are never rounded.
- Single free-point drags quantize the preview per frame and commit the snapped end through the usual one `MoveFreePointCommand` (`DragSession.start`/`startDrag` gained a `gridSnapStep` param; one `_freePointPosition` getter feeds preview and command; a drag that quantizes back onto its start commits nothing). Rigid `TranslateObjectsCommand` drags and `PointOnObject` slides deliberately never snap.
- 999 tests green (20 new), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched). Ad-hoc Playwright: popup toggle on → P-taps at odd coordinates land on step-50 crossings, a drag commits snapped, the saved document carries `snapToGrid: true`.

**Next**
- Phase 37 (Polygon kind + circle/polygon fill) heads the 37–39 queue; 43–44 can slot anywhere.
- `main` is ahead of `origin/main` (Phases 36 + 45) — push when convenient.

**Open questions / gotchas**
- Snapping is a hard quantize while on: a free point *cannot* be placed off-grid until the toggle goes off (deliberate — "fixed to grid", not a proximity gate). Pre-existing off-grid points stay put until dragged, then jump to the grid on the first preview frame.
- The macro/dialog tools' *position-only* taps (trapezium 4th tap, rectangle height, segment-by-length direction) do **not** snap — they project onto hidden curves (`PointOnObject` parameters), where quantizing the tap would not quantize the result anyway. Only ladder rung-4 free points and single free-point drags snap; watch for "the shape corner ignores the grid" feedback.
- In widget tests, popup-item text taps warn ("would not hit test") because a `CheckedPopupMenuItem`'s title paragraph never appears in the hit path — `grid_menu_test.dart` now taps `widgetWithText(CheckedPopupMenuItem, …)` instead; use that pattern for future popup tests.

## Session 50 — 2026-07-16

**Done**
- **Phase 36 complete** on `phase-36-axes-grid` (5 commits incl. docs), merged to `main` — XY axes + background grid.
- `DocumentSettings` (`showAxes`/`showGrid`, defaults false) + `documentSettingsProvider` — the `ViewportState` pattern: not undoable, File > New resets, File > Open applies, Save snapshots. Codec: two additive top-level keys beside `viewport` (absent → false, non-boolean → `FormatException`, no version bump).
- Painter background layer (drawn first, objects paint over): `gridStep(scale, {minPx: 48})` in `presentation/canvas/grid_layout.dart` (smallest `{1,2,5}×10^k` ≥ 48 px, fp-robust decade walk) + `formatTick` (trailing zeros trimmed, single `0`); hairline grid at every step multiple, 1.5-px axes through the world origin, tick labels riding the *visible* axes (off-screen axis → no labels; one `0` in the origin's lower-left quadrant). Colors via a new `CanvasColors` `ThemeExtension` — deliberately not `outline`/`outlineVariant`, which Material widgets read for their own chrome.
- UI: grid-icon popup (two checked items) after Reset in wide chrome, both entries absorbed into the compact overflow; `⇧G`/`⇧X` toggle grid/axes — single strokes resolve before the `G`/`X` leaders and the leaders' first strokes forbid Shift (resolver + editor tests pin no leader arming). Export dialog gains "Include axes & grid (as shown)" (`ExportOptions.includeAxesGrid`, shown only while either toggle is on); an unticked export is byte-identical to a toggles-off one (flow test).
- 978 tests green (23 new), analyze clean, new `grid` golden ×2 themes with the 14 existing goldens byte-identical. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors — after repairing drive.js (below). Ad-hoc Playwright check: `⇧G` inks the grid patch, `⇧X` adds axes after nudging the origin into view, saved document carries both flags, toggling off restores a pure-white canvas.

**Next**
- Phase 37 (Polygon kind + circle/polygon fill) heads the 37–39 queue; 43–45 can slot anywhere (45 now has its Phase 36 prerequisite).
- `main` is ahead of `origin/main` by this phase — push when convenient.

**Open questions / gotchas**
- **drive.js repaired again**: the grid button pushed the Lines group to the 1000-px viewport's exact midline, flipping its flyout side — Segment now activates via its `S` key (the Session 39 `X S` / Session 43 `P` precedent). No toolbar *group* flyout is exercised by the smoke anymore (File popup still covers real-browser popup mechanics); the next app-bar icon will shift popup sides again.
- The wide action cluster is now ~13 detected icons; `_wideChromeMinWidth = 980` still clears it (smoke ran wide at 1000 px), but Phase 38's Measure group re-measure note from Session 44 stands.
- Tick labels ride their axes, so with axes on but the origin panned far off-screen no coordinates are visible anywhere — GeoGebra clamps labels to the screen edge instead; revisit if it grates.
- The `0.05×–50×` zoom clamp keeps `gridStep` in {1, 2, 5} × 10⁰…10³ at the default 48-px minimum; `formatTick`'s fixed-6-decimals trim covers far beyond that but would print garbage past ~1e15 (unreachable).

## Session 49 — 2026-07-15

**Done**
- **Phase 46 complete** on `phase-46-merged-angle-tool`, merged to `main` — the vertex-angle and line-angle tools merged into one two-mode `AngleTool` on `A` (user request): first tap on a line → angle between two lines (`LineAngle.near`, tap-picked wedge), first tap on a point/empty canvas → arm–vertex–arm `VertexAngle`.
- The Phase 29b two-mode machine was extracted from `AngleBisectorTool` into abstract `TwoLineOrThreePointTool` (`buildFromLines`/`buildFromPoints` hooks); `AngleBisectorTool` and `AngleTool` are thin subclasses. `angle_bisector_tool_test.dart` passed **unchanged**, pinning the refactor as behavior-preserving.
- `TwoLineTool` deleted (fully unused after the merge); `AppAction.vertexAngleTool`+`lineAngleTool` collapsed into `angleTool`; **`⇧A` is now a free shortcut** (deliberately not rebound). Angles flyout is two rows ('Angle (two lines, or arm/vertex/arm)' + by-size); `_threePoint` helper lost its `allowCurveTaps` param (the domain flag stays — tested Phase 29b API, no production `false` user).
- 952 tests green (20 in new `angle_tool_test.dart` mirroring the bisector suite), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it never clicked the Angles flyout). Ad-hoc Playwright check of both modes end to end: `A`+3 empty taps → save parses `3×FreePoint + VertexAngle`, one Ctrl+Z empties; `A`+two line taps → `LineAngle`, marker pixels in the tapped wedge, zero `PointOnObject` glued; a mid-flow line tap in point mode glues nothing; `⇧A` activates nothing.

**Next**
- Phase 36 (XY axes + grid) still heads the 36–39 queue; 43–45 can slot anywhere. `⇧A` is available if a new tool wants it.
- `main` remains ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- Point mode now *ignores* curve taps outright (the bisector's rule) instead of `ThreePointTool(allowCurveTaps: false)`'s hit-set refusal — user-visible behavior is equivalent (no glue, no half-snapped free point), but the exact refusal condition differs at the margins: the old flag refused only when an in-threshold curve had no point hit; the new rule ignores any tap whose top hit is a line.
- The shortcut-cheat-sheet and flyout rows share the 'Angle (…)' wording but not a single constant — if the label is reworded, both `shortcut_table.dart` and `toolbar.dart` need the edit (same as every other tool row).

## Session 48 — 2026-07-15

**Done**
- **Phase 35 complete** on `phase-35-show-value` (4 commits incl. docs), merged to `main` — segments and angles can show their measured value in the label.
- `ObjectAttributes.showValue` (`@Default(false)`, additive — no codec change/version bump) + `measure_format.dart` (`formatLength` 2 decimals, `formatAngle` degrees 1 decimal + `°`, `formatArea` forwards to length for Phase 38).
- Shared `labelText(GeoObject)` in `label_layout.dart`: name part (`labelVisible` && named) and value part (`showValue` on a `Segment`/`GeoAngle`) compose as `c = 5.00` / bare part / null. Both `_drawLabel` (now takes the text) and `labelScreenRect` consume it, so painted text and drag rect can't drift; a value-only label is grabbable. `labelText` skips the visible/isDefined gates — callers own them.
- Inspector "Show value" tristate checkbox under "Show label" (Fill pattern): shown while the selection has a segment/angle, targets exactly that slice, one command per tap.
- New `measures` golden scene ×2 themes; the 12 existing goldens stayed byte-identical under the label refactor. 947 tests green (17 new), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — no toolbar/flyout changes at all this phase). Served-vs-disk hash verified again (the stale Jul 5 server on 8321 still running).

**Next**
- Phase 36 (XY axes + grid) heads the 36–39 queue; 43–45 can slot anywhere.
- `main` is ahead of `origin/main` (~20 commits) — push when convenient.

**Open questions / gotchas**
- `labelText` composes the *value* for any defined segment even when undefined-adjacent (coincident endpoints kill `isDefined` first, so nothing paints) — if a future kind gains a value whose definedness diverges from `isDefined`, revisit the gate split.
- Value labels use fixed decimals by design; long lengths (e.g. `12345.68`) widen the label rect — the 40-px label-drag clamp is on the *offset*, not the rect, so nothing breaks, but huge values can visually collide with nearby objects.
- `showValue` is independent of `labelVisible`: unticking "Show label" on a measured segment leaves the bare value painted. Deliberate (the name part is what it hides), but may read as "the label won't hide".

## Session 47 — 2026-07-15

**Done**
- **Phase 34 complete** on `phase-34-given-lengths` (4 commits incl. docs), merged to `main` — circles and segments with dialog-given lengths.
- `FixedRadiusCircle` (center parent + fixed `radius` param, constructor rejects ≤ 0/non-finite; undefined iff the center is; codec entry with `radius` via `_doubleParam`, kitchen-sink `frc`). Kind label deliberately rides the `GeoCircle` → "Circle" fallback, same as `CircleCenterPoint`.
- `FixedRadiusCircleTool` (`MultiPointTool`, `pointCount` 1, dedicated class for the tear-off highlight): dialog radius, one ladder-resolved tap = center. Circles flyout row 2 "Circle by radius (tap the center)…", `⇧C`, `circlesActive`.
- `FixedLengthSegmentTool`: ladder tap for endpoint A + position-only direction tap (trapezium 4th-tap precedent) → one `MacroCommand` of hidden `FixedRadiusCircle(A, L)` + visible `PointOnObject.near` B + visible `Segment(A, B)`; |AB| pinned under dragging A and sliding B. Lines flyout after Ray, `⇧S`, `linesActive`.
- Dialogs: shared `_LengthDialog` behind `askCircleRadius`/`askSegmentLength`; `_parseLength` reuses `_parseRatio` restricted to finite positive — fractions (`5/2`) work, garbage/non-positive reads as cancel.
- 930 tests green (14 new), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — Segment stays Lines row 2; the Circles flyout is never clicked by index). Served-vs-disk `main.dart.js` hash verified identical (the stale 8321 server again).

**Next**
- Phase 35 (show-value labels) heads the 35–39 queue; 43–45 can slot anywhere.
- `main` is ahead of `origin/main` (~15 commits) — push when convenient.

**Open questions / gotchas**
- The Lines flyout is 9 rows now ("Segment with given length…" sits 4th, after Ray); anything clicking Lines rows by index past row 3 must account for it (drive.js only uses row 2).
- `⇧C`/`⇧S` join `⇧B`/`⇧A`/`⇧T` — the shifted-letter tool namespace is filling up like the G leader.
- A `FixedLengthSegmentTool` direction tap on an existing point projects its position but never consumes it (trapezium rule) — the segment will *look* attached to that point without being tied to it; watch for confusion.
- The segment-by-length macro's B slides on a hidden circle: selecting B and dragging moves it around A (direction change), not along the segment — deliberate (Phase 14 slide-drag), but worth remembering when it reads as "the endpoint won't move freely".

## Session 46 — 2026-07-15

**Done**
- **Phase 33 complete** on `phase-33-lines-group` (4 commits), merged to `main` — the Lines group gains a perpendicular bisector and tangents from a point.
- `PerpendicularBisectorLine` (dedicated kind, `AngleBisectorLine` precedent): carrier `LineEq.pointDirection(midpoint, join.perpendicular)`; coincident parents (the `carrierLineThrough` `closeTo` convention) → undefined, recovers. Codec entry, empty params, kind label "Perpendicular bisector".
- `tangentPointsToCircle` (`domain/math/tangents.dart`): Thales circle over center–external ∩ the given circle via `intersectCircleCircle`, so the first-point-left-of-center→point branch order is continuous under drags; on-circle → the point itself, strictly inside naturally empty (the Thales circle lies wholly inside — documented, no guard needed), radius ≤ ε guarded empty.
- `TangentLine` (point + circle parents, `branch` 0/1): carrier point-direction through the touch point ⟂ the radius; both branches undefined together while inside, recover with sides preserved; on-circle both collapse to the tangent at the point. Codec entry (`branch` via `_intParam`, new `GeoCircle` typed-parent helper); the kitchen-sink tangent rides the ratio point at (9, 0) so it round-trips defined.
- Tools: perpendicular bisector = `TwoPointTool` + `buildPerpendicularBisector` tear-off (Lines flyout after Angle bisector, `⇧B`); new `TangentTool` (`PointAndLineTool` pattern with a circle slot consulted from `hit`/`extraHits` *before* the point ladder — a tap on the target circle never glues) emits **both** tangents in one `MacroCommand` (Lines flyout last, `G N`). `linesActive` covers both; Lines tooltip reworded.
- 916 tests green (27 new), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it clicks Lines row 2, Segment, which kept its position; the flyout is 8 rows now).

**Next**
- Phase 34 (FixedRadiusCircle + circle-by-radius / segment-by-length dialog tools) heads the 34–39 queue; 43–45 can slot anywhere.
- `main` is ahead of `origin/main` (the 4 pre-session commits plus this phase) — push when convenient.

**Open questions / gotchas**
- `TangentTool` ignores *any* circle-flavored tap while the circle slot is full — the target circle (deliberate, no gluing) but also a different circle (`PointAndLineTool` second-line parity). Silent refusals again — watch for "the tool feels stuck" feedback (the Phase 40 gotcha's sibling).
- The tangent pair is one `MacroCommand`: undo removes both lines, but each is individually deletable afterwards (per PLAN, deliberate).
- The G-leader now carries C/O/I/U/3/R/A/S/L/P/T/V/D/N — nothing conflicts yet, but the namespace is filling up.
- Anything clicking Lines flyout rows by index beyond row 2 must account for the two appended rows (drive.js only uses row 2 and is unaffected).

## Session 45 — 2026-07-15

**Done**
- **Phase 32 complete** on `phase-32-tree-multiselect-search`, merged to `main` — object tree gets row long-press multi-select and a search filter.
- Row long-press toggles the object in/out of the selection with `HapticFeedback.selectionClick` (`ListTile.onLongPress`, the touch shift-tap — canvas Phase 25b / header Phase 26 convention); new app-level cheat-sheet `GestureRow` "Long-press tree row". Header long-press stays a *union* (selects groups), row long-press is a *toggle* (targets individuals) — deliberate asymmetry carried over from Phase 26.
- Search field pinned at the top of the panel: case-insensitive substring over each row's display label (name, or kind label when unnamed), non-matching rows and empty groups hidden, `×` clears. The panel became a `ConsumerStatefulWidget`; the query is widget state and resets when the panel closes/the drawer dismisses. Filtering runs *before* grouping, so group-header select-by-kind acts on exactly the filtered matches with no extra plumbing. The existing `EditableText` focus guard covers the field — pinned by a widget test sending a raw `P` key.
- 889 tests green (4 new), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it never opens the tree).

**Next**
- Phase 33 (Lines group: perpendicular bisector + tangents from a point) heads the 33–39 queue; 43–45 can slot anywhere.
- `main` is 3 commits ahead of `origin/main` (the Session 44 backlog was pushed in the meantime) — push when convenient.

**Open questions / gotchas**
- The tree panel now always renders a `TextField`; any `EditorScreen` test asserting on `find.byType(TextField)` with the tree open must scope its finder (the hidden-object inspector test now looks inside `AttributesInspector`).
- Port 8321 had a stale `http.server` from Jul 5 still listening, so the fresh serve attempt died with "Address already in use" — harmless (the old server reads `build/web` from disk per request; served `main.dart.js` hash was verified identical to the fresh build), but kill it if a smoke ever looks stale.
- Search matches the *display* label only: a named object does not match its kind label ("Segment" finds unnamed segments, not named ones). Per spec, but watch for "search doesn't find my segment" feedback.

## Session 44 — 2026-07-10

**Done**
- **Phase 42 complete** on `phase-42-responsive-chrome`, merged to `main` — the Phase 25 `isCompact` gate split in two: `compactPanels` (shortestSide < 600) decides only drawers vs docked panels; new `compactChrome` (width < `_wideChromeMinWidth` = 980, sized to the wide action cluster with Measure-group headroom) decides app-bar density. iPad portrait now gets the compact bar over docked panels instead of `NavigationToolbar` painting the trailing cluster over the leading icon.
- The leading tree `IconButton` is now explicit in every layout (a null `leading` beside a `drawer` made Material inject the auto-hamburger — the reported burger) and branches on the *panel* gate: drawer opener under `compactPanels`, docked toggle with `isSelected` otherwise. The overflow's object-tree entry branches the same way and relabels to "Hide object tree" while the docked panel is open; the style button keys on `compactPanels` (a docked inspector is already visible).
- Test fallout embraced: 20 widget tests broke because flutter_test's default 800×600 window is now compact chrome — which is exactly the too-narrow-for-the-cluster window the gate exists for. New shared `test/wide_window.dart` (`useWideTestWindow`, 1280×800) called from every `EditorScreen`-pumping suite plus smoke/theme-toggle tests.
- 885 tests green (5 new: phone leading-opens-drawer + a tablet-portrait group incl. the hit-testability tap that a pre-42 overlap would fail), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched). Ad-hoc Playwright at 810×1080: leading icon click shifts the canvas right 240 px (docked panel, not a drawer) and back exactly.

**Next**
- Phase 32 (object tree: long-press multi-select + search) heads the 32–39 queue; 43–45 can slot anywhere.
- `main` now ~14 commits ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- drive.js's 1000-px viewport clears the 980-px wide-chrome gate by only 20 px. The constant carries Measure-group headroom, but if the *smoke viewport* ever narrows — or the gate widens — the whole suite silently flips into compact chrome. Re-check when Phase 38 lands.
- Any new `EditorScreen` widget-test file must call `useWideTestWindow` (or set its own size) — the flutter_test default now renders compact chrome.
- Landscape phones ≥ 980 px wide (e.g. 1000×500) get wide chrome over drawer panels: the wide cluster plus a drawer-opening leading icon. Intended by the gate split, but no test pins that combination.

## Session 43 — 2026-07-09

**Done**
- **Phase 41 complete** on `phase-41-delete-tool`, merged to `main` — respecced first (PLAN/TODO commit) per user request, widened from "selection-gated app-bar delete button" to a **tap-driven Delete tool** plus **Hide acting on the selection at activation**.
- New `DeleteTool` (`domain/tools/delete_tool.dart`, stateless `VisibilityTool` sibling): tap = one `DeleteObjectsCommand` = one undo step. The cascade dialog stays presentation-layer as a *canvas pre-gate*: `confirmCascadeDelete` extracted from `deleteSelectionWithConfirmation` (both paths share one dialog), awaited in `_handleTap` before dispatching to `handleInput`, with mounted/still-present guards so a cancelled dialog or stale hit never puts an empty delete on the stack.
- App-bar: always-visible delete button (both layouts, before undo/redo, `isSelected` while active via a narrow `toolProvider.select` watch) toggles the tool; activating with a selection deletes it first through the same confirmation. Inspector's Delete button removed. `Del`/`Backspace` one-shot behavior unchanged.
- Hide (`H`): activation now executes `VisibilityTool.hideAll` over the selection — one command over the visible subset, nothing on the stack when none visible, selection stays selected (Phase 7 precedent). Activation goes first so a Phase 30b drag commit precedes the hide on the undo stack (test pins the order). `Shift+H` deliberately untouched.
- 880 tests green (18 domain incl. `hideAll`, 4 canvas tap-delete widget tests, 8 flow tests in new `delete_tool_flow_test.dart` — the four inspector delete tests moved there and re-pointed — 4 new H/Shift+H shortcut tests), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors, plus an ad-hoc Playwright check of the button flow itself (activate → selection deleted → tap-delete → Esc).

**Next**
- Phase 42 (responsive chrome split) is the next small user-facing fix; the 32–39 queue behind it.
- `main` is ~12 commits ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- **drive.js broke and was repaired twice over**: (1) theme toggle re-indexed to `icons[length - 2]` — the always-enabled delete button is now the last detected glyph; (2) the cluster shift put the Points group at the 1000-px viewport's exact *midline*, flipping which side its flyout opens on — the first smoke section now activates the point tool with `P` (Session 39 Square precedent). Anything else added to the app bar will shift popup-side behavior again.
- A tap-delete on an object whose cascade stays self-contained is instant — no dialog, matching Del. Watch for "I deleted more than I meant" feedback anyway: the dialog only lists *unselected/untapped* casualties.
- The delete button is deliberately not selection-gated anymore (it must be reachable to *enter* tap-delete), so the compact actions row gained one permanent icon; Phase 42's ~980-px chrome constant must count it.

## Session 42 — 2026-07-09

**Done**
- **Phase 40 (transform images reused across gestures) complete** on `phase-40-transform-image-reuse`, merged to `main`. The reported duplicate-name bug: transforming polygon sides one by one re-imaged each shared vertex per gesture. Now `TransformObjectTool` consults a new `equivalentExisting` helper (`domain/tools/transform_equivalence.dart` — same concrete kind, identical parent *instances* slot-by-slot, equal params, `RotatedPoint.angle` exact) before adding any image point or rebuilt curve; equivalent image points are reused as parents (attributes untouched — hidden equivalents stay hidden).
- Additive `ToolInput.objects` (whole construction in insertion order, default `const []`) supplied at the canvas's single `ToolInput` site; the tool consults it at commit time.
- Design decision: a commit that would add nothing (the final image/rebuilt curve already exists) returns `ToolIgnored` **without resetting** — `handleInput` doesn't bump the preview revision on `ToolIgnored`, so resetting would leave stale halos. Instead the committing tap's tentative slot is unwound (`_point` / `_params.removeLast()`), the collection stays live, and a different center/mirror still commits.
- Also committed on `main` before starting: a stray uncommitted Phase 45 (snap to grid) spec in PLAN/TODO — written after Session 41's commit, apparently from a planning follow-up that ended without committing.
- 860 tests green (5 tool tests incl. unwind-in-either-order, 7 helper units, provider end-to-end through the naming interceptor pinning "shared vertex named once"), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched).

**Next**
- Phase 41 (delete out of the inspector, into the app bar) is the next small user-facing fix, then 42; the 32–39 queue behind them.
- `main` now ~4 commits ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- A refused duplicate commit is silent — the tap does nothing and the tool keeps waiting. Defensible (nothing to add), but watch for "the tool feels stuck" feedback.
- Cross-gesture reuse makes later commits depend on earlier gestures' image instances; safe under the strictly LIFO undo stack (gesture 2 always undoes before gesture 1) and cascade-delete already handles the rest.
- `equivalentExisting` scans the whole construction per image consult — O(objects), fine at realistic sizes.

## Session 41 — 2026-07-09

**Done**
- **Planning-only session**: five user-reported bugs/features specced into PLAN.md + TODO.md as Phases 40–44 (no code touched). Root causes confirmed in source first.
- **Phase 40** — transform duplicate names: `TransformObjectTool._commitSource`'s identity-keyed image map dedupes only *within* a gesture; segment-by-segment transforms re-image shared vertices. Fix: additive `ToolInput.objects` + equivalent-existing-object reuse (same kind, same parent instances, equal params).
- **Phase 41** — Delete leaves the inspector (it hid behind the mobile palette icon; deletion isn't styling) → selection-gated app-bar delete button on both layouts, same `deleteSelectionWithConfirmation` path.
- **Phase 42** — compact tree toggle "became a burger" because `leading: null` + a `drawer` makes Material inject `DrawerButton`; iPad-portrait overlap because the wide actions cluster (~800 px) exceeds the bar and `NavigationToolbar` paints trailing over leading. Fix: split `isCompact` into `compactPanels` (shortestSide < 600) and `compactChrome` (width < ~980), explicit `account_tree_outlined` leading.
- **Phase 43** — two-finger viewport rotation as *pure view state* (decided: coordinates and world-aligned grid stay intact; rotating the world would rewrite saved geometry). Additive viewport `rotation` key, arming threshold + snap-back, band containment goes screen-space.
- **Phase 44** — Cinderella-style line clipping: `lineClip` 0/1/2 — infinite / defining points / **incident-point span** (mode 2 counts on-carrier defining points, hosted `PointOnObject`s, parenting `IntersectionPoint`s — user-corrected from defining-points-only so bisectors/parallels and later-created farther points clip right; rays clamp their far end too). Display + hit only; carriers stay infinite.

**Next**
- Phases 40–42 are small user-facing fixes — worth scheduling ahead of the bigger 32–39 queue; 43–44 can slot anywhere (43 composes with 36's world-space grid in either order).
- `main` still ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- Phase 40's reuse is keyed on parent *instances* and exact params — a numerically-identical image built from different parents deliberately doesn't match.
- Phase 42's ~980 px chrome constant must be re-measured once the Measure group (Phase 38) lands; the widget test at iPad sizes is the guard.
- Phase 43 golden scenes need a rotated variant; check the exporter's region framing math under rotation when implementing (screen-rect → viewport assumes axis alignment today).

## Session 40 — 2026-07-08

**Done**
- **Phase 31 (line-angle wedge picked by taps) complete** on `phase-31-line-angle-wedge`, merged to `main`. `LineAngle` now marks the wedge the user pointed at instead of always folding to the acute angle: each tap picks the half of its line nearer the tap, and the marker opens between those half-lines with sweep in (0, π) — obtuse pairs reachable, the right-angle square lands in the tapped quadrant.
- New `AngleGeometry.betweenHalfLines` (directions read as given, not up to sign) beside `betweenLines` — deliberately *not* refactored into one to keep legacy rendering fp-byte-identical. `LineAngle` gains nullable `sign1`/`sign2` ∈ {−1, +1} (both-or-neither, constructor-validated) and a `.near` factory baking them from the taps (`TwoLineBisectorLine.near`'s sign convention). Null signs = legacy always-acute mode.
- `TwoLineBuilder` grows the two tap world-positions (`TwoLineTool` remembers the first tap); `buildLineAngle` switches to `LineAngle.near`. Codec: `sign1`/`sign2` params encoded only when present, decoded via a new `_optionalIntParam` — additive, no version bump; a kitchen-sink test pins that a null-signs `LineAngle` encodes with *empty* params and decodes back to the acute fold.
- 847 tests green (four tap-quadrant combos, obtuse sweep, right-angle quadrant arms, drag continuity over a 60°→90° sweep, parallel-creation fallback, sign validation, codec round-trip with signs + legacy), analyze clean, goldens untouched (golden scenes build `LineAngle` sign-less). Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it builds no angles).

**Next**
- Phase 32 (object tree: long-press multi-select + search) is the next unchecked phase; 33–39 queue behind it.
- `main` is ahead of `origin/main` (now ~12 commits) — push when convenient.

**Open questions / gotchas**
- The signs share `TwoLineBisectorLine.branch`'s documented wart: deterministic, not continuous — a drag that reverses a carrier's canonical direction (its defining points swapping order) flips which half the sign means, so the marked wedge jumps to the complement. Same acceptance as the intersection branch index.
- `LineAngle.near` on currently-parallel carriers falls back to signs +1/+1 (the angle is undefined then anyway); when the lines are later dragged to cross, the marked wedge is the +1/+1 one, not anything tap-derived.
- The stale `python3 -m http.server 8321` (running since Session 32) was reused for the smoke again — files are read per request, so the fresh build is what got tested.

## Session 39 (later) — 2026-07-08

**Done**
- **Phase 30b (commit in-progress drag on tool activation) complete** on `phase-30b-commit-drag-on-activate` (2 commits incl. the PLAN/TODO spec), merged to `main`. User feedback on Phase 30: "Pressing Shift-H after a V change of the drawing might undo the V change" — confirmed by repro test. `ToolNotifier.activate()` opened with `_abandonDrag()`, which rolls the drag preview back with **no command**; every tool shortcut always did this, but Phase 30 put tool activations on `H`/`Shift+H` — exactly the keys pressed right after arranging objects — where the old bindings ran plain commands and never touched the drag. A shortcut a beat before pointer-up (or within macOS three-finger drag's post-lift grace period) silently and *unrecoverably* discarded the move.
- Fix: `activate(tool)` with a non-null tool now **ends** the drag — the one start → end command executes on the stack — before switching; a committed half-drag is one undo away, a cancelled one is gone, so the asymmetry decides. `deactivate()` (`Esc`/`V`) keeps the rollback (Esc mid-drag stays the deliberate abort), as do the pointer-cancel paths.
- 839 tests green (3 provider: commit/abort/unmoved-drag; 2 widget: `Shift+H` mid-drag keeps the move + one undo restores, `Esc` mid-drag empty stack), analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched).

**Next**
- Phase 31 (line-angle wedge picked by taps) is the next unchecked phase; 32–39 queue behind it.
- `main` is ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- A tool switch mid-drag now commits the drag-so-far even if the user was about to fling the object back — they must undo rather than keep dragging. Deemed the right trade: reversible beats unrecoverable.
- `V` deactivates, so `V` mid-drag *aborts* the drag like Esc. Defensible (V = "back to move/select" = the mode the drag is already in), but if users read V as harmless, this could surprise — watch for feedback.

## Session 39 — 2026-07-08

**Done**
- **Phase 30 (Hide & Show/Hide tools) complete** on `phase-30-visibility-tool` (4 commits incl. a smoke-script repair), merged to `main`.
- New stateless `VisibilityTool` with `hide` / `showHide` named constructors: every tap on a hit object = one single-id `ChangeAttributesCommand` = one undo step; empty-canvas taps ignored; Hide refuses hidden hits (unreachable via the canvas, guarded anyway). `H`/`Shift+H` rebound from the old hide-selection/reveal-all actions (`AppAction.hideTool`/`showHideTool`); no toolbar entry v1.
- View plumbing: `CanvasHitTester` gained `includeHidden`, `GeometryPainter` gained `showHidden` (one 0.35 alpha factor dims halo, fill, stroke and label alike); the canvas keys both on `VisibilityTool.revealsHidden`. PNG export structurally unaffected — the exporter builds its own painter and the flag defaults false — plus a pixel test pinning it.
- 834 tests green, analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors — after repairing `drive.js`: the out-of-session commit `ca81277` (macro flyout reorder, triangles promoted) had silently broken the smoke's square section, which clicked flyout row 1; Square is now activated by its `X S` chord, immune to future reorders.

**Next**
- Phase 31 (line-angle wedge picked by taps) is the next unchecked phase; 32–39 queue behind it.

**Open questions / gotchas**
- The old `Shift+H` reveal-*all* bulk action has no single-key replacement: revealing many objects is now per-tap in Show/Hide, or tree-group-header select (hidden included) + the inspector's Visible checkbox.
- While Show/Hide is active, hidden objects hit-test at normal kind priority — a hidden point over a visible line wins the tap.
- `ca81277` predates this session and has no STATUS entry of its own; its test-side row-index updates were fine, only the smoke script had been missed.

## Session 38 (later) — 2026-07-07

**Done**
- **Phase 29b (angle tools without by-product points) complete** on `phase-29b-bisector-two-line` (3 commits incl. the PLAN/TODO spec), merged to `main`. User feedback on Phase 29: taps on curves in the bisector / vertex-angle tools still ran the Phase 20 ladder and permanently glued `PointOnObject`s — "fake points that remain".
- New kind `TwoLineBisectorLine` (two `GeoLine` parents + `branch` 0/1) with `twoLineBisector` math beside `angleBisector`; `.near` bakes the branch from the two tap positions so the created line bisects the tapped wedge; undefined while parallel. Codec entry (`branch` param, no version bump), kind label "Angle bisector".
- New two-mode `AngleBisectorTool`: line-first → two-line mode, zero points created; point/empty-first → the old three-point flow with curve taps *ignored*. Vertex angle keeps `ThreePointTool` but with new `MultiPointTool.allowCurveTaps: false` — curve-flavored taps refused (Angle-between-lines is the two-line path there). Other point-collecting tools deliberately keep the gluing ladder (it's a feature for segments/circles/macros).
- 817 tests green, analyze clean, web smoke on a fresh release build: **SMOKE PASS**, zero console errors.

**Next**
- Phase 30 (Hide & Show/Hide tools) is the next unchecked phase; 31–39 queue behind it.
- `main` is 19 commits ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- `TwoLineBisectorLine.branch` is carrier-relative like `IntersectionPoint.branchIndex`: deterministic, not continuous — dragging a parent through parallel swaps which wedge the branch means. Same documented wart, same acceptance.
- Only the *tapped wedge's* bisector is created (GeoGebra creates both). Tap the other wedge for the perpendicular partner.
- Vertex-angle taps near-but-not-on a line are also refused while `allowCurveTaps` is false (the hit set contains the curve) — a tap must be clear of every curve to drop a free point. Honest, but could surprise.

## Session 38 — 2026-07-07

**Done**
- **Phase 29 (tool-input highlighting) complete** on `phase-29-input-highlight` (2 commits), merged to `main`.
- `ToolInputPreview.previewObjectIds` beside `previewPositions`: existing objects consumed as tool inputs are haloed via the painter's selection-halo pass (union with `selectedIds`), instead of getting a projected dot+ring marker. Position-only taps and not-yet-committed `IntersectionPoint`/`PointOnObject` snaps keep the marker (they aren't in the construction yet), split on `resolvePoint`'s `isNew` flag.
- All five implementers report ids: `TwoLineTool`, `IntersectionTool`, `PointAndLineTool`, `TransformObjectTool`, `MultiPointTool`. The four single-purpose tools shed their tap-projection preview state (`_firstTap`/`_lineTap`/`_sourceTap`/`_mirrorTap`, `_sourceMarker`) — the halo replaced the only thing it fed.
- 795 tests green (per-tool halo/marker split incl. transform param taps and a kept marker on an uncommitted intersection snap; painter no-throw + `shouldRepaint` on the new set; widget test: mid-collection tapped line haloed, zero markers), analyze clean, goldens byte-identical (no preview state in golden scenes). Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it never asserts on previews).

**Next**
- Phase 30 (Hide & Show/Hide tools) is the next unchecked phase; 31–39 queue behind it.
- `main` is now 13 commits ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- `ToolInputPreview` is an `abstract interface class`, so `previewObjectIds` has no code-level default — any future preview tool must declare both getters (the analyzer enforces it). The "default empty" from PLAN lives at the canvas call site.
- The Phase 29 halo shares color and alpha with the selection halo. Deliberate for v1 (PLAN says "selection-style"); if tool-input feedback ever needs to read differently from selection, split the paint in `GeometryPainter`'s halo pass, not the id sets.

## Session 37 — 2026-07-07

**Done**
- **Phase 28 (label size styling) complete** on `phase-28-label-size` (3 commits), merged to `main`.
- `ObjectAttributes.labelFontSize` (default 12.0) — additive, no codec change, no version bump. The old `label_layout.dart` top-level constant is deleted; both `GeometryPainter._drawLabel` and the shared `labelScreenRect` now read the per-object attribute, so paint and label-drag hit rect stay in lockstep.
- Inspector "Label size" `_PresetSelector` row `S`/`M`/`L`/`XL` → 9/12/16/22. Since `labelAnchor` is total over kinds, every object is labelable — the row targets the *whole* selection (no slice) and always shows.
- 789 tests green (label hit-rect grows at size 22 with an unchanged top-left; inspector row = one command over a point + segment, single undo restores both; codec kitchen-sink segment carries `labelFontSize: 16`), analyze clean, goldens byte-identical (default = old constant). Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it styles no labels).

**Next**
- Phase 29 (tool-input highlighting — halo existing objects instead of fake point markers) is the next unchecked phase; 30–39 queue behind it.
- `main` is now 9 commits ahead of `origin/main` — push when convenient.

**Open questions / gotchas**
- The pre-existing fill-checkbox inspector test needed `ensureVisible` after its `scrollUntilVisible`: the new label-size row pushed the Fill tile's center off-screen, and `scrollUntilVisible` stops as soon as the widget is *built*, not centered. Any future row insertion above Fill may bite the same way elsewhere.
- The stale `python3 -m http.server 8321` (running since Session 32) was reused for the smoke — files are read per request, so the fresh build is what got tested.

## Session 36 — 2026-07-07

**Done**
- Housekeeping on `main` first: the working tree carried uncommitted edits from outside any session — a `flutter create --platforms=macos` run (untracked `macos/`, plus a `.metadata` rewrite that *dropped* the android/ios/web migration entries), newer-formatter churn in two files, and one deliberate change. Per the user: committed the deliberate bit (a **Gray** swatch in the inspector color palette, `3dd15e9`) and reverted everything else; the `macos/` scaffolding was moved aside to the session scratchpad rather than deleted.
- **Phase 27 (rename clash resolution) complete** on `phase-27-rename-clash` (2 commits), merged to `main`. Approach tweak folded into PLAN/TODO first: the two renames ride one **multi-id `ChangeAttributesCommand`** (the `_setForAll` idiom — the command already batches ids), not the originally sketched `MacroCommand` of two.
- `evictedName(usedNames, wanted)` beside `nextAutoName`: strip the wanted name's trailing digit run to get the base, return the first free `base1`, `base2`, … that also ≠ the wanted name; an all-digit name keeps itself as the base (`12` → `121`).
- Inspector `_renameTo`: when another object holds the submitted name, the holder is evicted to `evictedName(...)` in the same command — one undo unit, the chosen name never rejected. Clearing a name to empty never evicts (unnamed objects may repeat); rename-to-own-name stays a no-op.
- 787 tests green (5 `evictedName` units + 2 inspector widget tests: evict + single-undo-restores-both, own-name no-op), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it never drives renames).

**Next**
- Phase 28 (label size styling) is the next unchecked phase; 29–39 queue behind it. Phase 19's SVG stretch stays optional; Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand.

**Open questions / gotchas**
- The STATUS log has no entry covering the Phase 27–39 planning commits (post-Session-35) — the phases exist only in PLAN/TODO; treat those as the spec of record.
- If a saved file ever carries *duplicate* names, eviction renames only the first holder found in insertion order — subsequent duplicates keep the name until individually renamed.
- The user's macOS scaffolding was parked in the session scratchpad (`macos-removed/`), which is temporary — if desktop-macOS support is ever wanted, re-run `flutter create --platforms=macos .` (and don't let it strip the other platforms from `.metadata`).

## Session 35 — 2026-07-05

**Done**
- Renamed the app/package from `fgex` to `regula` project-wide at the user's request: `pubspec.yaml` name, all `package:fgex` imports across `test/`, Android (`applicationId`/`namespace` `com.apollonius.regula`, manifest label, `MainActivity.kt` moved to `com/apollonius/regula`), iOS (`PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleDisplayName`/`CFBundleName`), web (`index.html`, `manifest.json`), IDE `.iml` files (untracked, gitignored), and doc/prompt mentions in `CLAUDE.md` and `.claude/commands/continue-build.md`. Also swapped the placeholder `com.example` reverse-domain prefix for `com.apollonius`, and replaced hardcoded `/Users/stefanos.levantis` paths in tracked docs with `$HOME`. Older STATUS entries above are left untouched per the append-only convention — they accurately describe `fgex`/`com.example` at the time.
- Local project folder moved from `$HOME/Code/var/fgex/` to `$HOME/Code/var/regula/` (user opted in); `docs/PLAN.md`'s path reference updated to match.
- Wrote a succinct `README.md` (previously the one-line Flutter placeholder) and pushed the whole repo to a new remote `git@github.com:steveSuave/regula.git`.

**Next**
- No functional/phase work changed — pick up wherever Session 34 left off (all planned phases done; optional SVG export stretch and the two environment-blocked Phase 12 boxes remain).

**Open questions / gotchas**
- Anyone with a previous local clone under the old `fgex` name/path or with `package:fgex` imports in scratch/uncommitted work needs to update both.
- `ios/Flutter/Generated.xcconfig`, `ios/Flutter/flutter_export_environment.sh`, and `android/local.properties` still have the old absolute `fgex` path baked in from the last `flutter pub get` at the old location — all three are generated, gitignored files that self-correct next time `flutter pub get`/`flutter build` runs from the new location, so they were left alone.

## Session 34 — 2026-07-05

**Done**
- **Phase 26 (select-by-kind tree headers) complete** on `phase-26-select-by-kind`, merged to `main` — the last unchecked phase.
- Object-tree group headers (Points / Lines / Circles / Angles) are now `_GroupHeader` InkWells: tap replaces the selection with every object of that kind — hidden included, the tree's raison d'être — shift-tap unions, long-press unions (the touch shift, with `HapticFeedback.selectionClick`, matching the Phase 25b canvas convention; union-not-toggle is deliberate: headers select groups, the canvas toggles individuals). Tooltip "Select all points" etc. No new provider API — `selectMany(ids, additive:)` as planned.
- One display-only cheat-sheet `GestureRow` in the "Selection & app" section; the sheet auto-renders it.
- 780 tests green (2 new: header tap selects the kind incl. a hidden point after a cross-kind selection; shift-tap and long-press union with a segment selected), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it never opens the tree).

**Next**
- **All planned phases are done.** Remaining open items: the optional Phase 19 SVG-export stretch, and Phase 12's two environment-blocked boxes (iOS build needs a full Xcode install; Android emulator needs an AVD system image download). Next milestone is whatever new scope the user brings — or tackling one of those blockers.

**Open questions / gotchas**
- The header sits inside a `Tooltip` whose default touch trigger is also long-press; the InkWell's recognizer is deeper so it wins the arena — long-press selects and never shows the tooltip. Fine (tooltips are hover affordances here), but worth knowing if the tooltip ever seems dead on touch.
- The stale `python3 -m http.server 8321` from Session 32 is still serving `build/web` and was reused for the smoke (files are read per request, so the fresh build is what got tested).

## Session 33 — 2026-07-05

**Done**
- **Phase 22b** (user feedback on Phase 22) on `phase-22b-angle-hit-dash`, merged to `main`; **v0.1 tagged**.
- Angles are now selectable by clicking their marker on the canvas. Root cause: the viewport-free `CanvasHitTester` picked angles at the *vertex* only (screen-sized marker, world-space tester), where the vertex point always outranked them. Fix: optional `worldPerPx` hint on `hitTest`/`hitTestAll` (default 0 keeps the old behavior for viewport-less callers); `_angleDistance` measures to the wedge outline — sweep-clamped arc at the per-object marker radius plus the two straight edges, the `_sectorDistance` analogue; the right-angle square is approximated by its arc (≤ ~0.3 × radius off). The three canvas call sites (tap, drag-start, long-press) pass `screenToWorldLength(1)`. Priority unchanged: anything else on the wedge still wins.
- The inspector's "Line style" row is hidden when the selection has no dashable stroke: angle markers deliberately never dash (Phase 17), so the row was a silent no-op for angles — the second half of the user report (angle selected from the tree, dash change did nothing). Stroke width stays for angles: it genuinely styles the marker outline.
- 778 tests green, analyze clean: wedge-hit unit test (arc/edge/vertex hits, outside-sweep + interior misses, radius attribute tracked), canvas widget test (tap the wedge → angle selected; tap the vertex → point wins), inspector dash-absent assertions. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors.

**Next**
- Phase 26 (select-by-kind tree headers) is the last unchecked phase; SVG export stays optional; Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand.

**Open questions / gotchas**
- `worldPerPx = 0` (tests, any viewport-less caller) silently degrades angles to vertex-only hits — deliberate compatibility default; pass the hint anywhere selection UX matters.
- The band path (`objectsInRect`) still takes an angle by its vertex — banding the vertex bands the angle; unchanged and fine.
- An angle's wedge *interior* is not hittable (outline only, matching sectors); if users expect filled wedges (Phase 22 fill) to be clickable inside, extend `_angleDistance` to return 0 inside the wedge when `fillAlpha` is set — same question applies to filled sectors, so decide both together.

## Session 32 — 2026-07-05

**Done**
- **Phase 22 (angle-mark styling) complete** on `phase-22-angle-styling` (4 commits incl. docs), merged to `main`. In landing order:
- `ObjectAttributes.angleMarkerRadius` (default 20 = the old painter constant, screen px) — additive, no version bump; codec kitchen-sink gains non-default radius + `fillAlpha` on the `VertexAngle`.
- Painter: `_drawAngleMarker` reads the per-object radius; a sweep exactly π/2 (`defaultEpsilon`) draws the **closed right-angle square** (vertex → s·d1 → s·(d1+d2) → s·d2, s = 0.7 × radius) instead of the arc wedge — one path shared by stroke and fill. Non-right angles keep the exact pre-22 `drawArc(useCenter: true)` call, so default rendering is byte-identical (points/lines/circles/angles goldens unchanged). New `_drawFill` pass in `paint()` under the stroke: sectors' pie wedge + angle markers at `color.withValues(alpha: fillAlpha)` — the first time `Sector.fillAlpha` actually paints.
- Inspector: `_DashSelector` generalized to `_PresetSelector` (label + presets), backing both the dash row and the new "Marker size" `S`/`M`/`L`/`XL` → 12/20/28/36 row (angles slice); "Fill" tristate checkbox over angles + sectors toggling `fillAlpha` null ↔ 0.25 (the planned alpha byte 64 on the attribute's 0–1 scale — PLAN wording fixed). One `ChangeAttributesCommand` per tap via `_setForAll`, per-slice only.
- Goldens: decorations light+dark regenerated (its `fillAlpha: 0.25` sector now fills — the pre-logged expected diff); new `markers` scene light+dark (unfilled right-angle square, filled wedge, radius-36 wedge, a filled+resized `LineAngle` square over a real `PerpendicularLine` pinning the fp-exact π/2 path, filled sector).
- 776 tests green (2 new inspector: radius tap = one command over the angle slice only; fill tristate on a mixed angle+sector selection), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (drive.js untouched — it builds no angles).

**Next**
- Open queue: Phase 26 (select-by-kind tree headers) is the last unchecked phase; the SVG stretch stays optional. Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand. **The v0.1 tag suggestion from Session 31 still stands** — even more so with only Phase 26 left.

**Open questions / gotchas**
- The right-angle square keys off sweep == π/2 within `defaultEpsilon` (1e-9): perpendicular-construction angles hit it (fp-exact per PLAN), hand-placed arms at "roughly 90°" do not — deliberate, no toggle exists.
- The Fill checkbox writes `fillAlpha: 0.25`, but any 0–1 value from a saved file renders; a non-0.25 fill shows the tristate as "on" and toggling off→on normalizes it to 0.25.
- A stale `python3 -m http.server 8321` from an earlier session was still serving `build/web` — harmless (files are read per request, so the fresh build was what got smoked), but kill it if a *different* directory ever needs the port.
- Angle markers ignore `dashPeriod` by design (Phase 17 rule), yet angles sit in the inspector's strokes slice, so the dash row shows for them and does nothing — pre-existing, unchanged by 22.

## Session 31 — 2026-07-05

**Done**
- **Phase 19 (Export) complete** except the explicitly-optional SVG stretch, on `phase-19-export` (3 commits). User additions folded into PLAN first: transparency (already specced), a **drag-selected region** framing, and the **exact output size in pixels** always visible in the dialog.
- `application/export/png_exporter.dart`: `renderConstructionImage` (off-screen `PictureRecorder` + the real `GeometryPainter` — no UI chrome by construction; `canvas.scale(pixelRatio)` for 1×/2×/4×; optional background fill, null = transparent) + `encodePng` + combined `exportConstructionPng`. Framing helpers return `({viewport, logicalSize})`: current view, fit (via `fittedViewport`, null when nothing visible), region (same scale, pan re-anchored at the marquee's top-left — what's inside the marquee is exactly what exports). `savePngBytes` sibling in `file_io.dart`.
- Export dialog (`presentation/panels/export_dialog.dart`): framing radios (plain `ListTile`s — Flutter's radio tiles are mid-`RadioGroup`-migration), scale segments, transparent checkbox, live "Output: W × H px" line. "Select region…" pops the dialog with a sealed `ExportRegionPickRequested` outcome; `EditorScreen` arms `RegionPickOverlay` (stacked *on* the canvas in the editor — the canvas widget is untouched and pointer-blocked), release reopens the dialog with the region framing selected, Esc cancels back to the dialog, all other shortcuts are swallowed mid-pick. Options + region persist in editor state across round trips.
- Wiring: "Export as PNG…" in the wide File popup and the compact overflow (below Save…), `Ctrl/⌘ E` binding + exhaustive-switch case, cheat-sheet row auto-renders.
- 771 tests green (13 exporter: pixel-level transparency/background/scale/region-crop checks, PNG signature; 7 flow: menu → dialog → fake-picker save with IHDR dimension parsing, 2× doubles displayed and exported size, fit disabled when empty, region round trip, Esc cancel, sub-threshold drag stays armed, Ctrl+E), analyze clean. Web smoke on a fresh release build: **SMOKE PASS**, zero console errors (Export item appended *after* Save…, so the script's File-menu click coordinates held).
- Post-merge user report, second stint (`phase-19-dialog-overflow`, merged): shrinking the window overflowed the dialog's fixed-height `Column` (`RenderFlex overflowed by 27 pixels`) — content now wraps in a `SingleChildScrollView`. Regression test at an 800×300 window, verified to reproduce the exact overflow without the fix (772 tests green).

**Next**
- Open queue: Phases 22 (angle-mark styling) and 26 (select-by-kind); the SVG stretch stays optional. Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand — the export's native-picker path on Android rides them. **Consider the v0.1 tag now that Phase 19 has landed.**

**Open questions / gotchas**
- `RegionPickOverlay` anchors its rect at `onPanDown`, not `onPanStart` — the pan recognizer's acceptance point sits ~18 px past the true down position and would shave the marquee's corner (same class of bug as the canvas band's `_firstDown`, solved overlay-locally since it owns all pointers).
- Widget tests that drive an export must wrap the Export tap in `tester.runAsync` and poll for the fake picker's bytes: `Picture.toImage`/`toByteData` complete on real engine futures that `pumpAndSettle` never settles.
- The export dialog's output size uses the canvas's *laid-out* size at dialog-open time; a stale region rect survives viewport changes (it's screen-space) — deliberate, the dialog shows its pixel size so nothing is hidden.
- drive.js not extended with an export section: the browser-download delivery is the same `FilePicker.saveFile` path the Save… check already exercises, and the render/dimension correctness is pixel-tested in widget tests (parallelogram precedent).

## Session 30 — 2026-07-05

**Done**
- **Phase 25b** (user feedback on the Session 29 mobile chrome) on `phase-25b-single-row-longpress`, merged to `main`:
- Single-row compact bar: the two-row chrome (56-px app bar + 48-px `AppBar.bottom` strip) collapses into one 48-px row — `GeometryToolbar` scrolls in the app bar's *title slot* (`titleSpacing: 0`, `leadingWidth: 48`, `toolbarHeight: 48`), the File popup folds into the overflow menu (New/Open…/Save… above a divider; `Future<void> Function()` tear-offs assign fine to the popup's `VoidCallback`), and the style button moves from the strip's end into the actions row. `_toolbarStrip` deleted. Wide layout untouched.
- Long-press = touch shift-click: `onLongPressStart` on the canvas toggles the topmost hit object in the selection (`SelectionNotifier.toggle`, `HapticFeedback.selectionClick`), matching the Phase 26 group-header convention. Registered **only when no tool is active** — otherwise the recognizer would swallow slow taps mid-collection. Empty-canvas long-press is a no-op (clearing stays the tap's job). Hit radius reuses `hitThresholdFor(_firstDownKind)`.
- `debugShowCheckedModeBanner: false` — the corner DEBUG ribbon on device debug runs is gone.
- 751 tests green, analyze clean: compact layout test reworked (AppBar height == 48 pins the single row, File out of the bar / in the overflow), new canvas tests (long-press add/remove/no-clear; slow tap with a tool active still places a point). Full drive.js on a fresh release build: **SMOKE PASS**, zero console errors. Ad-hoc phone-viewport Playwright check (400×800, touch): chrome glyphs end at y=34 (one row), strip swipe-scrolls, long-press adds then removes point B (pixel-tint assertions), style button appears with the selection.

**Next**
- Open queue unchanged: Phases 19 (export), 22 (angle-mark styling), 26 (select-by-kind); Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand — real-device smoke for the compact chrome rides on those. v0.1 tag once Phase 19 lands.

**Open questions / gotchas**
- Deliberate long-press trade-off: in move/select mode, holding still past ~500 ms *before* dragging toggles the selection instead of starting the object drag / rubber band; drags that begin moving inside the timeout are unaffected (documented at the handler).
- The compact bar's fixed icons (hamburger + undo/redo/overflow, + style with a selection) leave ~200 px of scrolling toolbar on a 400-px phone — fine, but anything added to the compact actions row from here should go into the overflow instead.
- Phase 26's tree-header long-press should mirror the canvas semantics (additive union there vs toggle here is intentional: headers select groups, the canvas toggles individuals).

## Session 29 — 2026-07-05

**Done**
- **Phase 25 complete** on `phase-25-mobile` (5 commits), merged to `main`. In landing order:
- Compact gate + chrome: `isCompact = MediaQuery.sizeOf(context).shortestSide < 600` in the `EditorScreen` build. Compact app bar keeps File/undo/redo + one overflow popup (Fit, Reset, object tree, cheat sheet, theme); the `GeometryToolbar` moves to a 48-px horizontally scrollable strip as `AppBar.bottom`, six flyout groups reused untouched. The cheat-sheet header Row overflowed at phone widths (it's reachable from the overflow menu) — title now flexible with ellipsis.
- Compact panels: object tree → `Scaffold.drawer`, inspector → `endDrawer` (width `min(280, 0.85 × screen)`, widgets verbatim); a style icon at the strip's right end (visible while the selection is non-empty) opens the inspector — never auto-opens. Edge-swipe drawer gestures disabled: a drag starting at the screen edge is a draw. Drawers open via the auto hamburger, the overflow item and the style button (`_scaffoldKey`).
- `isMobileTarget` getter (`!kIsWeb` + Android/iOS): `main()` sets `SystemUiMode.immersiveSticky`; the body's `SafeArea` sides are active only on mobile targets, so web renders pixel-identically.
- Pointer-kind hit threshold: `GeometryCanvas.hitThresholdFor(kind)` — 16 px touch / 8 px otherwise. Taps read `TapUpDetails.kind`; drags read the kind recorded at the Listener's first pointer-down (scale-recognizer details carry no kind). Flows unchanged into `ToolInput.snapThreshold`, the Phase 20 ladder and the stamp radius (touch stamps are 2×, per PLAN).
- Dash selector: presets render `–`/`S`/`M`/`L` with the full word as segment tooltip + `bodySmall` text; width regression pinned against the 280-px panel.
- 749 tests green, analyze clean: new `compact_layout_test.dart` (strip present/scrollable at 250-px width, app-bar icon census both modes, overflow actions, drawers, style button, wide-layout no-drawers regression), touch-vs-mouse threshold test (12-px tap selects on touch, misses with mouse), inspector dash test updated to `M`. Web smoke re-run on a fresh release build: **SMOKE PASS**, zero console errors — drive.js untouched (its default viewport is wide; the wide chrome is unchanged). Extra Playwright phone-viewport check (400×800, touch): compact chrome renders, strip flyout → touch taps place auto-named points, zero console errors.

**Next**
- Open queue: Phases 19 (export), 22 (angle-mark styling), 26 (select-by-kind) in any order; Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand — real-device mobile smoke for Phase 25 rides on those. Consider a v0.1 tag once Phase 19 lands.

**Open questions / gotchas**
- All widget tests run with `defaultTargetPlatform == android`, so `isMobileTarget` is true there and the body `SafeArea` is always mounted in tests (zero insets — harmless, but don't assert on SafeArea absence).
- `tester.tapAt` defaults to `PointerDeviceKind.touch`, so every existing canvas test now exercises the 16-px threshold; tests needing the tight radius must pass `kind: PointerDeviceKind.mouse` (the new threshold test is the pattern).
- The overflow menu's "Show object tree" opens the drawer in compact mode; `_showObjectTree` still backs the wide layout's inline panel only.
- Phase 22's inspector angles slice should reuse the single-letter preset convention the dash selector now follows (S/M/L/XL radius labels).

## Session 28 — 2026-07-05

**Done**
- **Phase 24 complete** on `phase-24-object-transforms` (3 commits), merged to `main`. In landing order:
- `TransformObjectTool` (`domain/tools/transform_object_tool.dart`): one class with named constructors per isometry (`.reflectAboutLine`/`.reflectAboutPoint`/`.rotate(angle:)`/`.translate`) + a `transform` enum field. Transformee is the first input; slot-1 resolution is *topmost in-threshold curve decides* — a point hit wins (ladder rung-1 parity), a supported curve becomes the transformee, an unsupported line under reflect becomes the mirror-first slot (Phase 15 either-order), any other unsupported curve is an ignored tap (no ladder fall-through, so the tap never glues to the transformee). Later parameter taps (center, vector tail/tip) use the full Phase 20 `resolvePoint` ladder unchanged. Point mode reproduces the Phase 15 tools exactly: bare `AddObjectCommand` when everything tapped existed, reflect's point + line in either order, empty-tap-after-line creating the free point.
- Curve mode: same kind rebuilt over transform-point images of the defining points (identity-keyed map, shared parents image once), one `MacroCommand` in order params → images → curve, image points visible (auto-named by Phase 23 for free). Supported: `Segment`, `Ray`, `LineThroughTwoPoints`, `CircleCenterPoint`, `CompassCircle`, `ThreePointCircle`, `Arc`, `VertexAngle`, `Sector` except reflect-about-line. Reflected `VertexAngle` swaps arms (same wedge); the arc test pins the sweep sign flip; reflecting a line across itself is refused.
- Wiring: the four Transform flyout rows and `G L`/`G P`/`G T`/`G V` switch cases activate the new tool (labels say "object"); `transformActive` is a single type check; `RotatedPointTool` deleted (point-mode tests ported) along with the `buildReflectedPoint`/`buildCentralReflection`/`buildTranslatedPoint` tear-offs, simplifying the Points/Lines highlight exclusions.
- 742 tests green, analyze clean: 22 domain tests (transform × kind matrix, drag tracking, undo units, slot rules, previews) + a canvas widget test (`G L`, tap circle then line → congruent image circle, one undo unit); toolbar/editor-shortcut tests flipped to `TransformObjectTool`. Web smoke re-run on a fresh release build: **SMOKE PASS**, zero console errors — drive.js untouched (it never opens the Transform flyout; icon count unchanged).

**Next**
- Open queue unchanged otherwise: Phases 19 (export), 22 (angle-mark styling), 25 (mobile), 26 (select-by-kind) in any order; Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand. Consider a v0.1 tag once Phase 19 lands.

**Open questions / gotchas**
- Reflect's either-order means a *supported line* tapped first is only provisionally the transformee: a point second flips it to the mirror (Phase 15 parity), a line second commits curve mode. A circle/angle transformee + point second is ignored (no mirror possible).
- Slot-2+ parameter taps still glue via the ladder — a rotate-center tap on the transformee curve itself glues a `PointOnObject` to it (legal, no DAG cycle: curve → glued center → image points).
- Anything that used to type-check `RotatedPointTool` (or the deleted builder tear-offs) must switch to `TransformObjectTool` + its `transform`/`angle` fields — the updated toolbar/shortcut tests are the pattern.
- `Sector` + reflect-about-line and the non-point-parent line kinds stay ignored taps; if object-level recursion (image of `PerpendicularLine` = perpendicular through image point on image line) is ever wanted, PLAN sketches it under Phase 24.

## Session 27 — 2026-07-05

**Done**
- **Phase 23 complete** on `phase-23-auto-naming` (4 commits), merged to `main`. In landing order:
- Pure allocator `domain/construction/object_naming.dart`: `nextAutoName(usedNames, object)` — points `A…Z, A1…Z1, A2…` (GeoGebra-style, letter varies fastest); lines *and* circles share one lowercase pool `a…`; angles `α…ω, α1…` (24 lowercase Greek letters, final sigma excluded). First-free scan over used names, so gaps are reused and File > Open needs nothing special. 10 unit tests.
- Interceptor `_autoNameNewObjects` in `ToolNotifier.handleInput`, run on every `ToolCommitted` before `execute`: recurses into `MacroCommand.commands`, names only objects with an empty name **and** `visible: true` (hidden macro scaffolding burns no letters), tracks batch-local used names. Names bake into the object instance pre-first-apply, so undo/redo is stable with zero command state. Lines/circles get `labelVisible: false` at assignment (name shows in tree/inspector, not on canvas); points/angles keep their labels.
- Inspector single-selection header now shows `A — Point` (kind-only stays for unnamed objects). Tree rows already showed name-over-kind.
- 722 tests green (analyze clean): allocator units, provider naming tests (A then B; hidden/pre-named objects skipped in a macro batch; deleted B reused; undo/redo stable; segment named `a` with hidden label), inspector header widget test. Web smoke re-run on a fresh release build: **SMOKE PASS**, zero console errors.
- drive.js: new `markers()` step clusters raw dark blobs within 40 px into one marker per point — every placed point now renders dot + auto-name label ("A" ~18 px above), which raw blob counting saw as 2–3 blobs per point (merge depends on antialiasing). All blob-count/spread/nudge assertions now run on markers.

**Next**
- Phase 24 (whole-object transforms) is now unblocked — image defining points will get auto-names for free. Phases 19 (export), 22, 25, 26 remain open in any order. Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand.

**Open questions / gotchas**
- The interceptor only covers the `handleInput` funnel. Objects added by other paths (tests calling `construction.add` directly, hypothetical future programmatic inserts) stay unnamed — deliberate, matches the PLAN; if a second entry point for user-created objects ever appears, route it through the same interceptor.
- Naming keys off `attributes.visible` at commit time; a macro that ever commits a *visible* helper object would burn a letter for it.
- Blob-based smoke assertions must use `markers(darkBlobs(...))` from now on — raw `darkBlobs` counts are 1–2 per labeled point depending on antialiased pixels bridging dot and glyph.

## Session 26 — 2026-07-05

**Done**
- **Phase 21 complete** on `phase-21-random-stamps` (2 commits), merged to `main`. In landing order:
- `RandomShapeStampTool.convexQuadrilateral` named constructor (+ public `convex` flag): four vertices on one circle of the usual stamp radius — no radial jitter, sorted distinct angles on a circle are always in convex position — with angles from the gap method (4 uniform draws normalized onto 2π − 4·0.25 rad, prefix-summed from a random start; the wrap-around gap gets its minimum too, no rejection loop; an all-zero draw set falls back to equal gaps rather than NaN), then one anisotropic rotate–scale–rotate stretch about the tap (axis factors in [0.7, 1.3]) for variety — affine maps preserve convexity. The jittered path was refactored behind the same offsets list but draws from the RNG in the exact old order, so the triangle stamp is unchanged.
- Wiring: Macros flyout "Random polygon" row **replaced** by "Random quadrilateral (one tap)"; both stamp rows now carry `AppAction`s (`randomTriangleStamp`/`randomQuadrilateralStamp`) so the dimmed shortcut hints render; `X 3`/`X 4` chords (digit second strokes, `G 3` precedent; no numpad twins — `G 3` has none) + the two `main.dart` switch cases.
- 707 tests green (analyze clean): convexity over 200 seeds (consecutive edge cross products share sign, none zero), 4 vertices + 4 closing segments each of degree 2, one undo unit, stamp distance within the stretch bounds, `X 3`/`X 4` widget test asserting convex flag + vertex counts; toolbar sweep row renamed. Web smoke re-run on a fresh release build: **SMOKE PASS**, zero console errors — the Session 25 gotcha held, drive.js needed no changes (its macro section only drives Square, row 1).

**Next**
- Phase 23 (automatic naming) should land before Phase 24 (whole-object transforms) per the Session 25 ordering; Phases 19 (export), 22, 25, 26 are open in any order. Phase 12's two environment-blocked boxes (iOS build, Android emulator) still stand.

**Open questions / gotchas**
- `RandomShapeStampTool`'s convex mode keys off the `convex` field, not a subclass — the Macros highlight (`tool is RandomShapeStampTool`) covers both rows, but anything that ever needs to distinguish them must check the flag (the `X 3`/`X 4` widget test is the pattern).
- The convex stamp's vertex *insertion order* is the polygon order (angles are prefix-summed, hence increasing) — the convexity test relies on it; don't reorder the AddObjectCommands.

## Session 25 — 2026-07-05

**Done**
- **Planning-only session** — no code. Enriched `docs/PLAN.md` + `docs/TODO.md` with six new phases (21–26) covering the 11 user-requested features/fixes, every design validated against the actual code first (three parallel exploration passes + one design pass):
- **Phase 21** random stamps: the 4–7-vertex random polygon is *replaced* by an always-strictly-convex random quadrilateral (gap-method angles on one circle — no radial jitter — plus a convexity-preserving affine stretch); `X 3`/`X 4` chords reverse Phase 16's menu-only decision.
- **Phase 22** angle-mark styling: `angleMarkerRadius` attribute (default 20 = today's constant), *automatic* right-angle square at exactly π/2, wedge fill via the existing-but-never-painted `fillAlpha` (same pass finally implements Sector fill); inspector angles slice with S/M/L/XL presets. Additive attributes — no version bump.
- **Phase 23** automatic naming: pure first-free allocator (`A…` points, shared `a…` lines+circles, `α…` angles) applied in a single interceptor at `ToolNotifier.handleInput` — the one `AddObjectCommand` funnel — naming only visible objects (macro scaffolding burns no letters); undo/redo-stable for free since `AddObjectCommand` re-adds the same instance. Lines/circles named but `labelVisible: false`; points show A, B, C by default.
- **Phase 24** whole-object transforms by macro composition (same kind rebuilt over transform-point images; no new kinds); orientation decided: reflected `VertexAngle` swaps arms, `Sector`+reflect-about-line excluded; new `TransformObjectTool` with transformee-first slot rule (curve hits must beat the Phase 20 point ladder).
- **Phase 25** mobile: compact gate (shortest side < 600), immersive status bar, toolbar as a scrollable 48-px strip, panels as drawers, pointer-kind snap radius (16 px touch / 8 px mouse), dash-selector overflow fix (–/S/M/L + bodySmall).
- **Phase 26** select-by-kind via tappable object-tree group headers (tap = replace, shift-tap = additive, long-press = additive on touch — user-requested).
- User decisions recorded in PLAN: replace (not keep) the random polygon; right-angle square is automatic, no toggle; select-by-kind lives on tree headers with long-press for mobile.

**Next**
- Open queue: Phase 19 (export, last pre-existing spec) and the new Phases 21–26 — 21 is the smallest starter; 23 (naming) should land before 24 (transforms) so image points get names without rework. Phase 12's two environment-blocked boxes (iOS build, Android emulator) still gate Phase 25's real-device smoke — its acceptance is widget tests + Chrome device emulation.

**Open questions / gotchas**
- Phase 25 must keep the wide layout byte-identical (desktop web smoke zero-diff); drive.js indexing assumptions (icon count, "theme toggle is last") will need re-checking when the compact chrome lands.
- Phase 21 removes the "Random polygon" Macros row — drive.js's macro section only touches Square (row 1), so it should survive, but re-verify.
- Phase 22 goldens: any existing golden scene containing an exact right angle will change (square replaces arc) — regenerate deliberately.

## Session 24 — 2026-07-04

**Done**
- Merged `phase-20-smart-point-placement` to `main`, then **Phase 16 complete** on `phase-16-angle-macros` (6 commits). In landing order:
- `AngleBySizeTool` (arm point, vertex; size from a degrees dialog): emits a `RotatedPoint` + a `VertexAngle` in one undo unit. A negative size swaps the marker's arms so it measures |size| on the clockwise side instead of the 2π complement. Angles flyout row + `G D` chord (settled in PLAN first — "degrees", `A` was taken); the rotation dialog generalized to `_askDegrees(title)` serving both tools.
- Triangle macros (PLAN input schemes first): **equilateral** = 2 taps, apex = `RotatedPoint` by +60° — no scaffolding, no branch, left of A→B; **isosceles** = 2 base taps + position-only apex projected onto the hidden perpendicular bisector (hidden `Midpoint` + `PerpendicularLine`); **right** = the rectangle's height-tap mechanics, right angle at B. All one `MacroCommand`, degeneracy round-trips tested.
- `RegularPolygonMacroTool` (side count via dialog, integer 3–100 else cancel): vertices chain as `RotatedPoint`s — v₍ₖ₊₁₎ = v₍ₖ₋₁₎ about vₖ by 2π/n − π — regular, continuous, scaffolding-free. `RandomShapeStampTool` (one class, 3–3 and 4–7 ranges): one tap stamps free points at *sorted* random angles (non-self-intersecting) and jittered radii scaled ≈10× the snap threshold; injected `math.Random` keeps tests deterministic; menu-only.
- Wiring: 6 new Macros rows, `X E`/`X ⇧I`/`X ⇧R`/`X G` chords (`_x` helper grew a `shift` flag for the second stroke), 4 `AppAction`s + main.dart cases, side-count dialog. 703 tests green (33 new), analyze clean, web smoke re-run on a fresh release build: **SMOKE PASS**, zero console errors (no drive.js changes needed — no new app-bar icons, Square stays the Macros menu's row 1).

**Next**
- Phase 19 (export) is the last speced phase; the two environment-blocked Phase 12 boxes (iOS build, Android emulator smoke) remain open. Consider a v0.1 tag after Phase 19.

**Open questions / gotchas**
- The Macros flyout (14 rows) now overflows the 600-px widget-test screen — menu taps on later rows need `scrollUntilVisible` (the sweep test does this now).
- The random stamps read the tap's `snapThreshold` to size the stamp (≈80 screen px at any zoom); a `ToolInput` built without it (tests, programmatic) falls back to 80 world units.
- `X I` (isosceles trapezium) vs `X ⇧I` (isosceles triangle) rely on the resolver's per-stroke shift matching; the table test's ambiguity sweep covers the pair.
- drive.js not extended with Phase 16 sections (widget + domain tests cover the flows — the parallelogram precedent).

## Session 23 — 2026-07-04

**Done**
- **Phase 20 complete** on `phase-20-smart-point-placement` (4 commits). User request: merge Point / Point-on-object and fix "snap to line doesn't work for the angle bisector" — exploration showed *no* point-collecting tool glued to curves (shared `MultiPointTool.collectVertex` only snapped to existing points), so one fix covers both.
- New shared resolver `domain/tools/point_resolution.dart` — the ladder: existing point → `IntersectionPoint` at the nearest in-threshold branch (GeoGebra-style crossing snap, user opted in) → `PointOnObject` on the ranked-best curve → `FreePoint`. Used by `PointTool` and `collectVertex`, so point/line/segment/circle/midpoint/angle-bisector/transforms/macros all snap identically. `IntersectionTool`'s private `_nearestBranch` generalized into the resolver's `nearestIntersectionBranch` (returns null when disjoint; the tool maps null → 0 to keep committing non-intersecting pairs).
- `ToolInput` gains `extraHits` + `snapThreshold` (defaults keep all ~85 existing call sites bit-identical; `snapThreshold: 0` disables crossing snap). `CanvasHitTester.hitTestAll` returns the ranked in-threshold list; `hitTest` is now its `firstOrNull`. `_handleTap` passes the full ranked list + threshold. `PointOnObjectTool` deleted; toolbar row removed (it had no shortcut/action, so `main.dart`/`shortcut_table` untouched).
- 670 tests green (analyze clean): new `point_resolution_test.dart` (14 cases incl. branch picking, threshold fall-through, rank-order tie-break), point/two-point/triangle-center tool tests flipped to the glued expectation, `hitTestAll` ordering tests. drive.js extended with a Phase 20 section (glue + crossing snap verified through the saved doc's object types): **SMOKE PASS**, zero console errors.
- Deliberate behavior change (in PLAN): a free point can no longer be dropped *exactly on* a curve — place off-curve and drag if wanted.

**Next**
- Merge `phase-20-smart-point-placement` to `main`. Then Phase 16 (angle-by-size + triangle/polygon macros) or Phase 19 (export) as before.

**Open questions / gotchas**
- drive.js: File > New pops the discard-confirmation dialog whenever the construction is non-empty — a scripted click sequence that assumes the menu just closes silently eats the next clicks. The Phase 20 section clears the canvas with Ctrl+Z instead.
- A macro corner glued to a curve routes the macro's rigid drag through that curve's free ancestors (consistent with existing derived-parent semantics, but new for macros).
- `PointOnObject`/`IntersectionPoint` still bind to infinite carriers, so a P-tap near a crossing just *past* a segment's endpoint can snap to a point off the drawn extent — same pre-existing wart as `IntersectionTool`.
- Crossing snap reuses the 8 px hit threshold; if it feels too eager/timid, tune the `snapThreshold` the canvas passes — no domain change needed.

## Session 22 — 2026-07-04

**Done**
- **Phase 15 complete** on `phase-15-transforms` (3 commits), merged to `main`. In landing order:
- Four transformation point kinds, planned names kept: `ReflectedPoint` (point + `GeoLine` mirror, via new `LineEq.reflect`), `CentralReflectionPoint` (half-turn about a center), `RotatedPoint` (fixed CCW angle in radians about a center, via new `Vec2.rotated`), `TranslatedPoint` (by the live vector between two points). All ordinary derived `GeoPoint`s — painter/hit-tester/drag untouched. Codec entries with no version bump (`RotatedPoint.angle` rides `params`); kitchen-sink round-trip covers all four. Math helpers glados-tested (double reflection identity, perpendicular-bisector swap — the PLAN test-strategy property — rotation preserves length and composes additively).
- Tools: reflect-about-line reuses `PointAndLineTool`, reflect-about-point `TwoPointTool`, translate `ThreePointTool` (tap the point first, then center / vector tail+tip); rotation is a dedicated `RotatedPointTool` over `MultiPointTool` because a `TwoPointTool` closure capturing the dialog angle could never be a canonicalized tear-off, which the toolbar highlight keys on. Angle dialog takes degrees (CCW, negative = clockwise), stores radians, shared by flyout + chord like the ratio dialog.
- New Transform flyout (`Icons.flip`, between Angles and Macros per PLAN); Points catch-all and Lines highlights now exclude the transform builders. Chords `G L`/`G P`/`G T`/`G V` (PLAN updated first; `G T` = "turn", `R` taken); the failed-chord resolver test moved from `G P` to still-unbound `G Q`.
- 652 tests green (37 new), analyze clean. Web smoke re-run on a fresh release build: **SMOKE PASS**, zero console errors — drive.js re-indexed for 11 icons (Macros moved to `icons[6]`), and the File menu now opens *right*-aligned (button sits left of the midline with 11 icons), so the Save click moved to `fileX + 30`.
- Housekeeping: `devtools_options.yaml` (user-deleted, tool-regenerated) is now gitignored.

**Next**
- Phase 16 — angle-by-size (`AngleBySizeTool` = arm point, vertex, size dialog → `RotatedPoint` + `VertexAngle`; rotation dependency now landed) + triangle/polygon macros (input schemes to spec in PLAN first). Then Phase 19 (export). The two environment-blocked Phase 12 boxes remain open.

**Open questions / gotchas**
- Menu-open alignment is now split across the app bar: File (left of the window midline) opens right-aligned, the flyout groups farther right open left-aligned. Any smoke click into a menu must pick the side per button — the old "every menu opens left" note no longer holds.
- The transform flyout/highlight relies on builder tear-off identity like the rest of the toolbar; `RotatedPointTool` must stay a distinct class (see the PLAN tool-system note) or its highlight falls into the Points catch-all.
- Tap order convention chosen for transforms: the point being transformed is always the *first* tap (then center, or vector tail → tip). GeoGebra-compatible; flyout labels spell it out.

## Session 21 — 2026-07-04

**Done**
- **Phase 14 complete** on `phase-14-drag` (3 commits), merged to `main`. In landing order:
- `PointOnObject` slide-drag: `Construction.setPointOnObjectParameter` (the constrained-point sibling of `moveFreePoint` — recomputes the point itself *then* its dependents) + `SetPointOnObjectParameterCommand` (from/to parameters, float-exact replay). `DragSession` refactored into an abstract base with `_TranslateDragSession` (the old behavior, unchanged) and `_SlideDragSession`: the host curve's analytic form is captured once at grab (the drag can't change the curve), the pointer projects onto it per frame with a grab offset so the point rides the pointer instead of jumping under the cursor. `PointOnObject.parameter` is now a mutable field. tool_provider/canvas needed zero changes — they only know the `DragSession` interface.
- `CompassCircle` center-only drag: one special case in `DragSession.start` — the translated set is `freePointAncestors(target.center)`. Radius points stay put (the radius is a measurement); a derived/constrained center drags its own free ancestors.
- Web trackpad mapping decided and shipped (PLAN updated first): Figma-style. Plain scroll = pan (content moves against the wheel delta — document-like for wheels, content-follows-fingers for natural trackpads), pinch = zoom about cursor via `PointerScaleEvent`, physical Ctrl/Cmd+scroll = zoom. Cheat-sheet gesture rows reworded.
- 615 tests green (13 new domain + 4 canvas widget tests incl. slide-on-circle, compass drag, scroll-pan/Ctrl-zoom/`PointerScaleEvent`), analyze clean. Web smoke reworked (zoom section holds Ctrl; new plain-scroll pan check asserts translation without spread change) and re-run on a fresh release build: SMOKE PASS, zero console errors.
- Post-merge user report, second stint (`phase-14-arrow-nudge`, merged): arrow-key nudge flipped from camera to **content semantics** — pressing → now moves the drawing right. The Phase 11 camera direction wasn't a regression, but the new content-follows scroll pan made it read as inverted; now every pan gesture moves content with the gesture. Widget test + smoke assertion flipped (shift +32 px), SMOKE PASS again.

**Next**
- Phase 15 — transformations: four derived-point kinds (reflect about line/point, rotate by fixed angle, translate by vector) + tools + codec entries + invariant tests. Then Phase 16 (angle-by-size, triangle/polygon macros) and Phase 19 (export). The two environment-blocked Phase 12 boxes remain open.

**Open questions / gotchas**
- `pannedByScreen` is *content-follows* ("content follows a rightward/downward delta" — its doc), not camera semantics: the scroll handler negates the wheel delta. Sign errors here read as inverted scrolling; the canvas test pins both axes.
- On the ±π atan2 cut of a circle host, a slide-drag's stored parameter can legitimately come back as −π where +π went in (same rim position — the parameter is periodic); tests assert position, not raw parameter, there.
- The angular grab-offset normalization keeps circle parameters within one turn of the principal range; without it, repeated grabs near the cut could accumulate +2π per gesture.
- A compass circle whose center's free ancestors overlap the radius pair's (e.g. center = midpoint of the radius points) *does* change radius when dragged — deliberate, the rule is "the center's ancestors".
- Playwright can't fake a browser pinch (the engine synthesizes `PointerScaleEvent` only for ctrl-flagged wheels with no physical Ctrl down; `keyboard.down('Control')` makes it a real Ctrl+scroll) — the pinch path is widget-tested, the smoke covers Ctrl+scroll.

## Session 20 — 2026-07-04

**Done**
- Plan-only session: **Phase 19 — Export** specced in PLAN/TODO, no code. PLAN gained an "Export (`application/export/`)" subsection after Persistence: PNG committed (off-screen `PictureRecorder` + existing `GeometryPainter` — never a widget screenshot, so no UI chrome; fit-vs-current-viewport framing via `fittedViewport`; 1×/2×/4× scale; theme vs transparent background; bytes out through the existing `saveFile(bytes:)`), SVG as an explicit stretch (hand-written writer mirroring the painter), PDF/clipboard out of scope. Export is read-only view work — no `Command`, not undoable, no save-format change.
- Build-order item 18, `Ctrl/Cmd + E` in the shortcut table (marked Phase 19), and the app-bar file-menu mention added; TODO gained the Phase 19 checklist (renderer, dialog + menu + shortcut, delivery/platform verify, tests, SVG stretch).
- Reverted the Phase 17B group-tooltip keys line (user request): group-icon tooltips no longer list shortcut keys — the dimmed trailing hints next to the flyout subtool names are the only place keys show. Dead `keys` computation removed from `_ToolGroup`, tooltip test updated, PLAN's toolbar bullet corrected. Analyze clean, toolbar tests green (6).

**Next**
- Phase 14 remains the top open *implementation* phase (slide-drag, compass-circle drag, trackpad pan); Phase 19 queues behind 14–16 unless the user pulls it forward.

**Open questions / gotchas**
- `Ctrl/Cmd + E` verified unbound today — re-check for collisions when Phase 15/16 bindings land, since those are still proposals.

## Session 19 — 2026-07-04

**Done**
- Phases 17 & 18 planned from user feedback (5 items: draggable labels, dashed lines, shortcut hints on tools, cheat-sheet icon, rectangle/isosceles-trapezium + more quad macros). PLAN/TODO updated first; user confirmed rhombus, kite and right trapezium join Phase 18, shortcut hints as trailing menu text, labels free-but-clamped, dash presets discrete.
- **Phase 17 complete** on `phase-17-polish` (5 commits). In landing order:
- 17A: cheat-sheet toggle `IconButton` (keyboard icon) between Reset and the theme toggle — placement keeps drive.js's "theme toggle is last enabled icon" indexing valid; only its order comment changed.
- 17B: `shortcutDisplayFor(AppAction)` over the shortcut table (first cheat-sheet-visible binding wins, hidden alternates like Ctrl+Y never surface); toolbar flyout tuples grew an `AppAction?`; rows render the key as dimmed trailing text inside a fixed-width `SizedBox` row (popup menus size intrinsically — `Spacer` misbehaves there); group tooltips list their keys on a second line.
- 17C: `ObjectAttributes.dashPeriod` (0 = solid, dash = gap = period/2, additive → no codec version bump); hand-rolled `dashPath` via `PathMetrics` (no dependency); painter routes all stroked kinds through it (angle markers + selection halo deliberately solid); inspector "Line style" Solid/Fine/Medium/Coarse = 0/4/8/16 on the strokes slice. Goldens regenerated (decorations scene gained a dashed segment + dashed circle).
- 17D: `labelDx`/`labelDy` screen-px attributes (defaults = the old hardcoded (6, −18), so old saves render identically); shared `labelScreenRect` in `label_layout.dart` keeps painter and grab rect in lockstep; label drag lives in move/select mode, hit-tests labels *before* geometry on pan-start (reverse insertion order = topmost), previews via a painter `labelDragPreview` override held as canvas widget state, clamps the offset radially to 40 px, commits exactly one `ChangeAttributesCommand` (cancel just drops the state).
- 564 tests green, `flutter analyze` clean, web smoke SMOKE PASS (10 enabled icons, zero console errors).
- **Phase 18 complete** too, same session, on `phase-18-quad-macros` (2 commits): `mirrorPointAcross` (`domain/tools/mirror_point_scaffolding.dart`) reflects a point across a line as hidden perpendicular → branch-0 line∩line foot → `SegmentRatioPoint` ratio 2 — single-valued and continuous when the point drags across the axis, which circle-branch mirroring can't be (fixed branch indices swap sides). Five `MultiPointTool` subclasses over it and the existing primitives, all pure compositions (codec/painter/hit-tester untouched, one `MacroCommand` each): **Rectangle** (2 taps + position-only height tap → C on the hidden perpendicular through B, D closes via parallel ∩ perpendicular), **Right trapezium** (3 taps, D = perpendicular-through-A ∩ parallel-through-C), **Rhombus** (2 taps + position-only direction tap → C rides a hidden `CompassCircle(A,B,center:B)` so |BC| ≡ |AB|, D via the parallelogram trick), **Isosceles trapezium** (3 taps, D = C mirrored across AB's perpendicular bisector), **Kite** (3 taps, D = B mirrored across the hidden diagonal segment AC). Macros flyout, `AppAction` switch and X R/H/K/I/L chords wired; PLAN's Phase-16 triangle chord proposals moved to `X ⇧I`/`X ⇧R`.
- 596 tests green (32 new domain tests: geometry invariants re-checked after drags incl. across-axis crossings, one-undo-unit, degeneracy round-trips, hidden scaffolding, position-only taps never consuming points; + a toolbar activation sweep), analyze clean, web smoke re-run on the final build: SMOKE PASS.

**Next**
- Phase 14 (drag & gesture fixes: `PointOnObject` slide-drag, compass-circle center-only drag, web trackpad pan mapping) is now the top open phase; then Phases 15–16 (transformations, angle-by-size + triangle/polygon macros). The two environment-blocked Phase 12 boxes remain open.

**Open questions / gotchas**
- The dash selector pushed the inspector's read-only multi-selection list below the 600-px test fold — `scrollUntilVisible` needed in one more test (the delete-button idiom).
- Widget-test label drags must beat the recognizer's pan slop (~36 px): a 20 px `moveTo` never fires `onScaleStart` and the test passes vacuously. The label tests move 30/30.
- Dashed *infinite* lines walk the full extended path (reach ≈ anchor distance + canvas size) through `PathMetrics` every frame — fine today; revisit only if a screenful of dashed lines ever drags.
- drive.js not extended with Phase 17 pixel sections (label drag needs inspector-driven naming first — heavy UI scripting); widget tests cover the flows, parallelogram precedent.

## Session 18 — 2026-07-04

**Done**
- **Phase 13 complete** on `phase-13-toolbar` (4 commits), merged to `main`. In landing order:
- `IntersectionTool` (`domain/tools/intersection_tool.dart`): collects two distinct curves — lines *or* circles, carriers count — like `TwoLineTool`, then commits one `IntersectionPoint`. Branch disambiguation: the branch nearest the *second* tap wins, resolved by constructing both branch objects as throwaway probes so the choice rides the documented deterministic branch order (no duplicated intersection dispatch). Non-intersecting curves still commit a branch-0 point (undefined until dragged together). The previously deferred `I` binding landed with it. 11 domain tests + editor-wiring and canvas-flow widget tests.
- Toolbar regrouped into five flyouts and extracted from `main.dart` (940→600 lines) to `presentation/panels/toolbar.dart` per PLAN's layout table: Points / Lines / Circles / Angles / Macros. Standalone Point, Point-on-object (and the hours-old Intersection) buttons plus the line-constructions and triangle-centers menus retired. Builders are now *public* canonicalized tear-offs shared by menus and the keyboard switch; the Points highlight is a catch-all for any `TwoPointTool` builder no tear-off claims (the segment-ratio closure captures its ratio, so it can never be one).
- Deselect affordances: double-clicking the active (highlighted) group icon deactivates its tool; the `GestureDetector` mounts *only while active*, so the double-tap-timeout delay on opening a flyout applies only then; the active tooltip appends "double-click to deselect". New `toolbar_test.dart` (4 tests) + a rewritten deactivation canvas test.
- Cheat sheet: `V` unhidden (was a deliberate Esc twin — user asked for it); new display-only `GestureRow` list renders Space+drag / scroll / two-finger / pinch rows in the Viewport section — the resolver never sees them.
- Web smoke re-indexed and re-run against a fresh release build: **SMOKE PASS**, zero console errors. 548 tests green, `flutter analyze` clean.

**Next**
- Phase 14 — drag & gesture fixes: `PointOnObject` slide-drag via a new `SetPointOnObjectParameterCommand`, `CompassCircle` center-only drag, and the trackpad pan-mapping decision for web (no drag-to-pan exists in the browser today; see the Phase 14 TODO entry for the full diagnosis). Start a `phase-14-drag` branch.
- The two environment-blocked Phase 12 boxes (iOS build, Android emulator smoke) remain open.

**Open questions / gotchas**
- With only 9 enabled app-bar icons the whole action cluster sits right of the window midline, so **every** `PopupMenuButton` menu — File included — now opens *left-aligned* to its button (Flutter grows menus toward the side with more room). drive.js clicks left of every icon; any future menu test near the right edge needs the same treatment.
- Opening a flyout whose tool is active waits out the double-tap timeout (~300 ms) before the menu appears — the accepted cost of the double-click-to-deselect affordance; it exists only on the active group. In widget tests, `pumpAndSettle` alone won't fire the delayed tap: `pump(kDoubleTapTimeout)` first (see `toolbar_test.dart`).
- `find.text('Point')` is ambiguous in widget tests when the inspector is open (kind header) — use `.last` for the flyout item.
- The `hit == null ||` guard in `IntersectionTool.onInput` is load-bearing: Dart flow analysis won't promote `GeoObject?` through `hit is! GeoLine && hit is! GeoCircle` alone (same as the Session 8 gotcha).
- PLAN's "adapt the toolbar to mobile with a bottom sheet" remains open — not scoped into any phase yet.

## Session 17 — 2026-07-04

**Done**
- Docs-only session: hands-on user feedback (11 items) folded into the plan as **Phases 13–16**. No code changed.
- `docs/TODO.md`: four new phases — Phase 13 toolbar rework & tool-selection UX (intersection tool + `I`, unified Points flyout, Circle → circles menu, two-point menu → Lines absorbing perpendicular/parallel/bisector, deselect affordances), Phase 14 drag & gesture fixes (`PointOnObject` slide-drag, compass-circle center-only drag, trackpad pan-zoom bug below), Phase 15 transformations (reflect about line/point, rotate, translate by vector), Phase 16 angle-by-size + triangle/polygon macros.
- `docs/PLAN.md` updated to match: Panels toolbar grouping rewritten (Points / Lines / Circles / Angles / Transform / Macros) + new tool activation/deactivation paragraph; Canvas dragging bullet gains the `PointOnObject` and `CompassCircle` exceptions; Points subclass list gains the four planned transformation points; Tool system gains the planned tools; `I` un-deferred, proposed `X E`/`X I`/`X R`/`X G` chords; Build order extended 12–15.
- Mid-session revision: the dedicated Drag tool (and a select-only no-tool default) was cut after discussion — dragging stays in the no-tool move/select mode, `V` unchanged. New web finding logged instead: three-finger trackpad pan on macOS also resizes the drawing on top of moving it (expected pure pan) → Phase 14. First hypothesis (`details.scale` drift in `_scaleUpdate`'s nav branch) was wrong — on web, trackpad swipes arrive as browser wheel events → `_handlePointerSignal` → zoom-about-cursor, which scales *and* shifts the drawing when the cursor is off-center; and a macOS three-finger drag is a synthetic mouse drag that rubber-bands. So there is no trackpad drag-to-pan on web at all (Space+drag / arrow keys only) — Phase 14 is a gesture-mapping decision, not a recognizer bug.

**Next**
- Start Phase 13 on a `phase-13-toolbar` branch. First concrete step: `IntersectionTool` (object already exists; tool + toolbar entry + `I` binding), then the menu regrouping in `lib/main.dart`.
- The two environment-blocked Phase 12 boxes (iOS build, Android emulator smoke) remain open and independent of Phases 13–16.

**Open questions / gotchas**
- Assumptions baked into the docs, to correct if wrong: "normal polygon" = regular polygon (n via dialog); "random" macros = one-tap stamps of randomized free points; angle-by-size = GeoGebra convention (arm point, vertex, size → rotated point + `VertexAngle`), which makes Phase 16 depend on Phase 15's rotation.
- Native desktop builds deliver trackpad gestures as PointerPanZoom into the scale recognizer's nav branch (not wheel events like the browser), so the Phase 14 mapping decision must be checked on both paths — they can end up with different behavior for the same physical gesture.
- `V` is bound to move/select but hidden from the `?` cheat sheet (`showInCheatSheet: false`, a deliberate Esc twin) — user noticed; surfacing it plus the pointer-gesture pan rows is now a Phase 13 item.
- Transformation-point class names (`ReflectedPoint`, `CentralReflectionPoint`, `RotatedPoint`, `TranslatedPoint`) are placeholders; refine at implementation per the naming convention.

## Session 16 — 2026-07-04

**Done**
- Phase 12 started on `phase-12-polish` (3 commits, merged to `main`) — everything except the two environment-blocked items landed.
- Goldens: the Session 2 decision resolved — `golden_toolkit` (discontinued) removed from `pubspec.yaml`, plain `matchesGoldenFile` instead, zero new dependencies. `test/presentation/goldens/object_kinds_golden_test.dart`: five scenes (points / lines / circles / angles / decorations — the last covers labels, custom color/stroke/point-size, a filled sector, selection halos, preview markers) × light + dark = 10 goldens, every concrete object kind rendered. Scenes framed by `fittedViewport`, background painted inside the `RepaintBoundary` (the real canvas paints over the scaffold, so the boundary needs its own `ColoredBox`). New `dart_test.yaml` declares the `golden` tag; CI's `flutter test --exclude-tags golden` verified to still run the other 520.
- Tool-flow widget tests: audit first — 15 sessions of per-phase coverage were already dense (creation flows with undo units, selection, drags, pan/zoom, file menu, every shortcut path). The one missing PLAN scenario landed in `geometry_canvas_test.dart`: circumcircle via the circles menu, apex vertex dragged — the circle recomputes per preview frame, lands equidistant from all three vertices, undo restores the dependent. Save/load round-trip box ticked with no new work (Phase 9's kitchen-sink codec test + `file_menu_test` + browser save check already cover it).
- Builds/smoke: `flutter build apk` ✓ (49.5 MB release, first Gradle run installed CMake). Full web smoke re-run on this branch against a fresh release build: SMOKE PASS, zero console errors. 531 tests green locally (520 in CI mode), `flutter analyze` clean.

**Next**
- The two remaining Phase 12 boxes are blocked on the environment, not code: (1) iOS — install Xcode from the App Store, `sudo xcode-select --switch`, `sudo xcodebuild -runFirstLaunch`, install CocoaPods, then `flutter build ios` + simulator smoke; (2) Android emulator smoke — approve a multi-GB system image (`sdkmanager "system-images;android-XX;google_apis;arm64-v8a"`), `flutter emulators --create`, then `flutter run -d emulator`. After those, Phase 12 (and the plan) is done; consider a v0.1 tag.
- Optional backlog if development continues: intersection *tool* (unblocks the `I` binding), sliding `PointOnObject` along its curve, angle hit-target world-radius hint, pending-leader indicator.

**Open questions / gotchas**
- Goldens are macOS-rendered pixels — regenerate with `flutter test --update-goldens --tags golden` on a Mac only; other platforms will diff. CI keeps excluding the tag.
- Golden labels render in the test framework's default Ahem font (solid boxes): label *position and metrics* are locked, glyph shapes are not. Don't chase font loading unless glyph regressions ever matter.
- `dart_test.yaml` now exists at the repo root; new tags must be declared there or `flutter test` warns.
- The decorations golden's filled sector at `fillAlpha: 0.25` is faint on the light canvas — deliberate (it matches the app), not a rendering bug.

## Session 15 — 2026-07-04

**Done**
- Phase 11 complete on `phase-11-shortcuts` (6 commits), merged to `main`. PLAN updated first: the stock `Shortcuts`/`Actions` sketch was replaced by a declarative `ShortcutTable` + pure `ShortcutResolver` + one root-`Focus` `AppShortcuts` widget — two-stroke leader chords (`G`/`X`) and the "stand down while an `EditableText` has focus" guard don't fit `ShortcutActivator`'s single-stroke model.
- Table (`shortcut_table.dart`): every PLAN binding incl. modifier axes (`shift: null` = don't-care for `=`/`+`; `primary` = Ctrl *or* Cmd), hidden alternates (numpad twins, Backspace, Ctrl+Y), `repeats` for viewport keys, cheat-sheet labels/sections. Table tests reject ambiguous bindings and leaders shadowed by single strokes. Deferred per PLAN: `I` (no intersection tool exists — users currently can't build one; macros do it internally) and Tab-cycle (needs cursor tracking).
- Resolver: single strokes win; leaders go pending (no timeout); Esc or a missed second stroke *swallows* the chord rather than firing the stroke standalone; pure-modifier presses don't cancel a pending leader. Key auto-repeat bypasses the resolver (a held leader would cancel its own chord) and only drives `repeats` bindings.
- EditorScreen owns the one exhaustive `AppAction` switch (a new binding without wiring fails to compile). Arrow-key nudge (camera semantics, 32 px) finally wires `CanvasViewport.pannedByScreen` from Phase 8; `=`/`-` zoom about the canvas center; `0` = 100 % keeping the center pinned (unlike Reset). Del/Backspace shares the inspector's cascade-confirmation via extracted `deleteSelectionWithConfirmation`. Two-point menu builders became top-level functions shared with the keyboard path.
- Cheat sheet (`?`): in-tree overlay, deliberately not a dialog route (a route's focus scope cuts `AppShortcuts` off from keys, so `?` couldn't toggle it closed). Esc only closes the sheet — the active tool survives; any other shortcut closes it and executes.
- 520 tests green, `flutter analyze` clean. Web smoke extended (real browser key events): Ctrl+Z removes the whole square macro in one step, `=`×2 spread ratio 1.440 vs 1.44 expected, ArrowRight −32.0 px, `?` barrier 765→459 luminance. SMOKE PASS, zero console errors.

**Next**
- Phase 12 — tests & polish: golden tests light+dark per object kind (remember the Session 2 decision point: `golden_toolkit` is discontinued — pick `alchemist` or plain `matchesGoldenFile` first), representative tool-flow widget tests, cross-platform smoke (`flutter build apk` / iOS — Xcode was incomplete in Session 2, check `flutter doctor` before betting on iOS). Start a `phase-12-polish` branch.

**Open questions / gotchas**
- Clicking the canvas refocuses the shortcut layer via `AppShortcuts.refocus` (a `Listener` wrapper in `EditorScreen`) — plain `unfocus()` would strand key events on a focus scope that isn't an ancestor of the shortcut node, killing all shortcuts. Keep that wrapper if the canvas gets rehosted.
- Shift+H (reveal all) also reveals hidden macro scaffolding — "all" means all, and it's one undoable command. Revisit only if it confuses in practice.
- `?` arrives as `question` on some platforms and shifted `slash` on others; the table carries both (the twin is cheat-sheet-hidden). Same pattern for any future punctuation binding.
- Browser-reserved combos (Cmd+N new window, possibly Cmd+D) can't be intercepted on web even though Flutter preventDefaults handled keys; the bindings still work on desktop and in the widget tests. Not worth chasing.
- No pending-leader UI: after pressing `G`/`X` nothing indicates the chord is armed. Add an indicator if chords prove hard to trust.
- Still open from earlier phases: intersection *tool* (now also blocks the `I` binding); sliding `PointOnObject` along its curve; angle hit-target world-radius hint.

## Session 14 — 2026-07-04

**Done**
- Phase 10 started on `phase-10-macros` (4 commits, unmerged — parallelogram/trapezium still to come). Square macro landed end to end.
- Framework first: `MultiPointTool.buildObjects` now returns a `List<GeoObject>` (one `AddObjectCommand` per object inside the same single `MacroCommand`; list must be in dependency order). The three existing subclasses wrap their single object — no behaviour change, all 462 prior tests untouched.
- `SquareMacroTool` (2 taps): tapped points are adjacent corners A, B; C and D are *derived* — branch-1 `IntersectionPoint`s of a hidden `PerpendicularLine` (through B resp. A, referenced on the visible side `Segment` AB) with a hidden `CompassCircle` of radius |AB|. Pure composition of existing kinds: codec, painter, hit tester all untouched. Branch 1 along the carrier's CCW normal ⇒ the square lies to the *left* of A→B; tap order picks the side, and the side follows drags continuously (the carrier direction comes from parent order and is never re-canonicalized — checked against `LineEq` before coding).
- App bar: new shape-macros menu (`Icons.crop_square`), highlighted while a `SquareMacroTool` is active. 469 tests green (`flutter analyze` clean): tool geometry, one-undo-unit, drag stays square, degeneracy round-trip, hidden-scaffolding attributes, plus a widget test driving menu → two taps.
- Web smoke extended (`tool/web_smoke/drive.js`, release build served statically per the Session 13 rule): square renders all four sides + corner dots; hidden perpendiculars leave no pixels past the side extents (side BC lies *on* perpB's carrier, so beyond-extent pixels are the discriminator); hidden circles invisible; interior empty. SMOKE PASS.
- Second stint: `ParallelogramMacroTool` (2 more commits, 6 total). Three taps = consecutive corners A, B, C; D = A + (C − B) as the single-branch line∩line intersection of two hidden `ParallelLine`s referenced on the visible sides AB/BC — no side ambiguity, unlike the square. Collinearity leaves D undefined and it recovers. Joined the shapes menu (highlight covers both macros). 474 tests green, analyze clean. Parallelogram is widget-tested only — the browser smoke's macro section still drives just the square (same machinery; extend if a regression ever suggests it).

- Third stint: trapezium — **Phase 10 complete** (10 commits), merged to `main`. PLAN updated first with the point story: 3 corner taps + a *position-only* 4th tap that projects D onto the hidden parallel-to-AB through C via `PointOnObject.near` (direct manipulation over a ratio dialog). To host a trailing non-point input, `MultiPointTool`'s collect and commit steps became callable hooks (`collectVertex` / `commitCollected`; base `onInput` unchanged) — `TrapeziumMacroTool` overrides `onInput`, holds the 4th tap in a field alive only inside the commit turn. The 4th tap never consumes an existing point (D must stay constrained; tested). Degenerate collections (A≈B ⇒ parallel undefined) fall back to `parameter: 0` instead of `.near`'s undefined-curve throw — and since the parameter rides the analytic form, D recovers *exactly in place* after a degeneracy round-trip (test asserts the exact position). 481 tests green, analyze clean, web smoke re-run: PASS.

**Next**
- Phase 11 — keyboard shortcuts (`lib/presentation/shortcuts/`): `Shortcuts`/`Actions` wiring, central `ShortcutTable` (PLAN has the full binding tables), cheat-sheet overlay on `?`, widget tests sending key events. Arrow-key viewport nudge wiring (`CanvasViewport.pannedByScreen` has waited since Phase 8). Start a `phase-11-shortcuts` branch. PLAN's macro chords (`X` `S`/`P`/`T`) now have all three tools to bind to.

**Open questions / gotchas**
- Popup menus that would overflow the right window edge open shifted *left* of their button — the smoke script clicks left of the icon for the shapes menu, unlike the file menu. Any future menu near the right edge needs the same treatment.
- The shapes menu added an enabled app-bar icon: drive.js now indexes the theme toggle from the *end* of the enabled-icon row instead of a fixed index (fresh app: 12 enabled icons, undo/redo greyed out). Keep the order comment in drive.js synced with `main.dart`.
- `Sector`'s fill-alpha styling precedent may matter if macros ever want filled interiors; the square deliberately has none (interior-empty is smoke-asserted).
- Still open from earlier phases: sliding `PointOnObject` along its curve; angle hit-target world-radius hint.

## Session 13 — 2026-07-04

**Done**
- Phase 9 complete on `phase-9-persistence` (5 commits), merged to `main`. PLAN updated first: encode + decode live in *one* centralized codec (`application/persistence/construction_codec.dart`) instead of per-class `toJson` — the type↔constructor registry must exist centrally for decoding anyway, and the domain layer stays persistence-free. The cost (a forgotten kind fails at runtime) is covered by a kitchen-sink round-trip test instantiating every concrete object kind.
- Codec: `version: 1` stamped, files with a newer version rejected; objects written in insertion (= topological) order, parents resolved by id on decode; viewport snapshotted outside undo history per the Phase 8 decision. Every decode failure — malformed JSON/UTF-8, unknown type, unknown/ill-kinded parent, duplicate id, constructor-level `ArgumentError` — normalizes to `FormatException` with the offending object's id, so File > Open shows one dialog for any bad file.
- File menu (app bar): New confirms before discarding a non-empty construction (replace drops undo history) and centers the world origin — closing the Session 12 open question; app *launch* is unchanged (no size before first frame). Save hands bytes to `FilePicker.saveFile` (writes on all platforms, download on web). Widget tests override `FilePickerPlatform.instance` with a hand-rolled fake (the mocktail route fails `verifyToken`).
- Theme: `AppTheme` pins primary (default object color) and tertiary (selection) with ≥ 3:1 WCAG contrast against the canvas (= scaffold background) in both themes, test-enforced. `main()` awaits `SharedPreferences` once, injects via ProviderScope override; `themeModeProvider` reads the stored choice synchronously, defaults to system, persists explicit choices; app-bar toggle flips against the *rendered* brightness.
- 462 tests green, `flutter analyze` clean. Real-browser smoke extended in-repo (`tool/web_smoke/drive.js`): Save's download parses as a version-1 doc carrying the placed points and the zoomed viewport (scale 1.822 = e^0.6); theme toggle drops canvas luminance 765→73 and survives a reload.

**Next**
- Phase 10 — macros: square / parallelogram / trapezium tools over the existing `MacroCommand` machinery. Start a `phase-10-macros` branch. (Phase 11 shortcuts and Phase 12 goldens after that; remember the `golden_toolkit` replacement decision from Session 2.)

**Open questions / gotchas**
- **Do not smoke-test against `flutter run -d web-server`**: the debug DWDS server wedges after the first Playwright session disconnects and then serves blank white pages. Serve `flutter build web --release` statically (README updated). Cost real debugging time this session.
- The smoke script indexes app-bar icons by *enabled* glyph runs — disabled undo/redo sit below the darkness threshold. The theme toggle is the last enabled icon (after fit/reset), not before them; keep drive.js's order comment in sync with `main.dart`'s actions row.
- `PopupMenuButton` items in the smoke script are hit by coordinates (menu opens over the button, 48 px rows, ~8 px top padding) — works, but recheck if menu contents change.
- Codec decode wraps constructor `ArgumentError`s (bad branch index, self-intersection, duplicate id) into `FormatException` at the `Construction.add` call site — new object kinds with constructor validation get file-error handling for free, but a new kind must be added to *both* codec switches (encode + decode); the kitchen-sink test fails loudly if forgotten.
- `ObjectAttributes.fromJson` throws `TypeError` (not `CheckedFromJsonException`) on ill-typed fields — the codec catches all `Object` there deliberately.
- File > Open keeps the *file's* viewport; Fit remains the recovery if a file was saved zoomed into nowhere. Still open from earlier phases: sliding `PointOnObject` along its curve; angle hit-target world-radius hint.

## Session 12 — 2026-07-04

**Done**
- Phase 8 complete on `phase-8-viewport` (4 commits), merged to `main`. PLAN updated first with the decision the Session 11 entry teed up: viewport changes are *view* state — never `Command`s, never undoable (same reasoning as selection); the viewport still gets snapshotted into the Phase 9 save format, just outside undo history.
- Scroll-zoom: `CanvasViewport.zoomedAbout` pins the world point under the cursor, scale clamped 0.05–50 px/unit; factor is e^(−dy·0.002) so scroll up/down round-trips exactly; wired through `Listener.onPointerSignal` + `PointerSignalResolver`.
- Pinch + pan: canvas moved from pan to *scale* callbacks (Flutter forbids both on one detector; scale also receives trackpad pan-zoom, which reports as ≥2 pointers). Two fingers or held space = navigation: `CanvasViewport.pinning` solves zoom+pan each frame from a per-gesture baseline (no accumulated error). Navigation latches until every pointer lifts; a band/drag interrupted by a second finger cancels, never commits.
- Fit / reset: pure `fittedViewport` over per-kind world bounds (points, full circle discs, angle vertices; lines contribute nothing — their defining points already count; single point centers at 100 %). App-bar Fit + Reset buttons; canvas size read via a `GlobalKey` at tap time. `CanvasViewport.pannedByScreen` backs nudge; arrow-key wiring is Phase 11's shortcut table.
- 420 tests green, `flutter analyze` clean. Real-browser smoke (Playwright + `flutter run -d web-server`): 3 wheel notches measured spread ×1.820 vs e^0.6 ≈ 1.822 expected, focal point pinned within 0.5 px, zero console errors.
- The Playwright drive script now lives **in-repo** at `tool/web_smoke/drive.js` (+README) — Session 7's died with its scratchpad; extend it per phase instead of rewriting.

**Next**
- Phase 9 — persistence & theme: JSON codec (`version: 1`, topological order), Save/Open via `file_picker`, light/dark canvas palette, theme choice in `shared_preferences`, round-trip test on a construction using every object kind. Start a `phase-9-persistence` branch.

**Open questions / gotchas**
- `ScaleGestureRecognizer` reports the focal point only at *acceptance* (past ~18 px slop) — the canvas `Listener` records the true down position for the band anchor and drag hit test. `dragStartBehavior` is back to the default `.start`: the anchor no longer comes from the recognizer, and `.start` re-baselines `details.scale` at acceptance so a pinch can't open with a jump.
- The scale gesture has no cancel callback; pointer-cancel rollback lives in `Listener.onPointerCancel`, and the recognizer's trailing `onEnd` then finds nothing to commit (`endDrag` without a session is a no-op — relied upon).
- On finger add/remove the recognizer fires `onEnd` + fresh `onStart`; `ScaleEndDetails.pointerCount` 0 vs >0 is what separates "gesture over" from "reconfiguring". Don't collapse the two paths.
- Widget-testing multi-touch: per-finger moves are sequential events, so the span breathes mid-frame. Separate the fingers *perpendicular* to the drag direction (span ≈ constant) or the accept-time baseline bakes a spurious zoom into the assertions.
- Default viewport still puts the world origin at the canvas top-left; Fit is the recovery. If Phase 9's File > New should open centered instead, decide it there.
- Still open: sliding `PointOnObject` along its curve when dragged; angle hit-target world-radius hint now that zoom exists (marker is screen-sized, tester is world-space).

## Session 11 — 2026-07-03

**Done**
- Phase 7 finished, all on `phase-7-selection` (8 commits), merged into `main`. In landing order:
- Click selection (tap selects / shift-tap toggles / empty tap clears; taps while a tool is active never touch the selection) + selection halos in theme tertiary; rubber band from empty canvas takes what it *wholly* contains (infinite lines/rays never band), shift-band unions.
- Dragging: free point → `MoveFreePointCommand`; derived object → rigid translation of its free-point *ancestors* via `TranslateObjectsCommand`. `DragSession` (domain/tools) previews per frame and rolls back before the single commit — one command per gesture, per the CLAUDE.md carve-out. Derived *points* refuse to drag (sliding `PointOnObject` still open).
- Attributes inspector (right panel, exists exactly while something is selected): kind header, name field (single only), visible/label tristate checkboxes, color swatches (fixed palette + "Auto" = null = theme default), discrete stroke-width/point-size segments (stroke targets non-points, size targets points; each shown only when the selection has that kind). Every tap = exactly one `ChangeAttributesCommand`; mixed state = dash / no highlight.
- Cascading-delete UX: Delete button in the inspector; confirmation dialog *only* when the cascade reaches beyond the selection, listing the unselected casualties; always one `DeleteObjectsCommand`. `Construction.transitiveDependentsOf` added (public, non-mutating) for the preview.
- Object tree panel (left, toggled from the app bar, hidden by default): flat list grouped by sealed kind in insertion order; rows select on tap / toggle on shift-tap; per-row eye flips `visible` one command per tap — hidden objects are now reachable again.
- Painter now draws labels beside a per-kind `labelAnchor`. 401 tests green, `flutter analyze` clean.

**Next**
- Phase 8 — pan/zoom viewport: pinch, scroll-zoom, two-finger pan / space-drag, fit/reset/nudge. Start a `phase-8-viewport` branch. `viewportProvider` and `CanvasViewport` already exist; the work is gestures + commands-or-not decision (view state is not construction state — probably *not* undoable, mirror the selection's reasoning and note it in PLAN if confirmed).

**Open questions / gotchas**
- Selection pruning listens to the construction and can lag a build by one frame — panels must null-filter `construction.byId(id)` instead of assuming selected ids exist (both panels do; keep the idiom).
- Freezed `copyWith` uses the `freezed` sentinel, so `copyWith(colorArgb: null)` genuinely sets null — that's how "Auto" works; don't replace it with a hand-rolled copyWith.
- `SegmentedButton` with `emptySelectionAllowed: true` models the mixed state; a tap on the already-selected segment arrives as an *empty* selection — treat as no-op, not "clear the width".
- Inspector/tree are lazy `ListView`s: widget tests must `scrollUntilVisible` anything below the 600-px fold (see the delete-button test) or the finder comes up empty.
- Shift detection is `HardwareKeyboard.instance.isShiftPressed` in both canvas and tree — keep them consistent if a third selection surface appears.
- Still open from Phase 6/7: sliding `PointOnObject` along its curve when dragged; angle hit-target world-radius hint for `CanvasHitTester` if vertex-only picking feels too small in practice.

## Session 10 — 2026-07-02

**Done**
- Phase 6 finished. PLAN updated first (per CLAUDE.md) with the kind story: arcs/sectors are `GeoCircle`s with a carrier + *angular* extent (the circle-side twin of `Segment`/`Ray` on `GeoLine`); angles are a genuinely new 4th sealed kind `GeoAngle` whose value is an `AngleGeometry` (vertex, unit start direction, CCW sweep) — decorations plus a measure, no intersection math.
- `math/angle_geometry.dart`: `ccwSweep` (in [0, 2π)), `sweepThrough` (signed arc-branch pick), `AngleGeometry` with `fromRays` (directed, arm order picks the marker) and `betweenLines` (always acute/right, in (0, π/2]).
- `Arc` (start/via/end, signed sweep = branch containing via) and `Sector` (center + rim fixing radius/start angle + a point fixing only the end angle, CCW sweep): painter draws the branch via `drawArc` (world angles negate on screen, y-flip), hit tester clamps to the branch — off-branch falls back to endpoint distance (arc) or the two radius edges (sector).
- `GeoAngle` + `VertexAngle`/`LineAngle`. Adding the kind fanned out compiler-driven to every exhaustive switch: painter (marker wedge at fixed 20 px screen radius), hit tester (priority 3, picked at its *vertex* — the tester has no viewport, so it can't know the marker's world size), `PointOnObject`, `IntersectionPoint`, `PointAndLineTool`.
- Tools/chrome: arc + sector joined the circles menu (`ThreePointTool`); new angles menu (`Icons.square_foot`) with vertex angle (`ThreePointTool`) and `TwoLineTool` (new tool: collects two distinct existing lines, ignores everything else, previews the first tap projected on its carrier). Highlight logic extended to the new builder tear-offs.
- 336 tests green, `flutter analyze` clean. Merged `phase-6-objects` into `main`.

**Next**
- Phase 7 — Selection & attributes: multi-select (rubber band + shift-click), dragging derived objects via `TranslateObjectsCommand`, attributes inspector, hide/show, color/stroke, cascading-delete UX, object tree panel. Start a `phase-7-selection` branch.

**Open questions / gotchas**
- `VertexAngle` is *directed* (CCW from arm1's ray to arm2's): the two tap orders mark the two complementary angles. Deliberate — GeoGebra-style — and documented in the class; don't "fix" it to always-interior.
- `LineAngle` is undefined while its lines are parallel (no vertex to mark), even though "angle = 0" would be answerable. Also its vertex can sit outside a segment/ray parent's drawn extent (carrier semantics, same wart as `IntersectionPoint`).
- Angle hit testing is vertex-only, priority last. If Phase 7 selection makes that feel too small a target, the fix needs the viewport's zoom (marker radius is screen-space) — plumb a world-radius hint into `CanvasHitTester` rather than hardcoding one.
- `Sector.endRim` is a *computed* rim point (end projected onto the circle); `startRim` is the parent's own position. Painters/hit-testers must not assume `end.position` is on the circle.
- Screen-vs-world angle sign: `drawArc` needs both start angle and sweep *negated* (world y-up → screen y-down). Both call sites live in `_drawCarrierBranch`/`_drawAngleMarker`; keep any future angle drawing on that path.
- Dart's `%` on doubles is already Euclidean (non-negative for a positive divisor), but a tiny negative difference can round to exactly 2π — `ccwSweep` guards that edge; reuse it instead of inlining `% (2 * pi)`.

## Session 9 — 2026-07-02

**Done**
- Phase 6 continued on `phase-6-objects` (6 more commits, 18 total, still unmerged). Three object families landed end to end, each with domain tests, editor chrome and widget tests:
- `SegmentRatioPoint` (fixed lerp parameter along point1→point2; ratio outside [0,1] extrapolates deliberately). No new tool — a `TwoPointTool` builder captures the ratio. The two-point menu's values became async `TwoPointPick` factories so the ratio item can show a dialog (accepts `0.25` or `1/4`) before the tool exists; cancel or garbage input activates nothing.
- `ThreePointCircle` (circumcircle; undefined while collinear) and `CompassCircle` (radius = distance of two points, centered on a third; zero radius OK like `CircleCenterPoint`) — both reuse `ThreePointTool` from a new circles app-bar menu. The Session 8 highlight gotcha is resolved: builders are top-level functions, and the line/circle menu highlights compare `activeTool.build` against those canonicalized tear-offs.
- `Ray` (origin + through; carrier `GeoLine` like `Segment`): painter draws the half-line from the parent points' direction, hit tester got the predicted extent clamp — segment and ray now share one `_clampedDistance` helper (t in [0,1] vs [0,∞)).
- 286 tests green, `flutter analyze` clean.

**Next**
- Remaining Phase 6: arc (3-point), sector, angle (between lines / at vertex) + their tools. These likely need a new `GeoObject` kind (the sealed kinds are point/line/circle only) — per CLAUDE.md, update PLAN first and decide the kind/attribute story before coding.

**Open questions / gotchas**
- Dart won't infer lambda parameter types through an async closure's `FutureOr<TwoPointBuilder?>` return context — hence the `_pick` helper (typed parameter restores inference) and the typed local function in the ratio item. Don't "simplify" them back to bare lambdas.
- Disposing a `TextEditingController` right after `showDialog` returns crashes the dialog's exit animation; `_RatioDialog` is a StatefulWidget owning its controller for exactly that reason.
- Menu-highlight-by-builder relies on top-level function tear-offs being canonicalized (`==` across separate tear-offs). Inline lambdas would break it silently — keep `_build*` functions top-level.
- `Ray` painting/hit-testing must use the parent points, not `line.direction` — the carrier's direction is normalized independently of parent order. Noted in the class doc.
- `PointOnObject`'s line parameter is arc-length along the *unit* direction (parameter 1 ≠ "at the second defining point") — tripped up a test this session; worth remembering when writing expectations.

## Session 8 — 2026-07-02

**Done**
- Phase 6 started on branch `phase-6-objects` (3 commits, not yet merged — the phase is far from done). Triangle centers landed end to end: `TriangleCenterPoint` base (three `GeoPoint` vertices + undefined-state plumbing) with `Centroid`/`Orthocenter`/`Incenter`/`Circumcenter` as thin subclasses over `math/triangle_centers.dart`; one `TriangleCenterTool` covers all four via a `buildCenter` constructor tear-off (`Centroid.new`, …).
- First multi-input tool, so the supporting machinery landed with it: taps on existing points collect them (duplicates ignored), taps elsewhere create free points held privately until the third vertex, then everything commits as one `MacroCommand` (single undo unit). `ToolInputPreview` (domain) exposes collected positions; `GeometryPainter` draws dot+ring markers for them; minimal app-bar `PopupMenuButton` activates each center kind.
- New safety net: undo/redo and `constructionProvider.replace` now call `ToolNotifier.resetInProgress()` — without it, undoing a collected parent mid-collection made the eventual commit throw (`Construction.add`: parent not in construction). Covered by provider + widget tests.
- Second stint, same session: `PointOnObject` (stores a fixed parameter in the curve's *analytic* parameterization — new math APIs `LineEq.pointAt`/`parameterAt`, `CircleEq.angleAt` with property tests; `PointOnObject.near()` projects a tap). The collect-N logic then moved from `TriangleCenterTool` into an abstract `MultiPointTool`; `TwoPointTool` (builder lambda, positional args because param names differ per object) gives line/segment/circle/midpoint tools nearly for free — those two-point tools were missing from TODO entirely (added, ticked). `PointOnObjectTool` is stateless like `PointTool`. All wired into the app-bar chrome.
- Third stint: perpendicular/parallel lines and the angle bisector. `RelativeLine` template base (point + reference-line parents; subclass picks the direction from the reference carrier's unit normal/direction) with `PerpendicularLine`/`ParallelLine`; segments work as references through their carrier. The predicted new collect pattern landed as `PointAndLineTool`: two typed slots filled in either order (point slot also fills from an empty-canvas tap, MacroCommand-grouped like `MultiPointTool`; filled-slot input and circles ignored; line preview marker = tap projected onto the live carrier). Angle bisector: `math/angle_bisector.dart` (direction = û+v̂, falling back to (û−v̂)⊥ near straight angles — for unit vectors the two are orthogonal and never both small; null when an arm sits on the vertex) + `AngleBisectorLine` + `ThreePointTool` (positional-builder sibling of `TwoPointTool`, will also serve three-point circle/arc). The line_axis menu now carries `Tool Function()` factories so both tool types share it.
- 266 tests green, `flutter analyze` clean (12 commits on the branch).

**Next**
- Remaining Phase 6 items: segment-ratio point, three-point circle (reuse `ThreePointTool`), compass circle, arc, sector, angle, ray — each with its tool. Sector/angle may need a new `GeoObject` kind or attribute story — check PLAN before starting those.

**Open questions / gotchas**
- Constructor tear-off equality/constness is load-bearing in the editor menu (`PopupMenuItem(value: Centroid.new)` is const); the tear-offs all conform to `TriangleCenterBuilder` because extra optional params (`attributes`) don't break function-type assignability.
- `ToolInputPreview implements Tool` deliberately — an unrelated capability interface wouldn't type-promote after `tool is ToolInputPreview` (Dart promotes only to subtypes).
- `package:flutter/rendering.dart` does *not* re-export `listEquals`; the painter imports `foundation` for it.
- `TriangleCenterTool` allows coincident vertex *positions* (center goes undefined, recovers on drag apart) but rejects the same point *object* twice.
- `PointOnObject`'s parameter rides the *analytic* form (LineEq anchor/direction), not the defining points: translating a line along itself leaves the constrained point in place. Deterministic and documented in the class doc — same spirit as the intersection-branch wart. Revisit only if Phase 7 manual dragging makes it feel wrong.
- Dart flow analysis can't promote `GeoObject?` through `hit is! GeoLine && hit is! GeoCircle` — `PointOnObjectTool` needs the explicit `hit == null ||` first.
- Web smoke was not repeated this session (widget tests cover the flows); the Playwright drive script from Session 7 lived in that session's scratchpad and is gone — recreate it next time a real browser check is needed.
- The editor's line-constructions highlight treats any `ThreePointTool` as "this menu's tool" — once `ThreePointTool` also builds circles/arcs from another menu, the highlight must inspect the builder, not the type (comment in `main.dart`).
- `angleBisector` always returns the *internal* bisector; the external one (û−v̂ direction) is not exposed. If a future tool wants both, extend the math function rather than negating an arm at the call site.

## Session 7 — 2026-07-02

**Done**
- Phase 5 complete on branch `phase-5-canvas` (5 commits). `lib/domain/tools/`: `Tool` interface (`ToolInput` = world position + optional hit object; sealed `ToolResult` Accepted/Committed/Ignored; `reset()` for cancel/switch) + `PointTool` (stateless, ignores taps on existing points, injected `newId`). `lib/application/`: `object_ids.dart` (`newObjectId()`, the app's one UUID source) + `toolProvider` (`ActiveToolState` = nullable tool + revision, mirroring `ConstructionState`; `handleInput` funnels committed commands into `commandStackProvider`). `lib/presentation/canvas/`: `CanvasViewport`, `CanvasHitTester`, `GeometryPainter`, `GeometryCanvas`. `main.dart`: `ProviderScope` + minimal `EditorScreen` (point-tool toggle, undo/redo) — the real toolbar panel is Phases 6–7.
- 191 tests green, `flutter analyze` clean. Web smoke test done for real: `flutter run -d web-server` + Playwright/headless Chrome — 3 points placed under the cursor, undo×2, redo, all rendered, no console errors.

**Next**
- Phase 6 (object & tool coverage): triangle centers, `PointOnObject`, perpendicular/parallel, angle bisector, segment-ratio, three-point/compass circles, arc, sector, angle, ray — and a tool per object. First multi-input tools will exercise `ToolAccepted`/preview state for the first time; the painter needs in-progress input markers then too.

**Open questions / gotchas**
- Naming: PLAN's `Viewport`/`HitTester` collide with Flutter (`Viewport` widget) and flutter_test (`HitTester`) — landed as `CanvasViewport`/`CanvasHitTester`.
- World coordinates are **y-up**; the flip happens only in `CanvasViewport`. Default viewport puts world origin at the canvas top-left, so visible world y is negative until Phase 8's fit/center lands.
- `GeometryPainter.shouldRepaint` keys on construction *instance* + revision (+ viewport/color): `replace()` resets revisions, so instance identity alone distinguishes a swapped-in construction. `Construction.objects` returns a fresh iterable per call — never use it for identity.
- `toolProvider.handleInput` is the single entry point for canvas taps; presentation never touches commands directly. No active tool → `ToolIgnored` (a Phase 7 concern: that's where selection taps go).
- Web smoke gotcha for future driving: enabling Flutter's semantics tree reroutes canvas clicks through the GestureDetector's semantics node — `onTapUp` then reports the node *center*, not the cursor. Drive by raw coordinates with semantics off (script pattern in scratchpad `drive.js`; consider `/run-skill-generator` if we do this often).
- Infinite lines are drawn with far endpoints under a `clipRect`, reach scaled to anchor distance + canvas size — revisit only if extreme zoom-out shows artifacts.

## Session 6 — 2026-06-12

**Done**
- Phase 4 on branch `phase-4-providers` (2 commits + docs), merged to `main`. `lib/application/providers/` holds: `constructionProvider` (owns the `Construction`, bridges its listener API via a revision-counting `ConstructionState`; `replace()` swaps constructions for File > New/Open), `commandStackProvider` (wraps `CommandStack`; exposes `(canUndo, canRedo)` record), `selectionProvider` (selected-id set; prunes deleted ids), `viewportProvider` (`ViewportState` pan/scale only).
- 152 + 9 = 161 tests green, `flutter analyze` clean.
- `toolProvider` deferred to Phase 5 (TODO updated): the `Tool` interface doesn't exist yet, and designing it without Phase 5's canvas-input types would be guesswork.

**Next**
- Phase 5 (`lib/presentation/canvas/` + `lib/domain/tools/`): `Tool` interface + `toolProvider`, `Viewport` value type + transforms, `GeometryPainter`, `HitTester`, `GeometryCanvas`, `PointTool`, web smoke test.

**Open questions / gotchas**
- `@Riverpod(name: 'constructionProvider')` gives PLAN's provider names despite notifier classes being `ConstructionNotifier` etc. (a notifier class can't be called `Construction` — clashes with the domain class).
- `select` is not exported by `riverpod_annotation` — files needing it import `flutter_riverpod`. Fine in `application/`, never in `domain/`.
- Riverpod forbids touching `state` inside life-cycle callbacks (`ref.onDispose`): `ConstructionNotifier` keeps a `_construction` field mirroring `state.construction` for unsubscription. Keep the two in sync in `replace()`.
- `commandStackProvider` depends on the construction *instance* via `select` — NOT the revision — so undo history survives mutations but is dropped when `replace()` swaps constructions (undoing against a construction a command never touched would corrupt it). Don't "simplify" to a plain watch.
- `viewportProvider` stores state only; world↔screen transforms, zoom-about-focal-point, and scale clamping are deliberately left to Phase 5/8 gesture code. The presentation `Viewport` should be *built from* `ViewportState`, not duplicate it.
- Provider tests use plain `ProviderContainer()` + `addTearDown(dispose)`; no overrides were needed since providers wire to each other, not to injectables.

## Session 5 — 2026-06-12

**Done**
- Phase 3 complete on branch `phase-3-commands` (5 commits), merged to `main`. `lib/domain/commands/` holds: `Command` (abstract interface; LIFO-undo + replayable-apply contract documented), `AddObjectCommand`, `MoveFreePointCommand`, `DeleteObjectsCommand`, `TranslateObjectsCommand`, `ChangeAttributesCommand`, `MacroCommand`. `CommandStack` (plain class) lives in `lib/application/command_stack.dart`.
- New `Construction.setAttributes(id, attributes)` primitive so attribute edits notify listeners; covered in `construction_test.dart`.
- 139 tests green, `flutter analyze` clean.

**Next**
- Phase 4 (`lib/application/providers/`): `constructionProvider`, `selectionProvider`, `toolProvider`, `viewportProvider`, `commandStackProvider` — `@riverpod` code-gen (first riverpod_generator use; remember `dart run build_runner build --delete-conflicting-outputs`), bridging `Construction`'s listener API into a Notifier. Provider tests with overrides.

**Open questions / gotchas**
- Commands that capture state in `apply` (`DeleteObjectsCommand` batches, `TranslateObjectsCommand` before-positions, `ChangeAttributesCommand` previous values) are replay-safe: redo recaptures from the then-current construction. Don't share one command instance across two stacks.
- `DeleteObjectsCommand.undo` restores batches in *reverse* removal order — that's what makes cross-batch parent/child dependencies (select a parent and an unrelated root whose dependents interleave) restore validly. Don't "simplify" to forward order.
- `TranslateObjectsCommand` snapshots pre-move positions rather than applying `-delta`: float round-trip (`(x+d)-d ≠ x`) would break exact undo.
- `AddObjectCommand.undo` asserts (debug-only) that no dependents exist — out-of-order undo is a stack bug, not a user state.
- Commands validate up front (all-or-nothing): a bad id throws before anything mutates, so `CommandStack.execute` records nothing on failure.
- Mid-drag preview frames (direct `moveFreePoint` calls, no command) still notify listeners per frame — fine for repaint; Phase 5's gesture code must emit exactly one command per gesture on top of that.

## Session 4 — 2026-06-12

**Done**
- Phase 2 complete on branch `phase-2-construction-core` (3 commits), merged to `main`. `lib/domain/construction/` now holds: `ObjectAttributes` (freezed + json, first build_runner use — generated files are committed since CI doesn't run codegen), `GeoObject` base, the six minimal objects (`objects/` one file each), and the `Construction` DAG (insertion order = topological order; dependents lookup; cascade delete returning removed objects parents-first for restore; minimal pure-Dart listener API).
- 111 tests green, `flutter analyze` clean. Integration test: compass perpendicular-bisector construction (4-deep chain) tracks (A+B)/2 under dragging and survives degeneracy round-trips.

**Next**
- Phase 3 (`lib/domain/commands/`): `Command` interface, `AddObjectCommand`, `DeleteObjectsCommand` (holds `removeWithDependents` output), `MoveFreePointCommand`, `ChangeAttributesCommand`, `MacroCommand`; `CommandStack` lives in `application/` per PLAN.

**Open questions / gotchas**
- The hierarchy is sealed at the *kind* level (`GeoPoint`/`GeoLine`/`GeoCircle` in `geo_object.dart`), not on every concrete class — Dart's `sealed` requires same-library subtypes, which would conflict with one-file-per-object. Kind switches are exhaustive; concrete-type switches aren't.
- `Construction` is NOT a Flutter `ChangeNotifier` (domain layer can't import Flutter, contra PLAN's wording) — it has a hand-rolled `addListener`/`removeListener`. Phase 4 bridges it to Riverpod.
- `ObjectAttributes.colorArgb` is a raw ARGB int, null = theme default. Map to `Color` in presentation only.
- `IntersectionPoint` clamps its branch index at tangency (both branches sit on the single point) so branches separate cleanly again after a drag through tangency. Line∩circle branch identity is fixed by parent *type*, not argument order.
- Segments intersect via their infinite carrier line for now; clipping intersection points to segment extent is deferred (noted in `IntersectionPoint` doc).
- `Construction.restore` appends — z-order is not preserved across delete/undo. Revisit if/when z-order becomes user-visible.

## Session 3 — 2026-06-12

**Done**
- Phase 1 complete on branch `phase-1-math` (3 commits), merged to `main`. `lib/domain/math/` now holds: `Vec2` (+ shared `defaultEpsilon`), `LineEq` (normalized implicit form, unit normal → signed distance is one multiply-add), `CircleEq`, `intersections.dart` (line∩line/line∩circle/circle∩circle, all degenerate cases), `triangle_centers.dart` (centroid always defined; circumcenter/orthocenter/incenter return `null` on degenerate input).
- 74 tests green, `flutter analyze` clean. glados property tests use shared integer-grid generators in `test/domain/math/generators.dart` (no NaN, good shrinking) — reuse these.
- `test/domain/layer_rule_test.dart` enforces the no-Flutter-imports-in-domain invariant in CI from now on.

**Next**
- Phase 2 (`lib/domain/construction/`): sealed `GeoObject` + `ObjectAttributes` (freezed — first build_runner use), minimal object set (`FreePoint`, `Midpoint`, `LineThroughTwoPoints`, `Segment`, `CircleCenterPoint`, `IntersectionPoint`), then the `Construction` DAG with topological recompute.

**Open questions / gotchas**
- Two-point intersection results have a *documented deterministic order* (along line direction; first point left of the directed c1→c2 center line). Phase 2's `IntersectionPoint` must store its branch index against that contract.
- Triangle centers return `Vec2?` (null = degenerate). The construction layer needs an "undefined" object state to consume this — objects must survive a drag through a degeneracy and come back.
- Coincident lines/circles intersect in the empty list by design (no constructible point).
- Property tests gate out needle-thin triangles (`|cross| >= 1`) — the formulas are fine, the conditioning isn't; don't "fix" by loosening tolerances globally.

## Session 2 — 2026-06-11

**Done**
- Phase 0 complete on branch `phase-0-scaffolding` (3 commits): `flutter create . --empty` (web/android/ios, project name `fgex`), all runtime + dev deps pinned, strict `analysis_options.yaml`, GitHub Actions CI (`flutter analyze && flutter test --exclude-tags golden`), widget smoke test, committed `.claude/commands/continue-build.md`.
- CI gate verified locally: `flutter analyze` clean, `flutter test` green.

**Next**
- Merge `phase-0-scaffolding` to `main`, then start Phase 1 (`lib/domain/math/`): `Vec2`, `LineEq`/`CircleEq`, intersections, triangle centers, with unit + glados property tests.

**Open questions / gotchas**
- Riverpod codegen version dance: `riverpod_annotation` must stay at 4.0.2 (4.0.3 conflicts with `riverpod_generator` 4.0.3's analyzer bounds). Resolved set: `flutter_riverpod` 3.3.1 / annotation 4.0.2 / generator 4.0.3.
- `golden_toolkit` is discontinued (eBay archived it). Works today at 0.15.0; revisit before Phase 12 goldens — `alchemist` or plain `matchesGoldenFile` are candidate replacements.
- `flutter doctor`: Xcode installation incomplete, CocoaPods missing → iOS builds blocked until installed. Web + Android toolchains fully green; doesn't bite until the Phase 12 iOS smoke.
- Package name question from Session 1 settled: `fgex`.

## Session 1 — 2026-05-09

**Done**
- Brainstormed scope and architecture for the dynamic geometry app.
- Wrote `docs/PLAN.md` (architecture, layer separation, object catalog, persistence, test strategy, keyboard shortcuts, build order).
- Established the multi-session workflow: PLAN / STATUS / TODO / CLAUDE.md.
- Created `docs/TODO.md` (checklist mirroring the plan's build order) and `CLAUDE.md` (invariants + commands + session rituals).

**Next**
- Phase 0: install Flutter, initialise the project (`flutter create .` in the repo root), pin dependencies in `pubspec.yaml`, configure `analysis_options.yaml`, init git, set up CI placeholder.
- Then start Phase 1 (`lib/domain/math/`) — `Vec2`, line/circle types, intersections, triangle centers, plus their tests.

**Open questions / gotchas**
- Flutter is not yet installed on this machine. Install before next session (stable channel).
- Confirm package names: `flutter_riverpod` vs `riverpod_annotation` (we want code-gen providers via `@riverpod`).
- Decide repo name for `pubspec.yaml`'s `name` field — `fgex` or something more descriptive (e.g., `fgex_geometry`)?
- No git history yet — the next session should `git init` and make the first commit before any code is written.
