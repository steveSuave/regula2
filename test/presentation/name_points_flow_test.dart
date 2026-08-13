import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import '../wide_window.dart';

/// The Phase 53 name-points flow end to end: activation through the
/// Points flyout dialog, tap-by-tap naming on the canvas (one undo step
/// per tap), and the hint chip tracking the upcoming name.
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

  /// Activates the tool through the text-and-labels group's dialog with
  /// [input] typed into the field ('' = just OK).
  Future<void> activate(WidgetTester tester, String input) async {
    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name points in sequence…'));
    await tester.pumpAndSettle();
    if (input.isNotEmpty) {
      await tester.enterText(find.byType(TextField), input);
    }
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  void addPoint(String id, Vec2 position) {
    container
        .read(constructionProvider)
        .construction
        .add(FreePoint(id: id, position: position));
  }

  Future<void> tapWorld(WidgetTester tester, Offset offset) async {
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + offset);
    await tester.pumpAndSettle();
  }

  String nameOf(String id) => container
      .read(constructionProvider)
      .construction
      .byId(id)!
      .attributes
      .name;

  testWidgets('alphabet taps name points A, B — one undo step per tap — '
      'and the hint chip tracks the upcoming letter', (tester) async {
    await pumpEditor(tester);
    addPoint('a', const Vec2(100, -200));
    addPoint('b', const Vec2(300, -200));
    await tester.pump();

    expect(
      find.textContaining('Next name'),
      findsNothing,
      reason: 'no chip without the tool',
    );

    await activate(tester, '');
    expect(find.text('Next name: A'), findsOneWidget);

    await tapWorld(tester, const Offset(100, 200));
    expect(nameOf('a'), 'A');
    expect(find.text('Next name: B'), findsOneWidget);

    await tapWorld(tester, const Offset(300, 200));
    expect(nameOf('b'), 'B');
    expect(find.text('Next name: C'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(nameOf('b'), isEmpty, reason: 'one command per tap');
    expect(nameOf('a'), 'A');
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(nameOf('a'), isEmpty);
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('an empty-canvas tap burns nothing', (tester) async {
    await pumpEditor(tester);
    addPoint('a', const Vec2(100, -200));
    await tester.pump();

    await activate(tester, '');
    await tapWorld(tester, const Offset(500, 400));
    expect(
      find.text('Next name: A'),
      findsOneWidget,
      reason: 'missing the point consumes nothing',
    );
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('a naming string runs out and the chip says so', (tester) async {
    await pumpEditor(tester);
    addPoint('a', const Vec2(100, -200));
    addPoint('b', const Vec2(300, -200));
    addPoint('c', const Vec2(500, -200));
    await tester.pump();

    await activate(tester, 'MI');
    expect(find.text('Next name: M'), findsOneWidget);

    await tapWorld(tester, const Offset(100, 200));
    await tapWorld(tester, const Offset(300, 200));
    expect(nameOf('a'), 'M');
    expect(nameOf('b'), 'I');
    expect(find.text('All letters assigned'), findsOneWidget);

    await tapWorld(tester, const Offset(500, 200));
    expect(nameOf('c'), isEmpty, reason: 'exhausted taps are ignored');
  });
}
