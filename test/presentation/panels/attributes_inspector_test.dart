import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/panels/attributes_inspector.dart';

import '../../wide_window.dart';

void main() {
  late ProviderContainer container;

  /// The full editor with the inspector opened the way the user opens
  /// it — through the app-bar button. It no longer appears with the
  /// selection (a tap on the canvas used to resize the canvas), so every
  /// test about its *contents* has to open it first.
  Future<void> pumpEditor(WidgetTester tester, {bool open = true}) async {
    useWideTestWindow(tester);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    if (open) {
      await tester.tap(find.byTooltip('Style & properties'));
      await tester.pump();
    }
  }

  FreePoint addPoint(String id, Vec2 position) {
    final point = FreePoint(id: id, position: position);
    container.read(constructionProvider).construction.add(point);
    return point;
  }

  testWidgets('texts and measurements hide the stroke rows; texts also hide '
      'the dead show-label toggle', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(3, 4));
    container.read(constructionProvider).construction
      ..add(
        ExpressionText(
          id: 't',
          content: 'note',
          anchor: const Vec2(1, 1),
          references: const [],
        ),
      )
      ..add(DistanceMeasurement(id: 'd', point1: a, point2: b));

    container.read(selectionProvider.notifier).select('t');
    await tester.pump();
    expect(find.text('Text'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stroke-width')),
      findsNothing,
      reason: 'a text is pure label — stroke width is a silent no-op',
    );
    expect(find.byKey(const ValueKey('dash-style')), findsNothing);
    expect(
      find.widgetWithText(CheckboxListTile, 'Show label'),
      findsNothing,
      reason: 'a text never composes name = content',
    );
    expect(find.widgetWithText(CheckboxListTile, 'Visible'), findsOneWidget);

    container.read(selectionProvider.notifier).select('d');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stroke-width')),
      findsNothing,
      reason: 'measurements are pure label text too',
    );
    expect(find.byKey(const ValueKey('dash-style')), findsNothing);
    expect(
      find.widgetWithText(CheckboxListTile, 'Show label'),
      findsOneWidget,
      reason: 'a measurement still composes name = value',
    );

    // A mixed selection brings the stroke rows back for the segment.
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    container.read(selectionProvider.notifier).selectMany(['t', 's']);
    await tester.pump();
    expect(find.byKey(const ValueKey('stroke-width')), findsOneWidget);
  });

  testWidgets('the panel is opened by its button, not by the selection', (
    tester,
  ) async {
    await pumpEditor(tester, open: false);
    addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    expect(
      find.byType(AttributesInspector),
      findsNothing,
      reason: 'selecting something is not asking to restyle it',
    );

    await tester.tap(find.byTooltip('Style & properties'));
    await tester.pump();
    expect(find.text('Point'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide style & properties'));
    await tester.pump();
    expect(find.byType(AttributesInspector), findsNothing);
  });

  testWidgets('with nothing selected it says what to do', (tester) async {
    // A panel the user opened and that then vanished reads as broken, so
    // an empty selection gets a hint rather than a collapse.
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    await tester.pump();

    expect(find.byType(AttributesInspector), findsOneWidget);
    expect(find.text('Select an object to style it.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Point'), findsNothing);
  });

  testWidgets('single selection: kind header, rename commits one command, '
      'undo restores the old name', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    expect(find.text('Point'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(a.attributes.name, 'A');
    expect(container.read(commandStackProvider).canUndo, isTrue);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(a.attributes.name, '');
    expect(
      find.widgetWithText(TextField, 'A'),
      findsNothing,
      reason: 'undo swaps the field for one showing the restored name',
    );
  });

  testWidgets('single selection of a named object shows name + kind', (
    tester,
  ) async {
    await pumpEditor(tester);
    final point = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A'),
    );
    container.read(constructionProvider).construction.add(point);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    expect(find.text('A — Point'), findsOneWidget);
    expect(
      find.text('Point'),
      findsNothing,
      reason: 'the kind-only header appears only for unnamed objects',
    );
  });

  testWidgets('renaming to a taken name evicts the old holder, one undo '
      'restores both', (tester) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A'),
    );
    final b = FreePoint(
      id: 'b',
      position: Vec2(1, 0),
      attributes: const ObjectAttributes(name: 'B'),
    );
    final construction = container.read(constructionProvider).construction;
    construction.add(a);
    construction.add(b);
    container.read(selectionProvider.notifier).select('b');
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'A');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(b.attributes.name, 'A');
    expect(a.attributes.name, 'A1', reason: 'the old holder is evicted');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      b.attributes.name,
      'B',
      reason: 'both renames ride one command = one undo step',
    );
    expect(a.attributes.name, 'A');
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('renaming an object to its own name stays a no-op even when '
      'clash resolution is live', (tester) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A'),
    );
    container.read(constructionProvider).construction.add(a);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'A');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(a.attributes.name, 'A');
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('submitting an unchanged name adds nothing to the undo stack', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('visibility toggle: one command, undo restores, and the '
      'hidden object stays in the inspector', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Visible'));
    await tester.pump();
    expect(a.attributes.visible, isFalse);
    expect(container.read(commandStackProvider).canUndo, isTrue);
    // Hidden but still selected: the panel is the way back to un-hiding.
    expect(find.text('Point'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(a.attributes.visible, isTrue);
  });

  testWidgets('label toggle flips labelVisible', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Show label'));
    await tester.pump();
    expect(a.attributes.labelVisible, isFalse);
    expect(
      a.attributes.visible,
      isTrue,
      reason: 'the two toggles must not bleed into each other',
    );

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Show label'));
    await tester.pump();
    expect(a.attributes.labelVisible, isTrue);
  });

  testWidgets('multi-selection toggle: mixed resolves to all-on in one '
      'undoable command', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = FreePoint(
      id: 'b',
      position: const Vec2(4, 0),
      attributes: const ObjectAttributes(visible: false),
    );
    container.read(constructionProvider).construction.add(b);
    container.read(selectionProvider.notifier).selectMany(['a', 'b']);
    await tester.pump();

    final visibleTile = find.widgetWithText(CheckboxListTile, 'Visible');
    expect(
      tester.widget<CheckboxListTile>(visibleTile).value,
      isNull,
      reason: 'mixed visibility shows the tristate dash',
    );

    await tester.tap(visibleTile);
    await tester.pump();
    expect(a.attributes.visible, isTrue);
    expect(b.attributes.visible, isTrue);

    await tester.tap(visibleTile);
    await tester.pump();
    expect(a.attributes.visible, isFalse);
    expect(b.attributes.visible, isFalse);

    // One undo per tap: all-off -> all-on -> the original mixed state.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(a.attributes.visible, isTrue);
    expect(b.attributes.visible, isTrue);
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(a.attributes.visible, isTrue);
    expect(b.attributes.visible, isFalse);
  });

  testWidgets('color swatches: explicit color and back to Auto, one '
      'command each', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.tap(find.byTooltip('Red'));
    await tester.pump();
    expect(a.attributes.colorArgb, 0xFFE53935);

    await tester.tap(find.byTooltip('Auto'));
    await tester.pump();
    expect(
      a.attributes.colorArgb,
      isNull,
      reason:
          'Auto must set the color back to the theme-default null, '
          'not leave the previous explicit color in place',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      a.attributes.colorArgb,
      0xFFE53935,
      reason: 'each swatch tap is its own undo step',
    );
  });

  testWidgets('re-tapping the color the whole selection already has adds '
      'nothing to the undo stack', (tester) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.tap(find.byTooltip('Auto'));
    await tester.pump();
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('point size selector: points get it, strokes do not', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    final pointSize = find.byKey(const ValueKey('point-size'));
    expect(pointSize, findsOneWidget);
    expect(
      find.byKey(const ValueKey('stroke-width')),
      findsNothing,
      reason: 'stroke width means nothing for a point-only selection',
    );

    await tester.tap(find.descendant(of: pointSize, matching: find.text('8')));
    await tester.pump();
    expect(a.attributes.pointSize, 8.0);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(a.attributes.pointSize, 4.0);
  });

  testWidgets('mixed-kind selection: stroke width touches only the '
      'non-points', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final s = Segment(id: 's', point1: a, point2: b);
    container.read(constructionProvider).construction.add(s);
    container.read(selectionProvider.notifier).selectMany(['a', 'b', 's']);
    await tester.pump();

    final strokeWidth = find.byKey(const ValueKey('stroke-width'));
    expect(strokeWidth, findsOneWidget);
    expect(find.byKey(const ValueKey('point-size')), findsOneWidget);

    await tester.tap(
      find.descendant(of: strokeWidth, matching: find.text('6')),
    );
    await tester.pump();
    expect(s.attributes.strokeWidth, 6.0);
    expect(
      a.attributes.strokeWidth,
      2.0,
      reason:
          'points keep their (unused) stroke width — the command '
          'covers only the slice the control targets',
    );
    expect(a.attributes.pointSize, 4.0);
  });

  testWidgets('dash selector: strokes only, one command per tap, undo '
      'restores solid', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final s = Segment(id: 's', point1: a, point2: b);
    container.read(constructionProvider).construction.add(s);

    container.read(selectionProvider.notifier).select('a');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dash-style')),
      findsNothing,
      reason: 'dashing means nothing for a point-only selection',
    );

    container.read(selectionProvider.notifier).select('s');
    await tester.pump();
    final dashStyle = find.byKey(const ValueKey('dash-style'));
    expect(dashStyle, findsOneWidget);
    final segments = find.descendant(
      of: dashStyle,
      matching: find.byType(SegmentedButton<double>),
    );
    expect(
      tester.getSize(segments).width,
      lessThanOrEqualTo(AttributesInspector.panelWidth - 32),
      reason: 'single-letter segments fit the panel inside its padding',
    );

    // Single-letter labels (Phase 25): 'M' is Medium, tooltip carries
    // the word.
    await tester.tap(find.descendant(of: dashStyle, matching: find.text('M')));
    await tester.pump();
    expect(s.attributes.dashPeriod, 8.0);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(s.attributes.dashPeriod, 0.0);
  });

  testWidgets('equal-marks selector: segments only, one command per tap, '
      'undo restores no marks', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final s = Segment(id: 's', point1: a, point2: b);
    container.read(constructionProvider).construction
      ..add(line)
      ..add(s);

    container.read(selectionProvider.notifier).select('l');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('tick-marks')),
      findsNothing,
      reason: 'equal marks are congruence notation for segments alone',
    );

    container.read(selectionProvider.notifier).selectMany(['l', 's']);
    await tester.pump();
    final tickMarks = find.byKey(const ValueKey('tick-marks'));
    expect(tickMarks, findsOneWidget);

    await tester.tap(find.descendant(of: tickMarks, matching: find.text('2')));
    await tester.pump();
    expect(s.attributes.tickMarks, 2);
    expect(
      line.attributes.tickMarks,
      0,
      reason: 'the command covers only the segment slice',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(s.attributes.tickMarks, 0);
  });

  testWidgets('marker-radius selector: angles only, one command over the '
      'angle slice, undo restores the default', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', const Vec2(4, 0));
    final v = addPoint('v', Vec2.zero);
    final b = addPoint('b', const Vec2(1, 3));
    final s = Segment(id: 's', point1: a, point2: b);
    final angle = VertexAngle(id: 'ang', arm1: a, vertex: v, arm2: b);
    container.read(constructionProvider).construction
      ..add(s)
      ..add(angle);

    container.read(selectionProvider.notifier).select('s');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('marker-radius')),
      findsNothing,
      reason: 'a marker radius means nothing without an angle selected',
    );

    container.read(selectionProvider.notifier).select('ang');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dash-style')),
      findsNothing,
      reason: 'angle markers never dash — no silent no-op row',
    );
    expect(
      find.byKey(const ValueKey('stroke-width')),
      findsOneWidget,
      reason: 'stroke width does apply to the marker outline',
    );

    container.read(selectionProvider.notifier).selectMany(['s', 'ang']);
    await tester.pump();
    final markerRadius = find.byKey(const ValueKey('marker-radius'));
    await tester.scrollUntilVisible(
      markerRadius,
      100,
      scrollable: find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(Scrollable),
      ),
    );

    // 'XL' is scoped to the radius row anyway, matching the label-size
    // test's precaution.
    await tester.tap(
      find.descendant(of: markerRadius, matching: find.text('XL')),
    );
    await tester.pump();
    expect(angle.attributes.angleMarkerRadius, 36.0);
    expect(
      s.attributes.angleMarkerRadius,
      28.0,
      reason: 'the command covers only the angle slice',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(angle.attributes.angleMarkerRadius, 28.0);
  });

  testWidgets('extent selector: clippable lines only, one command over '
      'the line slice, undo restores infinite', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final s = Segment(id: 's', point1: a, point2: b);
    final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    container.read(constructionProvider).construction
      ..add(s)
      ..add(l);

    container.read(selectionProvider.notifier).select('a');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('line-extent')),
      findsNothing,
      reason: 'an extent means nothing for a point-only selection',
    );

    container.read(selectionProvider.notifier).select('s');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('line-extent')),
      findsNothing,
      reason: 'a segment is already its own clip',
    );

    container.read(selectionProvider.notifier).selectMany(['a', 's', 'l']);
    await tester.pump();
    final extent = find.byKey(const ValueKey('line-extent'));
    await tester.scrollUntilVisible(
      extent,
      100,
      scrollable: find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(Scrollable),
      ),
    );

    await tester.tap(find.descendant(of: extent, matching: find.text('P')));
    await tester.pump();
    expect(l.attributes.lineClip, 2);
    expect(
      s.attributes.lineClip,
      0,
      reason: 'the command covers only the clippable slice',
    );
    expect(a.attributes.lineClip, 0);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(l.attributes.lineClip, 0);
  });

  testWidgets('extent selector offers the defining-points mode only while '
      'a LineThroughTwoPoints is selected', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final c = addPoint('c', const Vec2(1, 3));
    final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final perp = PerpendicularLine(id: 'pp', through: c, reference: l);
    container.read(constructionProvider).construction
      ..add(l)
      ..add(perp);

    container.read(selectionProvider.notifier).select('pp');
    await tester.pump();
    final extent = find.byKey(const ValueKey('line-extent'));
    expect(extent, findsOneWidget);
    expect(
      find.descendant(of: extent, matching: find.text('D')),
      findsNothing,
      reason: 'a perpendicular has no defining pair on its carrier',
    );

    await tester.tap(find.descendant(of: extent, matching: find.text('P')));
    await tester.pump();
    expect(perp.attributes.lineClip, 2);

    container.read(selectionProvider.notifier).selectMany(['l', 'pp']);
    await tester.pump();
    expect(
      find.descendant(of: extent, matching: find.text('D')),
      findsOneWidget,
      reason: 'the line in the selection brings the mode back',
    );
  });

  testWidgets('label-size selector: whole selection, one command, undo '
      'restores the default', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final s = Segment(id: 's', point1: a, point2: b);
    // A measurement rides the same row — its text is all it has (Phase 38).
    final d = DistanceMeasurement(id: 'd', point1: a, point2: b);
    container.read(constructionProvider).construction
      ..add(s)
      ..add(d);

    container.read(selectionProvider.notifier).selectMany(['a', 's', 'd']);
    await tester.pump();
    final labelSize = find.byKey(const ValueKey('label-size'));
    await tester.scrollUntilVisible(
      labelSize,
      100,
      scrollable: find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(Scrollable),
      ),
    );

    // 'XL' is unique to this row today, but scope the tap anyway (the
    // marker-radius row shares it when an angle is selected).
    await tester.tap(find.descendant(of: labelSize, matching: find.text('XL')));
    await tester.pump();
    expect(a.attributes.labelFontSize, 22.0);
    expect(
      s.attributes.labelFontSize,
      22.0,
      reason: 'every kind carries a label — one command over all of it',
    );
    expect(d.attributes.labelFontSize, 22.0);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(a.attributes.labelFontSize, 16.0);
    expect(s.attributes.labelFontSize, 16.0);
    expect(d.attributes.labelFontSize, 16.0);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'both updates rode a single command',
    );
  });

  testWidgets('fill checkbox: angles + sectors, tristate over a mixed '
      'selection, toggles fillAlpha null ↔ 0.25', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', const Vec2(4, 0));
    final v = addPoint('v', Vec2.zero);
    final b = addPoint('b', const Vec2(1, 3));
    final angle = VertexAngle(id: 'ang', arm1: a, vertex: v, arm2: b);
    final sector = Sector(
      id: 'sec',
      center: v,
      start: a,
      end: b,
      attributes: const ObjectAttributes(fillAlpha: 0.25),
    );
    container.read(constructionProvider).construction
      ..add(angle)
      ..add(sector);

    container.read(selectionProvider.notifier).select('a');
    await tester.pump();
    expect(
      find.widgetWithText(CheckboxListTile, 'Fill'),
      findsNothing,
      reason: 'points have no filled form',
    );

    container.read(selectionProvider.notifier).selectMany(['ang', 'sec']);
    await tester.pump();
    final fill = find.widgetWithText(CheckboxListTile, 'Fill');
    await tester.scrollUntilVisible(
      fill,
      100,
      scrollable: find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(Scrollable),
      ),
    );
    // scrollUntilVisible stops once the tile is *built*, which can leave
    // its center off-screen (the row list grew in Phase 28) — bring it
    // fully in before tapping.
    await tester.ensureVisible(fill);
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(fill).value,
      isNull,
      reason: 'one filled, one unfilled — the tristate dash',
    );

    // Anything but all-on turns everything on…
    await tester.tap(fill);
    await tester.pump();
    expect(angle.attributes.fillAlpha, 0.25);
    expect(sector.attributes.fillAlpha, 0.25);
    expect(tester.widget<CheckboxListTile>(fill).value, isTrue);

    // …and all-on turns everything off.
    await tester.tap(fill);
    await tester.pump();
    expect(angle.attributes.fillAlpha, isNull);
    expect(sector.attributes.fillAlpha, isNull);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      angle.attributes.fillAlpha,
      0.25,
      reason: 'the all-off toggle was one command over both kinds',
    );
    expect(sector.attributes.fillAlpha, 0.25);
  });

  testWidgets('fill checkbox is withheld from a conic (Phase 120)', (
    tester,
  ) async {
    // A conic bounds nothing the painter can close — a hyperbola has no
    // interior, a clipped ellipse would need the viewport edges — so the
    // row would be a silent no-op. Withheld by *kind*: an undefined circle
    // still keeps its row (below), and a circle-shaped conic gains none.
    await pumpEditor(tester);
    final points = [
      for (final (i, t) in const [0.0, 1.0, 2.0, 3.0, 4.0].indexed)
        addPoint('q$i', Vec2(2 * math.cos(t), math.sin(t))),
    ];
    container
        .read(constructionProvider)
        .construction
        .add(FivePointConic(id: 'conic', points: points));

    container.read(selectionProvider.notifier).select('conic');
    await tester.pump();
    expect(
      find.widgetWithText(CheckboxListTile, 'Fill'),
      findsNothing,
      reason: 'a conic is a curve, not a region',
    );
  });

  testWidgets('an undefined circle keeps its fill row (Phase 120)', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(1, 0));
    final c = addPoint('c', const Vec2(2, 0));
    final collinear = ThreePointCircle(
      id: 'tpc',
      point1: a,
      point2: b,
      point3: c,
    );
    container.read(constructionProvider).construction.add(collinear);
    expect(collinear.isDefined, isFalse);

    container.read(selectionProvider.notifier).select('tpc');
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, 'Fill'), findsOneWidget);
  });

  testWidgets('fill checkbox covers circles and polygons, not arcs '
      '(Phase 37)', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final c = addPoint('c', const Vec2(1, 3));
    final circle = CircleCenterPoint(id: 'circ', center: a, onCircle: b);
    final polygon = Polygon(id: 'poly', vertices: [a, b, c]);
    final arc = Arc(id: 'arc', start: a, via: c, end: b);
    container.read(constructionProvider).construction
      ..add(circle)
      ..add(polygon)
      ..add(arc);

    container.read(selectionProvider.notifier).select('arc');
    await tester.pump();
    expect(
      find.widgetWithText(CheckboxListTile, 'Fill'),
      findsNothing,
      reason: 'an arc has no fill shape — the painter skips it',
    );

    container.read(selectionProvider.notifier).selectMany(['circ', 'poly']);
    await tester.pump();
    final fill = find.widgetWithText(CheckboxListTile, 'Fill');
    await tester.scrollUntilVisible(
      fill,
      100,
      scrollable: find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(fill);
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(fill).value,
      isFalse,
      reason: 'neither is filled yet',
    );

    await tester.tap(fill);
    await tester.pump();
    expect(circle.attributes.fillAlpha, 0.25);
    expect(polygon.attributes.fillAlpha, 0.25);
    expect(container.read(commandStackProvider).canUndo, isTrue);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      circle.attributes.fillAlpha,
      isNull,
      reason: 'both updates rode a single command',
    );
    expect(polygon.attributes.fillAlpha, isNull);
  });

  testWidgets('show-value checkbox: segments + angles only, one command '
      'over a mixed selection', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    final c = addPoint('c', const Vec2(1, 3));
    final s = Segment(id: 's', point1: a, point2: b);
    final angle = VertexAngle(
      id: 'ang',
      arm1: b,
      vertex: a,
      arm2: c,
      attributes: const ObjectAttributes(showValue: true),
    );
    container.read(constructionProvider).construction
      ..add(s)
      ..add(angle);

    container.read(selectionProvider.notifier).select('a');
    await tester.pump();
    expect(
      find.widgetWithText(CheckboxListTile, 'Show value'),
      findsNothing,
      reason: 'points have no measurable value',
    );

    // Point + segment + angle: the row shows and targets the measurables.
    container.read(selectionProvider.notifier).selectMany(['a', 's', 'ang']);
    await tester.pump();
    final showValue = find.widgetWithText(CheckboxListTile, 'Show value');
    expect(showValue, findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(showValue).value,
      isNull,
      reason: 'segment off, angle on — the tristate dash',
    );

    // Anything but all-on turns everything on…
    await tester.tap(showValue);
    await tester.pump();
    expect(s.attributes.showValue, isTrue);
    expect(angle.attributes.showValue, isTrue);
    expect(
      a.attributes.showValue,
      isFalse,
      reason: 'the point is outside the measurable slice',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      s.attributes.showValue,
      isFalse,
      reason: 'the toggle was one command over both measurables',
    );
    expect(angle.attributes.showValue, isTrue);

    // …and all-on turns everything off.
    await tester.tap(find.byIcon(Icons.redo));
    await tester.pump();
    await tester.tap(showValue);
    await tester.pump();
    expect(s.attributes.showValue, isFalse);
    expect(angle.attributes.showValue, isFalse);
  });

  testWidgets('multi-selection: count header and a read-only list', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    container.read(selectionProvider.notifier).selectMany(['a', 'b', 's']);
    await tester.pump();

    expect(find.text('3 selected'), findsOneWidget);
    // The dash selector pushed the read-only list below the lazy
    // ListView's fold — scroll it into existence first.
    await tester.scrollUntilVisible(
      find.text('Segment'),
      100,
      scrollable: find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Point'), findsNWidgets(2));
    expect(find.text('Segment'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the inspector carries no delete button — deletion lives in '
      'the app bar (Phase 41)', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    container.read(selectionProvider.notifier).selectMany(['a', 'b', 's']);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('delete-button')), findsNothing);
  });

  testWidgets('clearing the selection leaves the panel open and empty', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    final selection = container.read(selectionProvider.notifier);
    selection.select('a');
    await tester.pump();
    expect(find.text('Point'), findsOneWidget);

    selection.clear();
    await tester.pump();
    expect(find.text('Point'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('Select an object to style it.'),
      findsOneWidget,
      reason: 'the panel stays where the user put it',
    );
  });

  testWidgets('an object deleted out from under the selection drops out '
      'before the pruner runs', (tester) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    addPoint('b', const Vec2(4, 0));
    container.read(selectionProvider.notifier).selectMany(['a', 'b']);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    container.read(constructionProvider).construction.removeWithDependents('a');
    await tester.pump();

    // Down to one object — the header is the survivor's kind, not a count.
    expect(find.text('Point'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);
  });
}
