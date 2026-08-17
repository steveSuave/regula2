import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/application/providers/preferences_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/application/providers/theme_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/slope_measurement.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/angle_bisector_tool.dart';
import 'package:regula/domain/tools/angle_by_size_tool.dart';
import 'package:regula/domain/tools/angle_tool.dart';
import 'package:regula/domain/tools/area_tool.dart';
import 'package:regula/domain/tools/bifocal_conic_tool.dart';
import 'package:regula/domain/tools/conic_tool.dart';
import 'package:regula/domain/tools/distance_tool.dart';
import 'package:regula/domain/tools/equilateral_triangle_macro_tool.dart';
import 'package:regula/domain/tools/fixed_length_segment_tool.dart';
import 'package:regula/domain/tools/fixed_radius_circle_tool.dart';
import 'package:regula/domain/tools/focal_conic_tool.dart';
import 'package:regula/domain/tools/harmonic_conjugate_tool.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/locus_tool.dart';
import 'package:regula/domain/tools/point_and_line_tool.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/domain/tools/polar_line_tool.dart';
import 'package:regula/domain/tools/polygon_tool.dart';
import 'package:regula/domain/tools/radical_axis_tool.dart';
import 'package:regula/domain/tools/random_shape_stamp_tool.dart';
import 'package:regula/domain/tools/rectangle_macro_tool.dart';
import 'package:regula/domain/tools/regular_polygon_macro_tool.dart';
import 'package:regula/domain/tools/right_triangle_macro_tool.dart';
import 'package:regula/domain/tools/slope_tool.dart';
import 'package:regula/domain/tools/square_macro_tool.dart';
import 'package:regula/domain/tools/tangent_tool.dart';
import 'package:regula/domain/tools/three_point_tool.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/transform_object_tool.dart';
import 'package:regula/domain/tools/triangle_center_tool.dart';
import 'package:regula/domain/tools/triangle_circle_tool.dart';
import 'package:regula/domain/tools/two_point_tool.dart';
import 'package:regula/domain/tools/visibility_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import 'package:regula/presentation/canvas/trace_stats_overlay.dart';
import 'package:regula/presentation/panels/toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../wide_window.dart';

