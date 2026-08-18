import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/preferences_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
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
