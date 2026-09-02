import 'package:flutter/services.dart';

/// Everything a keyboard shortcut can do, by semantic name. The editor
/// screen maps each action to behaviour in one exhaustive switch, so a
/// binding added here without wiring fails to compile rather than
/// silently doing nothing.
enum AppAction {
  // Selection / app level.
  // Esc: two-stage — consumes the active tool's pending input first,
  // returns to move/select only once the tool is idle. V is the direct
  // switch ([returnToMoveSelect]) regardless of pending input.
  cancelOrReturnToMoveSelect,
  returnToMoveSelect,
  deleteSelection,
  undo,
  redo,
  selectAll,
  saveFile,
  openFile,
  newFile,
  exportPng,
  toggleTheme,
  hideTool,
  showHideTool,
  toggleCheatSheet,
  // Viewport.
  zoomIn,
  zoomOut,
  zoomTo100,
  fitView,
  declutterLabels,
  toggleAxes,
  toggleGrid,
  toggleSnapToGrid,
  toggleTraceOverlay,
  dumpTraceDiagnostics,
  nudgeLeft,
  nudgeRight,
  nudgeUp,
  nudgeDown,
  // Tools (single letter).
  pointTool,
  lineTool,
  segmentTool,
  rayTool,
  circleTool,
  midpointTool,
  intersectionTool,
  angleBisectorTool,
  angleTool,
  perpendicularTool,
  parallelTool,
  perpendicularBisectorTool,
  compassTool,
  fixedRadiusCircleTool,
  fixedLengthSegmentTool,
  fixedAngleLineTool,
  statedRadiusCircleTool,
  scaledCompassCircleTool,
  ratioApolloniusCircleTool,
  distanceTool,
  areaTool,
  slopeTool,
  locusTool,
  // Constructions behind the G leader.
  centroidTool,
  orthocenterTool,
  incenterTool,
  circumcenterTool,
  diameterCircleTool,
  threePointCircleTool,
  ninePointCircleTool,
  inscribedCircleTool,
  apolloniusCircleTool,
  conicTool,
  parabolaTool,
  ellipseTool,
  hyperbolaTool,
  focalConicTool,
  segmentRatioTool,
  projectionTool,
  harmonicConjugateTool,
  arcTool,
  sectorTool,
  tangentTool,
  polarLineTool,
  radicalAxisTool,
  reflectAboutLineTool,
  reflectAboutPointTool,
  rotateAroundPointTool,
  translateByVectorTool,
  dilateTool,
  angleBySizeTool,
  namePointsTool,
  textTool,
  // Shape macros behind the X leader.
  polygonTool,
  squareMacroTool,
  parallelogramMacroTool,
  trapeziumMacroTool,
  rectangleMacroTool,
  rhombusMacroTool,
  kiteMacroTool,
  isoscelesTrapeziumMacroTool,
  rightTrapeziumMacroTool,
  equilateralTriangleMacroTool,
  isoscelesTriangleMacroTool,
  rightTriangleMacroTool,
  regularPolygonMacroTool,
  randomTriangleStamp,
  randomQuadrilateralStamp,
}

/// Cheat-sheet grouping, mirroring the PLAN's shortcut tables.
enum ShortcutSection {
  appLevel('Selection & app'),
  viewport('Viewport'),
  tools('Tools'),
  constructions('Constructions (G, then…)'),
  macros('Shape macros (X, then…)'),
  textCalc('Text calculations (G E, then {…})');

  const ShortcutSection(this.title);

  final String title;
}

/// One key press with its required modifier state.
///
/// [shift] is three-valued: `true` requires Shift, `false` forbids it
/// (so `H` and `Shift+H` are distinct bindings), and `null` accepts
/// either — for keys like `=`/`+` where the shifted and unshifted
/// characters should behave the same.
///
/// [primary] models the PLAN's "Ctrl/Cmd": `true` matches when either
/// Control or Meta is down, `false` requires both up. Alt is always
/// required to be up — no binding uses it, and an Alt-modified letter
/// types special characters on macOS.
class KeyStroke {
  const KeyStroke(this.key, {this.shift = false, this.primary = false});

