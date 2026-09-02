import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/proof_highlight_provider.dart';
import 'package:regula/application/providers/prover_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_translation.dart';
import 'package:regula/domain/prover/carriers.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/questions.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';
import 'package:regula/presentation/panels/proof_panel.dart';

import '../../wide_window.dart';

void main() {
  late ProviderContainer container;

  FreePoint free(String id, String name, double x, double y) => FreePoint(
    id: id,
    position: Vec2(x, y),
    attributes: ObjectAttributes(name: name),
  );

  /// Varignon, in the container's live construction: the midpoint
  /// quadrilateral of any quadrilateral is a parallelogram, three rules
  /// and four givens deep.
  ({Fact goal, List<Midpoint> midpoints}) seedVarignon() {
    final construction = container.read(constructionProvider).construction;
    final a = free('a', 'A', 0, 0);
    final b = free('b', 'B', 6, 1);
    final c = free('c', 'C', 7, 5);
    final d = free('d', 'D', 1, 4);
    final mab = Midpoint(
      id: 'mab',
      point1: a,
      point2: b,
      attributes: const ObjectAttributes(name: 'M'),
    );
    final mbc = Midpoint(
      id: 'mbc',
      point1: b,
      point2: c,
      attributes: const ObjectAttributes(name: 'N'),
    );
    final mcd = Midpoint(
      id: 'mcd',
      point1: c,
      point2: d,
      attributes: const ObjectAttributes(name: 'P'),
    );
    final mda = Midpoint(
      id: 'mda',
      point1: d,
      point2: a,
      attributes: const ObjectAttributes(name: 'Q'),
    );
    for (final object in [a, b, c, d, mab, mbc, mcd, mda]) {
      construction.add(object);
    }
    return (
      goal: Fact(PredicateKind.para, [mab, mbc, mda, mcd]),
      midpoints: [mab, mbc, mcd, mda],
    );
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

  /// The editor has several scrollables (the app bar, the toolbar) and
  /// the inspector renders its own [ListTile]s once something is
  /// selected — so every structural finder is scoped to the panel.
  Finder inPanel(Finder matching) =>
      find.descendant(of: find.byType(ProofPanel), matching: matching);

  /// Unfolds [kind]'s group in the derived list. Groups start folded
  /// (Phase 158), so a test that reaches a row opens its group first,
  /// the way a user does; the whole header row is the fold target.
  Future<void> expandGroup(WidgetTester tester, GoalGroup group) async {
    final header = inPanel(find.text(group.label));
    // Scroll first, then ensure: a lazy list builds a header only near
    // the fold, and `ensureVisible` needs it built (session 168).
    await tester.scrollUntilVisible(
      header,
      60,
      scrollable: inPanel(find.byType(Scrollable)),
    );
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pump();
  }

  /// Opens [goal]'s proof through its row's arrow — the row itself
  /// points at the figure (Phase 158b).
  Future<void> openProof(WidgetTester tester, Fact goal) async {
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text(readFact(goal)),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Show proof'),
      ),
    );
    await tester.pump();
  }

  /// `perp-true-unproved.rgl` into the container, returning its point
  /// named [name]. Point C — a point on a line — is the selection that
  /// narrows the derived list to two of its six kinds; Varignon has no
  /// object that empties any kind at all (measured: every one of its
  /// eight points touches all five).
  GeoPoint loadPerpFixture({required String name}) {
    final construction = decodeDocument(
      jsonDecode(
        File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
      ) as Map<String, dynamic>,
    ).construction;
    container.read(constructionProvider.notifier).replace(construction);
    return construction.objects.whereType<GeoPoint>().firstWhere(
      (point) => point.attributes.name == name,
    );
  }

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('provableGoals', () {
    test('offers what was derived, never what was given', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).prove();
      final database = (container.read(proverProvider) as ProverReady).database;

      final goals = provableGoals(database);

      expect(goals, isNotEmpty);
      expect(
        goals.every((goal) => !database.derivationOf(goal)!.isHypothesis),
        isTrue,
        reason: 'a hypothesis is the figure, not a result',
      );
      expect(
        goals.length,
        lessThan(database.length),
        reason: 'the givens must actually have been dropped',
      );
      expect(
        goals,
        database.facts.where(
          (fact) => !database.derivationOf(fact)!.isHypothesis,
        ),
        reason: 'order is the database\'s own, so the panel is reproducible',
      );
    });

    test('a selection narrows to statements mentioning it', () async {
      final rig = seedVarignon();
      await container.read(proverProvider.notifier).prove();
      final database = (container.read(proverProvider) as ProverReady).database;
      final all = provableGoals(database);

      final narrowed = provableGoals(database, selectedIds: {'mab'});

      expect(narrowed, isNotEmpty);
      expect(narrowed.length, lessThan(all.length));
      expect(
        narrowed.every((goal) => goal.points.any((p) => p.id == 'mab')),
        isTrue,
      );
      // *At least one* selected point, not all of them: two selected
      // points ask what relates them, and the answer names others.
      expect(
        provableGoals(database, selectedIds: {'mab', 'mbc'}).length,
        greaterThanOrEqualTo(narrowed.length),
      );
      expect(
        provableGoals(database, selectedIds: {rig.midpoints.first.id}),
        narrowed,
      );
    });

    test('a selection nothing was derived about narrows to nothing', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).prove();
      final database = (container.read(proverProvider) as ProverReady).database;

      expect(provableGoals(database, selectedIds: {'nobody'}), isEmpty);
    });

    test('an empty database offers nothing', () {
      expect(provableGoals(FactDatabase()), isEmpty);
    });
  });

  group('stepReason', () {
    test('a given cites nothing; a deduction names its rule and steps', () {
      final given = ProofStep(
        number: 1,
        fact: Fact(PredicateKind.coll, [
          free('a', 'A', 0, 0),
          free('b', 'B', 1, 0),
          free('c', 'C', 2, 0),
        ]),
        rule: null,
        premiseSteps: const [],
      );
      expect(stepReason(given), 'given');

      final deduced = ProofStep(
        number: 3,
        fact: given.fact,
        rule: 'midline_para',
        premiseSteps: const [1, 2],
      );
      expect(stepReason(deduced), 'midline para from [1], [2]');
    });
  });

  group('isStale', () {
    test('only a finished run can be stale, and only off-revision', () {
      const idle = ProverIdle();
      expect(isStale(idle, 7), isFalse);
      expect(isStale(const ProverRunning(7), 9), isFalse);

      final ready = ProverReady(
        revision: 7,
        database: FactDatabase(),
        applications: 0,
        reachedFixpoint: true,
      );
      expect(isStale(ready, 7), isFalse);
      expect(isStale(ready, 8), isTrue);
    });
  });

  group('the panel', () {
    testWidgets('hidden by default; the app-bar button docks it', (
      tester,
    ) async {
      await pumpEditor(tester);
      expect(find.byType(ProofPanel), findsNothing);

      await openPanel(tester);
      expect(find.byType(ProofPanel), findsOneWidget);
      expect(find.textContaining('Nothing proved yet'), findsOneWidget);

      await tester.tap(find.byTooltip('Proof'));
      await tester.pump();
      expect(find.byType(ProofPanel), findsNothing);
    });

    testWidgets('proving lists what was derived, and a tap opens the proof', (
      tester,
    ) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);

      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      // The goal list, and the Varignon conclusion is in it. The list
      // is long enough to scroll, so reach the row the way a user does.
      final goalText = readFact(rig.goal);
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(goalText),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(goalText));
      await tester.pumpAndSettle();
      expect(find.text(goalText), findsOneWidget);

      await openProof(tester, rig.goal);
      await tester.pump();

      // The step list, rendered from `Proof.steps`: every step's
      // statement and reason, the goal's own row last.
      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      for (final step in proof.steps) {
        expect(find.text('[${step.number}]'), findsOneWidget);
        expect(find.text(stepReason(step)), findsWidgets);
      }
      expect(find.text('given'), findsNWidgets(proof.givens.length));
      expect(find.byTooltip('Back to the list'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pump();
      expect(find.byTooltip('Back to the list'), findsNothing);
    });

    testWidgets('an edit marks the run stale rather than clearing it', (
      tester,
    ) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Prove'), findsOneWidget);
      await expandGroup(tester, const KindGroup(PredicateKind.para));

      container
          .read(constructionProvider)
          .construction
          .add(free('e', 'E', 3, 3));
      await tester.pump();

      // The findings stay on screen — they were true of a figure the
      // user recognizes — and the button says the figure moved.
      expect(
        find.byTooltip('The figure changed — prove again'),
        findsOneWidget,
      );
      expect(inPanel(find.byType(ListTile)), findsWidgets);
    });

    testWidgets('the selection narrows the list live', (tester) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      final database = (container.read(proverProvider) as ProverReady).database;
      final id = rig.midpoints[0].id;
      final narrowed = provableGoals(database, selectedIds: {id});
      expect(
        narrowed.length,
        lessThan(provableGoals(database).length),
        reason: 'the rig must actually derive facts away from M',
      );

      container.read(selectionProvider.notifier).select(id);
      await tester.pump();
      final carriers = (container.read(proverProvider) as ProverReady).carriers;
      for (final kind in groupedGoals(narrowed, carriers: carriers).keys) {
        await expandGroup(tester, kind);
      }

      // Every narrowed goal is a row (reached the way a user does — the
      // grouped list is lazy and taller than the panel), and every row
      // ever built names M: the rendered rows are the narrowed list.
      final narrowedTexts = {for (final goal in narrowed) readFact(goal)};
      // Back to the top (opening the groups scrolled to the foot), then
      // down through the rows in the panel's own order — group by group,
      // database order within — so a downward search meets each one.
      await tester.drag(
        inPanel(find.byType(Scrollable)),
        const Offset(0, 5000),
      );
      await tester.pumpAndSettle();
      final inListOrder = groupedGoals(
        narrowed,
        carriers: carriers,
      ).values.expand((facts) => facts);
      for (final goal in inListOrder) {
        await tester.scrollUntilVisible(
          find.text(readFact(goal)),
          60,
          scrollable: inPanel(find.byType(Scrollable)),
        );
        expect(find.text(readFact(goal)), findsOneWidget);
        for (final row in tester.widgetList<ListTile>(
          inPanel(find.byType(ListTile)),
        )) {
          final text = find
              .descendant(of: find.byWidget(row), matching: find.byType(Text))
              .evaluate()
              .map((element) => (element.widget as Text).data)
              .firstWhere(narrowedTexts.contains, orElse: () => null);
          expect(text, isNotNull, reason: 'a row that does not name M');
        }
      }
    });

    testWidgets('tapping a step points at what it is about', (tester) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await openProof(tester, rig.goal);
      await tester.pump();
      expect(container.read(proofHighlightProvider), isEmpty);

      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      final step = proof.steps.first;
      await tester.tap(find.text(readFact(step.fact)).first);
      await tester.pump();

      expect(
        container.read(proofHighlightProvider),
        step.fact.points.map((point) => point.id).toSet(),
      );
      // The emphasis is not the selection: what a proof step is about
      // must not become what the next tool acts on.
      expect(container.read(selectionProvider), isEmpty);

      // Tapping the same step again turns it off — a highlight the user
      // cannot dismiss is one they have to close the panel to escape.
      await tester.tap(find.text(readFact(step.fact)).first);
      await tester.pump();
      expect(container.read(proofHighlightProvider), isEmpty);
    });

    testWidgets('the canvas pulses only while a step is being read', (
      tester,
    ) async {
      // An always-ticking controller would repaint the app's most
      // expensive paint forever for no visible reason, so the pulse is a
      // function of the highlight set. Read straight off the painter:
      // the value moving *is* the animation.
      double pulse() =>
          (tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: find.byType(GeometryCanvas),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter!
                  as GeometryPainter)
              .highlightPulse!
              .value;

      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await openProof(tester, rig.goal);
      await tester.pump();
      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      final stepText = readFact(proof.steps.first.fact);

      // Nothing highlighted: the pulse is parked.
      await tester.pump(const Duration(milliseconds: 200));
      expect(pulse(), 0);

      await tester.tap(find.text(stepText).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final moving = pulse();
      expect(moving, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pulse(), isNot(moving));

      await tester.tap(find.text(stepText).first);
      await tester.pump();
      final parked = pulse();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        pulse(),
        parked,
        reason: 'the pulse must stop when nothing is being read',
      );
    });

    testWidgets('going back to the list drops the emphasis', (tester) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await openProof(tester, rig.goal);
      await tester.pump();
      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      await tester.tap(find.text(readFact(proof.steps.first.fact)).first);
      await tester.pump();
      expect(container.read(proofHighlightProvider), isNotEmpty);

      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pump();

      expect(container.read(proofHighlightProvider), isEmpty);
    });

    testWidgets('closing the panel drops the emphasis', (tester) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await openProof(tester, rig.goal);
      await tester.pump();
      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      await tester.tap(find.text(readFact(proof.steps.first.fact)).first);
      await tester.pump();
      expect(container.read(proofHighlightProvider), isNotEmpty);

      // The canvas outlives the panel; it must not be left pulsing at a
      // step nobody is looking at. The clear is post-frame (a provider
      // may not be modified inside `dispose`), so settle for it.
      await tester.tap(find.byTooltip('Proof'));
      await tester.pumpAndSettle();

      expect(container.read(proofHighlightProvider), isEmpty);
    });

    testWidgets('a selection that phrases nothing says so', (tester) async {
      // Session 163's report: four selected segments, no chips, no
      // explanation. Four segments are four carriers, which Phase 159
      // now phrases — so the silent case here is one that stays silent.
      final rig = seedVarignon();
      final construction = container.read(constructionProvider).construction;
      final corners = [for (final m in rig.midpoints) m.point1];
      final sides = [
        for (var i = 0; i < 4; i++)
          Segment(
            id: 'side$i',
            point1: corners[i],
            point2: corners[(i + 1) % 4],
          ),
      ];
      for (final side in sides) {
        construction.add(side);
      }
      await pumpEditor(tester);
      await openPanel(tester);

      // Nothing selected: neither chips nor the hint — the derived list
      // is the panel then.
      expect(find.text('Ask about the selection'), findsNothing);
      expect(find.text(ProofPanel.unaskableSelectionHint), findsNothing);

      // Two sides and a stray corner: refused for good (half a selection
      // silently ignored is a question nobody asked).
      container.read(selectionProvider.notifier).selectMany([
        sides[0].id,
        sides[1].id,
        corners[2].id,
      ]);
      await tester.pump();
      expect(find.text(ProofPanel.unaskableSelectionHint), findsOneWidget);
      expect(find.text('Ask about the selection'), findsNothing);
      expect(inPanel(find.byType(QuestionChip)), findsNothing);

      // Session 163's four segments: three equal-angle readings, each
      // naming its segments' points.
      container
          .read(selectionProvider.notifier)
          .selectMany(sides.map((side) => side.id));
      await tester.pump();
      expect(find.text(ProofPanel.unaskableSelectionHint), findsNothing);
      expect(inPanel(find.byType(QuestionChip)), findsNWidgets(3));
      for (final question in askableQuestions(
        construction.objects,
        selectedIds: {for (final side in sides) side.id},
      )) {
        expect(question.kind, PredicateKind.eqangle);
        expect(find.text(questionLabel(question)), findsOneWidget);
      }

      // Two of them phrase perp / para / cong: chips, and the hint gone.
      container.read(selectionProvider.notifier).selectMany([
        sides[0].id,
        sides[2].id,
      ]);
      await tester.pump();
      expect(find.text(ProofPanel.unaskableSelectionHint), findsNothing);
      expect(find.text('Ask about the selection'), findsOneWidget);
      expect(inPanel(find.byType(QuestionChip)), findsNWidgets(3));

      // And a lone point is back to the hint.
      container.read(selectionProvider.notifier).select(corners.first.id);
      await tester.pump();
      expect(find.text(ProofPanel.unaskableSelectionHint), findsOneWidget);
    });

    testWidgets('four segments ask an equal-angle question, and the '
        'inscribed angle answers it', (tester) async {
      // P, Q, A, B on one circle: ∠APB = ∠AQB by `inscribed_angle`. The
      // four segments PA, PB, QA, QB are that statement's carriers, and
      // one of the three readings they offer is it.
      final construction = container.read(constructionProvider).construction;
      final o = free('o', 'O', 0, 0);
      final a = free('a', 'A', 5, 0);
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: a);
      GeoPoint on(String id, String name, double t) => PointOnObject(
        id: id,
        curve: circle,
        parameter: t,
        attributes: ObjectAttributes(name: name),
      );
      final b = on('b', 'B', 2.0);
      final p = on('p', 'P', 0.9);
      final q = on('q', 'Q', 4.0);
      final sides = [
        Segment(id: 'pa', point1: p, point2: a),
        Segment(id: 'pb', point1: p, point2: b),
        Segment(id: 'qa', point1: q, point2: a),
        Segment(id: 'qb', point1: q, point2: b),
      ];
      for (final object in [o, a, circle, b, p, q, ...sides]) {
        construction.add(object);
      }
      await pumpEditor(tester);
      await openPanel(tester);
      container
          .read(selectionProvider.notifier)
          .selectMany(sides.map((side) => side.id));
      await tester.pump();

      final inscribed = Fact.of(
        Predicate(PredicateKind.eqangle, [p, a, p, b, q, a, q, b]),
      );
      final questions = askableQuestions(
        construction.objects,
        selectedIds: {for (final side in sides) side.id},
      );
      final question = questions.singleWhere(
        (q) => q.spellings.any((s) => Fact.of(s) == inscribed),
      );
      final others = questions.where((q) => !identical(q, question));
      expect(others, hasLength(2));

      await tester.ensureVisible(find.text(questionLabel(question)));
      await tester.tap(find.text(questionLabel(question)));
      await tester.pumpAndSettle();

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(
        state.answer.proof!.steps.map((step) => step.rule),
        contains('inscribed_angle'),
      );
      // The other two readings are false in the figure: refuted, no run.
      for (final other in others) {
        await tester.tap(find.byTooltip('Back to the list'));
        await tester.pump();
        await tester.ensureVisible(find.text(questionLabel(other)));
        await tester.tap(find.text(questionLabel(other)));
        await tester.pumpAndSettle();
        expect(
          (container.read(proverProvider) as ProverAnswered).answer.verdict,
          ProverVerdict.refuted,
        );
      }
    });

    testWidgets('sugar reads as what was asked: concurrency and tangency', (
      tester,
    ) async {
      final construction = container.read(constructionProvider).construction;
      // Three lines through P, with Z naming PC beside C.
      final p = free('p', 'P', 0, 0);
      final a = free('a', 'A', 4, 0);
      final b = free('b', 'B', 0, 4);
      final c = free('c', 'C', 3, 3);
      final la = LineThroughTwoPoints(id: 'la', point1: p, point2: a);
      final lb = LineThroughTwoPoints(id: 'lb', point1: p, point2: b);
      final lc = LineThroughTwoPoints(id: 'lc', point1: p, point2: c);
      final z = PointOnObject(
        id: 'z',
        curve: lc,
        parameter: 2,
        attributes: const ObjectAttributes(name: 'Z'),
      );
      // A circle about O, its tangent from Q with the touch point K
      // drawn, and a secant through the rim point R and S.
      final o = free('o', 'O', 20, 0);
      final r = free('r', 'R', 23, 0);
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: r);
      final q = free('q', 'Q', 29, 0);
      final tangent = TangentLine(id: 't', point: q, circle: circle, branch: 0);
      final touch = IntersectionPoint(
        id: 'x',
        curve1: tangent,
        curve2: circle,
        branchIndex: 0,
        attributes: const ObjectAttributes(name: 'K'),
      );
      final s = free('s', 'S', 20, 9);
      final secant = LineThroughTwoPoints(id: 'l', point1: r, point2: s);
      for (final object in [
        p,
        a,
        b,
        c,
        la,
        lb,
        lc,
        z,
        o,
        r,
        circle,
        q,
        tangent,
        touch,
        s,
        secant,
      ]) {
        construction.add(object);
      }
      await pumpEditor(tester);
      await openPanel(tester);

      Future<ProverAnswered> askChip(Set<String> ids) async {
        container.read(selectionProvider.notifier).selectMany(ids);
        await tester.pump();
        final question = askableQuestions(
          construction.objects,
          selectedIds: ids,
        ).single;
        expect(question.reading, isNotNull);
        await tester.ensureVisible(find.text(question.reading!));
        await tester.tap(find.text(question.reading!));
        await tester.pumpAndSettle();
        return container.read(proverProvider) as ProverAnswered;
      }

      // Concurrent by construction: coll(P, C, Z) is a hypothesis.
      final concurrent = await askChip({'la', 'lb', 'lc'});
      expect(
        concurrent.answer.question.reading,
        'PA, PB and PC are concurrent',
      );
      expect(concurrent.answer.verdict, ProverVerdict.proved);
      expect(
        find.textContaining('“PA, PB and PC are concurrent” — proved'),
        findsOneWidget,
        reason: 'the verdict quotes what was asked, not the coll it became',
      );

      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pump();
      final tangentAnswer = await askChip({'t', 'k'});
      expect(
        tangentAnswer.answer.question.reading,
        'QK is tangent to the circle at K',
      );
      expect(tangentAnswer.answer.verdict, ProverVerdict.proved);

      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pump();
      final secantAnswer = await askChip({'l', 'k'});
      expect(
        secantAnswer.answer.question.reading,
        'RS is tangent to the circle at R',
      );
      expect(secantAnswer.answer.verdict, ProverVerdict.refuted);
      expect(
        find.textContaining('“RS is tangent to the circle at R” is not true'),
        findsOneWidget,
      );
    });

    testWidgets('the tangent–chord selection reads as the theorem, not its '
        'transpose (Phase 162)', (tester) async {
      final construction = decodeDocument(
        jsonDecode(File('test/fixtures/tangent-chord.rgl').readAsStringSync())
            as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      final byName = {
        for (final o in construction.objects) o.attributes.name: o.id,
      };
      await pumpEditor(tester);
      await openPanel(tester);
      container.read(selectionProvider.notifier).selectMany([
        byName['b']!,
        byName['d']!,
        byName['e']!,
        byName['f']!,
      ]);
      await tester.pump();

      expect(find.text('angles BCE and BDC are equal'), findsOneWidget);
      expect(find.text('angles ECD and CBD are equal'), findsNothing);
      expect(find.textContaining('the angle from'), findsNothing);

      // And asked, it is proved — by the tangent–chord rule Phase 163
      // put back, with the tangency and two radii as the givens.
      await tester.ensureVisible(find.text('angles BCE and BDC are equal'));
      await tester.tap(find.text('angles BCE and BDC are equal'));
      await tester.pumpAndSettle();
      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(
        state.answer.proof!.steps.map((step) => step.rule),
        contains('tangent_chord'),
      );
      expect(
        find.textContaining('“angles BCE and BDC are equal” — proved'),
        findsOneWidget,
      );
    });

    testWidgets('a long chip wraps, and an asked eqangle reads as spelled', (
      tester,
    ) async {
      final construction = container.read(constructionProvider).construction;
      // Multi-character names make every label long enough to overflow
      // the 300 px docked panel on one line.
      final a = free('a', 'Alpha', 0, 0);
      final b = free('b', 'Beta', 6, 1);
      final c = free('c', 'Gamma', 7, 5);
      final d = free('d', 'Delta', 1, 4);
      final sides = [
        Segment(id: 's0', point1: a, point2: b),
        Segment(id: 's1', point1: b, point2: c),
        Segment(id: 's2', point1: c, point2: d),
        Segment(id: 's3', point1: d, point2: a),
      ];
      for (final object in [a, b, c, d, ...sides]) {
        construction.add(object);
      }
      await pumpEditor(tester);
      await openPanel(tester);
      container
          .read(selectionProvider.notifier)
          .selectMany(sides.map((side) => side.id));
      await tester.pump();

      final questions = askableQuestions(
        construction.objects,
        selectedIds: {for (final side in sides) side.id},
      );
      for (final question in questions) {
        final label = questionLabel(question);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        final lineHeight = paragraph.text.style!.fontSize! * 1.2;
        expect(
          paragraph.size.height,
          greaterThan(lineHeight * 1.5),
          reason: '"$label" must wrap, not fade out at the chip edge',
        );
        expect(paragraph.size.width, lessThanOrEqualTo(ProofPanel.panelWidth));
      }

      // Ask one: the header and the verdict carry the question's own
      // spelling, which is the sentence on the chip.
      final question = questions.first;
      await tester.ensureVisible(find.text(questionLabel(question)));
      await tester.tap(find.text(questionLabel(question)));
      await tester.pumpAndSettle();
      expect(
        find.text(questionLabel(question)),
        findsNWidgets(2),
        reason: 'the chip, still offered, and the answer header',
      );
      expect(
        find.textContaining('“${questionLabel(question)}”'),
        findsOneWidget,
      );
    });

    testWidgets('a selection offers what it can phrase, and asking works', (
      tester,
    ) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      expect(find.text('Ask about the selection'), findsNothing);

      // Four points: cyclic plus the three pairings of perp/para/cong.
      container
          .read(selectionProvider.notifier)
          .selectMany(rig.goal.points.map((point) => point.id));
      await tester.pump();
      expect(find.text('Ask about the selection'), findsOneWidget);
      // The chip reads the question's own spelling (Phase 162), which
      // is the selection's order, not the canonical fact's.
      final question = askableQuestions(
        container.read(constructionProvider).construction.objects,
        selectedIds: rig.goal.points.map((point) => point.id).toSet(),
      ).singleWhere((q) => Fact.of(q.canonical) == rig.goal);
      final chip = questionLabel(question);
      expect(find.text(chip), findsOneWidget);

      await tester.ensureVisible(find.text(chip));
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();

      // Proved, and the proof reads as the step list already does.
      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(find.textContaining('proved'), findsOneWidget);
      // The numbered steps, read from the top (the list virtualizes).
      expect(find.text('[1]'), findsOneWidget);
      // And it still points at the figure.
      await tester.tap(
        find.text(readFact(state.answer.proof!.steps.first.fact)).first,
      );
      await tester.pump();
      expect(container.read(proofHighlightProvider), isNotEmpty);
    });

    testWidgets('a refuted question says false, not unprovable', (
      tester,
    ) async {
      final rig = seedVarignon();
      final construction = container.read(constructionProvider).construction;
      await pumpEditor(tester);
      await openPanel(tester);
      // The four *free* points: AB ⟂ CD is false of this quadrilateral.
      final free = construction.objects
          .whereType<FreePoint>()
          .map((point) => point.id)
          .toList();
      expect(free, hasLength(4));
      container.read(selectionProvider.notifier).selectMany(free);
      await tester.pump();

      final names = [
        for (final id in free)
          describePoint(construction.byId(id)! as GeoPoint),
      ];
      final chip = find.text(
        '${names[0]}${names[1]} is perpendicular to ${names[2]}${names[3]}',
      );
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.refuted);
      expect(
        find.textContaining('is not true of this construction'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot prove'),
        findsNothing,
        reason: 'false and unprovable must never read the same',
      );
      expect(rig.goal, isNotNull);
    });

    testWidgets('the user document answers "true, but not provable"', (
      tester,
    ) async {
      // perp-true-unproved.rgl end to end: select the two segments the
      // question is about and ask. The honest answer is the middle one.
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      await pumpEditor(tester);
      await openPanel(tester);

      // Segments DC and FD — the two the theorem relates.
      final segments = construction.objects.whereType<Segment>().toList();
      GeoPoint named(String name) => construction.objects
          .whereType<GeoPoint>()
          .firstWhere((point) => point.attributes.name == name);
      final d = named('D');
      final c = named('C');
      final f = named('F');
      bool joins(Segment s, GeoPoint x, GeoPoint y) =>
          (s.point1.id == x.id && s.point2.id == y.id) ||
          (s.point1.id == y.id && s.point2.id == x.id);
      final dc = segments.firstWhere((s) => joins(s, d, c));
      final fd = segments.firstWhere((s) => joins(s, f, d));
      container.read(selectionProvider.notifier).selectMany([dc.id, fd.id]);
      await tester.pump();

      await tester.ensureVisible(
        find.textContaining('is perpendicular to').first,
      );
      await tester.tap(find.textContaining('is perpendicular to').first);
      await tester.pumpAndSettle();

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.unproved);
      expect(find.textContaining('cannot prove it'), findsOneWidget);
      expect(
        find.textContaining('limit of the rule set'),
        findsOneWidget,
        reason: 'the reader must not read this as their theorem being wrong',
      );
    });

    testWidgets('and offers the point that would settle it', (tester) async {
      // The other half of the test above, and Phase 153's user-facing
      // half: the honest "cannot prove it" is followed by an offer, the
      // search finds JGEX's own point, and the answer says what it
      // built before showing steps that cite it.
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      await pumpEditor(tester);
      await openPanel(tester);

      GeoPoint named(String name) => construction.objects
          .whereType<GeoPoint>()
          .firstWhere((point) => point.attributes.name == name);
      final segments = construction.objects.whereType<Segment>().toList();
      bool joins(Segment s, GeoPoint x, GeoPoint y) =>
          (s.point1.id == x.id && s.point2.id == y.id) ||
          (s.point1.id == y.id && s.point2.id == x.id);
      container.read(selectionProvider.notifier).selectMany([
        segments.firstWhere((s) => joins(s, named('D'), named('C'))).id,
        segments.firstWhere((s) => joins(s, named('F'), named('D'))).id,
      ]);
      await tester.pump();
      await tester.ensureVisible(
        find.textContaining('is perpendicular to').first,
      );
      await tester.tap(find.textContaining('is perpendicular to').first);
      await tester.pumpAndSettle();

      final offer = find.text('Look for a point that would settle it');
      expect(offer, findsOneWidget);
      await tester.ensureVisible(offer);
      await tester.tap(offer);
      await tester.pumpAndSettle();

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(state.answer.auxiliary, isNotNull);

      // Named like a drawn point, and said out loud — a proof whose
      // steps cite a point the figure does not contain is not a proof
      // the reader can follow.
      expect(state.answer.auxiliary!.attributes.name, 'G');
      expect(
        find.textContaining('The proof needs G, which your figure does not'),
        findsOneWidget,
      );
      expect(find.textContaining('Midpoint of B, C'), findsOneWidget);
      expect(
        find.text('Look for a point that would settle it'),
        findsNothing,
        reason: 'the offer is spent',
      );

      // And accepting it is an ordinary reversible command.
      expect(construction.objects.contains(state.answer.auxiliary), isFalse);
      await tester.tap(find.text('Add it'));
      await tester.pumpAndSettle();
      expect(
        container.read(constructionProvider).construction.objects,
        contains(state.answer.auxiliary),
      );
      container.read(commandStackProvider.notifier).undo();
      await tester.pumpAndSettle();
      expect(
        container.read(constructionProvider).construction.objects,
        isNot(contains(state.answer.auxiliary)),
      );
    });

    testWidgets('an angle step shows the chase, not just its premises', (
      tester,
    ) async {
      // The panel is where M-P3's readability claim is settled: an
      // `angle_arithmetic` reason names what a step used and explains
      // nothing on its own. `perp-true-unproved.rgl` derives ten of
      // them, so this is the real thing rather than a rig.
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      final ready = container.read(proverProvider) as ProverReady;
      final goal = provableGoals(ready.database).firstWhere(
        (fact) =>
            ready.database.derivationOf(fact)!.rule == angleArithmeticRule,
      );
      final proof = ready.proofOf(goal)!;
      final step = proof.steps.last;
      expect(step.chase, isNotNull);

      final goalRow = find.text(readFact(goal));
      await expandGroup(tester, KindGroup(goal.kind));
      await tester.scrollUntilVisible(
        goalRow,
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(goalRow);
      await tester.pumpAndSettle();
      await openProof(tester, goal);
      await tester.pumpAndSettle();

      final lines = chaseLines(step, proof);
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(
          inPanel(find.text(line)),
          findsAtLeastNWidgets(1),
          reason: 'the chase line "$line" is not on screen',
        );
      }
      expect(inPanel(find.textContaining('⟹')), findsAtLeastNWidgets(1));
    });

    testWidgets('a DD step is left alone — its rule is the explanation', (
      tester,
    ) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      // A midline is parallel to the diagonal: one `midline_para` step
      // over `midp` givens, which the angle algebra cannot read — so this
      // proof is all DD, and adding a second line to every step would be
      // noise. (Varignon's theorem itself is no longer the rig for this:
      // since Phase 166 its last step is the closure's, chase and all.)
      final mab = rig.midpoints[0];
      final mbc = rig.midpoints[1];
      final midline = Fact(PredicateKind.para, [
        mab.point1,
        mbc.point2,
        mab,
        mbc,
      ]);
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(midline)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(midline)));
      await tester.pumpAndSettle();
      await openProof(tester, midline);
      await tester.pumpAndSettle();

      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        midline,
      )!;
      expect(proof.deductions.map((step) => step.rule), ['midline_para']);
      expect(proof.steps.every((step) => step.chase == null), isTrue);
      expect(inPanel(find.textContaining('θ(')), findsNothing);
    });

    testWidgets('an answer can go back to everything the run found', (
      tester,
    ) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      container
          .read(selectionProvider.notifier)
          .selectMany(rig.goal.points.map((point) => point.id));
      await tester.pump();
      final chip = find.text(
        questionLabel(
          askableQuestions(
            container.read(constructionProvider).construction.objects,
            selectedIds: rig.goal.points.map((point) => point.id).toSet(),
          ).singleWhere((q) => Fact.of(q.canonical) == rig.goal),
        ),
      );
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(container.read(proverProvider), isA<ProverAnswered>());

      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pump();

      expect(container.read(proverProvider), isA<ProverReady>());
    });

    testWidgets('a non-Euclidean document says so instead of a list', (
      tester,
    ) async {
      container
          .read(constructionProvider.notifier)
          .replace(
            Construction(
              kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
            ),
          );
      await pumpEditor(tester);
      await openPanel(tester);

      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Euclidean'), findsOneWidget);
      expect(inPanel(find.byType(ListTile)), findsNothing);
    });

    testWidgets('an exhausted run offers to keep going', (tester) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);

      // The shipped budget is far above Varignon, so exhaustion is
      // reached through the provider's per-call override — the state is
      // what the panel has to render, not how it was arrived at.
      await container.read(proverProvider.notifier).prove(applicationBudget: 3);
      await tester.pump();

      expect(find.text('Keep going'), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();

      expect(find.text('Keep going'), findsNothing);
      expect(
        (container.read(proverProvider) as ProverReady).reachedFixpoint,
        isTrue,
      );
    });

    testWidgets('the Stop button exists only while running, and a tap '
        'publishes the prefix', (tester) async {
      // A document whose run outlives its first chunk — Varignon
      // completes inside one, so a Stop there is never on screen long
      // enough to tap.
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      await pumpEditor(tester);
      await openPanel(tester);

      expect(inPanel(find.byTooltip('Stop')), findsNothing);
      expect(find.byTooltip('Prove'), findsOneWidget);

      // Unawaited on purpose: the run suspends at its first yield — a
      // timer the widget test's fake async holds until pumped — so the
      // running state is what is on screen.
      final pending = container.read(proverProvider.notifier).prove();
      await tester.pump();

      expect(container.read(proverProvider), isA<ProverRunning>());
      expect(inPanel(find.byTooltip('Stop')), findsOneWidget);
      expect(find.byTooltip('Prove'), findsNothing);
      // The first pass ran before the first yield, so the body already
      // reports how far the run has got rather than a bare 'Deriving…'.
      expect(find.textContaining('steps so far'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop'));
      await tester.pumpAndSettle();
      await pending;

      final state = container.read(proverProvider) as ProverReady;
      expect(state.reachedFixpoint, isFalse);
      expect(inPanel(find.byTooltip('Stop')), findsNothing);

      // The resume row sits at the foot of a list this document fills
      // far past the fold, so it has to be scrolled to before a finder
      // can see it.
      await tester.drag(
        inPanel(find.byType(Scrollable)),
        const Offset(0, -5000),
      );
      await tester.pump();
      expect(
        find.text('Keep going'),
        findsOneWidget,
        reason:
            'a stopped run resumes through the same row a spent '
            'budget does',
      );
    });

    testWidgets('a row is a sentence; the raw spelling is its tooltip', (
      tester,
    ) async {
      // Phase 157: prose is the row, and `describeFact`'s spelling —
      // what `Proof.render()` prints — stays reachable on it without a
      // second gesture design: a hover on desktop, a long-press on
      // touch, which is what a Tooltip already is.
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      await expandGroup(tester, const KindGroup(PredicateKind.para));

      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      expect(find.text(readFact(rig.goal)), findsOneWidget);
      expect(
        find.text(describeFact(rig.goal)),
        findsNothing,
        reason: 'the raw spelling must be the tooltip, not the row',
      );
      expect(find.byTooltip(describeFact(rig.goal)), findsOneWidget);

      // The proof view reads the same way: prose rows, raw tooltips —
      // on the goal header and on every step.
      await openProof(tester, rig.goal);
      await tester.pump();
      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      final step = proof.steps.first;
      expect(find.text(readFact(step.fact)), findsWidgets);
      expect(find.byTooltip(describeFact(step.fact)), findsWidgets);
      expect(find.text(describeFact(step.fact)), findsNothing);
    });

    testWidgets('the reading convention is stated once, at the foot of a '
        'list that needs it', (tester) async {
      // `perp-true-unproved.rgl` derives eqangle facts, whose plain "are
      // equal" leans on the mod-π convention — said once as a footnote,
      // not hedged on every line.
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      final ready = container.read(proverProvider) as ProverReady;
      expect(
        conventionApplies(provableGoals(ready.database)),
        isTrue,
        reason: 'the rig must derive an eqangle for this test to bite',
      );
      // The footnote sits below a list this document fills far past the
      // fold, and the docked list materializes lazily — a single long
      // drag stops short, so scroll until the note exists.
      await tester.scrollUntilVisible(
        find.text(factReadingConvention),
        200,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      expect(find.text(factReadingConvention), findsOneWidget);
    });

    testWidgets('no note where no fact leans on the convention', (
      tester,
    ) async {
      // Varignon's parallelogram proof is midp/para steps only — a
      // footnote there would be a claim about facts the proof does not
      // contain.
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await openProof(tester, rig.goal);
      await tester.pumpAndSettle();

      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
      expect(
        conventionApplies(proof.steps.map((step) => step.fact)),
        isFalse,
        reason: 'the rig must stay convention-free for this test to bite',
      );
      expect(find.text(factReadingConvention), findsNothing);
    });

    testWidgets('a raw-spelling tooltip waits out a passing pointer and '
        'dies on scroll', (tester) async {
      // The two guards against the web renderer's tooltip-overlay race
      // (see rawSpellingTooltip): a row the pointer merely passes over
      // must never begin to show, and a tooltip that is showing must be
      // gone the moment the list scrolls. The crash itself is only
      // reproducible under the real engine's mouse tracker — these pin
      // the behaviour each guard exists to provide.
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      final database = (container.read(proverProvider) as ProverReady).database;
      // Every group open, so the list overflows and a wheel actually
      // scrolls it — folded, Varignon's overview fits the panel and a
      // wheel would move nothing, which is no test of the guard. The
      // hovered row is the first of the first group: at the top of the
      // list, no scrolling needed to reach it.
      final groups = groupedGoals(
        provableGoals(database),
        carriers: (container.read(proverProvider) as ProverReady).carriers,
      );
      for (final kind in groups.keys) {
        await expandGroup(tester, kind);
      }
      final goal = groups.values.first.first;
      expect(rig.goal, isNot(goal), reason: 'rig sanity: distinct facts');
      // Opening the groups scrolled the list to its foot; back to the top.
      await tester.scrollUntilVisible(
        find.text(readFact(goal)),
        -60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(goal)));
      await tester.pumpAndSettle();
      final overlayText = find.text(describeFact(goal));

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 7,
      );
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text(readFact(goal))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        overlayText,
        findsNothing,
        reason:
            'a pointer merely passing through must not raise the '
            'overlay — that churn is the crash',
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(overlayText, findsOneWidget, reason: 'a settled hover shows it');

      // A small wheel scroll: the row shifts 4 px, so the pointer stays
      // inside it — only the scroll listener can be what dismisses.
      final wheel = TestPointer(8, PointerDeviceKind.mouse);
      wheel.hover(tester.getCenter(find.text(readFact(goal))));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 4)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        overlayText,
        findsNothing,
        reason: 'no tooltip overlay may exist while list rows churn',
      );
    });
  });

  group('the derived list, grouped like the object tree', () {
    // Phase 158: a flat column in database order became a per-kind
    // overview — headers in `PredicateKind`'s declaration order, folded
    // until opened, empty kinds absent, and what is about the run or the
    // reading kept outside the groups.
    test('groupedGoals buckets by kind in declaration order, whatever '
        'order the facts arrive in', () {
      final a = free('a', 'A', 0, 0);
      final b = free('b', 'B', 1, 0);
      final c = free('c', 'C', 2, 0);
      final d = free('d', 'D', 3, 0);
      final cong = Fact(PredicateKind.cong, [a, b, c, d]);
      final coll1 = Fact(PredicateKind.coll, [a, b, c]);
      final coll2 = Fact(PredicateKind.coll, [b, c, d]);
      final para = Fact(PredicateKind.para, [a, b, c, d]);

      final groups = groupedGoals([cong, coll1, para, coll2]);

      expect(groups.keys, const [
        KindGroup(PredicateKind.coll),
        KindGroup(PredicateKind.para),
        KindGroup(PredicateKind.cong),
      ]);
      // Within a bucket, arrival order — the database's own.
      expect(groups[const KindGroup(PredicateKind.coll)], [coll1, coll2]);
      expect(groups[const KindGroup(PredicateKind.para)], [para]);
      expect(groups[const KindGroup(PredicateKind.cong)], [cong]);
    });

    test('an empty bucket is absent, not present with zero', () {
      expect(groupedGoals(const []), isEmpty);
      final a = free('a', 'A', 0, 0);
      final b = free('b', 'B', 1, 0);
      final c = free('c', 'C', 2, 0);
      final groups = groupedGoals([
        Fact(PredicateKind.midp, [a, b, c]),
      ]);
      expect(groups.keys, const [KindGroup(PredicateKind.midp)]);
      expect(groups.containsKey(const KindGroup(PredicateKind.coll)), isFalse);
    });

    test('composed with the selection filter, a header counts the '
        'filtered facts', () async {
      final c = loadPerpFixture(name: 'C');
      await container.read(proverProvider.notifier).prove();
      final database = (container.read(proverProvider) as ProverReady).database;
      final narrowed = provableGoals(database, selectedIds: {c.id});
      final groups = groupedGoals(narrowed);

      expect(
        groups.values.fold(0, (sum, facts) => sum + facts.length),
        narrowed.length,
      );
      for (final facts in groups.values) {
        for (final fact in facts) {
          expect(fact.points, contains(c));
        }
      }
      // Grouping after filtering is what makes the surviving headers the
      // answer to "what does the prover know about this?" — fewer of
      // them than the full run has.
      expect(groups.keys, const [
        KindGroup(PredicateKind.para),
        KindGroup(PredicateKind.perp),
      ]);
      expect(
        groupedGoals(provableGoals(database)).length,
        greaterThan(groups.length),
      );
    });

    testWidgets('groups start folded with a count, open on a tap, and '
        'list their rows in database order', (tester) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      final ready = container.read(proverProvider) as ProverReady;
      final groups = groupedGoals(
        provableGoals(ready.database),
        carriers: ready.carriers,
      );
      expect(groups.length, greaterThan(1), reason: 'rig sanity');

      // Every kind with something has a header, every header is folded
      // and carries its count, and no row is on screen.
      for (final MapEntry(key: group, value: facts) in groups.entries) {
        final header = find.ancestor(
          of: inPanel(find.text(group.label)),
          matching: find.byType(InkWell),
        );
        expect(header, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.text('${facts.length}')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: header,
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsOneWidget,
        );
      }
      expect(inPanel(find.byType(ListTile)), findsNothing);

      // Opening one group shows its rows, in the order the database
      // holds them, and the count steps aside for them.
      final group = groups.keys.first;
      final facts = groups[group]!;
      await expandGroup(tester, group);
      final header = find.ancestor(
        of: inPanel(find.text(group.label)),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: header, matching: find.text('${facts.length}')),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.byIcon(Icons.expand_more)),
        findsOneWidget,
      );
      for (final fact in facts) {
        await tester.ensureVisible(find.text(readFact(fact)));
      }
      final tops = [
        for (final fact in facts)
          tester.getTopLeft(find.text(readFact(fact))).dy,
      ];
      expect(tops, [...tops]..sort());
      // The other groups stayed folded.
      expect(inPanel(find.byType(ListTile)), findsNWidgets(facts.length));

      // And a second tap folds it again.
      await expandGroup(tester, group);
      expect(inPanel(find.byType(ListTile)), findsNothing);
    });

    testWidgets('a kind with nothing in it has no header — with and '
        'without a selection', (tester) async {
      final c = loadPerpFixture(name: 'C');
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      final database = (container.read(proverProvider) as ProverReady).database;

      final carriers = (container.read(proverProvider) as ProverReady).carriers;
      final all = groupedGoals(provableGoals(database), carriers: carriers);
      expect(
        all.length,
        lessThan(PredicateKind.values.length),
        reason: 'the rig must leave some kind underived',
      );
      for (final kind in PredicateKind.values) {
        expect(
          inPanel(find.text(predicateKindLabel(kind))),
          all.containsKey(KindGroup(kind)) ? findsOneWidget : findsNothing,
        );
      }

      // Under a selection the survivors are the answer, and the kinds
      // the selection emptied are gone rather than shown at zero.
      final narrowed = groupedGoals(
        provableGoals(database, selectedIds: {c.id}),
        carriers: carriers,
      );
      expect(narrowed.length, lessThan(all.length), reason: 'rig sanity');
      container.read(selectionProvider.notifier).select(c.id);
      await tester.pump();
      for (final kind in PredicateKind.values) {
        expect(
          inPanel(find.text(predicateKindLabel(kind))),
          narrowed.containsKey(KindGroup(kind)) ? findsOneWidget : findsNothing,
        );
      }
      expect(inPanel(find.text('0')), findsNothing);
    });

    testWidgets('a selection that empties every bucket reaches the note, '
        'not an empty column', (tester) async {
      seedVarignon();
      final stranger = free('e', 'E', 3, 3);
      container.read(constructionProvider).construction.add(stranger);
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      final database = (container.read(proverProvider) as ProverReady).database;
      expect(
        provableGoals(database, selectedIds: {stranger.id}),
        isEmpty,
        reason: 'nothing may be derived about a point in no relation',
      );

      container.read(selectionProvider.notifier).select(stranger.id);
      await tester.pump();
      for (final kind in PredicateKind.values) {
        expect(inPanel(find.text(predicateKindLabel(kind))), findsNothing);
      }
      expect(
        find.textContaining('Nothing derived about the selection'),
        findsOneWidget,
      );
    });

    testWidgets('Keep going sits outside the groups', (tester) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await container.read(proverProvider.notifier).prove(applicationBudget: 3);
      await tester.pump();

      // Every group folded, and the run's own control is still there —
      // it is about the run, not about a kind, so no fold can hide it.
      expect(inPanel(find.byIcon(Icons.expand_more)), findsNothing);
      expect(find.text('Keep going'), findsOneWidget);
      expect(inPanel(find.byType(ListTile)), findsOneWidget);
    });

    testWidgets('the reading convention sits outside the groups', (
      tester,
    ) async {
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      container.read(constructionProvider.notifier).replace(construction);
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      // Nothing opened, and the note is at the foot regardless: it is
      // about how every row reads, not about one kind's rows.
      expect(inPanel(find.byIcon(Icons.expand_more)), findsNothing);
      await tester.ensureVisible(find.text(factReadingConvention));
      expect(find.text(factReadingConvention), findsOneWidget);
    });
  });

  group('the trivial group, and the row that points', () {
    // Phase 158b.
    test('groupedGoals puts what the carriers call trivial last, out of '
        'its kind — and has no such group without carriers', () {
      final a = free('a', 'A', 0, 0);
      final b = free('b', 'B', 1, 0);
      final c = free('c', 'C', 2, 0);
      final d = free('d', 'D', 0, 1);
      final e = free('e', 'E', 1, 1);
      final coll = Fact(PredicateKind.coll, [a, b, c]);
      final selfPara = Fact(PredicateKind.para, [a, b, a, c]);
      final realPara = Fact(PredicateKind.para, [a, b, d, e]);
      final carriers = CarrierIndex.over([coll]);

      final groups = groupedGoals([selfPara, realPara], carriers: carriers);
      expect(groups.keys, const [
        KindGroup(PredicateKind.para),
        TrivialGroup(),
      ]);
      expect(groups[const KindGroup(PredicateKind.para)], [realPara]);
      expect(groups[const TrivialGroup()], [selfPara]);

      // Nothing trivial, no group — the empty-bucket rule.
      expect(groupedGoals([realPara], carriers: carriers).keys, const [
        KindGroup(PredicateKind.para),
      ]);
      // No carriers, no notion of trivial.
      expect(groupedGoals([selfPara, realPara]).keys, const [
        KindGroup(PredicateKind.para),
      ]);
    });

    test(
      'ProverReady.carriers is the closure of the run\'s own facts',
      () async {
        loadPerpFixture(name: 'C');
        await container.read(proverProvider.notifier).prove();
        final ready = container.read(proverProvider) as ProverReady;
        final colls = ready.database.facts.where(
          (fact) => fact.kind == PredicateKind.coll,
        );
        expect(colls, isNotEmpty, reason: 'rig sanity');
        for (final coll in colls) {
          final [x, y, z] = coll.points;
          expect(ready.carriers.sameLine(x, y, y, z), isTrue);
        }
      },
    );

    testWidgets('the Trivial header is last, folded, and counts what the '
        'closure calls trivial', (tester) async {
      loadPerpFixture(name: 'C');
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      final ready = container.read(proverProvider) as ProverReady;
      final goals = provableGoals(ready.database);
      final trivial = goals.where(ready.carriers.isTrivial).toList();
      expect(trivial.length, greaterThan(1), reason: 'the rig must pollute');
      final groups = groupedGoals(goals, carriers: ready.carriers);
      expect(groups.keys.last, const TrivialGroup());
      expect(groups[const TrivialGroup()], trivial);

      final header = find.ancestor(
        of: inPanel(find.text('Trivial')),
        matching: find.byType(InkWell),
      );
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('${trivial.length}')),
        findsOneWidget,
      );
      // Below every kind header.
      final top = tester.getTopLeft(inPanel(find.text('Trivial'))).dy;
      for (final group in groups.keys) {
        if (group is TrivialGroup) continue;
        expect(
          tester.getTopLeft(inPanel(find.text(group.label))).dy,
          lessThan(top),
        );
      }
      // Its rows are not in their kind's group — on this fixture every
      // derived parallel is a line with itself, so the parallel group
      // is gone entirely, and no kind group holds a trivial fact.
      expect(groups.containsKey(const KindGroup(PredicateKind.para)), isFalse);
      for (final MapEntry(key: group, value: facts) in groups.entries) {
        if (group is KindGroup) {
          expect(facts.any(ready.carriers.isTrivial), isFalse);
        }
      }
      expect(find.text(trivialGroupNote), findsNothing);

      // Opened, it says what it is, then lists them.
      await expandGroup(tester, const TrivialGroup());
      expect(find.text(trivialGroupNote), findsOneWidget);
      expect(find.text(readFact(trivial.first)), findsOneWidget);
    });

    testWidgets('a tap on a row lights its points; the arrow opens the '
        'proof', (tester) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await expandGroup(tester, const KindGroup(PredicateKind.para));
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      expect(container.read(proofHighlightProvider), isEmpty);

      await tester.tap(find.text(readFact(rig.goal)));
      await tester.pump();
      expect(
        container.read(proofHighlightProvider),
        rig.goal.points.map((point) => point.id).toSet(),
      );
      // Still the list — no proof opened.
      expect(find.byTooltip('Back to the list'), findsNothing);
      final row = tester.widget<ListTile>(
        find.ancestor(
          of: find.text(readFact(rig.goal)),
          matching: find.byType(ListTile),
        ),
      );
      expect(row.selected, isTrue);

      // A second tap clears — a highlight the user cannot turn off is one
      // they would have to close the panel to escape.
      await tester.tap(find.text(readFact(rig.goal)));
      await tester.pump();
      expect(container.read(proofHighlightProvider), isEmpty);

      // The arrow opens the proof, and opening drops the emphasis.
      await tester.tap(find.text(readFact(rig.goal)));
      await tester.pump();
      await openProof(tester, rig.goal);
      expect(find.byTooltip('Back to the list'), findsOneWidget);
      expect(container.read(proofHighlightProvider), isEmpty);
    });
  });

  group('one spelling across the panel', () {
    test('questionLabel is readFact of the canonical statement', () {
      final question = ProverQuestion(PredicateKind.perp, [
        Predicate(PredicateKind.perp, [
          free('a', 'A', 0, 0),
          free('b', 'B', 1, 0),
          free('c', 'C', 2, 1),
          free('d', 'D', 2, 3),
        ]),
      ]);
      expect(questionLabel(question), 'AB is perpendicular to CD');
      expect(
        questionLabel(question),
        readFact(Fact.of(question.canonical)),
        reason: 'the chip and the derived row must be one sentence',
      );
    });

    test('verdictMessage quotes the sentence it judges', () {
      final question = ProverQuestion(PredicateKind.cong, [
        Predicate(PredicateKind.cong, [
          free('a', 'A', 0, 0),
          free('b', 'B', 3, 0),
          free('c', 'C', 0, 1),
          free('d', 'D', 3, 1),
        ]),
      ]);
      final message = verdictMessage(
        ProverAnswer(question: question, verdict: ProverVerdict.refuted),
      );
      // A sentence as the subject of another sentence needs its
      // boundary marked, or the reading garden-paths.
      expect(message, contains('“AB and CD are equal in length”'));
      expect(message, contains('is not true of this construction'));
    });

    test('an exhausted search is a stronger answer, and reads as one', () {
      final question = ProverQuestion(PredicateKind.cong, [
        Predicate(PredicateKind.cong, [
          free('a', 'A', 0, 0),
          free('b', 'B', 3, 0),
          free('c', 'C', 0, 1),
          free('d', 'D', 3, 1),
        ]),
      ]);
      const verdict = ProverVerdict.unproved;
      expect(
        verdictMessage(ProverAnswer(question: question, verdict: verdict)),
        contains('these rules cannot prove it'),
      );
      // "and no single extra point helps either" is more than the rule
      // set's limit, so it must not read as the same sentence.
      final exhausted = verdictMessage(
        ProverAnswer(
          question: question,
          verdict: verdict,
          searchExhausted: true,
        ),
      );
      expect(exhausted, contains('nor any one extra point'));
      expect(exhausted, isNot(contains('limit of the rule set')));
    });

    test('conventionApplies flags exactly the plain-read kinds', () {
      final p = [for (var i = 0; i < 8; i++) free('$i', '', i * 1.0, 0)];
      Fact fact(PredicateKind kind, int arity) =>
          Fact(kind, p.sublist(0, arity));
      expect(conventionApplies([fact(PredicateKind.eqangle, 8)]), isTrue);
      expect(conventionApplies([fact(PredicateKind.simtri, 6)]), isTrue);
      expect(conventionApplies([fact(PredicateKind.contri, 6)]), isTrue);
      expect(
        conventionApplies([
          fact(PredicateKind.para, 4),
          fact(PredicateKind.cong, 4),
          fact(PredicateKind.coll, 3),
          fact(PredicateKind.cyclic, 4),
          fact(PredicateKind.midp, 3),
          fact(PredicateKind.eqratio, 8),
        ]),
        isFalse,
      );
      expect(conventionApplies(const []), isFalse);
    });
  });

  /// Phase 154. On a phone the panel is a modal sheet, and until this
  /// phase it was a [FractionallySizedBox] at half the screen with no
  /// way to grow: a proof of any length was read four steps at a time.
  /// The tests here are about the *gesture*, not the numbers — asserting
  /// an initial fraction would pin the shape of the bug rather than the
  /// behaviour that fixes it.
  group('the proof sheet on a phone', () {
    const phone = Size(400, 800);

    /// The bar is one horizontal scrollable at this width, so the Proof
    /// button has to be scrolled to before it can be tapped — the same
    /// move `app_bar_layout_test.dart` makes.
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

    /// Drags the panel's own scrollable by [dy] — negative is upwards,
    /// which is the gesture that grows the sheet.
    Future<void> dragPanel(WidgetTester tester, double dy) async {
      await tester.drag(
        find.descendant(
          of: find.byType(ProofPanel),
          matching: find.byType(Scrollable),
        ),
        Offset(0, dy),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the button opens a sheet, not a docked panel', (tester) async {
      await pumpPhoneEditor(tester);
      expect(find.byType(ProofPanel), findsNothing);

      await openSheet(tester);

      expect(find.byType(ProofPanel), findsOneWidget);
      expect(find.textContaining('Nothing proved yet'), findsOneWidget);
      // The figure is still visible behind it: the sheet opens at half
      // the screen, which is the intent the phase kept.
      expect(
        tester.getSize(find.byType(ProofPanel)).height,
        lessThan(phone.height / 2 + 1),
      );
    });

    testWidgets('dragging the content up grows it past half the screen', (
      tester,
    ) async {
      seedVarignon();
      await pumpPhoneEditor(tester);
      await openSheet(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      final opened = tester.getSize(find.byType(ProofPanel)).height;
      await dragPanel(tester, -300);
      final grown = tester.getSize(find.byType(ProofPanel)).height;

      expect(grown, greaterThan(opened));
      // Past the old ceiling — this is the defect, in one expectation.
      expect(grown, greaterThan(phone.height / 2));
    });

    testWidgets('the empty state can be grown too — it is what the panel '
        'opens on', (tester) async {
      await pumpPhoneEditor(tester);
      await openSheet(tester);

      final opened = tester.getSize(find.byType(ProofPanel)).height;
      await dragPanel(tester, -300);

      expect(
        tester.getSize(find.byType(ProofPanel)).height,
        greaterThan(opened),
      );
    });

    testWidgets('dragging it down tucks it away without dismissing', (
      tester,
    ) async {
      seedVarignon();
      await pumpPhoneEditor(tester);
      await openSheet(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      final opened = tester.getSize(find.byType(ProofPanel)).height;
      await dragPanel(tester, 400);

      // Smaller, still there: a reader glancing at the figure has not
      // lost the proof they were in the middle of.
      final tucked = tester.getSize(find.byType(ProofPanel)).height;
      expect(tucked, lessThan(opened));
      expect(find.byType(ProofPanel), findsOneWidget);
    });

    testWidgets('the back affordance and Keep going survive the minimum size', (
      tester,
    ) async {
      seedVarignon();
      await pumpPhoneEditor(tester);
      await openSheet(tester);
      await container.read(proverProvider.notifier).prove(applicationBudget: 3);
      await tester.pumpAndSettle();

      // A goal open, so the header carries the back arrow. Groups start
      // folded, so open the first one before reaching for its row —
      // otherwise the first tile is *Keep going*.
      final ready = container.read(proverProvider) as ProverReady;
      await expandGroup(
        tester,
        groupedGoals(
          provableGoals(ready.database),
          carriers: ready.carriers,
        ).keys.first,
      );
      await tester.tap(inPanel(find.byTooltip('Show proof')).first);
      await tester.pumpAndSettle();
      await dragPanel(tester, 400);

      // The header is outside the scrollable and pinned, so shrinking
      // cannot hide it.
      expect(find.byTooltip('Back to the list'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pumpAndSettle();

      // And the run's own control is reachable by scrolling within
      // whatever height is left. Both moves, in this order: the list is
      // lazy, so the tile may not be built until the list is scrolled
      // toward it (the open group's rows push it past the cache extent
      // at the tucked height), and once built a finder matches it
      // off-screen, where only `ensureVisible` brings it in.
      await tester.scrollUntilVisible(
        find.text('Keep going'),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Keep going')).bottom,
        lessThanOrEqualTo(phone.height),
      );
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(
        (container.read(proverProvider) as ProverReady).reachedFixpoint,
        isTrue,
      );
    });

    testWidgets('the docked panel owns its own scrolling — no controller, '
        'and it still scrolls', (tester) async {
      seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();

      final panel = tester.widget<ProofPanel>(find.byType(ProofPanel));
      expect(panel.scrollController, isNull);

      final list = inPanel(find.byType(Scrollable));
      final before = tester.getSize(find.byType(ProofPanel));
      await tester.drag(list, const Offset(0, -60));
      await tester.pumpAndSettle();

      // A docked panel is sized by its column, not by a gesture: the
      // drag scrolled and did not resize anything.
      expect(tester.getSize(find.byType(ProofPanel)), before);
    });
  });
}
