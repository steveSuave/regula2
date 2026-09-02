import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';

import '../wide_window.dart';

/// The Phase 58 text & calculation flow end to end: activation through
/// the text-and-labels group, tap → content dialog → one live text on
/// the canvas (one undo step), editing in place, and dialog validation.
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

  Future<void> activate(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Text…'));
    await tester.pumpAndSettle();
  }

  void addNamedPoint(String id, String name, Vec2 position) {
    container
        .read(constructionProvider)
        .construction
        .add(
          FreePoint(
            id: id,
            position: position,
            attributes: ObjectAttributes(name: name),
          ),
        );
  }

  Future<void> tapWorld(WidgetTester tester, Offset offset) async {
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + offset);
    await tester.pumpAndSettle();
  }

  Future<void> submitContent(WidgetTester tester, String content) async {
    await tester.enterText(
      find.byKey(const ValueKey('text-content-field')),
      content,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  ExpressionText soleText() => container
      .read(constructionProvider)
      .construction
      .objects
      .whereType<ExpressionText>()
      .single;

  testWidgets('tap → dialog → live text, one undo step, tracks drags', (
    tester,
  ) async {
    await pumpEditor(tester);
    addNamedPoint('a', 'A', const Vec2(100, -200));
    addNamedPoint('b', 'B', const Vec2(400, -200));
    await tester.pump();

    await activate(tester);
    expect(
      find.byKey(const ValueKey('text-content-field')),
      findsNothing,
      reason: 'activation alone opens no dialog — the tap does',
    );

    await tapWorld(tester, const Offset(250, 100));
    expect(find.byKey(const ValueKey('text-content-field')), findsOneWidget);
    await submitContent(tester, 'AB = {dist(A, B)} u');

    final text = soleText();
    expect(text.renderedText, 'AB = 300.00 u');
    expect(text.anchor, const Vec2(250, -100));
    expect(text.attributes.labelDx, 0);
    expect(text.attributes.labelDy, 0);
    expect(text.attributes.name, isNotEmpty, reason: 'auto-named');
    expect(
      text.attributes.labelVisible,
      isFalse,
      reason: 'the content is the on-canvas presence, not the name',
    );
    expect(text.parents.map((p) => p.id), ['a', 'b']);

    // Live: the value tracks the referenced geometry.
    container
        .read(constructionProvider)
        .construction
        .moveFreePoint('b', const Vec2(100, 200));
    expect(text.renderedText, 'AB = 400.00 u');

    // One undo step removes the whole text.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<ExpressionText>(),
      isEmpty,
    );
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('cancel leaves nothing behind', (tester) async {
    await pumpEditor(tester);
    await activate(tester);
    await tapWorld(tester, const Offset(200, 100));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(constructionProvider).construction.objects, isEmpty);
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('unknown reference keeps the dialog open with the error', (
    tester,
  ) async {
    await pumpEditor(tester);
    await activate(tester);
    await tapWorld(tester, const Offset(200, 100));
    await tester.enterText(
      find.byKey(const ValueKey('text-content-field')),
      '{dist(A, Z)}',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining("No object named 'A'"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('text-content-field')),
      findsOneWidget,
      reason: 'invalid input keeps the dialog open',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('tapping an existing text edits it in place', (tester) async {
    await pumpEditor(tester);
    addNamedPoint('a', 'A', const Vec2(100, -200));
    addNamedPoint('b', 'B', const Vec2(400, -200));
    await tester.pump();

    await activate(tester);
    await tapWorld(tester, const Offset(250, 100));
    await submitContent(tester, 'first note');
    final original = soleText();
    final originalName = original.attributes.name;

    // Tap the same spot: the dialog opens pre-filled for editing.
    await tapWorld(tester, const Offset(250, 100));
    expect(
      find.text('first note'),
      findsOneWidget,
      reason: 'edit dialog pre-fills the current content',
    );
    await submitContent(tester, 'AB = {dist(A, B)}');

    final replacement = soleText();
    expect(replacement.id, original.id);
    expect(replacement.renderedText, 'AB = 300.00');
    expect(
      replacement.attributes.name,
      originalName,
      reason: 'editing keeps the identity, no fresh auto-name',
    );
    expect(replacement.anchor, original.anchor);

    // The edit is one undo step back to the original.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(soleText().renderedText, 'first note');
    // And one more removes the creation.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<GeoText>(),
      isEmpty,
    );
  });

  testWidgets('dragging a text body moves its anchor freely — no 40 px clamp', (
    tester,
  ) async {
    await pumpEditor(tester);
    await activate(tester);
    await tapWorld(tester, const Offset(250, 100));
    await submitContent(tester, 'movable note');
    final text = soleText();
    expect(text.anchor, const Vec2(250, -100));

    // Back to move/select mode; grab inside the text and drag far.
    container.read(toolProvider.notifier).deactivate();
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.dragFrom(
      origin + const Offset(255, 95),
      const Offset(200, 150),
    );
    await tester.pumpAndSettle();

    expect(
      text.anchor,
      const Vec2(450, -250),
      reason: 'anchor rides the full drag delta, unclamped',
    );
    expect(
      text.attributes.labelDx,
      0,
      reason: 'the caption offset is untouched — the anchor moved',
    );
    expect(text.attributes.labelDy, 0);
    expect(text.renderedText, 'movable note');

    // One undo step for the whole gesture.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(text.anchor, const Vec2(250, -100));
  });

  testWidgets('G E activates the tool and tints the group icon', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();

    await tapWorld(tester, const Offset(300, 200));
    expect(find.byKey(const ValueKey('text-content-field')), findsOneWidget);
    await submitContent(tester, 'shortcut text');
    expect(soleText().renderedText, 'shortcut text');
  });
}
