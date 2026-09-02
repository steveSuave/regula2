import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/construction/text_template.dart';
import 'package:regula/domain/math/expression.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/shortcuts/cheat_sheet.dart';
import 'package:regula/presentation/shortcuts/shortcut_table.dart';

import '../../wide_window.dart';

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

  /// `?` — sent as Shift+`/`, the form every keyboard produces; the
  /// table's twin `question` binding covers platforms that report the
  /// shifted logical key directly.
  Future<void> pressQuestionMark(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  testWidgets('? toggles the sheet; every section renders', (tester) async {
    await pumpEditor(tester);
    expect(find.byType(ShortcutCheatSheet), findsNothing);

    await pressQuestionMark(tester);
    expect(find.byType(ShortcutCheatSheet), findsOneWidget);
    for (final section in ShortcutSection.values) {
      expect(find.text(section.title), findsOneWidget);
    }
    // Spot-check a chord row: key text and label side by side.
    expect(find.text('G C'), findsOneWidget);
    expect(find.text('Centroid'), findsOneWidget);

    // `V` is no longer hidden as an Esc twin (Phase 13 discoverability).
    expect(find.text('V'), findsOneWidget);

    // Display-only pointer-gesture rows make panning findable.
    expect(find.text('Space + drag'), findsOneWidget);
    expect(find.text('Scroll'), findsOneWidget);

    // Display-only text-calculation rows document the `{…}` language.
    expect(find.text('dist(A, B)'), findsOneWidget);

    await pressQuestionMark(tester);
    expect(find.byType(ShortcutCheatSheet), findsNothing);
  });

  test('text-calc rows cover the whole expression language', () {
    final rows = [
      for (final row in infoRows)
        if (row.section == ShortcutSection.textCalc)
          '${row.display} ${row.label}',
    ].join('\n');
    for (final name in objectFunctionNames) {
      expect(rows, contains('$name('), reason: "accessor '$name' missing");
    }
    for (final name in numericFunctionNames) {
      expect(rows, contains(name), reason: "function '$name' missing");
    }
    for (final name in constantNames) {
      expect(rows, contains(name), reason: "constant '$name' missing");
    }
  });

  testWidgets('Esc only closes the sheet — the active tool survives', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await pressQuestionMark(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(ShortcutCheatSheet), findsNothing);
    expect(container.read(toolProvider).tool, isA<PointTool>());

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(container.read(toolProvider).tool, isNull);
  });

  testWidgets('a shortcut pressed on the open sheet closes it and fires', (
    tester,
  ) async {
    await pumpEditor(tester);
    await pressQuestionMark(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.byType(ShortcutCheatSheet), findsNothing);
    expect(container.read(toolProvider).tool, isA<PointTool>());
  });

  testWidgets('clicking the barrier dismisses', (tester) async {
    await pumpEditor(tester);
    await pressQuestionMark(tester);

    await tester.tapAt(const Offset(4, 300));
    await tester.pump();
    expect(find.byType(ShortcutCheatSheet), findsNothing);
  });

  testWidgets('the app-bar keyboard button toggles the sheet', (tester) async {
    await pumpEditor(tester);
    final button = find.byTooltip('Keyboard shortcuts (?)');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.byType(ShortcutCheatSheet), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.byType(ShortcutCheatSheet), findsNothing);
  });
}