  final LogicalKeyboardKey key;
  final bool? shift;
  final bool primary;

  bool matches(
    LogicalKeyboardKey pressed, {
    required bool shiftDown,
    required bool controlDown,
    required bool metaDown,
    required bool altDown,
  }) {
    if (pressed != key || altDown) {
      return false;
    }
    if (shift != null && shift != shiftDown) {
      return false;
    }
    return primary == (controlDown || metaDown);
  }
}

/// One row of the shortcut table: a one- or two-stroke [sequence]
/// triggering [action]. Two-stroke sequences are leader chords — the
/// first stroke is consumed and the resolver waits for the second.
///
/// [repeats] lets a held key auto-repeat the action (viewport nudge and
/// zoom); everything else fires once per physical press.
///
/// [showInCheatSheet] hides redundant alternates (numpad twins,
/// `Backspace` next to `Delete`) from the overlay while keeping them
/// live; [display] is the human-readable key text the cheat sheet and
/// tooltips render.
class ShortcutBinding {
  const ShortcutBinding({
    required this.sequence,
    required this.action,
    required this.label,
    required this.section,
    required this.display,
    this.repeats = false,
    this.showInCheatSheet = true,
  });

  /// One stroke, or two for a leader chord — enforced by the table test
  /// (a const constructor can't assert on a list's length).

  final List<KeyStroke> sequence;
  final AppAction action;
  final String label;
  final ShortcutSection section;
  final String display;
  final bool repeats;
  final bool showInCheatSheet;
}

/// A `G`-leader chord (constructions). [shift] shifts the *second*
/// stroke (`G ⇧ I` vs `G I`).
ShortcutBinding _g(
  LogicalKeyboardKey second,
  AppAction action,
  String label,
  String display, {
  bool shift = false,
}) => ShortcutBinding(
  sequence: [
    const KeyStroke(LogicalKeyboardKey.keyG),
    KeyStroke(second, shift: shift),
  ],
  action: action,
  label: label,
  section: ShortcutSection.constructions,
  display: display,
);

/// An `X`-leader chord (shape macros). [shift] shifts the *second*
/// stroke (`X ⇧ I` vs `X I`).
ShortcutBinding _x(
  LogicalKeyboardKey second,
  AppAction action,
  String label,
  String display, {
  bool shift = false,
}) => ShortcutBinding(
  sequence: [
    const KeyStroke(LogicalKeyboardKey.keyX),
    KeyStroke(second, shift: shift),
  ],
  action: action,
  label: label,
  section: ShortcutSection.macros,
  display: display,
);

