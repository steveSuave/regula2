import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/export/png_exporter.dart';
import 'application/object_ids.dart';
import 'application/persistence/file_io.dart';
import 'application/providers/command_stack_provider.dart';
import 'application/providers/construction_provider.dart';
import 'application/providers/document_settings_provider.dart';
import 'application/providers/preferences_provider.dart';
import 'application/providers/prover_provider.dart';
import 'application/providers/selection_provider.dart';
import 'application/providers/theme_provider.dart';
import 'application/providers/tool_provider.dart';
import 'application/providers/viewport_provider.dart';
import 'domain/commands/change_attributes_command.dart';
import 'domain/construction/construction.dart';
import 'domain/construction/geo_object.dart';
import 'domain/construction/objects/centroid.dart';
import 'domain/construction/objects/circumcenter.dart';
import 'domain/construction/objects/incenter.dart';
import 'domain/construction/objects/inscribed_circle.dart';
import 'domain/construction/objects/nine_point_circle.dart';
import 'domain/construction/objects/orthocenter.dart';
import 'domain/construction/objects/parallel_line.dart';
import 'domain/construction/objects/perpendicular_line.dart';
import 'domain/math/vec2.dart';
import 'domain/projective/tracing/trace_diagnostics.dart';
import 'domain/tools/angle_bisector_tool.dart';
import 'domain/tools/angle_by_size_tool.dart';
import 'domain/tools/angle_tool.dart';
import 'domain/tools/area_tool.dart';
import 'domain/tools/bifocal_conic_tool.dart';
import 'domain/tools/conic_tool.dart';
import 'domain/tools/delete_tool.dart';
import 'domain/tools/distance_tool.dart';
import 'domain/tools/equilateral_triangle_macro_tool.dart';
import 'domain/tools/fixed_length_segment_tool.dart';
import 'domain/tools/fixed_radius_circle_tool.dart';
import 'domain/tools/focal_conic_tool.dart';
import 'domain/tools/harmonic_conjugate_tool.dart';
import 'domain/tools/intersection_tool.dart';
import 'domain/tools/isosceles_trapezium_macro_tool.dart';
import 'domain/tools/isosceles_triangle_macro_tool.dart';
import 'domain/tools/kite_macro_tool.dart';
import 'domain/tools/locus_tool.dart';
import 'domain/tools/midpoint_tool.dart';
import 'domain/tools/name_points_tool.dart';
import 'domain/tools/parallelogram_macro_tool.dart';
import 'domain/tools/point_and_line_tool.dart';
import 'domain/tools/point_tool.dart';
import 'domain/tools/polar_line_tool.dart';
import 'domain/tools/polygon_tool.dart';
import 'domain/tools/radical_axis_tool.dart';
import 'domain/tools/random_shape_stamp_tool.dart';
import 'domain/tools/rectangle_macro_tool.dart';
import 'domain/tools/regular_polygon_macro_tool.dart';
import 'domain/tools/rhombus_macro_tool.dart';
import 'domain/tools/right_trapezium_macro_tool.dart';
import 'domain/tools/right_triangle_macro_tool.dart';
import 'domain/tools/slope_tool.dart';
import 'domain/tools/square_macro_tool.dart';
import 'domain/tools/tangent_tool.dart';
import 'domain/tools/text_tool.dart';
import 'domain/tools/three_point_tool.dart';
import 'domain/tools/transform_object_tool.dart';
import 'domain/tools/trapezium_macro_tool.dart';
import 'domain/tools/triangle_center_tool.dart';
import 'domain/tools/triangle_circle_tool.dart';
import 'domain/tools/two_point_tool.dart';
import 'domain/tools/visibility_tool.dart';
import 'presentation/canvas/canvas_viewport.dart';
import 'presentation/canvas/fit_viewport.dart';
import 'presentation/canvas/geometry_canvas.dart';
import 'presentation/canvas/label_declutter.dart';
import 'presentation/canvas/label_obstacles.dart';
import 'presentation/canvas/name_points_hint.dart';
import 'presentation/canvas/region_pick_overlay.dart';
import 'presentation/canvas/trace_stats_overlay.dart';
import 'presentation/canvas/twist_gate.dart';
import 'presentation/panels/attributes_inspector.dart';
import 'presentation/panels/delete_selection.dart';
import 'presentation/panels/export_dialog.dart';
import 'presentation/panels/geometry_menu.dart';
import 'presentation/panels/intersection_report.dart';
import 'presentation/panels/object_tree_panel.dart';
import 'presentation/panels/proof_panel.dart';
import 'presentation/panels/toolbar.dart';
import 'presentation/shortcuts/app_shortcuts.dart';
import 'presentation/shortcuts/cheat_sheet.dart';
import 'presentation/shortcuts/shortcut_table.dart';
import 'presentation/theme/app_theme.dart';

/// True on Android/iOS builds — the targets with OS chrome to hide and
/// notches to avoid. Web stays false even in a phone browser: the
/// browser owns its chrome.
bool get isMobileTarget =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _armTraceDiagnostics();
  if (isMobileTarget) {
    // Every canvas pixel counts on a phone: hide the OS status bar
    // (swipe from the edge peeks it back, then it re-hides).
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  // Loaded once here so settings providers can read stored values
  // synchronously (see preferences_provider.dart).
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const MainApp(),
    ),
  );
}

/// Points the tracing recorder at the console in debug and profile
/// builds (Phase 117c).
///
/// Armed rather than opt-in because the reports that matter are the ones
/// nobody thought to ask for: a frame slow enough to feel, or a frame
/// still running. Both stream out on their own, so reproducing a freeze
/// in `flutter run -d chrome` and copying the console is the whole
/// procedure. Quiet otherwise — an ordinary frame prints nothing.
///
/// Profile as well as debug, deliberately: on the web those two are
/// different compilers, not different flag sets — debug is DDC and
/// profile is optimized dart2js — so "is this the kernel or is this the
/// debug compiler?" is answered by running the same reproduction in
/// both and comparing these numbers. Instrumentation that only existed
/// in debug could not ask the question.
///
/// Release builds leave it disarmed.
void _armTraceDiagnostics() {
  if (kReleaseMode) {
    return;
  }
  TraceDiagnostics.sink = (String line) =>
      developer.log(line, name: 'regula.trace');
  TraceDiagnostics.enabled = true;
  if (kIsWeb && kDebugMode) {
    // Said once, up front, because it cost two sessions of hunting a
    // freeze that was not there. `flutter run -d chrome` compiles with
    // DDC, and on the kernel's complex arithmetic DDC measures ~25x
    // optimized dart2js (benchmark/run_locus_docs.sh, on the documents
    // that prompted this): a locus sweep that is 4 ms in a profile
    // build is 100-180 ms here, which presents as an app that crawls
    // and then wedges. Nothing about that is the engine.
    developer.log(
      'debug web build (DDC): kernel math runs ~25x slower than a '
      'profile build, so a heavy construction can crawl or appear to '
      'hang here and be fine in production. Judge performance with '
      '`flutter run -d chrome --profile`.',
      name: 'regula.trace',
    );
  }
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'regula',
      // The corner DEBUG banner costs canvas pixels on a phone and says
      // nothing the user can act on.
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const EditorScreen(),
    );
  }
}

