import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/preferences_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';
import 'package:regula/presentation/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../wide_window.dart';

/// Phase 126: the geometry menu — the first thing in M-CK a user can see.
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

  /// Two free points and their midpoint, added like real edits — the
  /// midpoint is the witness that the geometry actually changed, its CK
  /// value being 0.5 where the affine one is 0.4.
  void buildMidpoint() {
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(0.8, 0));
    stack
      ..execute(AddObjectCommand(a))
      ..execute(AddObjectCommand(b))
      ..execute(AddObjectCommand(Midpoint(id: 'm', point1: a, point2: b)));
  }

  double midpointX() {
    final construction = container.read(constructionProvider).construction;
    return (construction.byId('m')! as GeoPoint).position!.x;
  }

  FundamentalConic metric() =>
      container.read(constructionProvider).construction.kernel.metric;

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(
      find.byTooltip('Geometry: Euclidean, hyperbolic or elliptic'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('switching redraws the document in the new geometry', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildMidpoint();
    await tester.pump();
    expect(metric(), FundamentalConic.euclidean);
    expect(midpointX(), closeTo(0.4, 1e-12));

    await choose(tester, 'Hyperbolic');

    expect(metric(), FundamentalConic.hyperbolic);
    expect(midpointX(), closeTo(0.5, 1e-12));
  });

  testWidgets('the switch is an edit — undo puts the geometry back', (
    tester,
  ) async {
    // The reason it goes through the command stack rather than a provider
    // toggle: it recomputes every derived object and re-addresses every
    // intersection point, which is an edit by any measure.
    await pumpEditor(tester);
    buildMidpoint();
    await tester.pump();

    await choose(tester, 'Elliptic');
    expect(metric(), FundamentalConic.elliptic);
    final elliptic = midpointX();
    expect(elliptic, isNot(closeTo(0.4, 1e-6)));

    container.read(commandStackProvider.notifier).undo();
    await tester.pump();
    expect(metric(), FundamentalConic.euclidean);
    expect(midpointX(), closeTo(0.4, 1e-12));

    container.read(commandStackProvider.notifier).redo();
    await tester.pump();
    expect(metric(), FundamentalConic.elliptic);
    expect(midpointX(), closeTo(elliptic, 1e-12));
  });

  testWidgets('switching to hyperbolic frames the plane', (tester) async {
    // Without this the mode is present and invisible: the absolute is the
    // unit circle in *world* units and the default scale is one pixel per
    // world unit, so the entire hyperbolic plane was a two-pixel dot at
    // the origin while the figure sat hundreds of units outside it.
    await pumpEditor(tester);
    buildMidpoint();
    await tester.pump();
    expect(container.read(viewportProvider).scale, 1);

    await choose(tester, 'Hyperbolic');

    final scale = container.read(viewportProvider).scale;
    expect(scale, greaterThan(CanvasViewport.maxFitScale));
    // Euclidean and elliptic have no absolute to frame, so they leave the
    // view exactly where the user put it.
    await choose(tester, 'Elliptic');
    expect(container.read(viewportProvider).scale, scale);
  });

  testWidgets('the live canvas gets the theme wash, not the fallback', (
    tester,
  ) async {
    // The gap the contrast test could not see: it hands
    // `absoluteOutsideColor` to the renderer itself, so it proves the
    // colour separates inside from outside and proves nothing about the
    // app ever using that colour. This walks the real widget tree and
    // reads what the painter was actually built with.
    await pumpEditor(tester);
    await choose(tester, 'Hyperbolic');

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<GeometryPainter>()
        .single;
    final expected = AppTheme.light().extension<CanvasColors>()!;
    expect(painter.absoluteOutsideColor, expected.absoluteOutside);
    expect(painter.absoluteColor, expected.absolute);
    expect(painter.construction.kernel.metric, FundamentalConic.hyperbolic);
    // And it is not the constructor fallback that happens to be the same
    // literal — the theme is what supplied it.
    expect(painter.absoluteOutsideColor.a, greaterThan(0.2));
  });

  /// Two Euclidean-concyclic conics that *miss*, plus a point on their
  /// first crossing — the `geometry_switch_test` witness. Both conics are
  /// tier 1, so nothing moves when the geometry changes; only the
  /// numbering does, which is precisely the change a user cannot see and
  /// therefore has to be told about.
  void buildReaddressingPair() {
    final construction = Construction();
    FivePointConic concyclic(String id, Vec2 centre, double radius) {
      final points = [
        for (var i = 0; i < 5; i++)
          FreePoint(
            id: '$id$i',
            position:
                centre +
                Vec2(radius * math.cos(i * 1.1), radius * math.sin(i * 1.1)),
          ),
      ];
      for (final p in points) {
        construction.add(p);
      }
      final conic = FivePointConic(id: id, points: points);
      construction.add(conic);
      return conic;
    }

    final outer = concyclic('a', const Vec2(0, 0), 0.5);
    final inner = concyclic('b', const Vec2(0, 0.02), 0.2);
    construction.add(
      IntersectionPoint(id: 'x', curve1: outer, curve2: inner, branchIndex: 0),
    );
    container.read(constructionProvider.notifier).replace(construction);
  }

  testWidgets('a re-addressing switch tells the user', (tester) async {
    // The switch has reported since Phase 126 and the decoder's identical
    // report has been computed and discarded since Phase 120c; Phase 126e
    // is both of them arriving in the same place. Without this the
    // re-addressing is exactly the kind of correct-value-nobody-sees that
    // Phase 126b-d was four defects of.
    await pumpEditor(tester);
    buildReaddressingPair();
    await tester.pump();

    await choose(tester, 'Hyperbolic');

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(
        'Hyperbolic geometry: 1 intersection point kept its crossing '
        'under a new branch number.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an ordinary switch says nothing', (tester) async {
    // Most of a document keeps its addresses in every geometry, so the
    // usual report is no report. An unconditional notice would be noise
    // and would train the user to dismiss the one that matters.
    await pumpEditor(tester);
    buildMidpoint();
    await tester.pump();

    await choose(tester, 'Hyperbolic');

    expect(metric(), FundamentalConic.hyperbolic);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the current geometry is ticked', (tester) async {
    await pumpEditor(tester);
    await choose(tester, 'Hyperbolic');
    await tester.tap(
      find.byTooltip('Geometry: Euclidean, hyperbolic or elliptic'),
    );
    await tester.pumpAndSettle();
    final checked = tester
        .widgetList<CheckedPopupMenuItem<VoidCallback>>(
          find.byType(CheckedPopupMenuItem<VoidCallback>),
        )
        .where((item) => item.checked)
        .length;
    expect(checked, 1);
  });

  testWidgets('the guide opens and says what to build', (tester) async {
    await pumpEditor(tester);
    await tester.tap(
      find.byTooltip('Geometry: Euclidean, hyperbolic or elliptic'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('What can I do with this?…'));
    await tester.pumpAndSettle();
    expect(find.text('Trying the other geometries'), findsOneWidget);
    expect(find.text('Triangle angle sum'), findsOneWidget);
    expect(find.text('The parallel postulate'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Trying the other geometries'), findsNothing);
  });
}