/// The binding table — the single source of truth for every keyboard
/// shortcut (PLAN "Keyboard shortcuts"). The cheat-sheet overlay renders
/// it; the resolver matches against it; `shortcut_table_test.dart`
/// rejects ambiguous entries.
///
/// Deliberately absent, per PLAN: `Tab` object cycling (needs cursor
/// tracking; Tab traverses focus meanwhile). `Space`+drag panning lives
/// in the canvas's gesture code, not here — it is a modifier for a
/// pointer gesture, not a key action; the cheat sheet lists it (and the
/// other pointer gestures) via the display-only [gestureRows].
final List<ShortcutBinding> shortcutTable = [
  // ── Selection / app level ────────────────────────────────────────
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.escape)],
    action: AppAction.cancelOrReturnToMoveSelect,
    label: 'Cancel pending input, then back to move/select',
    section: ShortcutSection.appLevel,
    display: 'Esc',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyV)],
    action: AppAction.returnToMoveSelect,
    label: 'Move/select tool (deactivates the active tool)',
    section: ShortcutSection.appLevel,
    display: 'V',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.delete)],
    action: AppAction.deleteSelection,
    label: 'Delete selection (cascades to dependents)',
    section: ShortcutSection.appLevel,
    display: 'Del / ⌫',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.backspace)],
    action: AppAction.deleteSelection,
    label: 'Delete selection',
    section: ShortcutSection.appLevel,
    display: '⌫',
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyZ, primary: true)],
    action: AppAction.undo,
    label: 'Undo',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ Z',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyZ, primary: true, shift: true)],
    action: AppAction.redo,
    label: 'Redo',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ ⇧ Z',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyY, primary: true)],
    action: AppAction.redo,
    label: 'Redo',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ Y',
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyA, primary: true)],
    action: AppAction.selectAll,
    label: 'Select all',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ A',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyS, primary: true)],
    action: AppAction.saveFile,
    label: 'Save construction',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ S',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyO, primary: true)],
    action: AppAction.openFile,
    label: 'Open construction',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ O',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyN, primary: true)],
    action: AppAction.newFile,
    label: 'New construction',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ N',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyE, primary: true)],
    action: AppAction.exportPng,
    label: 'Export as PNG…',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ E',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyD, primary: true)],
    action: AppAction.toggleTheme,
    label: 'Toggle dark mode',
    section: ShortcutSection.appLevel,
    display: 'Ctrl/⌘ D',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyH)],
    action: AppAction.hideTool,
    label: 'Hide tool — tap objects to hide them',
    section: ShortcutSection.appLevel,
    display: 'H',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyH, shift: true)],
    action: AppAction.showHideTool,
    label: 'Show/Hide tool — hidden objects dimmed, tap toggles',
    section: ShortcutSection.appLevel,
    display: '⇧ H',
  ),
  const ShortcutBinding(
    // Shifted `/` arrives as `?` on some platforms and as shifted slash
    // on others; the twin binding below catches the latter.
    sequence: [KeyStroke(LogicalKeyboardKey.question, shift: null)],
    action: AppAction.toggleCheatSheet,
    label: 'Keyboard shortcut cheat sheet',
    section: ShortcutSection.appLevel,
    display: '?',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.slash, shift: true)],
    action: AppAction.toggleCheatSheet,
    label: 'Keyboard shortcut cheat sheet',
    section: ShortcutSection.appLevel,
    display: '?',
    showInCheatSheet: false,
  ),
  // ── Viewport ─────────────────────────────────────────────────────
  const ShortcutBinding(
    // `=` and its shifted `+` both zoom in, so a bare press works on
    // every layout without hunting for the plus.
    sequence: [KeyStroke(LogicalKeyboardKey.equal, shift: null)],
    action: AppAction.zoomIn,
    label: 'Zoom in',
    section: ShortcutSection.viewport,
    display: '+ / =',
    repeats: true,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.add, shift: null)],
    action: AppAction.zoomIn,
    label: 'Zoom in',
    section: ShortcutSection.viewport,
    display: '+',
    repeats: true,
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.numpadAdd)],
    action: AppAction.zoomIn,
    label: 'Zoom in',
    section: ShortcutSection.viewport,
    display: 'Numpad +',
    repeats: true,
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.minus)],
    action: AppAction.zoomOut,
    label: 'Zoom out',
    section: ShortcutSection.viewport,
    display: '−',
    repeats: true,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.numpadSubtract)],
    action: AppAction.zoomOut,
    label: 'Zoom out',
    section: ShortcutSection.viewport,
    display: 'Numpad −',
    repeats: true,
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.digit0)],
    action: AppAction.zoomTo100,
    label: 'Zoom to 100 %',
    section: ShortcutSection.viewport,
    display: '0',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyF)],
    action: AppAction.fitView,
    label: 'Fit construction to view',
    section: ShortcutSection.viewport,
    display: 'F',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyF, shift: true)],
    action: AppAction.declutterLabels,
    label: 'Declutter labels — move overlapped labels clear',
    section: ShortcutSection.viewport,
    display: '⇧ F',
  ),
  // Shifted single strokes, so the bare G/X leaders stay chord-only:
  // single-stroke bindings resolve before leaders, and the leaders'
  // first strokes forbid Shift anyway (pinned by a resolver test).
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyX, shift: true)],
    action: AppAction.toggleAxes,
    label: 'Show/hide axes',
    section: ShortcutSection.viewport,
    display: '⇧ X',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyG, shift: true)],
    action: AppAction.toggleGrid,
    label: 'Show/hide grid',
    section: ShortcutSection.viewport,
    display: '⇧ G',
  ),
  const ShortcutBinding(
    // Next to ⇧G (grid) in the same key family: primary escalates the
    // grid toggle to its snapping cousin.
    sequence: [KeyStroke(LogicalKeyboardKey.keyG, shift: true, primary: true)],
    action: AppAction.toggleSnapToGrid,
    label: 'Snap to grid on/off',
    section: ShortcutSection.viewport,
    display: 'Ctrl/⌘ ⇧ G',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyO, shift: true)],
    action: AppAction.toggleTraceOverlay,
    label: 'Show/hide trace overlay (drag-tracing step counts)',
    section: ShortcutSection.viewport,
    display: '⇧ O',
  ),
  const ShortcutBinding(
    // Next to ⇧O (the overlay) in the same key family: primary
    // escalates "show me the last frame" to "show me every frame".
    sequence: [KeyStroke(LogicalKeyboardKey.keyO, shift: true, primary: true)],
    action: AppAction.dumpTraceDiagnostics,
    label: 'Trace diagnostics report (copyable)',
    section: ShortcutSection.viewport,
    display: 'Ctrl/⌘ ⇧ O',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.arrowLeft)],
    action: AppAction.nudgeLeft,
    label: 'Nudge view',
    section: ShortcutSection.viewport,
    display: '← ↑ ↓ →',
    repeats: true,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.arrowRight)],
    action: AppAction.nudgeRight,
    label: 'Nudge view',
    section: ShortcutSection.viewport,
    display: '→',
    repeats: true,
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.arrowUp)],
    action: AppAction.nudgeUp,
    label: 'Nudge view',
    section: ShortcutSection.viewport,
    display: '↑',
    repeats: true,
    showInCheatSheet: false,
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.arrowDown)],
    action: AppAction.nudgeDown,
    label: 'Nudge view',
    section: ShortcutSection.viewport,
    display: '↓',
    repeats: true,
    showInCheatSheet: false,
  ),
  // ── Tools ────────────────────────────────────────────────────────
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyP)],
    action: AppAction.pointTool,
    label: 'Point',
    section: ShortcutSection.tools,
    display: 'P',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyL)],
    action: AppAction.lineTool,
    label: 'Line through two points',
    section: ShortcutSection.tools,
    display: 'L',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyS)],
    action: AppAction.segmentTool,
    label: 'Segment',
    section: ShortcutSection.tools,
    display: 'S',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyR)],
    action: AppAction.rayTool,
    label: 'Ray',
    section: ShortcutSection.tools,
    display: 'R',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyC)],
    action: AppAction.circleTool,
    label: 'Circle (center, then rim)',
    section: ShortcutSection.tools,
    display: 'C',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyM)],
    action: AppAction.midpointTool,
    label: 'Midpoint or center',
    section: ShortcutSection.tools,
    display: 'M',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyI)],
    action: AppAction.intersectionTool,
    label: 'Intersection of two curves',
    section: ShortcutSection.tools,
    display: 'I',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyB)],
    action: AppAction.angleBisectorTool,
    label: 'Angle bisector',
    section: ShortcutSection.tools,
    display: 'B',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyA)],
    action: AppAction.angleTool,
    label: 'Angle (arm/vertex/arm, or two lines)',
    section: ShortcutSection.tools,
    display: 'A',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyT)],
    action: AppAction.perpendicularTool,
    label: 'Perpendicular line',
    section: ShortcutSection.tools,
    display: 'T',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyT, shift: true)],
    action: AppAction.parallelTool,
    label: 'Parallel line',
    section: ShortcutSection.tools,
    display: '⇧ T',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyB, shift: true)],
    action: AppAction.perpendicularBisectorTool,
    label: 'Perpendicular bisector',
    section: ShortcutSection.tools,
    display: '⇧ B',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyC, shift: true)],
    action: AppAction.fixedRadiusCircleTool,
    label: 'Circle by radius…',
    section: ShortcutSection.tools,
    display: '⇧ C',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyS, shift: true)],
    action: AppAction.fixedLengthSegmentTool,
    label: 'Segment with given length…',
    section: ShortcutSection.tools,
    display: '⇧ S',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyO)],
    action: AppAction.compassTool,
    label: 'Compass circle',
    section: ShortcutSection.tools,
    display: 'O',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyD)],
    action: AppAction.distanceTool,
    label: 'Distance (two points, or tap a circle / arc)',
    section: ShortcutSection.tools,
    display: 'D',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyD, shift: true)],
    action: AppAction.areaTool,
    label: 'Area (tap a polygon, circle, sector or arc)',
    section: ShortcutSection.tools,
    display: '⇧ D',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyM, shift: true)],
    action: AppAction.slopeTool,
    label: 'Slope (tap a line, segment or ray)',
    section: ShortcutSection.tools,
    display: '⇧ M',
  ),
  const ShortcutBinding(
    sequence: [KeyStroke(LogicalKeyboardKey.keyL, shift: true)],
    action: AppAction.locusTool,
    label: 'Locus (driver point, then traced point)',
    section: ShortcutSection.tools,
    display: '⇧ L',
  ),
  // ── G leader: constructions ──────────────────────────────────────
  _g(LogicalKeyboardKey.keyC, AppAction.centroidTool, 'Centroid', 'G C'),
  _g(LogicalKeyboardKey.keyO, AppAction.orthocenterTool, 'Orthocenter', 'G O'),
  _g(LogicalKeyboardKey.keyI, AppAction.incenterTool, 'Incenter', 'G I'),
  _g(
    LogicalKeyboardKey.keyU,
    AppAction.circumcenterTool,
    'Circumcenter',
    'G U',
  ),
  _g(
    LogicalKeyboardKey.digit2,
    AppAction.diameterCircleTool,
    'Circle by diameter (the two endpoints)',
    'G 2',
  ),
  _g(
    LogicalKeyboardKey.digit3,
    AppAction.threePointCircleTool,
    'Circle through three points',
    'G 3',
  ),
  _g(
    LogicalKeyboardKey.digit9,
    AppAction.ninePointCircleTool,
    'Nine-point (Euler) circle',
    'G 9',
  ),
  _g(
    LogicalKeyboardKey.keyI,
    AppAction.inscribedCircleTool,
    'Inscribed circle (incircle)',
    'G ⇧ I',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyA,
    AppAction.apolloniusCircleTool,
    'Apollonius circle (A, B, then the ratio point)',
    'G ⇧ A',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyD,
    AppAction.fixedAngleLineTool,
    'Line at a stated angle…',
    'G ⇧ D',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyR,
    AppAction.statedRadiusCircleTool,
    'Circle with stated radius…',
    'G ⇧ R',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyO,
    AppAction.scaledCompassCircleTool,
    'Compass scaled by a stated ratio…',
    'G ⇧ O',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyQ,
    AppAction.ratioApolloniusCircleTool,
    'Apollonius circle with stated ratio…',
    'G ⇧ Q',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.digit5,
    AppAction.conicTool,
    'Conic through five points',
    'G 5',
  ),
  _g(
    LogicalKeyboardKey.keyB,
    AppAction.parabolaTool,
    'Parabola (focus, then directrix)',
    'G B',
  ),
  _g(
    LogicalKeyboardKey.keyE,
    AppAction.ellipseTool,
    'Ellipse (two foci, then a point on it)',
    'G ⇧ E',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyH,
    AppAction.hyperbolaTool,
    'Hyperbola (two foci, then a point on it)',
    'G ⇧ H',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyC,
    AppAction.focalConicTool,
    'Conic by focus, directrix and eccentricity…',
    'G ⇧ C',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyR,
    AppAction.segmentRatioTool,
    'Segment-ratio point…',
    'G R',
  ),
  _g(
    LogicalKeyboardKey.keyF,
    AppAction.projectionTool,
    'Projection onto a line (foot of the perpendicular)',
    'G F',
  ),
  _g(
    LogicalKeyboardKey.digit4,
    AppAction.harmonicConjugateTool,
    'Harmonic conjugate (fourth harmonic point)',
    'G 4',
  ),
  _g(LogicalKeyboardKey.keyA, AppAction.arcTool, 'Arc (three points)', 'G A'),
  _g(LogicalKeyboardKey.keyS, AppAction.sectorTool, 'Sector', 'G S'),
  _g(
    LogicalKeyboardKey.keyL,
    AppAction.reflectAboutLineTool,
    'Reflect about line',
    'G L',
  ),
  _g(
    LogicalKeyboardKey.keyP,
    AppAction.reflectAboutPointTool,
    'Reflect about point',
    'G P',
  ),
  _g(
    LogicalKeyboardKey.keyT,
    AppAction.rotateAroundPointTool,
    'Rotate around point…',
    'G T',
  ),
  _g(
    LogicalKeyboardKey.keyV,
    AppAction.translateByVectorTool,
    'Translate by vector',
    'G V',
  ),
  _g(
    LogicalKeyboardKey.keyH,
    AppAction.dilateTool,
    'Dilate from point (homothety)…',
    'G H',
  ),
  _g(
    LogicalKeyboardKey.keyD,
    AppAction.angleBySizeTool,
    'Angle by given size…',
    'G D',
  ),
  _g(
    LogicalKeyboardKey.keyN,
    AppAction.tangentTool,
    'Tangents from point to conic',
    'G N',
  ),
  _g(
    LogicalKeyboardKey.keyP,
    AppAction.polarLineTool,
    'Polar line of a point and conic',
    'G ⇧ P',
    shift: true,
  ),
  _g(
    LogicalKeyboardKey.keyX,
    AppAction.radicalAxisTool,
    'Radical axis of two circles',
    'G X',
  ),
  _g(
    LogicalKeyboardKey.keyM,
    AppAction.namePointsTool,
    'Name points in sequence…',
    'G M',
  ),
  _g(
    LogicalKeyboardKey.keyE,
    AppAction.textTool,
    'Text with live calculations…',
    'G E',
  ),
  // ── X leader: shape macros ───────────────────────────────────────
  _x(
    LogicalKeyboardKey.keyV,
    AppAction.polygonTool,
    'Polygon (tap the first vertex to close)',
    'X V',
  ),
  _x(LogicalKeyboardKey.keyS, AppAction.squareMacroTool, 'Square', 'X S'),
  _x(
    LogicalKeyboardKey.keyP,
    AppAction.parallelogramMacroTool,
    'Parallelogram',
    'X P',
  ),
  _x(LogicalKeyboardKey.keyT, AppAction.trapeziumMacroTool, 'Trapezium', 'X T'),
  _x(LogicalKeyboardKey.keyR, AppAction.rectangleMacroTool, 'Rectangle', 'X R'),
  _x(LogicalKeyboardKey.keyH, AppAction.rhombusMacroTool, 'Rhombus', 'X H'),
  _x(LogicalKeyboardKey.keyK, AppAction.kiteMacroTool, 'Kite', 'X K'),
  _x(
    LogicalKeyboardKey.keyI,
    AppAction.isoscelesTrapeziumMacroTool,
    'Isosceles trapezium',
    'X I',
  ),
  _x(
    LogicalKeyboardKey.keyL,
    AppAction.rightTrapeziumMacroTool,
    'Right trapezium',
    'X L',
  ),
  _x(
    LogicalKeyboardKey.keyE,
    AppAction.equilateralTriangleMacroTool,
    'Equilateral triangle',
    'X E',
  ),
  _x(
    LogicalKeyboardKey.keyI,
    AppAction.isoscelesTriangleMacroTool,
    'Isosceles triangle',
    'X ⇧ I',
    shift: true,
  ),
  _x(
    LogicalKeyboardKey.keyR,
    AppAction.rightTriangleMacroTool,
    'Right triangle',
    'X ⇧ R',
    shift: true,
  ),
  _x(
    LogicalKeyboardKey.keyG,
    AppAction.regularPolygonMacroTool,
    'Regular polygon…',
    'X G',
  ),
  _x(
    LogicalKeyboardKey.digit3,
    AppAction.randomTriangleStamp,
    'Random triangle',
    'X 3',
  ),
  _x(
    LogicalKeyboardKey.digit4,
    AppAction.randomQuadrilateralStamp,
    'Random quadrilateral',
    'X 4',
  ),
];

