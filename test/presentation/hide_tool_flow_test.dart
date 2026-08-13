import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/visibility_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import '../wide_window.dart';

/// The hide flows through the app-bar hide/delete group: its Hide item
/// activates the tap-driven hide [VisibilityTool] through the same path
/// as `H`, so the current selection hides at once (one undo step, still
/// selected) and the tool stays armed for tap-by-tap hiding. The group
/// icon tints while any of its tools is active; double-click or Esc
/// deactivates — the flyout-group precedent.
void main() {
  late ProviderContainer container;
  final group = find.byKey(const ValueKey('hide-delete-group'));

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

  Future<void> activateHide(WidgetTester tester) async {
    await tester.tap(group);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide objects'));
    await tester.pumpAndSettle();
  }

  void addPoint(String id, Vec2 position) {
    container
        .read(constructionProvider)
        .construction
        .add(FreePoint(id: id, position: position));
  }

  bool visible(String id) => container
      .read(constructionProvider)
      .construction
      .byId(id)!
      .attributes
      .visible;

  bool hideActive() => switch (container.read(toolProvider).tool) {
    VisibilityTool(mode: VisibilityMode.hide) => true,
    _ => false,
  };

  Color? groupIconColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color;

  testWidgets('the Hide item activates the tool and tints the group icon; '
      'double-clicking the icon deactivates and touches nothing', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    await tester.pump();

    expect(group, findsOneWidget);
    final theme = Theme.of(tester.element(group));
    expect(groupIconColor(tester), isNot(theme.colorScheme.primary));

    await activateHide(tester);
    expect(hideActive(), isTrue);
    expect(groupIconColor(tester), theme.colorScheme.primary);

    // Double-click the tinted group icon: the tool deactivates and the
    // flyout must not open.
    await tester.tap(group);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(hideActive(), isFalse);
    expect(find.text('Hide objects'), findsNothing, reason: 'no menu opened');
    expect(groupIconColor(tester), isNot(theme.colorScheme.primary));
    expect(visible('a'), isTrue);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'entering and leaving the mode is not an edit',
    );
  });

  testWidgets('Esc leaves hide mode', (tester) async {
    await pumpEditor(tester);
    await activateHide(tester);
    expect(hideActive(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(hideActive(), isFalse);
  });

  testWidgets('activation hides the selection in one undo step, keeps it '
      'selected and the tool active', (tester) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    addPoint('b', const Vec2(4, 0));
    container.read(selectionProvider.notifier).selectMany(['a', 'b']);
    await tester.pump();

    await activateHide(tester);

    expect(visible('a'), isFalse);
    expect(visible('b'), isFalse);
    expect(
      hideActive(),
      isTrue,
      reason: 'the selection hides and the tap tool stays armed',
    );
    expect(
      container.read(selectionProvider),
      containsAll(['a', 'b']),
      reason:
          'hiding keeps the selection — the inspector/tree is the '
          'way back',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(visible('a'), isTrue);
    expect(visible('b'), isTrue);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'the selection rode one command',
    );
  });

  testWidgets('after activation hides the selection, tap-by-tap hiding '
      'keeps working', (tester) async {
    await pumpEditor(tester);
    addPoint('a', const Vec2(100, -200));
    addPoint('b', const Vec2(300, -200));
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await activateHide(tester);
    expect(visible('a'), isFalse);

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(300, 200));
    await tester.pumpAndSettle();
    expect(
      visible('b'),
      isFalse,
      reason: 'the tool stayed active for per-tap hides',
    );
  });

  testWidgets('the Show/Hide item activates the toggle tool without '
      'touching the selection, and the group icon tints for it too', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await tester.tap(group);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Show or hide'));
    await tester.pumpAndSettle();

    final tool = container.read(toolProvider).tool;
    expect(tool, isA<VisibilityTool>());
    expect((tool! as VisibilityTool).mode, VisibilityMode.showHide);
    expect(
      visible('a'),
      isTrue,
      reason: 'Show/Hide has no act-on-selection step',
    );
    expect(container.read(commandStackProvider).canUndo, isFalse);

    final theme = Theme.of(tester.element(group));
    expect(groupIconColor(tester), theme.colorScheme.primary);
  });
}
