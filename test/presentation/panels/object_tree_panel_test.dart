import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/panels/attributes_inspector.dart';
import 'package:regula/presentation/panels/object_tree_panel.dart';
import '../../wide_window.dart';

void main() {
  late ProviderContainer container;

  /// The full editor, so the tree is reached the way the user reaches it:
  /// through the app-bar toggle.
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

  Future<void> openTree(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Show object tree'));
    await tester.pump();
  }

  /// Groups start folded; tests that need rows opt into them the way the
  /// user does, through the header chevron.
  Future<void> expandGroup(WidgetTester tester, String lowerLabel) async {
    await tester.tap(find.byTooltip('Expand $lowerLabel'));
    await tester.pump();
  }

  FreePoint addPoint(String id, Vec2 position) {
    final point = FreePoint(id: id, position: position);
    container.read(constructionProvider).construction.add(point);
    return point;
  }

  testWidgets('hidden by default; the app-bar toggle shows and hides it', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.byType(ObjectTreePanel), findsNothing);

    await openTree(tester);
    expect(find.byType(ObjectTreePanel), findsOneWidget);
    expect(find.text('No objects yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide object tree'));
    await tester.pump();
    expect(find.byType(ObjectTreePanel), findsNothing);
  });

  testWidgets('groups objects by kind, names win over kind labels', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A'),
    );
    container.read(constructionProvider).construction.add(a);
    final b = addPoint('b', const Vec2(2, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('Points')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('Lines')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('Circles')),
      findsNothing,
      reason: 'empty groups are skipped',
    );
    await expandGroup(tester, 'points');
    await expandGroup(tester, 'lines');
    // Named point: name as title, kind as subtitle. Unnamed: kind only.
    expect(find.descendant(of: tree, matching: find.text('A')), findsOneWidget);
    expect(
      find.descendant(of: tree, matching: find.text('Segment')),
      findsOneWidget,
    );
  });

  testWidgets('text objects land in a Texts group (regression: missing '
      'bucket threw and greyed the panel)', (tester) async {
    await pumpEditor(tester);
    container
        .read(constructionProvider)
        .construction
        .add(
          ExpressionText(
            id: 't',
            content: 'note',
            anchor: Vec2.zero,
            references: const [],
          ),
        );
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('Texts')),
      findsOneWidget,
    );
    await expandGroup(tester, 'texts');
    expect(
      find.descendant(of: tree, matching: find.text('Text')),
      findsOneWidget,
    );
  });

  testWidgets('tap selects exactly that object; shift-tap toggles', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(2, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    await openTree(tester);
    await expandGroup(tester, 'points');
    await expandGroup(tester, 'lines');

    final tree = find.byType(ObjectTreePanel);
    await tester.tap(find.descendant(of: tree, matching: find.text('Segment')));
    await tester.pump();
    expect(container.read(selectionProvider), {'s'});

    // Plain tap replaces the selection...
    final pointRows = find.descendant(of: tree, matching: find.text('Point'));
    await tester.tap(pointRows.first);
    await tester.pump();
    expect(container.read(selectionProvider), {'a'});

    // ...shift-tap unions, and shift-tapping again removes.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(pointRows.last);
    await tester.pump();
    expect(container.read(selectionProvider), {'a', 'b'});
    await tester.tap(pointRows.first);
    await tester.pump();
    expect(container.read(selectionProvider), {'b'});
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('header tap selects every object of the kind, hidden included', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final hidden = FreePoint(
      id: 'h',
      position: const Vec2(1, 1),
      attributes: const ObjectAttributes(visible: false),
    );
    container.read(constructionProvider).construction.add(hidden);
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: hidden));
    container.read(selectionProvider.notifier).select('s');
    await openTree(tester);

    expect(find.byTooltip('Select all points'), findsOneWidget);
    final tree = find.byType(ObjectTreePanel);
    await tester.tap(find.descendant(of: tree, matching: find.text('Points')));
    await tester.pump();
    expect(
      container.read(selectionProvider),
      {'a', 'h'},
      reason:
          'replaces the selection with exactly the kind, hidden and '
          'all — reaching hidden objects is the tree\'s raison d\'être',
    );
  });

  testWidgets('header shift-tap and long-press union with a cross-kind '
      'selection', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(2, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    container.read(selectionProvider.notifier).select('s');
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    final header = find.descendant(of: tree, matching: find.text('Points'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(header);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(container.read(selectionProvider), {'s', 'a', 'b'});

    // Long-press is the touch shift: it also unions, never replaces.
    container.read(selectionProvider.notifier).select('s');
    await tester.longPress(header);
    await tester.pump();
    expect(container.read(selectionProvider), {'s', 'a', 'b'});
  });

  testWidgets('eye toggle hides as one undoable command and shows again', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    await openTree(tester);
    await expandGroup(tester, 'points');

    await tester.tap(find.byTooltip('Hide'));
    await tester.pump();
    expect(a.attributes.visible, isFalse);
    expect(container.read(commandStackProvider).canUndo, isTrue);

    // The hidden object is unreachable on the canvas; the tree's eye is
    // the one-tap way back.
    await tester.tap(find.byTooltip('Show'));
    await tester.pump();
    expect(a.attributes.visible, isTrue);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      a.attributes.visible,
      isFalse,
      reason: 'each eye tap is its own undo step',
    );
  });

  testWidgets('a hidden object selected from the tree reaches the inspector', (
    tester,
  ) async {
    await pumpEditor(tester);
    final hidden = FreePoint(
      id: 'h',
      position: Vec2.zero,
      attributes: const ObjectAttributes(visible: false),
    );
    container.read(constructionProvider).construction.add(hidden);
    await openTree(tester);
    await expandGroup(tester, 'points');

    final tree = find.byType(ObjectTreePanel);
    await tester.tap(find.descendant(of: tree, matching: find.text('Point')));
    await tester.pump();

    expect(container.read(selectionProvider), {'h'});
    // The inspector is opened by its own button now — the tree selects,
    // it does not restyle.
    await tester.tap(find.byTooltip('Style & properties'));
    await tester.pump();
    // The inspector's name field only exists while something is selected.
    // (Scoped to the inspector — the tree's own search field is always
    // there.)
    expect(
      find.descendant(
        of: find.byType(AttributesInspector),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
  });

  testWidgets('row long-press toggles the object in and out of the selection', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A'),
    );
    container.read(constructionProvider).construction.add(a);
    addPoint('b', const Vec2(2, 0));
    container.read(selectionProvider.notifier).select('b');
    await openTree(tester);
    await expandGroup(tester, 'points');

    // Long-press is the touch shift-tap: it toggles, never replaces.
    final tree = find.byType(ObjectTreePanel);
    final rowA = find.descendant(of: tree, matching: find.text('A'));
    await tester.longPress(rowA);
    await tester.pump();
    expect(container.read(selectionProvider), {'b', 'a'});

    await tester.longPress(rowA);
    await tester.pump();
    expect(container.read(selectionProvider), {'b'});
  });

  testWidgets('groups start folded; the chevron expands and refolds, and '
      'the folded header still selects the whole group', (tester) async {
    await pumpEditor(tester);
    final a = addPoint('a', Vec2.zero);
    final b = addPoint('b', const Vec2(2, 0));
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('Point')),
      findsNothing,
      reason: 'a fresh panel shows headers only',
    );
    expect(
      find.descendant(of: tree, matching: find.text('Points')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('2')),
      findsOneWidget,
      reason: 'a count stands in for the hidden rows',
    );
    expect(
      find.descendant(of: tree, matching: find.text('Segment')),
      findsNothing,
      reason: 'every group starts folded',
    );

    // The fold hides rows, it doesn't disown them: select-by-kind still
    // acts on the whole group.
    await tester.tap(find.descendant(of: tree, matching: find.text('Points')));
    await tester.pump();
    expect(container.read(selectionProvider), {'a', 'b'});

    await expandGroup(tester, 'points');
    expect(
      find.descendant(of: tree, matching: find.text('Point')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: tree, matching: find.text('Segment')),
      findsNothing,
      reason: 'expanding one group leaves the rest folded',
    );

    await tester.tap(find.byTooltip('Collapse points'));
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('Point')),
      findsNothing,
    );
  });

  testWidgets('an active search overrides folding; clearing it restores '
      'the fold', (tester) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A1'),
    );
    container.read(constructionProvider).construction.add(a);
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('A1')),
      findsNothing,
      reason: 'groups start folded',
    );

    // A match inside a folded group must not read as "no matches".
    await tester.enterText(
      find.byKey(const ValueKey('tree-search-field')),
      'a1',
    );
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('A1')),
      findsOneWidget,
    );
    // While searching the chevron is disabled — everything is forced
    // open, so it reads expanded, not folded.
    expect(find.byTooltip('Expand points'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Collapse points'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('A1')),
      findsNothing,
      reason: 'the fold survives the search',
    );
  });

  testWidgets('search filters rows by display label and hides empty groups', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A1'),
    );
    container.read(constructionProvider).construction.add(a);
    final b = FreePoint(
      id: 'b',
      position: const Vec2(2, 0),
      attributes: const ObjectAttributes(name: 'B2'),
    );
    container.read(constructionProvider).construction.add(b);
    container
        .read(constructionProvider)
        .construction
        .add(Segment(id: 's', point1: a, point2: b));
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    final searchField = find.byKey(const ValueKey('tree-search-field'));
    // Case-insensitive substring over the display label (name, or kind
    // label when unnamed — the unnamed segment shows as 'Segment').
    await tester.enterText(searchField, 'a1');
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('A1')),
      findsOneWidget,
    );
    expect(find.descendant(of: tree, matching: find.text('B2')), findsNothing);
    expect(
      find.descendant(of: tree, matching: find.text('Points')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('Lines')),
      findsNothing,
      reason: 'a group with no matching rows is hidden',
    );

    // The unnamed segment matches on its kind label.
    await tester.enterText(searchField, 'segm');
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('Segment')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('Points')),
      findsNothing,
    );

    await tester.enterText(searchField, 'zzz');
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('No matches')),
      findsOneWidget,
    );

    // The × clears the query; the groups return to their folded state,
    // headers only.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('Points')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('Lines')),
      findsOneWidget,
    );
    expect(find.descendant(of: tree, matching: find.text('A1')), findsNothing);
  });

  testWidgets('header tap under an active filter selects the matches only', (
    tester,
  ) async {
    await pumpEditor(tester);
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A1'),
    );
    container.read(constructionProvider).construction.add(a);
    final b = FreePoint(
      id: 'b',
      position: const Vec2(2, 0),
      attributes: const ObjectAttributes(name: 'B2'),
    );
    container.read(constructionProvider).construction.add(b);
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    await tester.enterText(
      find.byKey(const ValueKey('tree-search-field')),
      'a1',
    );
    await tester.pump();
    await tester.tap(find.descendant(of: tree, matching: find.text('Points')));
    await tester.pump();
    expect(
      container.read(selectionProvider),
      {'a'},
      reason:
          'the header acts on the rows it is heading — the filtered '
          'matches, not the whole kind',
    );
  });

  testWidgets('typing in the search field fires no tool shortcut', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    await openTree(tester);

    await tester.tap(find.byKey(const ValueKey('tree-search-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(
      container.read(toolProvider).tool,
      isNull,
      reason: 'the EditableText focus guard must cover the search field',
    );
  });

  testWidgets('rows track construction changes: delete via undo removes the '
      'row', (tester) async {
    await pumpEditor(tester);
    addPoint('a', Vec2.zero);
    await openTree(tester);
    await expandGroup(tester, 'points');

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('Point')),
      findsOneWidget,
    );

    container.read(constructionProvider).construction.removeWithDependents('a');
    await tester.pump();
    expect(
      find.descendant(of: tree, matching: find.text('Point')),
      findsNothing,
    );
    expect(find.text('No objects yet'), findsOneWidget);
  });

  testWidgets('conics get their own header instead of being filed under '
      'Circles (Phase 132b)', (tester) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    // A real circle and a five-point conic, side by side.
    final c = addPoint('c', Vec2.zero);
    final r = addPoint('r', const Vec2(3, 0));
    construction.add(CircleCenterPoint(id: 'k', center: c, onCircle: r));
    final on = [
      addPoint('e0', const Vec2(4, 0)),
      addPoint('e1', const Vec2(0, 3)),
      addPoint('e2', const Vec2(-4, 0)),
      addPoint('e3', const Vec2(0, -3)),
      addPoint('e4', const Vec2(2.4, 2.4)),
    ];
    construction.add(FivePointConic(id: 'q', points: on));
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('Circles')),
      findsOneWidget,
      reason: 'the circle is still a circle',
    );
    expect(
      find.descendant(of: tree, matching: find.text('Conics')),
      findsOneWidget,
      reason: 'and the conic is no longer filed under it',
    );

    await expandGroup(tester, 'conics');
    expect(
      find.descendant(of: tree, matching: find.text('Conic')),
      findsOneWidget,
      reason: 'the row label was already right; only the header was wrong',
    );
  });

  testWidgets('a document with only circles shows no Conics header', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final c = addPoint('c', Vec2.zero);
    final r = addPoint('r', const Vec2(3, 0));
    construction.add(CircleCenterPoint(id: 'k', center: c, onCircle: r));
    await openTree(tester);

    final tree = find.byType(ObjectTreePanel);
    expect(
      find.descendant(of: tree, matching: find.text('Circles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('Conics')),
      findsNothing,
      reason: 'empty groups are still skipped',
    );
  });
}
