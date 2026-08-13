import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/delete_tool.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/panels/attributes_inspector.dart';
import 'package:regula/presentation/panels/object_tree_panel.dart';
import 'package:regula/presentation/panels/toolbar.dart';

/// Phase 47 unified app bar (supersedes the Phase 25/42 compact chrome):
/// one chrome at every window width — tree toggle, title, File, the
/// seven tool groups, view icons, theme, delete, undo/redo — and when
/// the window is narrower than the row, the bar scrolls horizontally in
/// its entirety instead of re-arranging into a compact variant. Panel
/// placement still follows the 600-px shortest-side gate: drawers on
/// phones, docked panels otherwise.
void main() {
  late ProviderContainer container;

  Future<void> pumpEditor(WidgetTester tester, {required Size screen}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
  }

  Finder inAppBar(Finder finder) =>
      find.descendant(of: find.byType(AppBar), matching: finder);

  final barScrollable = find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(Scrollable),
  );

  /// Scrolls the bar until [icon] is on-screen — the unified bar's
  /// equivalent of opening the retired overflow menu.
  Future<void> revealInBar(WidgetTester tester, IconData icon) =>
      tester.scrollUntilVisible(
        inAppBar(find.byIcon(icon)),
        80,
        scrollable: barScrollable,
      );

  group('phone (drawer panels, bar wider than the window)', () {
    const phone = Size(400, 800);

    testWidgets('one chrome: the full wide cluster is in the bar — '
        'no overflow menu, no auto-hamburger', (tester) async {
      await pumpEditor(tester, screen: phone);

      // Every affordance of the wide bar is present (off-screen parts
      // included — the row is one scrollable unit, nothing collapses
      // into a popup).
      expect(
        inAppBar(find.byIcon(Icons.account_tree_outlined)),
        findsOneWidget,
      );
      expect(inAppBar(find.text('regula')), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.folder_outlined)), findsOneWidget);
      expect(inAppBar(find.byType(GeometryToolbar)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.fit_screen)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.filter_center_focus)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.grid_4x4)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.keyboard_outlined)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.dark_mode_outlined)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.delete_outline)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.undo)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.redo)), findsOneWidget);

      // The compact-chrome artifacts are gone.
      expect(inAppBar(find.byIcon(Icons.more_vert)), findsNothing);
      expect(inAppBar(find.byType(DrawerButton)), findsNothing);
      expect(inAppBar(find.byIcon(Icons.menu)), findsNothing);

      // Same row, slim phone height: canvas pixels matter most here.
      expect(tester.getSize(find.byType(AppBar)).height, 48);
    });

    testWidgets('the whole row scrolls: the trailing delete / undo / redo '
        'are reachable and live', (tester) async {
      await pumpEditor(tester, screen: phone);

      final position = tester.state<ScrollableState>(barScrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));

      // Scrolled-to buttons receive taps: open the hide/delete flyout at
      // the far end of the row and activate the delete tool from it.
      await revealInBar(tester, Icons.delete_outline);
      await tester.tap(inAppBar(find.byIcon(Icons.delete_outline)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete objects'));
      await tester.pumpAndSettle();
      expect(container.read(toolProvider).tool, isA<DeleteTool>());

      await revealInBar(tester, Icons.redo);
      expect(inAppBar(find.byIcon(Icons.redo)).hitTestable(), findsOneWidget);
    });

    testWidgets('toolbar flyouts still activate tools', (tester) async {
      await pumpEditor(tester, screen: phone);

      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();

      expect(container.read(toolProvider).tool, isA<PointTool>());
    });

    testWidgets('the tool groups stay reachable on a very narrow window', (
      tester,
    ) async {
      await pumpEditor(tester, screen: const Size(250, 600));

      await revealInBar(tester, Icons.straighten);
      expect(
        inAppBar(find.byIcon(Icons.straighten)).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('the leading tree icon opens the object-tree drawer', (
      tester,
    ) async {
      await pumpEditor(tester, screen: phone);
      expect(find.byType(ObjectTreePanel), findsNothing);

      await tester.tap(inAppBar(find.byIcon(Icons.account_tree_outlined)));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(ObjectTreePanel),
        ),
        findsOneWidget,
      );
    });

    testWidgets('style button appears with the selection and opens the '
        'inspector drawer — never auto-opens', (tester) async {
      await pumpEditor(tester, screen: phone);
      expect(find.byIcon(Icons.palette_outlined), findsNothing);

      container
          .read(constructionProvider)
          .construction
          .add(FreePoint(id: 'a', position: Vec2.zero));
      container.read(selectionProvider.notifier).select('a');
      await tester.pump();

      // Selection made: the button is there, but no drawer opened itself.
      expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);

      await tester.tap(find.byIcon(Icons.palette_outlined));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(AttributesInspector),
        ),
        findsOneWidget,
      );
      expect(find.text('Point'), findsOneWidget);
    });
  });

  group('tablet portrait (docked panels, bar still scrolls)', () {
    // iPad-portrait-ish: shortestSide ≥ 600 keeps the panels docked; the
    // bar is the same row as everywhere and simply scrolls a little.
    const tabletPortrait = Size(810, 1080);

    testWidgets('same bar over docked panels — no drawers, no overflow', (
      tester,
    ) async {
      await pumpEditor(tester, screen: tabletPortrait);

      expect(inAppBar(find.byIcon(Icons.more_vert)), findsNothing);
      expect(inAppBar(find.byIcon(Icons.folder_outlined)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.redo)), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNull);
      expect(scaffold.endDrawer, isNull);
    });

    testWidgets('the leading tree icon is hit-testable and toggles the '
        'docked panel — no overlap, no drawer', (tester) async {
      await pumpEditor(tester, screen: tabletPortrait);
      expect(find.byType(ObjectTreePanel), findsNothing);

      await tester.tap(inAppBar(find.byIcon(Icons.account_tree_outlined)));
      await tester.pumpAndSettle();
      expect(find.byType(ObjectTreePanel), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);

      await tester.tap(inAppBar(find.byIcon(Icons.account_tree_outlined)));
      await tester.pumpAndSettle();
      expect(find.byType(ObjectTreePanel), findsNothing);
    });

    testWidgets('no style button with a selection — the docked inspector '
        'is already visible', (tester) async {
      await pumpEditor(tester, screen: tabletPortrait);

      container
          .read(constructionProvider)
          .construction
          .add(FreePoint(id: 'a', position: Vec2.zero));
      container.read(selectionProvider.notifier).select('a');
      await tester.pump();

      expect(find.byIcon(Icons.palette_outlined), findsNothing);
      expect(find.byType(AttributesInspector), findsOneWidget);
    });
  });

  group('wide (desktop-sized screen)', () {
    testWidgets('everything fits without scrolling and the action cluster '
        'is right-aligned', (tester) async {
      await pumpEditor(tester, screen: const Size(1280, 800));

      final position = tester.state<ScrollableState>(barScrollable).position;
      expect(position.maxScrollExtent, 0);

      expect(inAppBar(find.byIcon(Icons.more_vert)), findsNothing);
      expect(inAppBar(find.byIcon(Icons.folder_outlined)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.fit_screen)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.filter_center_focus)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.keyboard_outlined)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.undo)), findsOneWidget);
      expect(inAppBar(find.byIcon(Icons.redo)), findsOneWidget);

      // The Spacer between the title and the cluster keeps the wide
      // look: tree icon flush left, redo at the right edge.
      expect(
        tester
            .getTopLeft(inAppBar(find.byIcon(Icons.account_tree_outlined)))
            .dx,
        lessThan(40),
      );
      expect(
        tester.getTopRight(inAppBar(find.byIcon(Icons.redo))).dx,
        greaterThan(1200),
      );

      // Panels stay inline: no drawers on desktop. Bar at the Material
      // default height — the slim 48-px variant is phones-only.
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNull);
      expect(scaffold.endDrawer, isNull);
    });

    testWidgets('the leading tree icon toggles the docked panel', (
      tester,
    ) async {
      await pumpEditor(tester, screen: const Size(1280, 800));

      await tester.tap(inAppBar(find.byIcon(Icons.account_tree_outlined)));
      await tester.pumpAndSettle();
      expect(find.byType(ObjectTreePanel), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });
  });
}
