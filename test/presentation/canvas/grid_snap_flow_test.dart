import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';

import '../../wide_window.dart';

/// End-to-end snap-to-grid (Phase 45): with the document toggle on, the
/// canvas supplies the drawn grid's adaptive step to the tools and the
/// drag sessions — free-point taps and drags land exactly on grid
/// crossings; with it off, everything is byte-identical to before.
///
/// The editor launches with the world origin at the canvas top-left at
/// scale 1, where the adaptive grid step is 50 (48 px minimum spacing).
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

  void snapOn() =>
      container.read(documentSettingsProvider.notifier).toggleSnapToGrid();

  void activatePointTool() {
    var next = 0;
    container
        .read(toolProvider.notifier)
        .activate(PointTool(newId: () => 'p${next++}'));
  }

  List<FreePoint> freePoints() => container
      .read(constructionProvider)
      .construction
      .objects
      .whereType<FreePoint>()
      .toList();

  testWidgets('a snapped tap lands the free point on a grid crossing', (
    tester,
  ) async {
    await pumpEditor(tester);
    snapOn();
    activatePointTool();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tapAt(origin + const Offset(203, 127));
    await tester.pump();

    expect(
      freePoints().single.position,
      const Vec2(200, -150),
      reason: 'world (203, −127) quantizes to the step-50 grid',
    );
  });

  testWidgets('the snap step follows the zoom level', (tester) async {
    await pumpEditor(tester);
    snapOn();
    // At scale 4 the adaptive step is 20 (48 px / 4 = 12 world units →
    // next {1,2,5}×10^k is 20).
    container
        .read(viewportProvider.notifier)
        .set(const ViewportState(scale: 4));
    activatePointTool();
    // The tap handler reads the viewport captured at build time — let the
    // canvas rebuild with the zoomed one first.
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tapAt(origin + const Offset(150, 90));
    await tester.pump();

    expect(
      freePoints().single.position,
      const Vec2(40, -20),
      reason: 'world (37.5, −22.5) quantizes to the step-20 grid',
    );
  });

  testWidgets('with the toggle off a tap is byte-identical to before', (
    tester,
  ) async {
    await pumpEditor(tester);
    activatePointTool();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tapAt(origin + const Offset(203, 127));
    await tester.pump();

    expect(freePoints().single.position, const Vec2(203, -127));
  });

  testWidgets('a snapped free-point drag previews on crossings and commits one '
      'undoable move', (tester) async {
    await pumpEditor(tester);
    snapOn();
    activatePointTool();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(200, 150)); // on-grid already
    await tester.pump();
    container.read(toolProvider.notifier).deactivate();
    await tester.pump();
    FreePoint point() => freePoints().single;
    expect(point().position, const Vec2(200, -150));

    final drag = await tester.startGesture(origin + const Offset(200, 150));
    await drag.moveTo(origin + const Offset(263, 216));
    await tester.pump();
    expect(
      point().position,
      const Vec2(250, -200),
      reason: 'the preview frame lands on a crossing, not at the pointer',
    );
    await drag.up();
    await tester.pump();
    expect(point().position, const Vec2(250, -200));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      point().position,
      const Vec2(200, -150),
      reason: 'the whole snapped gesture is one undo unit',
    );
    expect(
      container.read(commandStackProvider).canUndo,
      isTrue,
      reason: 'only the tap-created point remains on the stack',
    );
  });

  testWidgets('a rigid drag does not snap even with the toggle on', (
    tester,
  ) async {
    await pumpEditor(tester);
    snapOn();
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: const Vec2(100, -100));
    final b = FreePoint(id: 'b', position: const Vec2(300, -100));
    construction
      ..add(a)
      ..add(b)
      ..add(Segment(id: 's', point1: a, point2: b));
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // The move must clear the gesture slop and land off-grid.
    final drag = await tester.startGesture(origin + const Offset(200, 100));
    await drag.moveTo(origin + const Offset(233, 141));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(
      a.position,
      const Vec2(133, -141),
      reason: 'rigid translations move by the raw delta',
    );
    expect(b.position, const Vec2(333, -141));
  });
}
