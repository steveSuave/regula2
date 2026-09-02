import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/commands/set_geometry_command.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/tools/angle_by_size_tool.dart';
import 'package:regula/domain/tools/area_tool.dart';
import 'package:regula/domain/tools/bifocal_conic_tool.dart';
import 'package:regula/domain/tools/conic_tool.dart';
import 'package:regula/domain/tools/distance_tool.dart';
import 'package:regula/domain/tools/equilateral_triangle_macro_tool.dart';
import 'package:regula/domain/tools/fixed_angle_line_tool.dart';
import 'package:regula/domain/tools/fixed_length_segment_tool.dart';
import 'package:regula/domain/tools/fixed_radius_circle_tool.dart';
import 'package:regula/domain/tools/focal_conic_tool.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/isosceles_trapezium_macro_tool.dart';
import 'package:regula/domain/tools/isosceles_triangle_macro_tool.dart';
import 'package:regula/domain/tools/kite_macro_tool.dart';
import 'package:regula/domain/tools/multi_point_tool.dart';
import 'package:regula/domain/tools/name_points_tool.dart';
import 'package:regula/domain/tools/parallelogram_macro_tool.dart';
import 'package:regula/domain/tools/point_and_line_tool.dart';
import 'package:regula/domain/tools/polar_line_tool.dart';
import 'package:regula/domain/tools/polygon_tool.dart';
import 'package:regula/domain/tools/radical_axis_tool.dart';
import 'package:regula/domain/tools/random_shape_stamp_tool.dart';
import 'package:regula/domain/tools/ratio_apollonius_circle_tool.dart';
import 'package:regula/domain/tools/rectangle_macro_tool.dart';
import 'package:regula/domain/tools/regular_polygon_macro_tool.dart';
import 'package:regula/domain/tools/rhombus_macro_tool.dart';
import 'package:regula/domain/tools/right_trapezium_macro_tool.dart';
import 'package:regula/domain/tools/right_triangle_macro_tool.dart';
import 'package:regula/domain/tools/scaled_compass_circle_tool.dart';
import 'package:regula/domain/tools/slope_tool.dart';
import 'package:regula/domain/tools/square_macro_tool.dart';
import 'package:regula/domain/tools/stated_radius_circle_tool.dart';
import 'package:regula/domain/tools/tangent_tool.dart';
import 'package:regula/domain/tools/three_point_tool.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/transform_object_tool.dart';
import 'package:regula/domain/tools/trapezium_macro_tool.dart';
import 'package:regula/domain/tools/triangle_circle_tool.dart';
import 'package:regula/domain/tools/two_point_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/panels/conic_icon.dart';
import 'package:regula/presentation/panels/toolbar.dart';
import 'package:regula/presentation/shortcuts/shortcut_table.dart';
import '../../wide_window.dart';

