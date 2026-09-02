import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/main.dart';

import '../wide_window.dart';

/// The Phase 36 axes/grid popup: checked items over the per-document
/// `DocumentSettings` toggles — its grid-icon popup sits in the unified
/// app bar at every width (Phase 47), scrolled into view on phones.
void main() {
  late ProviderContainer container;

  Future<void> pumpEditor(WidgetTester tester, {Size? screen}) async {
    if (screen != null) {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    } else {
      useWideTestWindow(tester);
    }
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
  }

  DocumentSettings settings() => container.read(documentSettingsProvider);

  /// Taps a popup entry by its label, targeting the whole item — the
  /// bare Text inside a popup item never appears in the hit path (a
  /// ListTile-title quirk), which makes text taps warn on every run.
  Future<void> tapItem(WidgetTester tester, String label) => tester.tap(
    find.widgetWithText(CheckedPopupMenuItem<VoidCallback>, label),
  );

  testWidgets('wide chrome: the grid popup toggles axes and grid', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(settings(), const DocumentSettings());

    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    await tapItem(tester, 'Show grid');
    await tester.pumpAndSettle();
    expect(settings(), const DocumentSettings(showGrid: true));

    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    await tapItem(tester, 'Show axes');
    await tester.pumpAndSettle();
    expect(settings(), const DocumentSettings(showAxes: true, showGrid: true));

    // The menu re-opens with the toggled items checked (snap still off),
    // and tapping unchecks.
    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CheckedPopupMenuItem<VoidCallback>>(
            find.byType(CheckedPopupMenuItem<VoidCallback>),
          )
          .map((item) => item.checked),
      [true, true, false],
    );
    await tapItem(tester, 'Show grid');
    await tester.pumpAndSettle();
    expect(settings(), const DocumentSettings(showAxes: true));
  });

  testWidgets('wide chrome: Snap to grid toggles from the popup', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    await tapItem(tester, 'Snap to grid');
    await tester.pumpAndSettle();
    expect(settings(), const DocumentSettings(snapToGrid: true));

    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    await tapItem(tester, 'Snap to grid');
    await tester.pumpAndSettle();
    expect(settings(), const DocumentSettings());
  });

  testWidgets('phone width: the same popup sits in the scrollable bar', (
    tester,
  ) async {
    await pumpEditor(tester, screen: const Size(400, 800));

    // The unified bar carries the grid popup at every width — scroll it
    // into view instead of reaching for the retired overflow menu.
    await tester.scrollUntilVisible(
      find.byIcon(Icons.grid_4x4),
      80,
      scrollable: find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    await tapItem(tester, 'Show axes');
    await tester.pumpAndSettle();
    expect(settings(), const DocumentSettings(showAxes: true));

    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();
    await tapItem(tester, 'Snap to grid');
    await tester.pumpAndSettle();
    expect(
      settings(),
      const DocumentSettings(showAxes: true, snapToGrid: true),
    );
  });

  testWidgets('the rows show their shortcuts as trailing text, like the '
      'tool flyouts', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.grid_4x4));
    await tester.pumpAndSettle();

    expect(find.text('⇧ X'), findsOneWidget);
    expect(find.text('⇧ G'), findsOneWidget);
    expect(find.text('Ctrl/⌘ ⇧ G'), findsOneWidget);
  });
}