/// Canvas plus the app chrome: object tree, file menu, the
/// [GeometryToolbar] flyout groups, viewport buttons, theme toggle and
/// undo/redo. Tool builders live in `presentation/panels/toolbar.dart`;
/// the keyboard switch below reuses them so shortcuts and menu items
/// activate identical tools.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  /// Object-tree visibility is ephemeral UI state (not undoable, not
  /// persisted), so it lives here rather than in a provider. Hidden by
  /// default: the tree is a secondary surface next to the canvas.
  bool _showObjectTree = false;

  /// Whether the `?` cheat-sheet overlay is up. Same ephemeral-UI
  /// reasoning as [_showObjectTree].
  bool _showCheatSheet = false;

  /// True while the export region-pick overlay owns the canvas. Ephemeral
  /// UI state like [_showCheatSheet]; while set, `_handleShortcut`
  /// swallows everything except Esc (which cancels back to the dialog).
  bool _pickingExportRegion = false;

  /// Whether the tracing debug overlay (Phase 116: per-drag-frame step
  /// counts) is up. Same ephemeral-UI reasoning as [_showObjectTree].
  bool _showTraceOverlay = false;

  /// Whether the style & properties panel is docked. Ephemeral UI state
  /// like [_showObjectTree], and hidden by default: it used to appear
  /// and disappear with the selection, which made a tap on the canvas
  /// resize the canvas.
  bool _showInspector = false;

  /// Whether the proof panel is docked (M-P4). Ephemeral UI state like
  /// [_showObjectTree], and hidden by default for the same reason: the
  /// prover is the on-demand path, and a panel that opened itself would
  /// be the always-on one.
  bool _showProofPanel = false;

  /// The last drag-selected export region (canvas screen coordinates) and
  /// the last-used export options — kept so the dialog reopens where the
  /// user left it, both after a region pick and across separate exports.
  Rect? _exportRegion;
  ExportOptions _exportOptions = const ExportOptions();

  /// Fit-to-viewport needs the canvas's laid-out size at tap time; the
  /// key reads it without threading sizes through providers.
  final GlobalKey _canvasKey = GlobalKey();

  /// Opens the compact-mode drawers from the overflow menu and the strip's
  /// style button — both live outside the Scaffold's own context.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// World origin at the canvas center, 100 % — where File > New puts the
  /// view. (The app still *launches* with the origin at the top-left; the
  /// canvas has no laid-out size before the first frame. Revisit with the
  /// Phase 11 shortcuts if it grates.)
  ViewportState _centeredViewport() {
    final size = _canvasKey.currentContext?.size;
    if (size == null) {
      return const ViewportState();
    }
    return CanvasViewport.pinning(
      world: Vec2.zero,
      focal: size.center(Offset.zero),
      scale: 1,
    );
  }

  Future<void> _newConstruction() async {
    final construction = ref.read(constructionProvider).construction;
    if (!construction.isEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New construction'),
          content: const Text(
            'Discard the current construction? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) {
        return;
      }
    }
    ref.read(constructionProvider.notifier).replace(Construction());
    ref.read(viewportProvider.notifier).set(_centeredViewport());
    ref.read(documentSettingsProvider.notifier).reset();
    // The prover's held engine is about the document that just went
    // away; without this the panel shows its facts marked stale, and
    // *Keep going* would extend a run about a construction that no
    // longer exists (Phase 156).
    ref.read(proverProvider.notifier).clear();
  }

  Future<void> _openConstruction() async {
    try {
      final decoded = await openConstructionFile();
      if (decoded == null) {
        return;
      }
      ref.read(constructionProvider.notifier).replace(decoded.construction);
      ref.read(viewportProvider.notifier).set(decoded.viewport);
      ref.read(documentSettingsProvider.notifier).set(decoded.settings);
      // Same as File > New: the held run is about the replaced document.
      ref.read(proverProvider.notifier).clear();
      // The reader may have moved intersection points the file had
      // stacked on one crossing, and may have found some it could not
      // move. Both are invisible on the canvas — a re-pointed crossing
      // looks exactly like the one the user tapped — so they are said
      // out loud, in the same place a geometry switch says its own
      // re-addressing (Phase 126e). The kernel needs no separate apply:
      // it rides on `decoded.construction`, which the codec built with
      // it, and reading `decoded.kernel` here would be a second source.
      final repair = decodeRepairMessage(
        decoded,
        // Named rather than counted (Phase 131): the unrepairable half is
        // a defect the user has to *act* on, and "2 points are stacked"
        // is not something anyone can act on.
        names: {
          for (final object in decoded.construction.objects)
            object.id: object.attributes.name,
        },
      );
      if (repair != null && mounted) {
        showIntersectionReport(context, repair);
      }
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Could not open file'),
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _saveConstruction() => saveConstructionFile(
    ref.read(constructionProvider).construction,
    viewport: ref.read(viewportProvider),
    settings: ref.read(documentSettingsProvider),
  );

  /// Export flow: options dialog → (optionally a region-pick round trip
  /// via [_onExportRegionPicked]) → off-screen render → platform save.
  /// Read-only view work throughout — no `Command`, nothing undoable.
  Future<void> _exportPng() async {
    final size = _canvasKey.currentContext?.size;
    if (size == null) {
      return;
    }
    final objects = ref.read(constructionProvider).construction.objects;
    final settings = ref.read(documentSettingsProvider);
    final outcome = await showExportDialog(
      context,
      canvasSize: size,
      canFit: visibleWorldBounds(objects) != null,
      region: _exportRegion,
      initial: _exportOptions,
      hasBackgroundLayer: settings.showAxes || settings.showGrid,
    );
    if (outcome == null || !mounted) {
      return;
    }
    _exportOptions = outcome.options;
    switch (outcome) {
      case ExportRegionPickRequested():
        setState(() => _pickingExportRegion = true);
      case ExportConfirmed(:final options):
        await _runExport(options, size);
    }
  }

  void _onExportRegionPicked(Rect region) {
    setState(() {
      _pickingExportRegion = false;
      _exportRegion = region;
      _exportOptions = _exportOptions.copyWith(
        framing: ExportFramingChoice.region,
      );
    });
    _exportPng();
  }

  Future<void> _runExport(ExportOptions options, Size canvasSize) async {
    final construction = ref.read(constructionProvider).construction;
    final viewportState = ref.read(viewportProvider);
    final framing = switch (options.framing) {
      // Fit can be stale-selected against a construction that just went
      // empty; falling back beats surprising the user with an error.
      ExportFramingChoice.fitConstruction =>
        fitConstructionFraming(construction.objects, canvasSize) ??
            currentViewFraming(viewportState, canvasSize),
      ExportFramingChoice.currentView => currentViewFraming(
        viewportState,
        canvasSize,
      ),
      ExportFramingChoice.region => regionFraming(
        viewportState,
        _exportRegion!,
      ),
    };
    final theme = Theme.of(context);
    // "As shown": the export renders the document's own toggles, gated
    // by the dialog's include checkbox.
    final settings = ref.read(documentSettingsProvider);
    final canvasColors = theme.extension<CanvasColors>();
    final bytes = await exportConstructionPng(
      construction,
      viewport: framing.viewport,
      logicalSize: framing.logicalSize,
      pixelRatio: options.scale.toDouble(),
      background: options.transparent ? null : theme.scaffoldBackgroundColor,
      defaultColor: theme.colorScheme.primary,
      showAxes: settings.showAxes && options.includeAxesGrid,
      showGrid: settings.showGrid && options.includeAxesGrid,
      axisColor: canvasColors?.axis ?? const Color(0xFF757575),
      gridColor: canvasColors?.grid ?? const Color(0xFFE3E6EA),
      absoluteColor: canvasColors?.absolute ?? const Color(0xFFB26A00),
      absoluteOutsideColor:
          canvasColors?.absoluteOutside ?? const Color(0x40B26A00),
    );
    await savePngBytes(bytes);
  }

  /// Frames the plane after a geometry switch (Phase 126).
  ///
  /// A hyperbolic document lives inside the unit circle, and the default
  /// scale is one pixel per world unit — so without this the whole plane
  /// is a two-pixel dot at the origin and the figure sits far outside it,
  /// which is where the mode looks like it does nothing. Euclidean and
  /// elliptic have no absolute to frame and leave the view alone: there
  /// is no privileged region in either, so moving the view would be
  /// arbitrary.
  void _frameAbsolute() {
    final size = _canvasKey.currentContext?.size;
    if (size == null) {
      return;
    }
    final framed = fittedToAbsolute(
      ref.read(constructionProvider).construction.kernel,
      size,
      rotation: ref.read(viewportProvider).rotation,
    );
    if (framed != null) {
      ref.read(viewportProvider.notifier).set(framed);
    }
  }

  void _fitConstruction() {
    final size = _canvasKey.currentContext?.size;
    if (size == null) {
      return;
    }
    final fitted = fittedViewport(
      ref.read(constructionProvider).construction.objects,
      size,
      // Fit frames, the compass levels (Phase 61): keep the view angle.
      rotation: ref.read(viewportProvider).rotation,
    );
    if (fitted != null) {
      ref.read(viewportProvider.notifier).set(fitted);
    }
  }

  /// One-shot declutter (Phase 55): move every overlapped label to the
  /// clearest nearby spot — one batch [ChangeAttributesCommand], so one
  /// undo restores every label. Clean and manually-placed labels stay
  /// put; nothing to move is a silent no-op (no undo-stack noise).
  /// Shows the recorded trace diagnostics (Phase 117c) — the report the
  /// engine has been accumulating since launch — in a selectable,
  /// copyable dialog, and mirrors it to the console.
  ///
  /// The dialog exists because the console is not always reachable: on
  /// a wedged tab DevTools may be the only thing still responding, and
  /// on a merely-slow one the user should not have to open it at all.
  Future<void> _dumpTraceDiagnostics() async {
    final report = TraceDiagnostics.report();
    developer.log(report, name: 'regula.trace');
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trace diagnostics'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              TraceDiagnostics.reset();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: report)),
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _declutterLabels() {
    final size = _canvasKey.currentContext?.size;
    if (size == null) {
      return;
    }
    final construction = ref.read(constructionProvider).construction;
    final viewport = CanvasViewport(ref.read(viewportProvider));
    final scene = buildDeclutterScene(construction, viewport, size);
    final moved = declutterLabels(
      labels: scene.labels,
      rects: scene.rects,
      capsules: scene.capsules,
      canvas: Offset.zero & size,
      maxOffset: GeometryCanvas.labelOffsetMaxPx,
    );
    if (moved.isEmpty) {
      return;
    }
    ref
        .read(commandStackProvider.notifier)
        .execute(
          ChangeAttributesCommand({
            for (final entry in moved.entries)
              entry.key: construction
                  .byId(entry.key)!
                  .attributes
                  .copyWith(labelDx: entry.value.dx, labelDy: entry.value.dy),
          }),
        );
  }

  /// Zoom step per key press; scroll zoom is continuous, keys are not.
  static const double _keyZoomFactor = 1.2;

  /// Screen pixels per arrow-key viewport nudge.
  static const double _nudgeStep = 32;

  Offset? get _canvasCenter =>
      _canvasKey.currentContext?.size?.center(Offset.zero);

  void _zoomAboutCenter(double factor) {
    final center = _canvasCenter;
    if (center == null) {
      return;
    }
    final viewport = CanvasViewport(ref.read(viewportProvider));
    ref
        .read(viewportProvider.notifier)
        .set(viewport.zoomedAbout(center, factor));
  }

  /// Back to 100 % keeping the world point at the canvas center fixed —
  /// unlike Reset, which also jumps the view back to the origin.
  void _zoomTo100() {
    final center = _canvasCenter;
    if (center == null) {
      return;
    }
    final viewport = CanvasViewport(ref.read(viewportProvider));
    ref
        .read(viewportProvider.notifier)
        .set(
          CanvasViewport.pinning(
            world: viewport.screenToWorld(center),
            focal: center,
            scale: 1,
            rotation: viewport.state.rotation,
          ),
        );
  }

  /// Arrow-key nudge with content semantics: pressing → moves the drawing
  /// right, matching the Phase 14 scroll mapping where every pan gesture
  /// moves content in the gesture's direction ([delta] is the *content*
  /// shift that [CanvasViewport.pannedByScreen] expects). Flipped from
  /// camera semantics in Session 21 — the trackpad pan made the old
  /// direction read as inverted.
  void _nudgeView(Offset delta) {
    final viewport = CanvasViewport(ref.read(viewportProvider));
    ref.read(viewportProvider.notifier).set(viewport.pannedByScreen(delta));
  }

  Future<void> _deleteSelectedObjects() {
    final construction = ref.read(constructionProvider).construction;
    final objects = [
      for (final id in ref.read(selectionProvider))
        if (construction.byId(id) case final GeoObject object) object,
    ];
    if (objects.isEmpty) {
      return Future.value();
    }
    return deleteSelectionWithConfirmation(context, ref, objects);
  }

  /// The hide/delete flyout's Delete item: activates the tap-driven
  /// [DeleteTool]. Activating with a selection deletes it first (same
  /// confirmation path as Del), then the tool stays active for
  /// tap-by-tap deleting — a cancelled dialog keeps delete mode, since
  /// that's what the press asked for. Activation goes first so a Phase
  /// 30b drag commit lands on the undo stack before the selection's
  /// delete. Leaving the mode follows the flyout precedent: double-click
  /// the group icon, Esc or `V`.
  void _activateDeleteTool() {
    ref.read(toolProvider.notifier).activate(const DeleteTool());
    _deleteSelectedObjects();
  }

  /// Hide (`H`): the current selection hides at once — one command,
  /// nothing on the stack when no selected object is visible — then the
  /// tool stays active for tap-by-tap hiding. The selection stays
  /// selected (Phase 7 precedent: the inspector/tree is the way back).
  /// Show/Hide (`Shift+H`) deliberately has no such on-activation
  /// action: toggling a mixed selection is ambiguous.
  void _activateHideTool() {
    ref.read(toolProvider.notifier).activate(VisibilityTool.hide());
    final construction = ref.read(constructionProvider).construction;
    final command = VisibilityTool.hideAll([
      for (final id in ref.read(selectionProvider))
        if (construction.byId(id) case final GeoObject object) object,
    ]);
    if (command != null) {
      ref.read(commandStackProvider.notifier).execute(command);
    }
  }

  /// Show/Hide (`Shift+H` and the hide/delete flyout): unlike Hide,
  /// deliberately no act-on-selection step — toggling a mixed selection
  /// is ambiguous.
  void _activateShowHideTool() {
    ref.read(toolProvider.notifier).activate(VisibilityTool.showHide());
  }

  Future<void> _activateSegmentRatioTool() async {
    final build = await askRatioBuilder(context);
    if (build == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(TwoPointTool(newId: newObjectId, build: build));
  }

  Future<void> _activateFocalConicTool() async {
    final eccentricity = await askEccentricity(context);
    if (eccentricity == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(
          FocalConicTool(newId: newObjectId, eccentricity: eccentricity),
        );
  }

  Future<void> _activateDilateTool() async {
    final ratio = await askDilationRatio(context);
    if (ratio == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(TransformObjectTool.dilate(newId: newObjectId, ratio: ratio));
  }

  Future<void> _activateRotateTool() async {
    final angle = await askRotationAngle(context);
    if (angle == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(TransformObjectTool.rotate(newId: newObjectId, angle: angle));
  }

  Future<void> _activateAngleBySizeTool() async {
    final angle = await askAngleSize(context);
    if (angle == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(AngleBySizeTool(newId: newObjectId, angle: angle));
  }

  Future<void> _activateNamePointsTool() async {
    final tool = await askNamePointsTool(context);
    if (tool == null) {
      return;
    }
    ref.read(toolProvider.notifier).activate(tool);
  }

  Future<void> _activateFixedRadiusCircleTool() async {
    final radius = await askCircleRadius(context);
    if (radius == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(FixedRadiusCircleTool(newId: newObjectId, radius: radius));
  }

  Future<void> _activateFixedLengthSegmentTool() async {
    final length = await askSegmentLength(context);
    if (length == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(FixedLengthSegmentTool(newId: newObjectId, length: length));
  }

  Future<void> _activateRegularPolygonTool() async {
    final sides = await askPolygonSideCount(context);
    if (sides == null) {
      return;
    }
    ref
        .read(toolProvider.notifier)
        .activate(
          RegularPolygonMacroTool(newId: newObjectId, sideCount: sides),
        );
  }

  /// The one undo entry point — the Ctrl/⌘ Z shortcut and the app-bar
  /// button both land here. Two-stage (Phase 59): pending tool input is
  /// consumed first; the stack pops only once the tool is idle.
  void _undo() {
    if (ref.read(toolProvider).tool?.hasPartialInput ?? false) {
      ref.read(toolProvider.notifier).resetInProgress();
    } else if (ref.read(commandStackProvider).canUndo) {
      ref.read(commandStackProvider.notifier).undo();
    }
  }

  /// The one exhaustive [AppAction] switch — a binding added to the
  /// table without behaviour here fails to compile.
  void _handleShortcut(AppAction action) {
    // The region-pick overlay owns the canvas: Esc cancels back to the
    // export dialog, every other shortcut is swallowed (activating a tool
    // or opening a file mid-pick would fight the overlay).
    if (_pickingExportRegion) {
      if (action == AppAction.cancelOrReturnToMoveSelect ||
          action == AppAction.returnToMoveSelect) {
        setState(() => _pickingExportRegion = false);
        _exportPng();
      }
      return;
    }
    // Any shortcut closes the cheat sheet. Esc *only* closes it — the
    // active tool survives, one Esc per surface — while a working
    // shortcut (it is a reference card, after all) also executes.
    if (_showCheatSheet && action != AppAction.toggleCheatSheet) {
      setState(() => _showCheatSheet = false);
      if (action == AppAction.cancelOrReturnToMoveSelect ||
          action == AppAction.returnToMoveSelect) {
        return;
      }
    }
    final tools = ref.read(toolProvider.notifier);
    // Two-stage cancel (Phase 59): while the active tool holds
    // partially-collected input, Esc and undo consume *that* first — the
    // tool stays active, the stack stays untouched — and only act at app
    // level on a second press. V stays a direct switch to move/select.
    final toolMidCollection =
        ref.read(toolProvider).tool?.hasPartialInput ?? false;
    switch (action) {
      case AppAction.cancelOrReturnToMoveSelect:
        if (toolMidCollection) {
          tools.resetInProgress();
        } else {
          tools.deactivate();
        }
      case AppAction.returnToMoveSelect:
        tools.deactivate();
      case AppAction.deleteSelection:
        _deleteSelectedObjects();
      case AppAction.undo:
        _undo();
      case AppAction.redo:
        if (ref.read(commandStackProvider).canRedo) {
          ref.read(commandStackProvider.notifier).redo();
        }
      case AppAction.selectAll:
        ref.read(selectionProvider.notifier).selectAll();
      case AppAction.saveFile:
        _saveConstruction();
      case AppAction.openFile:
        _openConstruction();
      case AppAction.newFile:
        _newConstruction();
      case AppAction.exportPng:
        _exportPng();
      case AppAction.toggleTheme:
        ref
            .read(themeModeProvider.notifier)
            .toggle(Theme.of(context).brightness);
      case AppAction.hideTool:
        _activateHideTool();
      case AppAction.showHideTool:
        _activateShowHideTool();
      case AppAction.toggleCheatSheet:
        setState(() => _showCheatSheet = !_showCheatSheet);
      case AppAction.zoomIn:
        _zoomAboutCenter(_keyZoomFactor);
      case AppAction.zoomOut:
        _zoomAboutCenter(1 / _keyZoomFactor);
      case AppAction.zoomTo100:
        _zoomTo100();
      case AppAction.fitView:
        _fitConstruction();
      case AppAction.declutterLabels:
        _declutterLabels();
      case AppAction.toggleAxes:
        ref.read(documentSettingsProvider.notifier).toggleAxes();
      case AppAction.toggleGrid:
        ref.read(documentSettingsProvider.notifier).toggleGrid();
      case AppAction.toggleSnapToGrid:
        ref.read(documentSettingsProvider.notifier).toggleSnapToGrid();
      case AppAction.toggleTraceOverlay:
        setState(() => _showTraceOverlay = !_showTraceOverlay);
      case AppAction.dumpTraceDiagnostics:
        _dumpTraceDiagnostics();
      case AppAction.nudgeLeft:
        _nudgeView(const Offset(-_nudgeStep, 0));
      case AppAction.nudgeRight:
        _nudgeView(const Offset(_nudgeStep, 0));
      case AppAction.nudgeUp:
        _nudgeView(const Offset(0, -_nudgeStep));
      case AppAction.nudgeDown:
        _nudgeView(const Offset(0, _nudgeStep));
      case AppAction.pointTool:
        tools.activate(PointTool(newId: newObjectId));
      case AppAction.lineTool:
        tools.activate(TwoPointTool(newId: newObjectId, build: buildLine));
      case AppAction.segmentTool:
        tools.activate(TwoPointTool(newId: newObjectId, build: buildSegment));
      case AppAction.rayTool:
        tools.activate(TwoPointTool(newId: newObjectId, build: buildRay));
      case AppAction.circleTool:
        tools.activate(TwoPointTool(newId: newObjectId, build: buildCircle));
      case AppAction.diameterCircleTool:
        tools.activate(
          TwoPointTool(newId: newObjectId, build: buildDiameterCircle),
        );
      case AppAction.midpointTool:
        tools.activate(MidpointTool(newId: newObjectId));
      case AppAction.intersectionTool:
        tools.activate(IntersectionTool(newId: newObjectId));
      case AppAction.angleBisectorTool:
        tools.activate(AngleBisectorTool(newId: newObjectId));
      case AppAction.angleTool:
        tools.activate(AngleTool(newId: newObjectId));
      case AppAction.perpendicularTool:
        tools.activate(
          PointAndLineTool(newId: newObjectId, build: PerpendicularLine.new),
        );
      case AppAction.parallelTool:
        tools.activate(
          PointAndLineTool(newId: newObjectId, build: ParallelLine.new),
        );
      case AppAction.perpendicularBisectorTool:
        tools.activate(
          TwoPointTool(newId: newObjectId, build: buildPerpendicularBisector),
        );
      case AppAction.projectionTool:
        tools.activate(
          PointAndLineTool(newId: newObjectId, build: buildProjectionPoint),
        );
      case AppAction.harmonicConjugateTool:
        tools.activate(HarmonicConjugateTool(newId: newObjectId));
      case AppAction.tangentTool:
        tools.activate(TangentTool(newId: newObjectId));
      case AppAction.polarLineTool:
        tools.activate(PolarLineTool(newId: newObjectId));
      case AppAction.radicalAxisTool:
        tools.activate(RadicalAxisTool(newId: newObjectId));
      case AppAction.fixedRadiusCircleTool:
        _activateFixedRadiusCircleTool();
      case AppAction.fixedLengthSegmentTool:
        _activateFixedLengthSegmentTool();
      case AppAction.distanceTool:
        tools.activate(DistanceTool(newId: newObjectId));
      case AppAction.areaTool:
        tools.activate(AreaTool(newId: newObjectId));
      case AppAction.slopeTool:
        tools.activate(SlopeTool(newId: newObjectId));
      case AppAction.locusTool:
        tools.activate(LocusTool(newId: newObjectId));
      case AppAction.compassTool:
        tools.activate(
          ThreePointTool(newId: newObjectId, build: buildCompassCircle),
        );
      case AppAction.centroidTool:
        tools.activate(
          TriangleCenterTool(newId: newObjectId, buildCenter: Centroid.new),
        );
      case AppAction.orthocenterTool:
        tools.activate(
          TriangleCenterTool(newId: newObjectId, buildCenter: Orthocenter.new),
        );
      case AppAction.incenterTool:
        tools.activate(
          TriangleCenterTool(newId: newObjectId, buildCenter: Incenter.new),
        );
      case AppAction.circumcenterTool:
        tools.activate(
          TriangleCenterTool(newId: newObjectId, buildCenter: Circumcenter.new),
        );
      case AppAction.threePointCircleTool:
        tools.activate(
          ThreePointTool(newId: newObjectId, build: buildThreePointCircle),
        );
      case AppAction.ninePointCircleTool:
        tools.activate(
          TriangleCircleTool(
            newId: newObjectId,
            buildCircle: NinePointCircle.new,
          ),
        );
      case AppAction.inscribedCircleTool:
        tools.activate(
          TriangleCircleTool(
            newId: newObjectId,
            buildCircle: InscribedCircle.new,
          ),
        );
      case AppAction.apolloniusCircleTool:
        tools.activate(
          ThreePointTool(newId: newObjectId, build: buildApolloniusCircle),
        );
      case AppAction.conicTool:
        tools.activate(ConicTool(newId: newObjectId));
      case AppAction.parabolaTool:
        tools.activate(FocalConicTool(newId: newObjectId));
      case AppAction.ellipseTool:
        tools.activate(BifocalConicTool(newId: newObjectId, difference: false));
      case AppAction.hyperbolaTool:
        tools.activate(BifocalConicTool(newId: newObjectId, difference: true));
      case AppAction.focalConicTool:
        _activateFocalConicTool();
      case AppAction.segmentRatioTool:
        _activateSegmentRatioTool();
      case AppAction.arcTool:
        tools.activate(ThreePointTool(newId: newObjectId, build: buildArc));
      case AppAction.sectorTool:
        tools.activate(ThreePointTool(newId: newObjectId, build: buildSector));
      case AppAction.reflectAboutLineTool:
        tools.activate(
          TransformObjectTool.reflectAboutLine(newId: newObjectId),
        );
      case AppAction.reflectAboutPointTool:
        tools.activate(
          TransformObjectTool.reflectAboutPoint(newId: newObjectId),
        );
      case AppAction.rotateAroundPointTool:
        _activateRotateTool();
      case AppAction.translateByVectorTool:
        tools.activate(TransformObjectTool.translate(newId: newObjectId));
      case AppAction.dilateTool:
        _activateDilateTool();
      case AppAction.angleBySizeTool:
        _activateAngleBySizeTool();
      case AppAction.namePointsTool:
        _activateNamePointsTool();
      case AppAction.textTool:
        tools.activate(TextTool(newId: newObjectId));
      case AppAction.polygonTool:
        tools.activate(PolygonTool(newId: newObjectId));
      case AppAction.squareMacroTool:
        tools.activate(SquareMacroTool(newId: newObjectId));
      case AppAction.parallelogramMacroTool:
        tools.activate(ParallelogramMacroTool(newId: newObjectId));
      case AppAction.trapeziumMacroTool:
        tools.activate(TrapeziumMacroTool(newId: newObjectId));
      case AppAction.rectangleMacroTool:
        tools.activate(RectangleMacroTool(newId: newObjectId));
      case AppAction.rhombusMacroTool:
        tools.activate(RhombusMacroTool(newId: newObjectId));
      case AppAction.kiteMacroTool:
        tools.activate(KiteMacroTool(newId: newObjectId));
      case AppAction.isoscelesTrapeziumMacroTool:
        tools.activate(IsoscelesTrapeziumMacroTool(newId: newObjectId));
      case AppAction.rightTrapeziumMacroTool:
        tools.activate(RightTrapeziumMacroTool(newId: newObjectId));
      case AppAction.equilateralTriangleMacroTool:
        tools.activate(EquilateralTriangleMacroTool(newId: newObjectId));
      case AppAction.isoscelesTriangleMacroTool:
        tools.activate(IsoscelesTriangleMacroTool(newId: newObjectId));
      case AppAction.rightTriangleMacroTool:
        tools.activate(RightTriangleMacroTool(newId: newObjectId));
      case AppAction.regularPolygonMacroTool:
        _activateRegularPolygonTool();
      case AppAction.randomTriangleStamp:
        tools.activate(
          RandomShapeStampTool(
            newId: newObjectId,
            minVertices: 3,
            maxVertices: 3,
          ),
        );
      case AppAction.randomQuadrilateralStamp:
        tools.activate(
          RandomShapeStampTool.convexQuadrilateral(newId: newObjectId),
        );
    }
  }

  /// Slim app-bar height for phones — visibly slimmer than the 56-px
  /// Material default while still fitting the standard 48-px icon-button
  /// touch targets. Canvas pixels matter most where the screen is
  /// smallest; the row's content is identical at every height.
  static const double _phoneBarHeight = 48;

  /// The proof sheet's three sizes, as fractions of the screen.
  ///
  /// Initial keeps the docked-panel intent — the figure stays visible
  /// and the proof is read alongside it. The minimum is a tuck rather
  /// than a dismissal: enough sheet left to grab and to read the header,
  /// so a reader can glance at the figure without losing the proof. The
  /// maximum stops short of the full screen so the scrim is still
  /// visible and tappable, which is how the sheet is closed.
  static const double _proofSheetInitial = 0.5;
  static const double _proofSheetMin = 0.25;
  static const double _proofSheetMax = 0.95;

  /// The app bar's one row — tree toggle, title, then the full action
  /// cluster through undo/redo. The same chrome shows at every window
  /// width (Phase 47, user feedback on the Phase 42 compact variant):
  /// when the row outgrows the window it scrolls horizontally in its
  /// entirety instead of re-arranging into a compact layout, so every
  /// affordance keeps one home. [IntrinsicWidth] over the min-width
  /// constraint sizes the row to max(content, bar), so the [Spacer]
  /// right-aligns the action cluster while it fits and is exactly
  /// zero-width once the row scrolls.
  Widget _appBarRow({
    required bool compactPanels,
    required bool hasSelection,
    required bool textLabelsActive,
    required bool hideDeleteActive,
    required UndoRedoState undoRedo,
    required bool toolMidCollection,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(
            child: Row(
              children: [
                // Always an explicit tree button (never Material's
                // auto-hamburger). What it opens follows the panel gate:
                // drawer under [compactPanels], docked-panel toggle
                // otherwise.
                if (compactPanels)
                  IconButton(
                    tooltip: 'Show object tree',
                    icon: const Icon(Icons.account_tree_outlined),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  )
                else
                  IconButton(
                    tooltip: _showObjectTree
                        ? 'Hide object tree'
                        : 'Show object tree',
                    isSelected: _showObjectTree,
                    icon: const Icon(Icons.account_tree_outlined),
                    onPressed: () =>
                        setState(() => _showObjectTree = !_showObjectTree),
                  ),
                // Styled by the AppBar's DefaultTextStyle (titleLarge).
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('regula'),
                ),
                const Spacer(),
                PopupMenuButton<Future<void> Function()>(
                  tooltip: 'File: new, open, save',
                  popUpAnimationStyle: AnimationStyle.noAnimation,
                  icon: const Icon(Icons.folder_outlined),
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _newConstruction,
                      child: const Text('New'),
                    ),
                    PopupMenuItem(
                      value: _openConstruction,
                      child: const Text('Open…'),
                    ),
                    PopupMenuItem(
                      value: _saveConstruction,
                      child: const Text('Save…'),
                    ),
                    PopupMenuItem(
                      value: _exportPng,
                      child: const Text('Export as PNG…'),
                    ),
                  ],
                ),
                const GeometryToolbar(),
                _textLabelsGroup(active: textLabelsActive),
                IconButton(
                  tooltip: 'Fit construction to view',
                  icon: const Icon(Icons.fit_screen),
                  onPressed: _fitConstruction,
                ),
                IconButton(
                  tooltip: 'Reset view (origin at 100 %)',
                  icon: const Icon(Icons.filter_center_focus),
                  onPressed: () => ref.read(viewportProvider.notifier).reset(),
                ),
                _gridMenu(),
                GeometryMenu(onFrameAbsolute: _frameAbsolute),
                // Beside the geometry menu (user request): both answer
                // questions *about* the document rather than editing it,
                // and the prover's vocabulary is Euclidean, so which
                // geometry is selected decides whether it can speak at
                // all. The panel follows the object tree's gate — docked
                // where there is room, a sheet where there is not, since
                // both drawers are already spoken for.
                IconButton(
                  tooltip: 'Proof',
                  isSelected: !compactPanels && _showProofPanel,
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: () => compactPanels
                      ? _openProofSheet()
                      : setState(() => _showProofPanel = !_showProofPanel),
                ),
                IconButton(
                  tooltip: 'Keyboard shortcuts (?)',
                  isSelected: _showCheatSheet,
                  icon: const Icon(Icons.keyboard_outlined),
                  onPressed: () =>
                      setState(() => _showCheatSheet = !_showCheatSheet),
                ),
                IconButton(
                  tooltip: Theme.of(context).brightness == Brightness.dark
                      ? 'Switch to light theme'
                      : 'Switch to dark theme',
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                  onPressed: () => ref
                      .read(themeModeProvider.notifier)
                      .toggle(Theme.of(context).brightness),
                ),
                _hideDeleteGroup(active: hideDeleteActive),
                // Between delete and undo (user request), which puts it
                // with the buttons that act on the selection rather than
                // with the view chrome.
                //
                // Style & properties is a panel the user opens, not one
                // the selection opens for them: selecting something is
                // not asking to restyle it, and a panel that appeared on
                // every tap moved the canvas under the pointer
                // mid-gesture. The button is always here, for the same
                // reason the object tree's is — a toolbar whose buttons
                // come and go is a toolbar you cannot aim at — and the
                // panel says what to do when nothing is picked.
                IconButton(
                  tooltip: _showInspector
                      ? 'Hide style & properties'
                      : 'Style & properties',
                  isSelected: !compactPanels && _showInspector,
                  icon: const Icon(Icons.palette_outlined),
                  onPressed: () => compactPanels
                      ? _scaffoldKey.currentState?.openEndDrawer()
                      : setState(() => _showInspector = !_showInspector),
                ),
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo),
                  // Enabled while a tool holds pending input even on an
                  // empty stack — the two-stage first press has work to do.
                  onPressed: undoRedo.canUndo || toolMidCollection
                      ? _undo
                      : null,
                ),
                IconButton(
                  tooltip: 'Redo',
                  icon: const Icon(Icons.redo),
                  onPressed: undoRedo.canRedo
                      ? () => ref.read(commandStackProvider.notifier).redo()
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The compass (Phase 43b, relocated to the canvas corner in Phase 60
  /// — the app-bar button was too easy to miss): a floating chip on the
  /// canvas's top-right, the map-app convention, mounted only while the
  /// view is rotated — it doubles as the "you are rotated" indicator,
  /// and clicking it levels the view about the canvas center, keeping
  /// pan and zoom (Reset/Fit both move the view; this is the way back
  /// to straight that doesn't). The needle turns with the content,
  /// pointing where world-up points on screen, over a live
  /// signed-degrees readout.
  ///
  /// Its own [Consumer] over a rotation select, so twist frames rebuild
  /// this one chip instead of the whole screen.
  Widget _compassChip() {
    return Positioned(
      top: 12,
      right: 12,
      child: Consumer(
        builder: (context, ref, _) {
          final rotation = ref.watch(
            viewportProvider.select((state) => state.rotation),
          );
          if (rotation == 0) {
            return const SizedBox.shrink();
          }
          final degrees = (normalizeAngle(rotation) * 180 / math.pi).round();
          final scheme = Theme.of(context).colorScheme;
          return Material(
            key: const ValueKey('compass-button'),
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            borderRadius: BorderRadius.circular(16),
            child: Tooltip(
              message: 'Straighten the view',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _levelView,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Screen angles are clockwise-positive; world-up on
                      // screen sits at −rotation from straight up.
                      Transform.rotate(
                        angle: -rotation,
                        child: Icon(
                          Icons.navigation_outlined,
                          size: 30,
                          color: scheme.primary,
                        ),
                      ),
                      Text(
                        '$degrees°',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Back to a level view: rotation to 0, the world point at the canvas
  /// center stays put, scale untouched.
  void _levelView() {
    final current = ref.read(viewportProvider);
    final center = _canvasCenter;
    ref
        .read(viewportProvider.notifier)
        .set(
          center == null
              ? ViewportState(pan: current.pan, scale: current.scale)
              : CanvasViewport.pinning(
                  world: CanvasViewport(current).screenToWorld(center),
                  focal: center,
                  scale: current.scale,
                ),
        );
  }

  /// Name-points and declutter as one text-and-labels flyout group (user
  /// request): both act on the drawing's text — one writes names, the
  /// other moves overlapped labels clear — and the group leaves room for
  /// the planned text and calculation tools. Built like
  /// [_hideDeleteGroup]: primary-tinted icon while the naming tool is
  /// active, rows with shortcut hints, double-click to deactivate.
  /// Declutter is a one-shot action, not a mode — its row fires
  /// immediately and never tints the icon.
  Widget _textLabelsGroup({required bool active}) {
    const idleTooltip =
        'Text & labels: text with calculations, name points, declutter';
    final button = PopupMenuButton<VoidCallback>(
      key: const ValueKey('text-labels-group'),
      tooltip: active ? '$idleTooltip — double-click to deselect' : idleTooltip,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: Icon(
        Icons.text_fields,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => ref
              .read(toolProvider.notifier)
              .activate(TextTool(newId: newObjectId)),
          child: ToolMenuRow(
            label: 'Text… (wrap calculations in {braces})',
            display: shortcutDisplayFor(AppAction.textTool),
          ),
        ),
        PopupMenuItem(
          value: _activateNamePointsTool,
          child: ToolMenuRow(
            label: 'Name points in sequence…',
            display: shortcutDisplayFor(AppAction.namePointsTool),
          ),
        ),
        PopupMenuItem(
          value: _declutterLabels,
          child: ToolMenuRow(
            label: 'Declutter labels (move overlapped labels clear)',
            display: shortcutDisplayFor(AppAction.declutterLabels),
          ),
        ),
      ],
    );
    if (!active) {
      return button;
    }
    // Same reasoning as _ToolGroup: the double-tap recognizer is mounted
    // only while active, so it delays the menu-opening tap only then.
    return GestureDetector(
      onDoubleTap: () => ref.read(toolProvider.notifier).deactivate(),
      child: button,
    );
  }

  /// Hide, Show/Hide and Delete as one flyout group, visually matching
  /// the [GeometryToolbar] groups: primary-tinted icon while one of its
  /// tools is active, rows with shortcut hints, double-click to
  /// deactivate. It lives here rather than in the toolbar because Hide
  /// and Delete act on the current selection at activation, which the
  /// toolbar's pure tool factories don't do.
  Widget _hideDeleteGroup({required bool active}) {
    const idleTooltip =
        'Hide & delete: tap objects to hide, reveal or '
        'delete them';
    final button = PopupMenuButton<VoidCallback>(
      key: const ValueKey('hide-delete-group'),
      tooltip: active ? '$idleTooltip — double-click to deselect' : idleTooltip,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: Icon(
        Icons.delete_outline,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _activateHideTool,
          child: ToolMenuRow(
            label: 'Hide objects',
            display: shortcutDisplayFor(AppAction.hideTool),
          ),
        ),
        PopupMenuItem(
          value: _activateShowHideTool,
          child: ToolMenuRow(
            label: 'Show or hide objects (hidden show dimmed)',
            display: shortcutDisplayFor(AppAction.showHideTool),
          ),
        ),
        PopupMenuItem(
          value: _activateDeleteTool,
          child: ToolMenuRow(
            label: 'Delete objects',
            display: shortcutDisplayFor(AppAction.deleteSelection),
          ),
        ),
      ],
    );
    if (!active) {
      return button;
    }
    // The toolbar's _ToolGroup reasoning: the double-tap recognizer is
    // mounted only while active, so it delays the menu-opening tap only
    // then.
    return GestureDetector(
      onDoubleTap: () => ref.read(toolProvider.notifier).deactivate(),
      child: button,
    );
  }

  /// The Phase 36 axes/grid popup: two checked items flipping the
  /// per-document `DocumentSettings` toggles — view chrome like the
  /// viewport buttons around it, not undoable, persisted per document.
  Widget _gridMenu() {
    final settings = ref.watch(documentSettingsProvider);
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Axes & grid',
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: const Icon(Icons.grid_4x4),
      onSelected: (action) => action(),
      // The rows show their shortcuts like the tool flyouts do (Phase 17
      // discoverability, extended here on user request) — the cheat
      // sheet must not be the only place the grid keys appear.
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          checked: settings.showAxes,
          value: () => ref.read(documentSettingsProvider.notifier).toggleAxes(),
          child: ToolMenuRow(
            label: 'Show axes',
            display: shortcutDisplayFor(AppAction.toggleAxes),
          ),
        ),
        CheckedPopupMenuItem(
          checked: settings.showGrid,
          value: () => ref.read(documentSettingsProvider.notifier).toggleGrid(),
          child: ToolMenuRow(
            label: 'Show grid',
            display: shortcutDisplayFor(AppAction.toggleGrid),
          ),
        ),
        CheckedPopupMenuItem(
          checked: settings.snapToGrid,
          value: () =>
              ref.read(documentSettingsProvider.notifier).toggleSnapToGrid(),
          child: ToolMenuRow(
            label: 'Snap to grid',
            display: shortcutDisplayFor(AppAction.toggleSnapToGrid),
          ),
        ),
      ],
    );
  }

  /// The proof panel where there is no room to dock it. A sheet rather
  /// than a third drawer: the drawers are the object tree and the
  /// inspector, and the panel is read alongside the figure, not instead
  /// of it — so it opens at half the height and leaves the canvas
  /// visible.
  ///
  /// Half is the *initial* size and not the ceiling (Phase 154). The
  /// original bare [FractionallySizedBox] was right about the first
  /// impression and wrong about the maximum: a proof of any length was
  /// unreadable in half a phone, and there was no gesture that said
  /// "now I want the proof, not the figure".
  ///
  /// The two gestures divide cleanly, which is why the drag handle
  /// stays: dragging the *content* resizes the sheet between
  /// [_proofSheetMin] and [_proofSheetMax], and the handle or the scrim
  /// dismisses it. `shouldCloseOnMinExtent: false` is what keeps those
  /// separate — dragging the list all the way down tucks the sheet away
  /// rather than closing a proof the reader was in the middle of.
  void _openProofSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Both required for a sheet taller than half: without it the route
      // constrains itself to half the screen and the maximum is
      // unreachable however the child is built.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: _proofSheetInitial,
        minChildSize: _proofSheetMin,
        maxChildSize: _proofSheetMax,
        shouldCloseOnMinExtent: false,
        builder: (context, controller) =>
            ProofPanel(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final undoRedo = ref.watch(commandStackProvider);
    // One gate (PLAN "Unified scrollable app bar"): the Material compact
    // breakpoint decides only where the panels live (drawers vs docked).
    // The app bar itself is the same at every width — too-narrow windows
    // scroll it horizontally instead of re-arranging it.
    final screen = MediaQuery.sizeOf(context);
    final compactPanels = screen.shortestSide < 600;
    // Watched only with drawer panels: the app bar's style button
    // appears with the selection (it opens the inspector drawer, which
    // never auto-opens); a docked inspector is already visible.
    final hasSelection =
        compactPanels && ref.watch(selectionProvider).isNotEmpty;
    // Narrow selects: tool taps bump the provider's revision every input,
    // and the scaffold must not rebuild per tap.
    final textLabelsActive = ref.watch(
      toolProvider.select(
        (state) => state.tool is NamePointsTool || state.tool is TextTool,
      ),
    );
    final hideDeleteActive = ref.watch(
      toolProvider.select(
        (state) => state.tool is DeleteTool || state.tool is VisibilityTool,
      ),
    );
    // Flips only when a tool arms/disarms, not per collected input, so
    // the scaffold still doesn't rebuild per tap.
    final toolMidCollection = ref.watch(
      toolProvider.select((state) => state.tool?.hasPartialInput ?? false),
    );
    final drawerWidth = math.min(
      AttributesInspector.panelWidth,
      MediaQuery.sizeOf(context).width * 0.85,
    );

    return AppShortcuts(
      onAction: _handleShortcut,
      child: Scaffold(
        key: _scaffoldKey,
        // Edge swipes belong to the canvas — a drag starting at the
        // screen edge is usually a draw, not a panel request. The drawers
        // open from the hamburger, the overflow menu and the style
        // button only.
        drawerEnableOpenDragGesture: false,
        endDrawerEnableOpenDragGesture: false,
        drawer: compactPanels
            ? Drawer(width: drawerWidth, child: const ObjectTreePanel())
            : null,
        endDrawer: compactPanels
            ? Drawer(width: drawerWidth, child: const AttributesInspector())
            : null,
        appBar: AppBar(
          // The whole bar is [_appBarRow] in the title slot; no leading
          // (a null leading with a drawer set would inject Material's
          // auto-hamburger — the row carries its own tree button).
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          // Same row everywhere, but slimmer on phones (user feedback):
          // the height rides the panel gate, not a chrome gate.
          toolbarHeight: compactPanels ? _phoneBarHeight : null,
          title: _appBarRow(
            compactPanels: compactPanels,
            hasSelection: hasSelection,
            textLabelsActive: textLabelsActive,
            hideDeleteActive: hideDeleteActive,
            undoRedo: undoRedo,
            toolMidCollection: toolMidCollection,
          ),
          // Non-empty actions suppress the end-drawer button Material
          // injects when `endDrawer` is set — the inspector drawer opens
          // from the row's style button only.
          actions: const [SizedBox.shrink()],
        ),
        body: SafeArea(
          // A no-op except on notched mobile devices, where the
          // immersive mode set in main() leaves the display cutout to
          // avoid.
          left: isMobileTarget,
          top: isMobileTarget,
          right: isMobileTarget,
          bottom: isMobileTarget,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compactPanels && _showObjectTree)
                    const ObjectTreePanel(),
                  Expanded(
                    // Clicking the canvas pulls focus back to the shortcut
                    // layer: a focused name field commits (focus-loss
                    // commit) and stops suppressing the single-letter
                    // shortcuts.
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => AppShortcuts.refocus(context),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GeometryCanvas(key: _canvasKey),
                          const NamePointsHint(),
                          if (_showTraceOverlay) const TraceStatsOverlay(),
                          // Before the region-pick overlay, so an export
                          // pick owns the whole surface.
                          _compassChip(),
                          // Sits on top of (and exactly over) the canvas,
                          // so its local coordinates are canvas
                          // coordinates; opaque, so the canvas can't
                          // react to the pick drag.
                          if (_pickingExportRegion)
                            RegionPickOverlay(
                              onSelected: _onExportRegionPicked,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!compactPanels && _showProofPanel)
                    const SizedBox(
                      width: ProofPanel.panelWidth,
                      child: ProofPanel(),
                    ),
                  if (!compactPanels && _showInspector)
                    const AttributesInspector(),
                ],
              ),
              if (_showCheatSheet)
                ShortcutCheatSheet(
                  onDismiss: () => setState(() => _showCheatSheet = false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