/// The render-ready key text for [action]'s primary binding — the first
/// cheat-sheet-visible entry in table order, so hidden alternates (the
/// numpad twins, `Ctrl/⌘ Y`, `Backspace`) never surface in tooltips.
/// Null when the action has no binding.
String? shortcutDisplayFor(AppAction action) {
  for (final binding in shortcutTable) {
    if (binding.action == action && binding.showInCheatSheet) {
      return binding.display;
    }
  }
  return null;
}

/// A display-only cheat-sheet row. Not a binding — the resolver never
/// sees these; they exist so non-keyboard knowledge (pointer gestures,
/// the text tool's expression language) is discoverable next to the
/// shortcuts.
class InfoRow {
  const InfoRow({
    required this.display,
    required this.label,
    required this.section,
  });

  final String display;
  final String label;
  final ShortcutSection section;
}

const List<InfoRow> infoRows = [
  InfoRow(
    display: 'Tap tree header',
    label:
        'Select every object of that kind '
        '(Shift-tap or long-press adds)',
    section: ShortcutSection.appLevel,
  ),
  InfoRow(
    display: 'Long-press tree row',
    label: 'Toggle that object in the selection (touch shift-tap)',
    section: ShortcutSection.appLevel,
  ),
  InfoRow(
    display: 'Space + drag',
    label: 'Pan (hold Space, works with any tool)',
    section: ShortcutSection.viewport,
  ),
  InfoRow(
    display: 'Scroll',
    label: 'Pan (mouse wheel or two-finger swipe)',
    section: ShortcutSection.viewport,
  ),
  InfoRow(
    display: 'Ctrl/Cmd + scroll',
    label: 'Zoom about the cursor',
    section: ShortcutSection.viewport,
  ),
  InfoRow(
    display: 'Alt/Option + scroll',
    label: 'Rotate about the cursor (near level snaps straight)',
    section: ShortcutSection.viewport,
  ),
  InfoRow(
    display: 'Two-finger drag',
    label: 'Pan (touch)',
    section: ShortcutSection.viewport,
  ),
  InfoRow(
    display: 'Pinch',
    label: 'Zoom about the cursor (touch or trackpad)',
    section: ShortcutSection.viewport,
  ),
  InfoRow(
    display: 'Two-finger twist',
    label: 'Rotate the view (touch; releasing near level snaps straight)',
    section: ShortcutSection.viewport,
  ),
  // ── Text tool expression language (Phase 58) ─────────────────────
  // Mirrors `objectFunctionNames` / `_numericFunctions` in the domain;
  // pinned against them by `cheat_sheet_test.dart`.
  InfoRow(
    display: '{…}',
    label: 'Live calculation inside a text — e.g. AB = {dist(A, B)}',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'dist(A, B)',
    label: 'Distance between two points',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'len(s)',
    label:
        'Segment length; circle circumference, arc length, '
        'sector perimeter',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'angle(A, B, C)',
    label: 'Angle at vertex B, in degrees',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'area(p)',
    label: 'Area of a polygon, circle, sector or arc segment',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'perimeter(p)',
    label: 'Perimeter of a polygon',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'radius(c)',
    label: 'Radius of a circle',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'x(A), y(A)',
    label: 'Coordinates of a point',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'Bare name',
    label: 'Segment → its length, angle → degrees, measurement → value',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: '+ − * / ^ ( )',
    label: 'Arithmetic; ^ is power. Pasted ×, ·, ÷ work too',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'sqrt, abs, …',
    label:
        'Also round, floor, ceil, min, max; sin, cos, tan and '
        'asin, acos, atan in degrees',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: 'pi, e',
    label: 'Constants — they shadow objects named pi or e',
    section: ShortcutSection.textCalc,
  ),
  InfoRow(
    display: '?',
    label:
        'Shown while a value is undefined (unknown name, wrong kind, '
        'division by zero)',
    section: ShortcutSection.textCalc,
  ),
];