/// Widget tests for the keyboard shortcut wiring: key events go in, the
/// providers (tool, selection, viewport, command stack) change as the
/// shortcut table promises.
void main() {
  late ProviderContainer container;

  Future<void> pumpEditor(WidgetTester tester) async {
    useWideTestWindow(tester);
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
  }

  Tool? activeTool() => container.read(toolProvider).tool;

  /// Feeds the active tool a canvas input directly — the canvas→tool
  /// funnel has its own tests; here only the activation matters.
  void tapWorld(double x, double y) =>
      container.read(toolProvider.notifier).handleInput(ToolInput(Vec2(x, y)));

  /// Two free points and their midpoint, added like real edits.
  (FreePoint, FreePoint, Midpoint) buildSmallConstruction() {
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 2));
    final m = Midpoint(id: 'm', point1: a, point2: b);
    stack.execute(AddObjectCommand(a));
    stack.execute(AddObjectCommand(b));
    stack.execute(AddObjectCommand(m));
    return (a, b, m);
  }

  testWidgets('letter keys activate tools; Esc and V leave them', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(activeTool(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(activeTool(), isA<PointTool>());

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(activeTool(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    expect(activeTool(), isA<PointAndLineTool>());

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    expect(activeTool(), isNull);
  });

  testWidgets('Esc and undo are two-stage while a tool holds pending input', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    final construction = container.read(constructionProvider).construction;

    // Undo first consumes the pending point, only then pops the stack.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    tapWorld(10, 10);
    expect(activeTool()!.hasPartialInput, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(
      activeTool(),
      isA<TwoPointTool>(),
      reason: 'the tool survives the first undo',
    );
    expect(activeTool()!.hasPartialInput, isFalse);
    expect(construction.length, 3, reason: 'the stack was not touched');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(construction.length, 2, reason: 'the second undo pops the stack');

    // Esc likewise: pending input first, move/select second.
    tapWorld(10, 10);
    expect(activeTool()!.hasPartialInput, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(
      activeTool(),
      isA<TwoPointTool>(),
      reason: 'the first Esc only clears the pending point',
    );
    expect(activeTool()!.hasPartialInput, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(activeTool(), isNull, reason: 'the second Esc leaves the tool');
  });

  testWidgets('the app-bar undo button is two-stage like Ctrl+Z', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    final construction = container.read(constructionProvider).construction;
    final undoButton = find.byTooltip('Undo');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    tapWorld(10, 10);
    await tester.pump();

    await tester.tap(undoButton);
    await tester.pump();
    expect(
      activeTool(),
      isA<TwoPointTool>(),
      reason: 'the first press only clears the pending point',
    );
    expect(activeTool()!.hasPartialInput, isFalse);
    expect(construction.length, 3, reason: 'the stack was not touched');

    await tester.tap(undoButton);
    await tester.pump();
    expect(construction.length, 2, reason: 'the second press pops the stack');
  });

  testWidgets('the undo button enables for pending input on an empty stack', (
    tester,
  ) async {
    await pumpEditor(tester);
    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    IconButton button() => tester.widget<IconButton>(undoButton);
    expect(button().onPressed, isNull, reason: 'nothing to undo or consume');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    tapWorld(10, 10);
    await tester.pump();
    expect(
      button().onPressed,
      isNotNull,
      reason: 'a pending point is consumable even with an empty stack',
    );

    await tester.tap(undoButton);
    await tester.pump();
    expect(activeTool()!.hasPartialInput, isFalse);
    expect(button().onPressed, isNull, reason: 'nothing left to consume');
  });

  testWidgets('B activates the two-mode angle bisector tool', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(activeTool(), isA<AngleBisectorTool>());
  });

  testWidgets('A activates the two-mode angle tool', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(activeTool(), isA<AngleTool>());
  });

  testWidgets('⇧B builds a perpendicular bisector end to end', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(activeTool(), isA<TwoPointTool>());

    tapWorld(0, 0);
    tapWorld(4, 0);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<PerpendicularBisectorLine>());
    final bisector = objects.last as PerpendicularBisectorLine;
    expect(
      bisector.line!.contains(const Vec2(2, 7)),
      isTrue,
      reason: 'vertical bisector of the horizontal pair at x = 2',
    );
  });

  testWidgets('G F builds a projection point end to end', (tester) async {
    await pumpEditor(tester);
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 0));
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    for (final object in [a, b, line]) {
      stack.execute(AddObjectCommand(object));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    final tool = activeTool();
    expect(tool, isA<PointAndLineTool>());
    expect((tool as PointAndLineTool).build, buildProjectionPoint);

    final tools = container.read(toolProvider.notifier);
    tools.handleInput(ToolInput(const Vec2(2, 0), hit: line));
    tools.handleInput(const ToolInput(Vec2(1, 3)));

    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<ProjectionPoint>());
    final foot = objects.last as ProjectionPoint;
    expect(
      foot.position!.closeTo(const Vec2(1, 0)),
      isTrue,
      reason: 'the foot of the perpendicular from (1, 3) onto y = 0',
    );
  });

  testWidgets('G H asks for the ratio; OK activates the dilate transform '
      'and builds a homothetic point end to end, cancel activates nothing', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '-1/2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(activeTool(), isA<TransformObjectTool>());

    tapWorld(4, 2); // the point, then the center
    tapWorld(0, 0);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<HomotheticPoint>());
    final image = objects.last as HomotheticPoint;
    expect(image.ratio, -0.5);
    expect(image.position!.closeTo(const Vec2(-2, -1)), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      activeTool(),
      isA<TransformObjectTool>(),
      reason: 'cancel leaves the previous tool active',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      (activeTool()! as TransformObjectTool).ratio,
      -0.5,
      reason: 'ratio 0 would collapse onto the center — reads as cancel',
    );
  });

  testWidgets('G 4 builds a harmonic conjugate end to end', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    expect(activeTool(), isA<HarmonicConjugateTool>());

    tapWorld(0, 0);
    tapWorld(4, 0);
    tapWorld(1, 0);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<HarmonicConjugatePoint>());
    final conjugate = objects.last as HarmonicConjugatePoint;
    expect(
      conjugate.position!.closeTo(const Vec2(-2, 0)),
      isTrue,
      reason: 'the fourth harmonic of the quarter point',
    );
  });

  testWidgets('D measures a distance end to end', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    expect(activeTool(), isA<DistanceTool>());

    tapWorld(0, 0);
    tapWorld(3, 4);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<DistanceMeasurement>());
    expect((objects.last as DistanceMeasurement).value, 5);
  });

  testWidgets('⇧D activates the area tool and measures a tapped polygon', (
    tester,
  ) async {
    await pumpEditor(tester);
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 0));
    final c = FreePoint(id: 'c', position: const Vec2(4, 3));
    final polygon = Polygon(id: 'p', vertices: [a, b, c]);
    for (final object in [a, b, c, polygon]) {
      stack.execute(AddObjectCommand(object));
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(activeTool(), isA<AreaTool>());

    container
        .read(toolProvider.notifier)
        .handleInput(ToolInput(const Vec2(3, 1), hit: polygon));
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<AreaMeasurement>());
    expect((objects.last as AreaMeasurement).value, 6);
  });

  testWidgets('⇧M activates the slope tool and measures a tapped line', (
    tester,
  ) async {
    await pumpEditor(tester);
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 2));
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    for (final object in [a, b, line]) {
      stack.execute(AddObjectCommand(object));
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(activeTool(), isA<SlopeTool>());

    container
        .read(toolProvider.notifier)
        .handleInput(ToolInput(const Vec2(2, 1), hit: line));
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<SlopeMeasurement>());
    expect((objects.last as SlopeMeasurement).value, closeTo(0.5, 1e-12));
  });

  testWidgets('⇧L activates the locus tool and traces driver → traced', (
    tester,
  ) async {
    await pumpEditor(tester);
    final stack = container.read(commandStackProvider.notifier);
    final center = FreePoint(id: 'o', position: const Vec2(0, 0));
    final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
    final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
    final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
    final p = FreePoint(id: 'p', position: const Vec2(4, 0));
    final traced = Midpoint(id: 'tr', point1: driver, point2: p);
    for (final object in [center, rim, host, driver, p, traced]) {
      stack.execute(AddObjectCommand(object));
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(activeTool(), isA<LocusTool>());

    final tools = container.read(toolProvider.notifier);
    tools.handleInput(ToolInput(const Vec2(2, 0), hit: driver));
    tools.handleInput(ToolInput(const Vec2(3, 0), hit: traced));
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<Locus>());
    final locus = objects.last as Locus;
    expect(locus.driver, same(driver));
    expect(locus.samples!.whereType<Vec2>(), hasLength(128));
    expect(
      locus.attributes.name,
      isNotEmpty,
      reason: 'auto-named from the lowercase pool',
    );
    expect(
      locus.attributes.labelVisible,
      isFalse,
      reason: 'curve convention: named, label hidden until revealed',
    );
  });

  testWidgets('⇧C asks for the radius; OK builds a circle by radius end '
      'to end, cancel activates nothing', (tester) async {
    await pumpEditor(tester);

    Future<void> pressShiftC() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await pressShiftC();
    expect(find.text('Circle radius'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(activeTool(), isNull);

    await pressShiftC();
    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final tool = activeTool();
    expect(tool, isA<FixedRadiusCircleTool>());
    expect((tool! as FixedRadiusCircleTool).radius, 2.5);

    tapWorld(1, 1);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<FixedRadiusCircle>());
    expect((objects.last as FixedRadiusCircle).circle!.radius, 2.5);
  });

  testWidgets('⇧S asks for the length; OK builds a fixed-length segment '
      'end to end', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Segment length'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final tool = activeTool();
    expect(tool, isA<FixedLengthSegmentTool>());
    expect((tool! as FixedLengthSegmentTool).length, 3);

    tapWorld(1, 1);
    tapWorld(9, 1);
    final segment = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<Segment>()
        .single;
    expect(
      segment.point1.position!.distanceTo(segment.point2.position!),
      closeTo(3, 1e-12),
      reason: 'the length is pinned regardless of where the direction tap is',
    );
  });

  testWidgets('G N chords to the tangent tool, one pair = both tangents', (
    tester,
  ) async {
    await pumpEditor(tester);
    final stack = container.read(commandStackProvider.notifier);
    final c = FreePoint(id: 'c', position: const Vec2(0, 0));
    final r = FreePoint(id: 'r', position: const Vec2(1, 0));
    final circle = CircleCenterPoint(id: 'circ', center: c, onCircle: r);
    for (final object in [c, r, circle]) {
      stack.execute(AddObjectCommand(object));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(activeTool(), isA<TangentTool>());

    container
        .read(toolProvider.notifier)
        .handleInput(ToolInput(const Vec2(1, 0.01), hit: circle));
    tapWorld(5, 0);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.whereType<TangentLine>(), hasLength(2));
    container.read(commandStackProvider.notifier).undo();
    expect(
      container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<TangentLine>(),
      isEmpty,
      reason: 'the pair plus the new point is one undo unit',
    );
  });

  testWidgets('S builds segments end to end', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(activeTool(), isA<TwoPointTool>());

    tapWorld(0, 0);
    tapWorld(4, 0);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects, hasLength(3));
    expect(objects.last, isA<Segment>());
  });

  testWidgets('I builds an intersection point end to end', (tester) async {
    await pumpEditor(tester);
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 0));
    final c = FreePoint(id: 'c', position: const Vec2(2, -2));
    final d = FreePoint(id: 'd', position: const Vec2(2, 2));
    final ab = Segment(id: 'ab', point1: a, point2: b);
    final cd = Segment(id: 'cd', point1: c, point2: d);
    for (final object in [a, b, c, d, ab, cd]) {
      stack.execute(AddObjectCommand(object));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect(activeTool(), isA<IntersectionTool>());

    final tools = container.read(toolProvider.notifier);
    tools.handleInput(ToolInput(const Vec2(1, 0.1), hit: ab));
    tools.handleInput(ToolInput(const Vec2(1.9, 1), hit: cd));

    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<IntersectionPoint>());
    final point = objects.last as IntersectionPoint;
    expect(point.position!.closeTo(const Vec2(2, 0)), isTrue);
  });

  testWidgets('shifted letters pick the shifted variant', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    final tool = activeTool();
    expect(tool, isA<PointAndLineTool>());
    expect(
      (tool as PointAndLineTool).build,
      ParallelLine.new,
      reason: 'plain T is the perpendicular variant',
    );
  });

  testWidgets('⇧G/⇧X toggle grid and axes; the leaders stay chord-only', (
    tester,
  ) async {
    await pumpEditor(tester);
    DocumentSettings settings() => container.read(documentSettingsProvider);
    expect(settings(), const DocumentSettings());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(settings().showGrid, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(settings().showAxes, isTrue);

    // Neither shifted stroke armed its leader: the next letter is the
    // segment tool, not a chord second — and toggling again turns off.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(activeTool(), isA<TwoPointTool>());
    expect(settings(), const DocumentSettings(showAxes: true, showGrid: true));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(settings(), const DocumentSettings());
  });

  testWidgets('Ctrl/⌘ ⇧ G toggles snap to grid without touching the grid', (
    tester,
  ) async {
    await pumpEditor(tester);
    DocumentSettings settings() => container.read(documentSettingsProvider);
    expect(settings(), const DocumentSettings());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(settings(), const DocumentSettings(snapToGrid: true));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(settings(), const DocumentSettings());
  });

  testWidgets('⇧O toggles the trace overlay; a traced drag fills in the '
      'step counts (Phase 116)', (tester) async {
    await pumpEditor(tester);
    expect(find.byType(TraceStatsOverlay), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.byType(TraceStatsOverlay), findsOneWidget);
    expect(find.text('trace: waiting for a traced drag'), findsOneWidget);

    // A smooth free-point drag resolves each frame in one accepted trial.
    final (a, _, _) = buildSmallConstruction();
    final tools = container.read(toolProvider.notifier);
    expect(tools.startDrag(a, Vec2.zero), isTrue);
    tools.updateDrag(const Vec2(1, 1));
    tools.endDrag();
    await tester.pump();
    expect(
      find.text('trace: 1 accepted · 0 rejected · 0 detours'),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.byType(TraceStatsOverlay), findsNothing);
  });

  testWidgets('G leader chords reach constructions', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(activeTool(), isNull, reason: 'leader alone activates nothing');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(activeTool(), isA<TriangleCenterTool>());

    tapWorld(0, 0);
    tapWorld(4, 0);
    tapWorld(0, 3);
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    expect(objects.last, isA<Centroid>());
  });

  testWidgets('a held (auto-repeating) leader still chords', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(activeTool(), isA<TriangleCenterTool>());
  });

  testWidgets('a failed chord swallows the stroke instead of firing it', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    expect(activeTool(), isNull, reason: 'G Q is no chord, Q must not fire');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(activeTool(), isA<PointTool>(), reason: 'table is clean again');
  });

  testWidgets('X leader reaches the macros', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(activeTool(), isA<SquareMacroTool>());
  });

  testWidgets('shifted X chords pick the triangles, unshifted the '
      'quadrilaterals', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    expect(activeTool(), isA<EquilateralTriangleMacroTool>());

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(activeTool(), isA<RightTriangleMacroTool>());

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(
      activeTool(),
      isA<RectangleMacroTool>(),
      reason: 'plain X R still belongs to the rectangle',
    );
  });

  testWidgets('X G asks for the side count; OK activates the '
      'regular-polygon tool, cancel activates nothing', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(find.text('Number of sides'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(activeTool(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = activeTool();
    expect(tool, isA<RegularPolygonMacroTool>());
    expect((tool! as RegularPolygonMacroTool).sideCount, 6);
  });

  testWidgets('X V activates the polygon tool', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    expect(activeTool(), isA<PolygonTool>());
  });

  testWidgets('X digit chords reach the random stamps', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    var tool = activeTool();
    expect(tool, isA<RandomShapeStampTool>());
    var stamp = tool! as RandomShapeStampTool;
    expect(stamp.convex, isFalse, reason: 'X 3 is the jittered triangle');
    expect(stamp.maxVertices, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    tool = activeTool();
    expect(tool, isA<RandomShapeStampTool>());
    stamp = tool! as RandomShapeStampTool;
    expect(stamp.convex, isTrue, reason: 'X 4 is the convex quadrilateral');
    expect(stamp.minVertices, 4);
  });

  testWidgets('G 9 and G ⇧ I activate the triangle-circle tools', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    var tool = activeTool();
    expect(tool, isA<TriangleCircleTool>());
    expect(
      (tool! as TriangleCircleTool).buildCircle,
      NinePointCircle.new,
      reason: 'G 9 is the nine-point circle',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    tool = activeTool();
    expect(tool, isA<TriangleCircleTool>());
    expect(
      (tool! as TriangleCircleTool).buildCircle,
      InscribedCircle.new,
      reason: 'G ⇧ I is the inscribed circle — G I stays the incenter',
    );
  });

  testWidgets('G ⇧ A and G X activate the circle-relation tools', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    final tool = activeTool();
    expect(tool, isA<ThreePointTool>());
    expect(
      (tool! as ThreePointTool).build,
      buildApolloniusCircle,
      reason: 'G ⇧ A is the Apollonius circle — G A stays the arc',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    expect(activeTool(), isA<RadicalAxisTool>());
  });

  testWidgets('G ⇧ P activates the polar-line tool', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      activeTool(),
      isA<PolarLineTool>(),
      reason: 'G ⇧ P is the polar line — G P stays reflect-about-point',
    );
  });

  testWidgets('G 2 activates the circle-by-diameter tool', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    final tool = activeTool();
    expect(tool, isA<TwoPointTool>());
    expect(
      (tool! as TwoPointTool).build,
      buildDiameterCircle,
      reason: 'G 2 pairs with G 3 — two points fix a diameter',
    );
  });

  testWidgets('G 5 activates the five-point conic tool', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    expect(
      activeTool(),
      isA<ConicTool>(),
      reason: 'G 5 joins G 2/G 3/G 9 — the digit is the point count',
    );
  });

  testWidgets('G B, G ⇧E and G ⇧H reach the conic constructors', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    var tool = activeTool();
    expect(tool, isA<FocalConicTool>());
    expect(
      (tool! as FocalConicTool).eccentricity,
      1,
      reason: 'G B is the parabola — the focal conic at e = 1',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    tool = activeTool();
    expect(tool, isA<BifocalConicTool>());
    expect((tool! as BifocalConicTool).difference, isFalse, reason: 'ellipse');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    tool = activeTool();
    expect(tool, isA<BifocalConicTool>());
    expect((tool! as BifocalConicTool).difference, isTrue, reason: 'hyperbola');
  });

  testWidgets('G ⇧C asks for an eccentricity, then arms the focal conic', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1/2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = activeTool();
    expect(tool, isA<FocalConicTool>());
    expect(
      (tool! as FocalConicTool).eccentricity,
      0.5,
      reason: 'the dialog parses expressions, like every numeric dialog',
    );
  });

  testWidgets('G chords reach the transform tools', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    var tool = activeTool();
    expect(tool, isA<TransformObjectTool>());
    expect(
      (tool! as TransformObjectTool).transform,
      ObjectTransform.reflectAboutLine,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    tool = activeTool();
    expect(tool, isA<TransformObjectTool>());
    expect(
      (tool! as TransformObjectTool).transform,
      ObjectTransform.reflectAboutPoint,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    tool = activeTool();
    expect(tool, isA<TransformObjectTool>());
    expect((tool! as TransformObjectTool).transform, ObjectTransform.translate);
  });

  testWidgets('G T asks for the angle; OK in degrees activates the rotate '
      'tool, cancel activates nothing', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(find.text('Rotation angle'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(activeTool(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '-45');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = activeTool();
    expect(tool, isA<TransformObjectTool>());
    expect((tool! as TransformObjectTool).angle, closeTo(-0.7853981, 1e-6));
    expect((tool as TransformObjectTool).transform, ObjectTransform.rotate);
  });

  testWidgets('G D asks for the angle size; OK in degrees activates the '
      'angle-by-size tool, cancel activates nothing', (tester) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.text('Angle size'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(activeTool(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = activeTool();
    expect(tool, isA<AngleBySizeTool>());
    expect((tool! as AngleBySizeTool).angle, closeTo(0.5235987, 1e-6));
  });

  testWidgets('G R asks for the ratio; cancel activates nothing', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(find.text('Segment ratio'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(activeTool(), isNull);
  });

  testWidgets('undo/redo shortcuts, on both primary modifiers', (tester) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    final construction = container.read(constructionProvider).construction;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(construction.length, 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(construction.length, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(construction.length, 2, reason: 'Ctrl+Shift+Z redoes');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(construction.length, 3, reason: 'Ctrl+Y redoes too');

    // An empty redo stack must not throw (the handler gates on canRedo).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(construction.length, 3);
  });

  testWidgets('select all keeps working alongside the H rebinding', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(container.read(selectionProvider), hasLength(3));
  });

  testWidgets('H and Shift+H activate the visibility tool variants', (
    tester,
  ) async {
    await pumpEditor(tester);
    final (a, _, _) = buildSmallConstruction();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    final hide = activeTool();
    expect(hide, isA<VisibilityTool>());
    expect((hide as VisibilityTool).revealsHidden, isFalse);

    container
        .read(toolProvider.notifier)
        .handleInput(ToolInput(Vec2.zero, hit: a));
    expect(a.attributes.visible, isFalse, reason: 'a hide tap hides');
    expect(
      container.read(commandStackProvider).canUndo,
      isTrue,
      reason: 'every visibility tap is a command',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    final showHide = activeTool();
    expect(showHide, isA<VisibilityTool>());
    expect((showHide as VisibilityTool).revealsHidden, isTrue);

    container
        .read(toolProvider.notifier)
        .handleInput(ToolInput(Vec2.zero, hit: a));
    expect(a.attributes.visible, isTrue, reason: 'a Show/Hide tap toggles');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(activeTool(), isNull, reason: 'Esc deactivates like any tool');
  });

  testWidgets('H with a mixed selection hides the visible objects in one '
      'undo step and keeps the selection (Phase 41)', (tester) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(4, 2));
    construction
      ..add(a)
      ..add(b);
    construction.setAttributes('b', const ObjectAttributes(visible: false));
    container.read(selectionProvider.notifier).selectMany(['a', 'b']);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();

    expect(activeTool(), isA<VisibilityTool>());
    expect(a.attributes.visible, isFalse);
    expect(
      container.read(selectionProvider),
      {'a', 'b'},
      reason:
          'hiding keeps the selection — the tree/inspector is the '
          'way back (Phase 7 precedent)',
    );

    container.read(commandStackProvider.notifier).undo();
    expect(a.attributes.visible, isTrue);
    expect(
      b.attributes.visible,
      isFalse,
      reason: 'b was hidden before H and the undo must not reveal it',
    );
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'the whole selection hid in one command',
    );
  });

  testWidgets('H with an empty or all-hidden selection puts nothing on the '
      'undo stack', (tester) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    construction.add(FreePoint(id: 'a', position: Vec2.zero));
    construction.setAttributes('a', const ObjectAttributes(visible: false));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    expect(activeTool(), isA<VisibilityTool>());
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'no selection, nothing to hide',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'an all-hidden selection has nothing to hide',
    );
  });

  testWidgets('Shift+H with a selection performs no on-activation action', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: Vec2.zero);
    construction.add(a);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(activeTool(), isA<VisibilityTool>());
    expect(
      a.attributes.visible,
      isTrue,
      reason:
          'toggling a mixed selection is ambiguous — Show/Hide '
          'only ever acts per tap',
    );
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('H mid-drag with a selection: the drag commit precedes the '
      'hide on the undo stack', (tester) async {
    await pumpEditor(tester);
    final p = FreePoint(id: 'p', position: const Vec2(100, -100));
    container.read(constructionProvider).construction.add(p);
    container.read(selectionProvider.notifier).select('p');
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final gesture = await tester.startGesture(origin + const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(p.position.x, closeTo(160, 1), reason: 'drag preview applied');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(p.attributes.visible, isFalse, reason: 'the selection hid');
    expect(
      p.position.x,
      closeTo(160, 1),
      reason: 'the move survived the tool switch (Phase 30b)',
    );

    container.read(commandStackProvider.notifier).undo();
    expect(p.attributes.visible, isTrue, reason: 'first undo = the hide');
    expect(p.position.x, closeTo(160, 1));

    container.read(commandStackProvider.notifier).undo();
    expect(p.position.x, closeTo(100, 1), reason: 'second undo = the drag');
  });

  testWidgets(
    'Shift+H mid-drag commits the move as one undo step (Phase 30b)',
    (tester) async {
      await pumpEditor(tester);
      final p = FreePoint(id: 'p', position: const Vec2(100, -100));
      container.read(constructionProvider).construction.add(p);
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(GeometryCanvas));
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(p.position.x, closeTo(160, 1), reason: 'drag preview applied');

      // The tool switch arrives while the pointer is still down — the
      // common "shortcut a beat before releasing" case.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(activeTool(), isA<VisibilityTool>());
      expect(
        p.position.x,
        closeTo(160, 1),
        reason: 'the move must survive the tool switch',
      );
      container.read(commandStackProvider.notifier).undo();
      expect(
        p.position.x,
        closeTo(100, 1),
        reason: 'the drag-so-far is one command',
      );
    },
  );

  testWidgets('Esc mid-drag still aborts: preview rolls back, no command', (
    tester,
  ) async {
    await pumpEditor(tester);
    final p = FreePoint(id: 'p', position: const Vec2(100, -100));
    container.read(constructionProvider).construction.add(p);
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final gesture = await tester.startGesture(origin + const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(p.position.x, closeTo(160, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(p.position.x, closeTo(100, 1), reason: 'Esc aborts the drag');
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'an aborted drag leaves nothing to undo',
    );
  });

  testWidgets('Del deletes a self-contained selection without asking', (
    tester,
  ) async {
    await pumpEditor(tester);
    final (a, b, m) = buildSmallConstruction();
    container.read(selectionProvider.notifier).selectMany([a.id, b.id, m.id]);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(container.read(constructionProvider).construction.isEmpty, isTrue);
  });

  testWidgets('Del warns when the cascade reaches beyond the selection', (
    tester,
  ) async {
    await pumpEditor(tester);
    final (a, _, _) = buildSmallConstruction();
    container.read(selectionProvider.notifier).select(a.id);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('Delete dependent objects too?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    final construction = container.read(constructionProvider).construction;
    expect(construction.length, 1, reason: 'a and the midpoint are gone');
    expect(construction.contains('b'), isTrue);
  });

  testWidgets('arrow keys nudge with content semantics, repeating', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    var pan = container.read(viewportProvider).pan;
    expect(
      pan.x,
      lessThan(0),
      reason: '→ moves the drawing right, so the camera looks left',
    );
    expect(pan.y, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    pan = container.read(viewportProvider).pan;
    expect(
      pan.y,
      lessThan(0),
      reason: '↑ moves the drawing up, camera down (world y-up)',
    );
    expect(
      pan.y,
      -2 * 32,
      reason: 'held arrows auto-repeat: one press + one repeat',
    );
  });

  testWidgets('zoom keys: in, out, and back to 100 % about the center', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    expect(container.read(viewportProvider).scale, closeTo(1.2, 1e-12));

    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    expect(container.read(viewportProvider).scale, closeTo(1, 1e-12));

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    expect(container.read(viewportProvider).scale, 1);
  });

  testWidgets('F fits the construction', (tester) async {
    await pumpEditor(tester);
    container
        .read(commandStackProvider.notifier)
        .execute(
          AddObjectCommand(
            FreePoint(id: 'far', position: const Vec2(100, 100)),
          ),
        );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    final viewport = container.read(viewportProvider);
    expect(viewport.scale, 1, reason: 'single point centers at 100 %');
    expect(viewport.pan, isNot(Vec2.zero));
  });

  testWidgets('Ctrl/Cmd+N asks before discarding a construction', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('New construction'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(container.read(constructionProvider).construction.isEmpty, isTrue);
  });

  testWidgets('Ctrl/Cmd+D toggles the theme', (tester) async {
    await pumpEditor(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // The test surface renders light, so the toggle lands on dark.
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('shortcuts stand down while a text field is focused', (
    tester,
  ) async {
    await pumpEditor(tester);
    final (a, _, _) = buildSmallConstruction();
    container.read(selectionProvider.notifier).select(a.id);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(activeTool(), isNull, reason: 'typing a name must not switch tools');

    // Clicking the canvas takes focus back; shortcuts revive.
    await tester.tap(find.byType(GeometryCanvas), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(activeTool(), isA<PointTool>());
  });

  testWidgets('shortcuts revive after committing a rename with Enter', (
    tester,
  ) async {
    await pumpEditor(tester);
    final (a, _, _) = buildSmallConstruction();
    container.read(selectionProvider.notifier).select(a.id);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Q');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(a.attributes.name, 'Q', reason: 'the rename committed');

    // No canvas click in between: leaving the field must hand focus
    // back to the shortcut layer by itself.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(
      activeTool(),
      isA<PointTool>(),
      reason: 'shortcuts must not stay dead after a rename',
    );
  });

  testWidgets('shortcuts revive after leaving the name field unchanged', (
    tester,
  ) async {
    await pumpEditor(tester);
    final (a, _, _) = buildSmallConstruction();
    container.read(selectionProvider.notifier).select(a.id);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(
      activeTool(),
      isA<PointTool>(),
      reason: 'an unchanged commit must also hand focus back',
    );
  });
}