/// Tests for the toolbar's group flyouts: activation, the active-group
/// highlight (including the segment-ratio closure that no canonicalized
/// tear-off can claim), and the deselect affordances. The double-click
/// deactivation flow itself is covered in `geometry_canvas_test.dart`.
void main() {
  late ProviderContainer container;

  Future<void> pumpEditor(WidgetTester tester) async {
    useWideTestWindow(tester);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
  }

  /// The colour a group's glyph actually paints.
  ///
  /// The active tint arrives through the ambient [IconTheme] rather than
  /// an explicit `color` argument (see `_ToolGroup`), which is how [Icon]
  /// resolves its own colour and is what lets the Conics group's painted
  /// [ConicIcon] tint identically to a font glyph. Reading the widget's
  /// `color` property alone would therefore always see null.
  Color? effectiveColor(WidgetTester tester, Finder finder, Color? own) =>
      own ?? IconTheme.of(tester.element(finder)).color;

  Color? iconColor(WidgetTester tester, IconData icon) {
    final finder = find.byIcon(icon);
    return effectiveColor(tester, finder, tester.widget<Icon>(finder).color);
  }

  Color? conicIconColor(WidgetTester tester) {
    final finder = find.byType(ConicIcon);
    return effectiveColor(
      tester,
      finder,
      tester.widget<ConicIcon>(finder).color,
    );
  }

  testWidgets('picking a flyout item activates its tool and highlights '
      'only that group', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intersection of two curves'));
    await tester.pumpAndSettle();

    expect(container.read(toolProvider).tool, isA<IntersectionTool>());
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.control_point), theme.colorScheme.primary);
    expect(iconColor(tester, Icons.timeline), isNot(theme.colorScheme.primary));
    expect(
      iconColor(tester, Icons.circle_outlined),
      isNot(theme.colorScheme.primary),
    );
  });

  testWidgets('every Conics row activates its tool and highlights Conics, '
      'not Circles (Phase 120b)', (tester) async {
    // The group holds conic-valued kinds only, and each of its tools is
    // its own type — so nothing here may leak into the Circles, Lines or
    // Points catch-alls.
    for (final (label, matcher) in [
      ('Conic through five points', isA<ConicTool>()),
      ('Parabola', isA<FocalConicTool>()),
      ('Ellipse', isA<BifocalConicTool>()),
      ('Hyperbola', isA<BifocalConicTool>()),
    ]) {
      await pumpEditor(tester);
      await tester.tap(find.byType(ConicIcon));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(container.read(toolProvider).tool, matcher, reason: label);
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(
        conicIconColor(tester),
        theme.colorScheme.primary,
        reason: '$label must highlight the Conics group',
      );
      for (final other in const [
        Icons.circle_outlined,
        Icons.timeline,
        Icons.control_point,
      ]) {
        expect(
          iconColor(tester, other),
          isNot(theme.colorScheme.primary),
          reason: '$label must not highlight $other',
        );
      }
    }
  });

  testWidgets('the eccentricity item asks for a ratio; cancel and garbage '
      'activate nothing (Phase 120b)', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byType(ConicIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conic by focus, directrix and eccentricity…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await tester.tap(find.byType(ConicIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conic by focus, directrix and eccentricity…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3/2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<FocalConicTool>());
    expect((tool! as FocalConicTool).eccentricity, 1.5);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(conicIconColor(tester), theme.colorScheme.primary);
  });

  testWidgets('the segment-ratio closure highlights Points, not Lines — '
      'the catch-all for non-tear-off builders', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segment-ratio point…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1/2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(container.read(toolProvider).tool, isA<TwoPointTool>());
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.control_point), theme.colorScheme.primary);
    expect(iconColor(tester, Icons.timeline), isNot(theme.colorScheme.primary));
  });

  testWidgets('the projection row highlights Points, not Lines — the one '
      'PointAndLineTool that builds a point', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projection onto a line'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<PointAndLineTool>());
    expect((tool as PointAndLineTool).build, buildProjectionPoint);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.control_point), theme.colorScheme.primary);
    expect(iconColor(tester, Icons.timeline), isNot(theme.colorScheme.primary));
  });

  testWidgets('the Measure rows activate their tools and highlight the '
      'Measure group — distance is a TwoPointTool the Points catch-all '
      'must not claim', (tester) async {
    await pumpEditor(tester);
    final theme = Theme.of(tester.element(find.byType(AppBar)));

    await tester.tap(find.byIcon(Icons.straighten));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distance'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isA<DistanceTool>());
    expect(iconColor(tester, Icons.straighten), theme.colorScheme.primary);
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
      reason: 'DistanceTool is claimed by Measure, not the Points catch-all',
    );

    await tester.tap(find.byIcon(Icons.straighten));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Area'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isA<AreaTool>());
    expect(iconColor(tester, Icons.straighten), theme.colorScheme.primary);

    await tester.tap(find.byIcon(Icons.straighten));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slope'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isA<SlopeTool>());
    expect(iconColor(tester, Icons.straighten), theme.colorScheme.primary);
  });

  testWidgets('a single tap on the active group icon still opens its menu', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();

    // While active, the ancestor double-tap recognizer holds the tap for
    // its timeout; only after it expires does the tap win and the flyout
    // open (with the tool still active).
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.text('Midpoint or center'), findsOneWidget);
    expect(container.read(toolProvider).tool, isNotNull);
  });

  testWidgets('the active group tooltip advertises double-click to deselect', (
    tester,
  ) async {
    await pumpEditor(tester);
    // Shortcut keys live next to the flyout rows, not in the tooltip.
    const idleTooltip = 'Points: free, derived and constrained points';

    expect(find.byTooltip(idleTooltip), findsOneWidget);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('$idleTooltip — double-click to deselect'),
      findsOneWidget,
    );
    expect(find.byTooltip(idleTooltip), findsNothing);
  });

  testWidgets('every quadrilateral macro activates from the Macros flyout '
      'and highlights the group', (tester) async {
    await pumpEditor(tester);
    final rows = {
      'Rectangle': RectangleMacroTool,
      'Rhombus': RhombusMacroTool,
      'Isosceles trapezium': IsoscelesTrapeziumMacroTool,
      'Right trapezium': RightTrapeziumMacroTool,
      'Kite': KiteMacroTool,
      'Equilateral triangle': EquilateralTriangleMacroTool,
      'Isosceles triangle': IsoscelesTriangleMacroTool,
      'Right triangle': RightTriangleMacroTool,
      'Random triangle': RandomShapeStampTool,
      'Random quadrilateral': RandomShapeStampTool,
    };
    final theme = Theme.of(tester.element(find.byType(AppBar)));

    for (final MapEntry(key: label, value: toolType) in rows.entries) {
      container.read(toolProvider.notifier).deactivate();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      // The grown menu overflows the test screen; later rows scroll in.
      // The open flyout is the last Scrollable — the unified app bar
      // (Phase 47) is one too, so the default lookup is ambiguous.
      await tester.scrollUntilVisible(
        find.text(label),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(container.read(toolProvider).tool.runtimeType, toolType);
      expect(
        iconColor(tester, Icons.crop_square),
        theme.colorScheme.primary,
        reason: '$label must highlight the Macros group',
      );
    }
  });

  testWidgets('every transform tool activates from the Transform flyout and '
      'highlights that group, not Points or Lines', (tester) async {
    await pumpEditor(tester);
    final theme = Theme.of(tester.element(find.byType(AppBar)));

    Future<void> pickTransform(String label) async {
      container.read(toolProvider.notifier).deactivate();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    void expectTransformHighlight(String label) {
      expect(
        iconColor(tester, Icons.flip),
        theme.colorScheme.primary,
        reason: '$label must highlight the Transform group',
      );
      expect(
        iconColor(tester, Icons.control_point),
        isNot(theme.colorScheme.primary),
        reason: '$label must not fall into the Points catch-all',
      );
      expect(
        iconColor(tester, Icons.timeline),
        isNot(theme.colorScheme.primary),
        reason: '$label must not highlight Lines',
      );
    }

    await pickTransform('Reflect about line');
    final reflectTool = container.read(toolProvider).tool;
    expect(reflectTool, isA<TransformObjectTool>());
    expect(
      (reflectTool! as TransformObjectTool).transform,
      ObjectTransform.reflectAboutLine,
    );
    expectTransformHighlight('Reflect about line');

    await pickTransform('Reflect about point');
    final centralTool = container.read(toolProvider).tool;
    expect(centralTool, isA<TransformObjectTool>());
    expect(
      (centralTool! as TransformObjectTool).transform,
      ObjectTransform.reflectAboutPoint,
    );
    expectTransformHighlight('Reflect about point');

    await pickTransform('Translate by vector');
    final translateTool = container.read(toolProvider).tool;
    expect(translateTool, isA<TransformObjectTool>());
    expect(
      (translateTool! as TransformObjectTool).transform,
      ObjectTransform.translate,
    );
    expectTransformHighlight('Translate by vector');
  });

  testWidgets('the rotate item asks for an angle in degrees; cancel '
      'activates nothing', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.flip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate around point…'));
    await tester.pumpAndSettle();
    expect(find.text('Rotation angle'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await tester.tap(find.byIcon(Icons.flip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate around point…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '90');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<TransformObjectTool>());
    expect((tool! as TransformObjectTool).angle, closeTo(1.5707963, 1e-6));
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.flip), theme.colorScheme.primary);
  });

  testWidgets('the dilate item asks for a ratio; OK activates the dilate '
      'transform and highlights Transform, cancel and zero activate '
      'nothing (Phase 68)', (tester) async {
    await pumpEditor(tester);

    Future<void> openDilateDialog() async {
      await tester.tap(find.byIcon(Icons.flip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dilate from point…'));
      await tester.pumpAndSettle();
    }

    await openDilateDialog();
    expect(find.text('Dilation ratio'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await openDilateDialog();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      container.read(toolProvider).tool,
      isNull,
      reason: 'ratio 0 collapses onto the center — reads as cancel',
    );

    await openDilateDialog();
    await tester.enterText(find.byType(TextField), '-3/2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<TransformObjectTool>());
    final dilate = tool! as TransformObjectTool;
    expect(dilate.transform, ObjectTransform.dilate);
    expect(dilate.ratio, -1.5);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.flip), theme.colorScheme.primary);
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
      reason: 'dilate lives in Transform now, not Points',
    );
  });

  testWidgets('dialogs evaluate expressions and show the tool shortcut in '
      'the title (Phase 69)', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.flip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dilate from point…'));
    await tester.pumpAndSettle();
    expect(
      find.text('G H'),
      findsOneWidget,
      reason: 'the dialog title carries the chord',
    );
    await tester.enterText(find.byType(TextField), 'sqrt(2)');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final dilate = container.read(toolProvider).tool! as TransformObjectTool;
    expect(dilate.ratio, closeTo(math.sqrt2, 1e-12));

    container.read(toolProvider.notifier).deactivate();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Circle by radius…'));
    await tester.pumpAndSettle();
    expect(find.text('⇧ C'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'pi');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final circle = container.read(toolProvider).tool! as FixedRadiusCircleTool;
    expect(circle.radius, closeTo(math.pi, 1e-12));
  });

  testWidgets('Points flyout: intersection sits directly below Point, above '
      'Midpoint; the homothetic row is gone (Phase 68)', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();

    expect(
      find.text('Homothetic point…'),
      findsNothing,
      reason: 'retired in favor of the Transform-group dilate',
    );

    final pointY = tester.getTopLeft(find.text('Point')).dy;
    final intersectionY = tester
        .getTopLeft(find.text('Intersection of two curves'))
        .dy;
    final midpointY = tester.getTopLeft(find.text('Midpoint or center')).dy;
    expect(pointY, lessThan(intersectionY));
    expect(
      intersectionY,
      lessThan(midpointY),
      reason: 'row order is Point, Intersection, Midpoint',
    );
    final otherRowBetween =
        [
          'Segment-ratio point…',
          'Projection onto a line',
          'Harmonic conjugate',
          'Centroid',
        ].any((label) {
          final y = tester.getTopLeft(find.textContaining(label).first).dy;
          return y > pointY && y < midpointY;
        });
    expect(
      otherRowBetween,
      isFalse,
      reason: 'nothing else sits between Point and Midpoint',
    );
  });

  test('every row the toolbar disables is one its tool refuses', () {
    // One fact written twice — `euclideanOnlyMacros` for the user and
    // `availableUnder` for the construction — so the two are checked
    // against each other rather than trusted to stay in step.
    final macros = <AppAction, MultiPointTool>{
      AppAction.equilateralTriangleMacroTool: EquilateralTriangleMacroTool(
        newId: () => 'x',
      ),
      AppAction.isoscelesTriangleMacroTool: IsoscelesTriangleMacroTool(
        newId: () => 'x',
      ),
      AppAction.rightTriangleMacroTool: RightTriangleMacroTool(
        newId: () => 'x',
      ),
      AppAction.squareMacroTool: SquareMacroTool(newId: () => 'x'),
      AppAction.rectangleMacroTool: RectangleMacroTool(newId: () => 'x'),
      AppAction.parallelogramMacroTool: ParallelogramMacroTool(
        newId: () => 'x',
      ),
      AppAction.rhombusMacroTool: RhombusMacroTool(newId: () => 'x'),
      AppAction.trapeziumMacroTool: TrapeziumMacroTool(newId: () => 'x'),
      AppAction.isoscelesTrapeziumMacroTool: IsoscelesTrapeziumMacroTool(
        newId: () => 'x',
      ),
      AppAction.rightTrapeziumMacroTool: RightTrapeziumMacroTool(
        newId: () => 'x',
      ),
      AppAction.kiteMacroTool: KiteMacroTool(newId: () => 'x'),
      AppAction.regularPolygonMacroTool: RegularPolygonMacroTool(
        newId: () => 'x',
        sideCount: 5,
      ),
    };

    expect({
      for (final entry in macros.entries)
        if (!entry.value.availableUnder(Absolute.hyperbolic)) entry.key,
    }, euclideanOnlyMacros.keys.toSet());
  });

  test('every constant row the toolbar disables is one its tool refuses', () {
    // The Phase 184 twin of the macro check above: `euclideanOnlyConstants`
    // for the user, the tools' own refusal for the construction.
    final constants = <AppAction, bool Function()>{
      AppAction.fixedAngleLineTool: () =>
          FixedAngleLineTool(
                newId: () => 'x',
                turn: Rational.fromInts(1, 3),
              ).onInput(
                const ToolInput(Vec2(1, 1), absolute: Absolute.hyperbolic),
              )
              is ToolIgnored,
      AppAction.statedRadiusCircleTool: () => !StatedRadiusCircleTool(
        newId: () => 'x',
        radius: Rational.one,
      ).availableUnder(Absolute.hyperbolic),
      AppAction.scaledCompassCircleTool: () => !ScaledCompassCircleTool(
        newId: () => 'x',
        factor: Rational.whole(2),
      ).availableUnder(Absolute.hyperbolic),
      AppAction.ratioApolloniusCircleTool: () => !RatioApolloniusCircleTool(
        newId: () => 'x',
        ratio: Rational.whole(2),
      ).availableUnder(Absolute.hyperbolic),
    };
    expect({
      for (final entry in constants.entries)
        if (entry.value()) entry.key,
    }, euclideanOnlyConstants.keys.toSet());
  });

  testWidgets('the stated-angle item asks in degrees and keeps the residue; '
      'the stated-radius item refuses an irrational', (tester) async {
    await pumpEditor(tester);
    final theme = Theme.of(tester.element(find.byType(AppBar)));

    Future<void> pickStatedAngle() async {
      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Line at a stated angle…'));
      await tester.pumpAndSettle();
    }

    await pickStatedAngle();
    expect(find.text('Stated angle'), findsOneWidget);
    expect(
      find.text('G ⇧ D'),
      findsOneWidget,
      reason: 'the title carries the chord',
    );
    await tester.enterText(find.byType(TextField), 'pi/3');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      container.read(toolProvider).tool,
      isNull,
      reason: 'the exact dialog reads an expression as cancel, never rounds',
    );

    await pickStatedAngle();
    await tester.enterText(find.byType(TextField), '-120');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final line = container.read(toolProvider).tool;
    expect(line, isA<FixedAngleLineTool>());
    expect(
      (line! as FixedAngleLineTool).turn,
      Rational.fromInts(1, 3),
      reason: '−120° is the 60° line: degrees over 180, reduced mod 1',
    );
    expect(
      iconColor(tester, Icons.timeline),
      theme.colorScheme.primary,
      reason: 'FixedAngleLineTool must highlight the Lines group',
    );

    container.read(toolProvider.notifier).deactivate();
    await tester.pump();

    Future<void> pickStatedRadius() async {
      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Circle with stated radius…'));
      await tester.pumpAndSettle();
    }

    await pickStatedRadius();
    expect(find.text('Stated radius'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sqrt(2)');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await pickStatedRadius();
    await tester.enterText(find.byType(TextField), '-2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull, reason: 'positive only');

    await pickStatedRadius();
    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final circle = container.read(toolProvider).tool;
    expect(circle, isA<StatedRadiusCircleTool>());
    expect((circle! as StatedRadiusCircleTool).radius, Rational.fromInts(5, 2));
    expect(
      iconColor(tester, Icons.circle_outlined),
      theme.colorScheme.primary,
      reason: 'StatedRadiusCircleTool must highlight the Circles group',
    );
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
    );
  });

  testWidgets('the compass-scale and Apollonius-ratio items ask, and 1 is '
      'accepted by both', (tester) async {
    await pumpEditor(tester);

    Future<void> pickCircleItem(String name) async {
      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    await pickCircleItem('Compass scaled by a stated ratio…');
    expect(find.text('Compass scale'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '3/2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final compass = container.read(toolProvider).tool;
    expect(compass, isA<ScaledCompassCircleTool>());
    expect(
      (compass! as ScaledCompassCircleTool).factor,
      Rational.fromInts(3, 2),
    );

    container.read(toolProvider.notifier).deactivate();
    await tester.pump();
    await pickCircleItem('Apollonius circle with stated ratio…');
    expect(find.text('Apollonius ratio'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final apollonius = container.read(toolProvider).tool;
    expect(apollonius, isA<RatioApolloniusCircleTool>());
    expect(
      (apollonius! as RatioApolloniusCircleTool).ratio,
      Rational.one,
      reason: 'ratio 1 is a legal ask — the tool builds the bisector for it',
    );
  });

  testWidgets('the constant rows are disabled in a curved plane, with the '
      'reason where the explanation was', (tester) async {
    await pumpEditor(tester);

    Future<Map<String, bool>> rowsOf(IconData icon) async {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      final rows = <String, bool>{};
      for (final element in find.byType(ToolMenuRow).evaluate()) {
        final row = element.widget as ToolMenuRow;
        final item = element
            .findAncestorWidgetOfExactType<PopupMenuItem<ToolPick>>()!;
        rows[row.label] = item.enabled;
      }
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      return rows;
    }

    expect(
      (await rowsOf(
        Icons.timeline,
      ))['Line at a stated angle (point, then reference line)…'],
      isTrue,
    );

    container
        .read(commandStackProvider.notifier)
        .execute(
          SetGeometryCommand(
            const DocumentKernel(metric: FundamentalConic.hyperbolic),
          ),
        );
    await tester.pumpAndSettle();

    final lines = await rowsOf(Icons.timeline);
    expect(
      lines['Line at a stated angle (a stated angle is Euclidean)'],
      isFalse,
    );
    expect(
      lines['Perpendicular line'],
      isTrue,
      reason: 'only the constant rows',
    );
    final circles = await rowsOf(Icons.circle_outlined);
    expect(
      circles['Circle with stated radius (a stated length is Euclidean)'],
      isFalse,
    );
    expect(
      circles['Compass scaled by a stated ratio (a stated ratio is Euclidean)'],
      isFalse,
    );
    expect(
      circles['Apollonius circle with stated ratio (a stated ratio is Euclidean)'],
      isFalse,
    );
    expect(
      circles.entries.where((row) => !row.value).length,
      3,
      reason: 'the float circle-by-radius row and the rest stay enabled',
    );
  });

  testWidgets('the macros a curved plane has no figure for are disabled, '
      'with the reason where the explanation was', (tester) async {
    await pumpEditor(tester);

    Future<Map<String, bool>> macroRows() async {
      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      final rows = <String, bool>{};
      for (final element in find.byType(ToolMenuRow).evaluate()) {
        final row = element.widget as ToolMenuRow;
        final item = element
            .findAncestorWidgetOfExactType<PopupMenuItem<ToolPick>>()!;
        rows[row.label] = item.enabled;
      }
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      return rows;
    }

    final euclidean = await macroRows();
    expect(euclidean['Rectangle (two corners, then height)'], isTrue);
    expect(euclidean.values.every((enabled) => enabled), isTrue);

    container
        .read(commandStackProvider.notifier)
        .execute(
          SetGeometryCommand(
            const DocumentKernel(metric: FundamentalConic.hyperbolic),
          ),
        );
    await tester.pumpAndSettle();

    final hyperbolic = await macroRows();
    expect(
      hyperbolic['Rectangle (no four right angles outside Euclid)'],
      isFalse,
      reason: 'the row still names its tool, and says why it is out',
    );
    expect(
      hyperbolic['Rhombus (two corners, then direction)'],
      isTrue,
      reason:
          'a gap rather than an impossibility, and Phase 138 closed it — '
          'the row keeps its ordinary label',
    );
    expect(
      hyperbolic['Kite (apex, side corner, apex)'],
      isTrue,
      reason: 'a kite is a reflection symmetry, which every geometry has',
    );
    expect(
      hyperbolic.entries.where((row) => !row.value).length,
      euclideanOnlyMacros.length,
    );
  });

  testWidgets('the regular-polygon item says what its two taps mean, and '
      "the document's geometry decides", (tester) async {
    await pumpEditor(tester);

    Future<String> subtitle() async {
      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Regular polygon…'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      final row = tester.widget<ToolMenuRow>(
        find.ancestor(
          of: find.text('Regular polygon…'),
          matching: find.byType(ToolMenuRow),
        ),
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      return row.label;
    }

    expect(await subtitle(), contains('two corners'));

    container
        .read(commandStackProvider.notifier)
        .execute(
          SetGeometryCommand(
            const DocumentKernel(metric: FundamentalConic.hyperbolic),
          ),
        );
    await tester.pumpAndSettle();

    expect(
      await subtitle(),
      contains('centre, then a corner'),
      reason:
          'the same gesture builds an orbit rather than a chain in a '
          'proper geometry (Phase 128), and the label is the only place '
          'that says so',
    );
  });

  testWidgets('the regular-polygon item asks for the side count; cancel '
      'activates nothing', (tester) async {
    await pumpEditor(tester);

    Future<void> pickPolygon() async {
      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      // Last Scrollable: the open flyout, not the scrollable app bar.
      await tester.scrollUntilVisible(
        find.text('Regular polygon…'),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Regular polygon…'));
      await tester.pumpAndSettle();
    }

    await pickPolygon();
    expect(find.text('Number of sides'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await pickPolygon();
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      container.read(toolProvider).tool,
      isNull,
      reason: 'an out-of-range count reads as cancel',
    );

    await pickPolygon();
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final tool = container.read(toolProvider).tool;
    expect(tool, isA<RegularPolygonMacroTool>());
    expect((tool! as RegularPolygonMacroTool).sideCount, 5);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.crop_square), theme.colorScheme.primary);
  });

  testWidgets('the angle-by-size item asks for a size in degrees; cancel '
      'activates nothing', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.square_foot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angle by given size…'));
    await tester.pumpAndSettle();
    expect(find.text('Angle size'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await tester.tap(find.byIcon(Icons.square_foot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angle by given size…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '60');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<AngleBySizeTool>());
    expect((tool! as AngleBySizeTool).angle, closeTo(1.0471975, 1e-6));
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(
      iconColor(tester, Icons.square_foot),
      theme.colorScheme.primary,
      reason: 'AngleBySizeTool must highlight the Angles group',
    );
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
      reason: 'it must not fall into the Points catch-all',
    );
  });

  testWidgets('the circle-by-radius item asks for a radius; cancel and '
      'garbage activate nothing', (tester) async {
    await pumpEditor(tester);

    Future<void> pickCircleByRadius() async {
      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Circle by radius…'));
      await tester.pumpAndSettle();
    }

    await pickCircleByRadius();
    expect(find.text('Circle radius'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);

    await pickCircleByRadius();
    await tester.enterText(find.byType(TextField), '-2');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      container.read(toolProvider).tool,
      isNull,
      reason: 'a non-positive radius reads as cancel',
    );

    await pickCircleByRadius();
    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final tool = container.read(toolProvider).tool;
    expect(tool, isA<FixedRadiusCircleTool>());
    expect((tool! as FixedRadiusCircleTool).radius, 2.5);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(
      iconColor(tester, Icons.circle_outlined),
      theme.colorScheme.primary,
      reason: 'FixedRadiusCircleTool must highlight the Circles group',
    );
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
      reason: 'it must not fall into the Points catch-all',
    );
  });

  testWidgets('the segment-by-length item asks for a length and '
      'highlights Lines', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segment with given length…'));
    await tester.pumpAndSettle();
    expect(find.text('Segment length'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<FixedLengthSegmentTool>());
    expect((tool! as FixedLengthSegmentTool).length, 3);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(
      iconColor(tester, Icons.timeline),
      theme.colorScheme.primary,
      reason: 'FixedLengthSegmentTool must highlight the Lines group',
    );
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
      reason: 'it must not fall into the Points catch-all',
    );
  });

  testWidgets('perpendicular bisector, tangent and polygon rows activate from '
      'the Lines flyout and highlight Lines, not Points', (tester) async {
    await pumpEditor(tester);
    final theme = Theme.of(tester.element(find.byType(AppBar)));

    Future<void> pickLinesRow(String label) async {
      container.read(toolProvider.notifier).deactivate();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();
      // Last Scrollable: the open flyout, not the scrollable app bar.
      await tester.scrollUntilVisible(
        find.text(label),
        50,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    void expectLinesHighlight(String label) {
      expect(
        iconColor(tester, Icons.timeline),
        theme.colorScheme.primary,
        reason: '$label must highlight the Lines group',
      );
      expect(
        iconColor(tester, Icons.control_point),
        isNot(theme.colorScheme.primary),
        reason: '$label must not fall into the Points catch-all',
      );
    }

    await pickLinesRow('Perpendicular bisector');
    expect(container.read(toolProvider).tool, isA<TwoPointTool>());
    expectLinesHighlight('Perpendicular bisector');

    await pickLinesRow('Tangents from point');
    expect(container.read(toolProvider).tool, isA<TangentTool>());
    expectLinesHighlight('Tangents from point');

    await pickLinesRow('Polygon');
    expect(container.read(toolProvider).tool, isA<PolygonTool>());
    expectLinesHighlight('Polygon');
  });

  group('name-points dialog (Phase 53)', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.text_fields));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name points in sequence…'));
      await tester.pumpAndSettle();
    }

    testWidgets('empty input activates the plain alphabet and tints the '
        'group — not the Points group', (tester) async {
      await pumpEditor(tester);
      await openDialog(tester);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final tool = container.read(toolProvider).tool;
      expect(tool, isA<NamePointsTool>());
      expect((tool! as NamePointsTool).startLetter, 'A');
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(iconColor(tester, Icons.text_fields), theme.colorScheme.primary);
      expect(
        iconColor(tester, Icons.control_point),
        isNot(theme.colorScheme.primary),
        reason:
            'the tool lives in the text & labels group, not the '
            'Points catch-all',
      );
    });

    testWidgets('double-clicking the active group deselects without '
        'opening the menu or the dialog', (tester) async {
      await pumpEditor(tester);
      await openDialog(tester);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(container.read(toolProvider).tool, isA<NamePointsTool>());

      await tester.tap(find.byIcon(Icons.text_fields));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.byIcon(Icons.text_fields));
      await tester.pumpAndSettle();

      expect(container.read(toolProvider).tool, isNull);
      expect(
        find.text('Name points in sequence…'),
        findsNothing,
        reason: 'no menu opened',
      );
      expect(find.text('OK'), findsNothing, reason: 'no dialog opened');
    });

    testWidgets('a single letter starts the alphabet there, case respected', (
      tester,
    ) async {
      await pumpEditor(tester);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'm');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final tool = container.read(toolProvider).tool;
      expect((tool! as NamePointsTool).startLetter, 'm');
    });

    testWidgets('a word activates string mode', (tester) async {
      await pumpEditor(tester);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'MID');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final tool = container.read(toolProvider).tool;
      expect((tool! as NamePointsTool).letters, 'MID');
    });

    testWidgets('repeated characters keep the dialog open with an inline '
        'error; fixing the input clears it', (tester) async {
      await pumpEditor(tester);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'MOM');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('only once'), findsOneWidget);
      expect(
        container.read(toolProvider).tool,
        isNull,
        reason: 'invalid input must not activate anything',
      );

      await tester.enterText(find.byType(TextField), 'MID');
      await tester.pump();
      expect(
        find.textContaining('only once'),
        findsNothing,
        reason: 'editing clears the error',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(container.read(toolProvider).tool, isA<NamePointsTool>());
    });

    testWidgets('cancel leaves the current tool untouched', (tester) async {
      await pumpEditor(tester);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'MID');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(toolProvider).tool, isNull);
    });
  });

  testWidgets('the Move button is highlighted while no tool is active and '
      'a single tap deactivates the active tool — the touch-friendly '
      'alternative to double-tap/Esc', (tester) async {
    await pumpEditor(tester);
    final theme = Theme.of(tester.element(find.byType(AppBar)));

    // Move/select is the default mode: only the Move button is tinted.
    expect(iconColor(tester, Icons.near_me), theme.colorScheme.primary);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNotNull);
    expect(iconColor(tester, Icons.near_me), isNot(theme.colorScheme.primary));
    expect(iconColor(tester, Icons.control_point), theme.colorScheme.primary);

    // One tap — no double-tap, no Esc — returns to move/select.
    await tester.tap(find.byIcon(Icons.near_me));
    await tester.pumpAndSettle();
    expect(container.read(toolProvider).tool, isNull);
    expect(iconColor(tester, Icons.near_me), theme.colorScheme.primary);
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
    );
  });

  testWidgets('the nine-point-circle row activates its tool and highlights '
      'Circles', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    // Parenthetical labels split into two Texts — target the name only.
    await tester.tap(find.text('Nine-point circle'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<TriangleCircleTool>());
    expect((tool! as TriangleCircleTool).buildCircle, NinePointCircle.new);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.circle_outlined), theme.colorScheme.primary);
  });

  testWidgets('the inscribed-circle row activates its tool and highlights '
      'Circles', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inscribed circle'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<TriangleCircleTool>());
    expect((tool! as TriangleCircleTool).buildCircle, InscribedCircle.new);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.circle_outlined), theme.colorScheme.primary);
  });

  testWidgets('the Apollonius-circle row activates its tool and highlights '
      'Circles', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apollonius circle'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<ThreePointTool>());
    expect((tool! as ThreePointTool).build, buildApolloniusCircle);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.circle_outlined), theme.colorScheme.primary);
  });

  testWidgets('the polar-line row activates its tool and highlights Lines', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polar line'));
    await tester.pumpAndSettle();

    expect(container.read(toolProvider).tool, isA<PolarLineTool>());
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.timeline), theme.colorScheme.primary);
    expect(
      iconColor(tester, Icons.circle_outlined),
      isNot(theme.colorScheme.primary),
    );
  });

  testWidgets('Lines flyout: Polar line sits below Tangents, above '
      'Radical axis (Phase 71)', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();

    final tangentsY = tester.getTopLeft(find.text('Tangents from point')).dy;
    final polarY = tester.getTopLeft(find.text('Polar line')).dy;
    final radicalAxisY = tester.getTopLeft(find.text('Radical axis')).dy;
    expect(
      tangentsY,
      lessThan(polarY),
      reason: 'the two point-and-circle tools stay adjacent',
    );
    expect(polarY, lessThan(radicalAxisY));
  });

  testWidgets('the radical-axis row activates its tool and highlights Lines', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radical axis'));
    await tester.pumpAndSettle();

    expect(container.read(toolProvider).tool, isA<RadicalAxisTool>());
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.timeline), theme.colorScheme.primary);
    expect(
      iconColor(tester, Icons.circle_outlined),
      isNot(theme.colorScheme.primary),
    );
  });

  testWidgets('the circle-by-diameter row activates its tool and highlights '
      'Circles, not Points', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Circle by diameter'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<TwoPointTool>());
    expect((tool! as TwoPointTool).build, buildDiameterCircle);
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    expect(iconColor(tester, Icons.circle_outlined), theme.colorScheme.primary);
    expect(
      iconColor(tester, Icons.control_point),
      isNot(theme.colorScheme.primary),
      reason:
          'a two-point circle builder must not fall into the Points '
          'catch-all',
    );
  });

  testWidgets('Lines flyout: Radical axis sits above Polygon (Phase 70)', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();

    final radicalAxisY = tester.getTopLeft(find.text('Radical axis')).dy;
    final polygonY = tester.getTopLeft(find.text('Polygon')).dy;
    expect(radicalAxisY, lessThan(polygonY));
  });

  testWidgets('flyout rows show their shortcut as trailing text', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();

    // Each Lines row pairs its label with the table's display string.
    expect(find.text('Segment'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('Perpendicular line'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('Angle bisector'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });
}
