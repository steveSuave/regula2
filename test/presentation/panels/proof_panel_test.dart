import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/prover_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/main.dart';
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
      final goalText = describeFact(rig.goal);
      await tester.scrollUntilVisible(
        find.text(goalText),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      expect(find.text(goalText), findsOneWidget);

      await tester.tap(find.text(goalText));
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

      // Short enough now that the whole narrowed list is laid out, so
      // the rendered rows are the list — and every one names M.
      expect(inPanel(find.byType(ListTile)), findsNWidgets(narrowed.length));
      for (final goal in narrowed) {
        expect(find.text(describeFact(goal)), findsOneWidget);
      }
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
  });
}
