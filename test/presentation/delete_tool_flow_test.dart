import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/delete_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';

import '../wide_window.dart';

/// The Phase 41 delete flows, all through the app-bar hide/delete
/// group's Delete item (the inspector's Delete button is gone):
/// selecting it activates the tap-driven [DeleteTool] and deletes the
/// current selection first, through the same cascade confirmation as
/// the Del/Backspace shortcut. Deactivation follows the flyout-group
/// precedent — double-click the group icon, or Esc.
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

  Future<void> activateDelete(WidgetTester tester) async {
    await tester.tap(group);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete objects'));
    await tester.pumpAndSettle();
  }

  FreePoint addPoint(String id, Vec2 position) {
    final point = FreePoint(id: id, position: position);
    container.read(constructionProvider).construction.add(point);
    return point;
  }

  bool has(String id) =>
      container.read(constructionProvider).construction.contains(id);

  bool deleteActive() => container.read(toolProvider).tool is DeleteTool;

  Color? groupIconColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color;

  testWidgets('the Delete item activates the tool and tints the group '
      'icon; double-clicking the icon deactivates and touches nothing', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    await tester.pump();

    expect(group, findsOneWidget);
    final theme = Theme.of(tester.element(group));
    expect(groupIconColor(tester), isNot(theme.colorScheme.primary));

    await activateDelete(tester);
    expect(deleteActive(), isTrue);
    expect(groupIconColor(tester), theme.colorScheme.primary);
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'no selection, nothing to confirm or delete',
    );

    // Double-click the tinted group icon: the tool deactivates and the
    // flyout must not open.
    await tester.tap(group);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(deleteActive(), isFalse);
    expect(find.text('Delete objects'), findsNothing, reason: 'no menu opened');
    expect(groupIconColor(tester), isNot(theme.colorScheme.primary));
    expect(has('a'), isTrue);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'entering and leaving the mode is not an edit',
    );
  });

  testWidgets('Esc leaves delete mode', (tester) async {
    await pumpEditor(tester);
    await activateDelete(tester);
    expect(deleteActive(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(deleteActive(), isFalse);
  });

  testWidgets('delete without dependents: no dialog, one undoable command, '
      'tool stays active', (tester) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await activateDelete(tester);

    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'nothing beyond the selection is affected — no dialog',
    );
    expect(has('a'), isFalse);
    expect(
      deleteActive(),
      isTrue,
      reason: 'the selection deletes and the tap tool stays armed',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(has('a'), isTrue);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'the selection rode one command',
    );
  });

  testWidgets('delete with unselected dependents asks first; Cancel leaves '
      'everything in place but delete mode on', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    container
        .read(constructionProvider)
        .construction
        .add(
          Segment(
            id: 's',
            point1: a,
            point2: b,
            attributes: const ObjectAttributes(name: 'base'),
          ),
        );
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await activateDelete(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('base'),
      findsOneWidget,
      reason: 'the dialog lists the casualties by name',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(has('s'), isTrue);
    expect(
      container.read(commandStackProvider).canUndo,
      isFalse,
      reason: 'a cancelled delete must not touch the undo stack',
    );
    expect(
      deleteActive(),
      isTrue,
      reason:
          'the press asked for delete mode; only the cascade was '
          'declined',
    );
  });

  testWidgets('confirming a cascading delete removes the dependents in the '
      'same undo step', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await activateDelete(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();

    expect(has('a'), isFalse);
    expect(has('s'), isFalse);
    expect(has('b'), isTrue, reason: 'the other endpoint does not depend on a');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(has('a'), isTrue);
    expect(has('s'), isTrue);
  });

  testWidgets('a selection already containing all its dependents deletes '
      'without asking', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(4, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    container.read(selectionProvider.notifier).selectMany(['a', 'b', 's']);
    await tester.pump();

    await activateDelete(tester);

    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'the cascade reaches nothing beyond the selection',
    );
    expect(container.read(constructionProvider).construction.isEmpty, isTrue);
  });

  testWidgets('after activation deletes the selection, tap-by-tap deleting '
      'keeps working', (tester) async {
    await pumpEditor(tester);
    addPoint('a', const Vec2(100, -200));
    addPoint('b', const Vec2(300, -200));
    container.read(selectionProvider.notifier).select('a');
    await tester.pump();

    await activateDelete(tester);
    expect(has('a'), isFalse);

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(300, 200));
    await tester.pumpAndSettle();
    expect(
      has('b'),
      isFalse,
      reason: 'the tool stayed active for per-tap deletes',
    );
  });
}
