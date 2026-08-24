import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/proof_highlight_provider.dart';
import 'package:regula/application/providers/prover_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_translation.dart';
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
      await tester.scrollUntilVisible(
        find.text(goalText),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(goalText));
      await tester.pumpAndSettle();
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
        expect(find.text(readFact(goal)), findsOneWidget);
      }
    });

    testWidgets('tapping a step points at what it is about', (tester) async {
      final rig = seedVarignon();
      await pumpEditor(tester);
      await openPanel(tester);
      await tester.tap(find.byTooltip('Prove'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(readFact(rig.goal)));
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
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(readFact(rig.goal)));
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
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(readFact(rig.goal)));
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
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(readFact(rig.goal)));
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
      final names = rig.goal.points.map(describePoint).toList();
      final chip =
          '${names[0]}${names[1]} is parallel to ${names[2]}${names[3]}';
      expect(find.text(chip), findsOneWidget);

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
      await tester.tap(
        find.text(
          '${names[0]}${names[1]} is perpendicular to ${names[2]}${names[3]}',
        ),
      );
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
            )
            as Map<String, dynamic>,
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
            )
            as Map<String, dynamic>,
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
      await tester.scrollUntilVisible(
        goalRow,
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(goalRow);
      await tester.pumpAndSettle();
      await tester.tap(goalRow);
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
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();

      // Varignon reaches its parallelogram through `midp`, which the
      // angle algebra cannot read — so this proof is all DD, and adding
      // a second line to every step would be noise.
      final proof = (container.read(proverProvider) as ProverReady).proofOf(
        rig.goal,
      )!;
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
      final names = rig.goal.points.map(describePoint).toList();
      await tester.tap(
        find.text(
          '${names[0]}${names[1]} is parallel to ${names[2]}${names[3]}',
        ),
      );
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
            )
            as Map<String, dynamic>,
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
      await tester.tap(find.text(readFact(rig.goal)));
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
            )
            as Map<String, dynamic>,
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
      await tester.scrollUntilVisible(
        find.text(readFact(rig.goal)),
        60,
        scrollable: inPanel(find.byType(Scrollable)),
      );
      await tester.ensureVisible(find.text(readFact(rig.goal)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(readFact(rig.goal)));
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
      // The first derived row — at the top of the list, no scrolling
      // needed to hover it.
      final goal = provableGoals(database).first;
      expect(rig.goal, isNot(goal), reason: 'rig sanity: distinct facts');
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

      // A goal open, so the header carries the back arrow.
      await tester.tap(inPanel(find.byType(ListTile)).first);
      await tester.pumpAndSettle();
      await dragPanel(tester, 400);

      // The header is outside the scrollable and pinned, so shrinking
      // cannot hide it.
      expect(find.byTooltip('Back to the list'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pumpAndSettle();

      // And the run's own control is reachable by scrolling within
      // whatever height is left. `ensureVisible` rather than a raw drag:
      // the list builds all its children, so a finder matches an
      // off-screen row and a scroll-until-found would scroll nothing.
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
