import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/prover_provider.dart';
import 'package:regula/application/providers/question_draft_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/fixed_angle_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/question_draft.dart';
import 'package:regula/domain/prover/question_template.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import 'package:regula/presentation/panels/proof_panel.dart';
import 'package:regula/presentation/panels/question_builder_bar.dart';

import '../../wide_window.dart';

void main() {
  late ProviderContainer container;

  FreePoint free(String id, String name, double x, double y) => FreePoint(
    id: id,
    position: Vec2(x, y),
    attributes: ObjectAttributes(name: name),
  );

  /// Varignon at screen scale: the default viewport maps world (x, y)
  /// to canvas (x, −y), so these sit a few hundred pixels into the
  /// canvas, well above the bar along its bottom. M N P Q are the
  /// midpoints of AB, BC, CD, DA; MN ∥ QP is the theorem, MN ⟂ QP is
  /// false.
  Map<String, Midpoint> seedVarignon() {
    final construction = container.read(constructionProvider).construction;
    final a = free('a', 'A', 100, -100);
    final b = free('b', 'B', 400, -120);
    final c = free('c', 'C', 440, -380);
    final d = free('d', 'D', 120, -360);
    Midpoint mid(String id, String name, FreePoint p, FreePoint q) => Midpoint(
      id: id,
      point1: p,
      point2: q,
      attributes: ObjectAttributes(name: name),
    );
    final m = mid('m', 'M', a, b);
    final n = mid('n', 'N', b, c);
    final p = mid('p', 'P', c, d);
    final q = mid('q', 'Q', d, a);
    for (final object in [a, b, c, d, m, n, p, q]) {
      construction.add(object);
    }
    return {'m': m, 'n': n, 'p': p, 'q': q};
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    useWideTestWindow(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Proof'));
    await tester.pump();
  }

  /// The panel's Ask menu, picking [template].
  Future<void> openBuilder(
    WidgetTester tester,
    QuestionTemplate template,
  ) async {
    await tester.tap(find.byTooltip('Ask a question'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(template.label).last);
    await tester.pumpAndSettle();
  }

  /// Taps the figure where [point] is drawn.
  Future<void> tapPoint(WidgetTester tester, GeoPoint point) async {
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final world = point.position!;
    await tester.tapAt(origin + Offset(world.x, -world.y));
    await tester.pump();
  }

  String slotText(WidgetTester tester, int index) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(QuestionBuilderBar.slotKey(index)),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// Scoped to the bar: the panel's chips can carry the same sentence.
  Finder inBar(Finder matching) => find.descendant(
    of: find.byKey(QuestionBuilderBar.barKey),
    matching: matching,
  );

  FilledButton askButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Ask'));

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('the question builder', () {
    testWidgets('opens from the panel, fills from taps on the figure in '
        'order, and asks', (tester) async {
      final mids = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      expect(find.byKey(QuestionBuilderBar.barKey), findsNothing);

      await openBuilder(tester, QuestionTemplate.para);
      expect(find.byKey(QuestionBuilderBar.barKey), findsOneWidget);
      expect(
        slotText(tester, 0),
        'Line',
        reason: 'an empty slot shows its role',
      );
      expect(
        find.textContaining('Tap a line, or two points on the figure'),
        findsOneWidget,
      );
      expect(askButton(tester).onPressed, isNull);

      // Four taps, two points a slot: the order is the slots'.
      for (final id in ['m', 'n', 'q', 'p']) {
        await tapPoint(tester, mids[id]!);
      }
      expect(slotText(tester, 0), 'M·N');
      expect(slotText(tester, 1), 'Q·P');
      expect(
        container.read(selectionProvider),
        isEmpty,
        reason: 'the taps filled slots, not the selection',
      );
      // The verdict before OK: true in the figure, so the question reads
      // and Ask is live.
      expect(inBar(find.text('MN is parallel to QP')), findsOneWidget);
      expect(askButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(find.byKey(QuestionBuilderBar.barKey), findsNothing);
      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(state.answer.question.canonical.toString(), 'para(m, n, q, p)');
      expect(find.textContaining('proved'), findsOneWidget);
    });

    testWidgets('a statement the figure denies is refuted before OK, with '
        'no run', (tester) async {
      final mids = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await openBuilder(tester, QuestionTemplate.perp);
      for (final id in ['m', 'n', 'q', 'p']) {
        await tapPoint(tester, mids[id]!);
      }

      expect(find.textContaining('Not true in this figure'), findsOneWidget);
      expect(askButton(tester).onPressed, isNull);
      expect(container.read(proverProvider), isA<ProverIdle>());
    });

    testWidgets('a slot menu fills without the figure and clears one slot', (
      tester,
    ) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await openBuilder(tester, QuestionTemplate.coll);

      await tester.tap(find.byKey(QuestionBuilderBar.slotKey(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('M ·'));
      await tester.pumpAndSettle();
      expect(slotText(tester, 1), 'M');
      expect(
        container.read(questionDraftProvider)!.current,
        0,
        reason: 'the next open slot is still the first',
      );

      await tester.tap(find.byKey(QuestionBuilderBar.slotKey(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(slotText(tester, 1), 'Point');
    });

    testWidgets('opens seeded from the selection, and switching the '
        'relation reseeds', (tester) async {
      seedVarignon();
      await pumpEditor(tester);
      container.read(selectionProvider.notifier).selectMany([
        'm',
        'n',
        'p',
        'q',
      ]);
      await openPanel(tester);

      await openBuilder(tester, QuestionTemplate.para);
      expect(slotText(tester, 0), 'M·N');
      expect(slotText(tester, 1), 'P·Q');
      expect(inBar(find.text('MN is parallel to PQ')), findsOneWidget);

      // The relation dropdown, in the bar.
      await tester.tap(find.byType(DropdownButton<QuestionTemplate>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(QuestionTemplate.cyclic.label).last);
      await tester.pumpAndSettle();
      expect(
        container.read(questionDraftProvider)!.template,
        QuestionTemplate.cyclic,
      );
      expect(slotText(tester, 3), 'Q');

      await tester.tap(find.byTooltip('Close the question builder'));
      await tester.pumpAndSettle();
      expect(find.byKey(QuestionBuilderBar.barKey), findsNothing);
      expect(container.read(questionDraftProvider), isNull);
    });

    testWidgets('a deleted object leaves its slot, not a dangling name', (
      tester,
    ) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      container.read(selectionProvider.notifier).selectMany(['m', 'n', 'q']);
      await openBuilder(tester, QuestionTemplate.coll);
      expect(slotText(tester, 0), 'M');

      container
          .read(constructionProvider)
          .construction
          .removeWithDependents('m');
      await tester.pump();
      expect(slotText(tester, 0), 'Point');
      expect(container.read(questionDraftProvider)!.values[0], isNull);
      expect(
        container.read(questionDraftProvider)!.values[1],
        isA<PointValue>(),
      );
    });
  });

  group('on a phone', () {
    const phone = Size(400, 800);

    Future<void> pumpPhoneEditor(WidgetTester tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.fact_check_outlined),
        ),
        80,
        scrollable: find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byIcon(Icons.fact_check_outlined));
      await tester.pumpAndSettle();
    }

    testWidgets('the sheet closes for the builder, and reopens with the '
        'answer', (tester) async {
      seedVarignon();
      await pumpPhoneEditor(tester);
      container.read(selectionProvider.notifier).selectMany([
        'm',
        'n',
        'p',
        'q',
      ]);
      await openSheet(tester);
      expect(find.byType(ProofPanel), findsOneWidget);

      await openBuilder(tester, QuestionTemplate.para);
      expect(
        find.byType(ProofPanel),
        findsNothing,
        reason: 'the sheet covers the figure the builder is filled from',
      );
      expect(find.byKey(QuestionBuilderBar.barKey), findsOneWidget);
      expect(inBar(find.text('MN is parallel to PQ')), findsOneWidget);

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(find.byKey(QuestionBuilderBar.barKey), findsNothing);
      expect(find.byType(ProofPanel), findsOneWidget, reason: 'reopened');
      expect(
        (container.read(proverProvider) as ProverAnswered).answer.verdict,
        ProverVerdict.proved,
      );
      expect(find.textContaining('proved'), findsOneWidget);
    });
  });

  group('the value templates and the reader (Phase 185)', () {
    /// Line AB and the 60° line through C carrying P, at screen scale.
    Map<String, GeoPoint> seedSixty() {
      final construction = container.read(constructionProvider).construction;
      final a = free('a', 'A', 100, -300);
      final b = free('b', 'B', 400, -300);
      final c = free('c', 'C', 150, -150);
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final sixty = FixedAngleLine(
        id: 'sixty',
        through: c,
        reference: ab,
        turn: Rational.fromInts(1, 3),
      );
      final p = PointOnObject(
        id: 'p',
        curve: sixty,
        parameter: 80,
        attributes: const ObjectAttributes(name: 'P'),
      );
      for (final object in [a, b, c, ab, sixty, p]) {
        construction.add(object);
      }
      return {'a': a, 'b': b, 'c': c, 'p': p};
    }

    TextButton readButton(WidgetTester tester) =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Read'));

    testWidgets('an angle of stated size waits for its value, reads it '
        'from the construction, and asks with it', (tester) async {
      final at = seedSixty();
      await pumpEditor(tester);
      await openPanel(tester);
      await openBuilder(tester, QuestionTemplate.aconst);
      expect(find.byKey(QuestionBuilderBar.valueKey), findsOneWidget);
      expect(readButton(tester).onPressed, isNull, reason: 'slots first');

      for (final id in ['a', 'b', 'c', 'p']) {
        await tapPoint(tester, at[id]!);
      }
      expect(slotText(tester, 0), 'A·B');
      expect(slotText(tester, 1), 'C·P');
      expect(
        inBar(find.textContaining('Type the angle in degrees, or Read')),
        findsOneWidget,
      );
      expect(askButton(tester).onPressed, isNull, reason: 'no value yet');
      expect(readButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(QuestionBuilderBar.valueKey),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '60',
        reason: 'the reader fills the field, in degrees',
      );
      expect(
        container.read(questionDraftProvider)!.value,
        Rational.fromInts(1, 3),
      );
      expect(
        inBar(find.text('the angle from AB to CP is π/3')),
        findsOneWidget,
      );
      expect(askButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(
        state.answer.question.canonical.toString(),
        'aconst(a, b, c, p; 1/3)',
      );
    });

    testWidgets('a typed value is exact and in degrees; a wrong one is '
        'refuted before Ask; an undetermined read says so', (tester) async {
      final at = seedSixty();
      await pumpEditor(tester);
      await openPanel(tester);
      await openBuilder(tester, QuestionTemplate.aconst);
      for (final id in ['a', 'b', 'c', 'p']) {
        await tapPoint(tester, at[id]!);
      }

      await tester.enterText(find.byKey(QuestionBuilderBar.valueKey), '-120');
      await tester.pump();
      expect(
        container.read(questionDraftProvider)!.value,
        Rational.fromInts(1, 3),
        reason: '−120° is the 60° line',
      );
      expect(askButton(tester).onPressed, isNotNull);

      await tester.enterText(find.byKey(QuestionBuilderBar.valueKey), '45');
      await tester.pump();
      expect(find.textContaining('Not true in this figure'), findsOneWidget);
      expect(askButton(tester).onPressed, isNull);

      await tester.enterText(find.byKey(QuestionBuilderBar.valueKey), 'pi/3');
      await tester.pump();
      expect(container.read(questionDraftProvider)!.value, isNull);
      expect(
        inBar(find.textContaining('Type the angle in degrees')),
        findsOneWidget,
      );

      // AC is at no stated angle to AB: the reader has nothing to say.
      final notifier = container.read(questionDraftProvider.notifier);
      notifier.put(1, at['c']!);
      notifier.put(1, at['a']!);
      await tester.pump();
      expect(slotText(tester, 1), 'C·A');
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(
        find.text('The construction does not determine this value.'),
        findsOneWidget,
      );
      expect(container.read(questionDraftProvider)!.value, isNull);
    });
  });
}
