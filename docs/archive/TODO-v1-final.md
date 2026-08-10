# Build TODO

Live checklist for the build phases described in `docs/PLAN.md`. Tick items as they land on `main` with `flutter analyze` clean and `flutter test` green.

Definition of done for each phase: code merged, tests passing, `docs/TODO.md` updated, `docs/STATUS.md` entry written.

Rotation: this file holds open phases plus the most recent couple of completed ones. Fully-completed phase checklists move to `docs/archive/TODO-completed-phases.md` — move a phase there once it's merged and a newer phase has landed after it.

## Phase 12 — Tests & polish
- [x] Widget tests for representative tool flows (audit found 15 sessions of per-phase coverage already dense — creation flows, undo units, selection, drags, pan/zoom, file menu, every shortcut path; the one missing PLAN scenario landed: a circumcircle recomputing live under a real vertex-drag gesture, restored by undo)
- [x] Golden tests (light + dark) for each object kind (Session 2 decision resolved: discontinued `golden_toolkit` dropped for plain `matchesGoldenFile` — five scenes ×2 themes framed by `fittedViewport`, tagged `golden` via new `dart_test.yaml`; CI's `--exclude-tags golden` still skips them, regenerate with `flutter test --update-goldens --tags golden`)
- [x] Save/load round-trip on a non-trivial construction (already covered since Phase 9: the codec kitchen-sink test round-trips every concrete kind + attributes + viewport, `file_menu_test` drives Save/Open at the widget level, and the browser smoke parses a real downloaded document — no new work needed)
- [ ] Manual cross-platform smoke (`flutter run -d chrome`, Android emulator, iOS simulator) (web done — full `tool/web_smoke/drive.js` suite SMOKE PASS on a release build, zero console errors; Android emulator needs an AVD first, and no system image is installed — a multi-GB `sdkmanager` download to approve; iOS simulator blocked on the incomplete Xcode install)
- [ ] `flutter build apk` and `flutter build ios` succeed (`flutter build apk` ✓ — 49.5 MB release APK; `flutter build ios` still blocked: Xcode incomplete + CocoaPods missing since Session 2 — needs an App Store install and `sudo xcode-select --switch`, then `sudo xcodebuild -runFirstLaunch`)

## Phase 19 — Export
- [x] Off-screen PNG renderer in `lib/application/export/` (`PictureRecorder` + `GeometryPainter`; framing: fit construction / current viewport / drag-selected region; scale factor 1×/2×/4×; theme-color vs transparent background; no UI chrome — selection halos, in-progress markers, band never render) (landed as `png_exporter.dart`: `renderConstructionImage` + `encodePng` + `exportConstructionPng`, framings as a `({viewport, logicalSize})` record; the canvas `scale(pixelRatio)` upscales strokes/labels like a Hi-DPI screen would)
- [x] Export options dialog: framing choice, scale, background, and the **exact output size in pixels** shown live ("Output: 1920 × 1080 px"); File-menu "Export as PNG…" entry (wide File popup + compact overflow) + `Ctrl/Cmd + E` shortcut + cheat-sheet row (export is read-only view work: no `Command`, not undoable, no save-format change) (framing radios are plain `ListTile`s + icon pairs — Flutter's radio tiles are mid-migration to `RadioGroup`; options persist across dialog round trips in `EditorScreen` state; a stale fit/region initial framing sanitizes to current view)
- [x] Region picking: one-shot marquee overlay stacked on the canvas (canvas widget untouched); drag → rect in canvas screen coords → dialog reopens with region framing; Esc cancels; region viewport = same scale, pan at the rect's top-left corner (`RegionPickOverlay` anchors at `onPanDown` — `onPanStart` would shave the ~18 px slop off the corner; scrim with a cutout previews the crop; sub-8-px drags keep the overlay armed; all *other* shortcuts are swallowed mid-pick)
- [x] Delivery via a `savePngBytes` sibling in `file_io.dart`; verified on web via the widget-test picker fake + the smoke's existing Save… download path (same `FilePicker.saveFile` route) — Android native-picker check rides the Phase 12 emulator blocker
- [x] Tests: pixel check on the rendered image for a known scene (dimensions × scale, transparent vs opaque background, object pixels present, region crop correct); widget test for the menu → dialog → save flow and the region-pick round trip (13 exporter tests + 7 flow widget tests, incl. PNG IHDR dimension parsing and Esc-cancel; 771 green, analyze clean, web smoke SMOKE PASS on a fresh release build)
- [ ] Stretch: hand-written SVG writer mirroring the painter per kind (`dashPeriod` → `stroke-dasharray`, labels as `<text>`) + "Export as SVG…" entry — may slip; PDF and clipboard-copy stay out of scope

## Phase 72 — Configurable measurement rounding (user request)
- [x] `docs/PLAN.md` updated first: build-order item 55, `valueDecimals` on the attributes line, Phase 72 notes on the measure-format and inspector sections
- [x] `ObjectAttributes.valueDecimals` (`int?`, default null = kind default: 2 for lengths/areas, 1 for angles — the pre-72 fixed counts; additive with a default, no save-format version bump)
- [x] `measure_format.dart`: `formatLength`/`formatAngle`/`formatArea` take `{int? decimals}` falling back to new `defaultLengthDecimals`/`defaultAngleDecimals` constants; `labelText` passes the object's `valueDecimals`
- [x] Inspector: Decimals preset row `0`–`5` (`_PresetSelector`) over value-carrying kinds (segments, angles, measurements, expression texts with slots), placed under Show value; values shown as each object's *effective* count so fresh lengths highlight 2 and fresh angles 1
- [x] Text `{…}` slots (follow-up user request): `formatComputedValue`/`TextTemplate.render` take `{int? decimals}` (null = 2; negative-zero guard generalized to every count), `ExpressionText.recompute` passes `attributes.valueDecimals`, `Construction.setAttributes` re-renders texts (the one carve-out from "attributes never recompute" — parents untouched, texts have no dependents), `ExpressionText.hasExpressions` gates the inspector row off literal-only texts
- [x] Tests: formatter decimals overrides (presentation + domain), `labelText` end-to-end (segment 4dp, angle 0dp, measurement 1dp), text render + setAttributes re-render + `hasExpressions`, attributes default + JSON round-trip — analyze clean, 1597 green

## Phase 73 — Slope measurement of a line (user request)
- [x] `docs/PLAN.md` updated first: Phase 73 sentence in the Measurements bullet + build-order item 56
- [x] `SlopeMeasurement` (`GeoMeasurement`; one `GeoLine` subject, constructor kind-guard on the `AreaMeasurement` model); value = carrier `direction.y / direction.x`, undefined for vertical lines or while the subject is; anchor from `parameterExtent` (segment midpoint, ray origin, `pointOnLine` for infinite carriers)
- [x] `SlopeTool`: stateless one-tap on the `AreaTool` model — topmost `GeoLine` from `hits`, else ignored
- [x] Registration: codec (+ kitchen-sink round-trip + ill-typed-subject `FormatException`), `object_kind_label.dart` ('Slope'), Measure flyout row 4 + tooltip + `measureActive`, `AppAction.slopeTool` + `⇧ M` shortcut row, `main.dart` switch
- [x] Tests: object recompute/undefined units (incl. vertical line, ray/segment anchors), tool funnel (commit, reusable, extraHits, ignored), toolbar row + highlight, `⇧ M` end-to-end — analyze clean, suite green (1613 tests)
