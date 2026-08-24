import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/prover_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_translation.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/questions.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  FreePoint free(String id, String name, double x, double y) => FreePoint(
    id: id,
    position: Vec2(x, y),
    attributes: ObjectAttributes(name: name),
  );

  /// The Varignon rig of `proof_test.dart`, built into the container's
  /// live construction so the provider reads it the way the app does.
  ///
  /// The midpoint quadrilateral of any quadrilateral is a parallelogram:
  /// both midlines are parallel to the diagonal `AC`, so the goal is
  /// three rules and four givens deep.
  ({Fact goal, Construction construction}) seedVarignon() {
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
      construction: construction,
    );
  }

  /// The same pipeline the provider drives, run straight through in the
  /// domain — the control the provider is checked against.
  FactDatabase straightRun(Iterable<GeoObject> objects) {
    final all = List.of(objects);
    final filter = DiagramFilter.probe(all);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(all), filter);
    // The exchange, not DD alone: since Phase 166 Varignon's theorem is
    // reached by the angle closure's publisher (`para_transitive` was a
    // row sum), so a DD-only control would be strictly smaller.
    Prover(database: database, filter: filter).run();
    return database;
  }

  group('proverProvider', () {
    test('starts idle — DD is the on-demand path, not the always-on one', () {
      expect(container.read(proverProvider), const ProverIdle());
    });

    test('proves Varignon, and the proof verifies as a certificate', () async {
      final rig = seedVarignon();

      await container.read(proverProvider.notifier).prove();

      final state = container.read(proverProvider) as ProverReady;
      expect(state.reachedFixpoint, isTrue);
      final proof = state.proofOf(rig.goal);
      expect(proof, isNotNull, reason: 'the run must reach the goal');
      expect(
        proof!.verify(),
        isEmpty,
        reason: 'every step must be a sound instantiation of its own rule',
      );
      expect(proof.steps.last.fact, rig.goal);
      expect(proof.givens, isNotEmpty);
      expect(proof.deductions, isNotEmpty);
    });

    test('derives exactly what a straight domain-side run derives', () async {
      final rig = seedVarignon();
      final control = straightRun(rig.construction.objects);

      await container.read(proverProvider.notifier).prove();

      final state = container.read(proverProvider) as ProverReady;
      expect(state.database.facts.toSet(), control.facts.toSet());
      expect(
        state.database.length,
        control.length,
        reason: 'chunking through the boundary changes when, never what',
      );
    });

    test('records the revision it read, so staleness is comparable', () async {
      seedVarignon();
      final revision = container.read(constructionProvider).revision;

      await container.read(proverProvider.notifier).prove();

      final state = container.read(proverProvider) as ProverReady;
      expect(state.revision, revision);

      // An edit does not touch the held run — the provider does not
      // watch the construction — but it does move the revision the
      // consumer compares against.
      container
          .read(constructionProvider)
          .construction
          .add(free('e', 'E', 3, 3));
      expect(container.read(proverProvider), same(state));
      expect(
        container.read(constructionProvider).revision,
        greaterThan(state.revision),
      );
    });

    test('publishes a running state before it yields', () async {
      seedVarignon();
      final seen = <ProverState>[];
      container.listen(proverProvider, (_, next) => seen.add(next));

      final pending = container.read(proverProvider.notifier).prove();
      // At least one: the initial publish is synchronous, and each pass
      // republishes with its progress (Phase 156), so a document that
      // runs past its first pass before the first yield adds more.
      expect(seen.whereType<ProverRunning>(), isNotEmpty);
      expect(seen.first, isA<ProverRunning>());
      await pending;

      expect(seen.last, isA<ProverReady>());
    });

    test('progress is republished per pass, and the count climbs', () async {
      // Varignon completes inside one chunk, so the progress reports
      // need the document whose run takes many — the Phase 148 rig.
      container
          .read(constructionProvider.notifier)
          .replace(
            decodeDocument(
              jsonDecode(
                    File(
                      'test/fixtures/perp-true-unproved.rgl',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>,
            ).construction,
          );
      final seen = <ProverState>[];
      container.listen(proverProvider, (_, next) => seen.add(next));

      await container.read(proverProvider.notifier).prove();

      final progress = seen
          .whereType<ProverRunning>()
          .map((state) => state.applications)
          .toList();
      expect(progress.first, 0, reason: 'the initial publish knows nothing');
      expect(
        progress.length,
        greaterThan(2),
        reason: 'a many-pass run must report along the way, not just start',
      );
      expect(
        progress.last,
        (seen.last as ProverReady).applications,
        reason: 'the final report is the finished run\'s own count',
      );
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });

    test('an empty document proves nothing and says so plainly', () async {
      await container.read(proverProvider.notifier).prove();

      final state = container.read(proverProvider) as ProverReady;
      expect(state.reachedFixpoint, isTrue);
      expect(state.database.length, 0);
      expect(state.applications, 0);
    });

    test('a fact the run did not derive has no proof, not an error', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).prove();
      final state = container.read(proverProvider) as ProverReady;
      final a = state.database.facts.first.points.first;

      expect(state.proofOf(Fact(PredicateKind.perp, [a, a, a, a])), isNull);
    });

    test(
      'refuses a non-Euclidean document rather than approximating',
      () async {
        container
            .read(constructionProvider.notifier)
            .replace(
              Construction(
                kernel: const DocumentKernel(
                  metric: FundamentalConic.hyperbolic,
                ),
              ),
            );

        await container.read(proverProvider.notifier).prove();

        final state = container.read(proverProvider);
        expect(state, isA<ProverRefused>());
        expect((state as ProverRefused).reason, contains('Euclidean'));
      },
    );

    test('clear() drops the held run', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).prove();
      expect(container.read(proverProvider), isA<ProverReady>());

      container.read(proverProvider.notifier).clear();

      expect(container.read(proverProvider), const ProverIdle());
    });

    test('a run cleared while in flight never publishes', () async {
      // The pin for the generation guard. `prove` runs synchronously up
      // to its first `await`, so a caller that clears in between has a
      // finished run's answer already computed and on its way — and it
      // must be dropped, not delivered on top of the idle state the
      // user asked for.
      seedVarignon();
      final pending = container.read(proverProvider.notifier).prove();

      container.read(proverProvider.notifier).clear();
      await pending;

      expect(container.read(proverProvider), const ProverIdle());
    });

    test('a superseded run does not clobber the newer one', () async {
      seedVarignon();
      final first = container.read(proverProvider.notifier).prove();
      final second = container.read(proverProvider.notifier).prove();
      await Future.wait([first, second]);

      final state = container.read(proverProvider) as ProverReady;
      expect(state.reachedFixpoint, isTrue);

      // The first run's result must have been dropped, not merged: the
      // published database is the second run's, and it is complete.
      final control = straightRun(
        container.read(constructionProvider).construction.objects,
      );
      expect(state.database.facts.toSet(), control.facts.toSet());
    });
  });

  group('asking', () {
    /// The user document Phase 148 opened on: right angle at B, D the
    /// midpoint of AB, E the midpoint of DB, the perpendicular to CA
    /// through E meeting BC at F. `perp(C,D,D,F)` is a theorem — the
    /// filter confirms it in every perturbation — and the 44-application
    /// fixpoint cannot reach it, because only two of the 23 rules
    /// conclude a `perp` and neither has a route here.
    Construction loadUnprovable() => decodeDocument(
      jsonDecode(
            File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
          )
          as Map<String, dynamic>,
    ).construction;

    GeoPoint named(Construction construction, String name) => construction
        .objects
        .whereType<GeoPoint>()
        .firstWhere((point) => point.attributes.name == name);

    ProverQuestion questionOf(PredicateKind kind, List<GeoPoint> points) =>
        ProverQuestion(kind, [Predicate(kind, points)]);

    test('a proved question comes back with its certificate', () async {
      final rig = seedVarignon();
      final notifier = container.read(proverProvider.notifier);

      await notifier.ask(
        ProverQuestion(PredicateKind.para, [rig.goal.statement]),
      );

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(state.answer.proof, isNotNull);
      expect(state.answer.proof!.verify(), isEmpty);
      expect(state.answer.proof!.steps.last.fact, rig.goal);
    });

    test('an equal-angle question DD never stores is answered by the angle '
        'side', () async {
      // The four sides of the Varignon parallelogram: ∠(MN, NP) =
      // ∠(QP, MQ), from MN ∥ QP and NP ∥ MQ. No rule concludes it, so the
      // database of a complete run does not hold it; the closure does.
      final rig = seedVarignon();
      GeoPoint at(String id) => rig.construction.byId(id)! as GeoPoint;
      final (m, n, p, q) = (at('mab'), at('mbc'), at('mcd'), at('mda'));
      final question = questionOf(PredicateKind.eqangle, [
        m,
        n,
        n,
        p,
        q,
        p,
        m,
        q,
      ]);
      final notifier = container.read(proverProvider.notifier);

      await notifier.ask(question);

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      final proof = state.answer.proof!;
      expect(proof.verify(), isEmpty);
      expect(proof.steps.last.fact, Fact.of(question.canonical));
      expect(proof.steps.last.rule, angleArithmeticRule);
      expect(proof.steps.last.chase, isNotNull);
    });

    test('a complete run is consulted for it too, closure included', () async {
      // The same question after ▶: the held engine answers without a
      // second run, and "answers" includes what only the closure holds.
      final rig = seedVarignon();
      GeoPoint at(String id) => rig.construction.byId(id)! as GeoPoint;
      final (m, n, p, q) = (at('mab'), at('mbc'), at('mcd'), at('mda'));
      final notifier = container.read(proverProvider.notifier);
      await notifier.prove();
      final ready = container.read(proverProvider) as ProverReady;
      expect(ready.reachedFixpoint, isTrue);
      final fact = Fact.of(
        Predicate(PredicateKind.eqangle, [m, n, n, p, q, p, m, q]),
      );
      expect(
        ready.database.contains(fact),
        isFalse,
        reason: 'DD never stores it',
      );

      await notifier.ask(
        questionOf(PredicateKind.eqangle, [m, n, n, p, q, p, m, q]),
      );

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.proved);
      expect(state.answer.proof!.verify(), isEmpty);
      expect(state.run!.applications, ready.applications, reason: 'no new run');
    });

    test('a false claim is refuted without the prover running', () async {
      seedVarignon();
      final construction = container.read(constructionProvider).construction;
      final a = named(construction, 'A');
      final b = named(construction, 'B');
      final c = named(construction, 'C');
      final d = named(construction, 'D');
      final notifier = container.read(proverProvider.notifier);

      // AB ⟂ CD is false of a generic quadrilateral.
      await notifier.ask(questionOf(PredicateKind.perp, [a, b, c, d]));

      final state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.refuted);
      expect(state.answer.proof, isNull);
      expect(
        state.run,
        isNull,
        reason: 'a refutation is the filter\'s answer; no run happened',
      );
    });

    test('true but out of reach is its own verdict, not a refusal', () async {
      final construction = loadUnprovable();
      container.read(constructionProvider.notifier).replace(construction);
      final question = questionOf(PredicateKind.perp, [
        named(construction, 'C'),
        named(construction, 'D'),
        named(construction, 'D'),
        named(construction, 'F'),
      ]);

      await container.read(proverProvider.notifier).ask(question);

      final state = container.read(proverProvider) as ProverAnswered;
      expect(
        state.answer.verdict,
        ProverVerdict.unproved,
        reason:
            'the run finished and could not get there — that is not '
            'the statement being false',
      );
      expect(state.answer.proof, isNull);
      expect(state.run!.reachedFixpoint, isTrue);
    });

    test(
      'a budget too small to settle it says undecided, not unproved',
      () async {
        final construction = loadUnprovable();
        container.read(constructionProvider.notifier).replace(construction);
        final question = questionOf(PredicateKind.perp, [
          named(construction, 'C'),
          named(construction, 'D'),
          named(construction, 'D'),
          named(construction, 'F'),
        ]);
        final notifier = container.read(proverProvider.notifier);

        await notifier.ask(question, applicationBudget: 3);

        var state = container.read(proverProvider) as ProverAnswered;
        expect(
          state.answer.verdict,
          ProverVerdict.undecided,
          reason: 'an unfinished run has shown nothing about reachability',
        );

        await notifier.askMore();

        state = container.read(proverProvider) as ProverAnswered;
        expect(state.answer.verdict, ProverVerdict.unproved);
      },
    );

    test('any spelling counts — a question is a statement', () async {
      // The scan must reach past the first spelling. `coll(A,D,B)` is
      // one `midp_coll` away from a given; `coll(A,E,B)` needs
      // `coll_transitive` on top of that. Under a budget that reaches
      // the first and not the second, a question listing them in the
      // unhelpful order must still come back proved — which is only
      // true if every spelling is tried.
      //
      // Phase 150 note: before the coll-propagation rules landed, the
      // second of these was simply unreachable and this test needed no
      // budget. That it now needs one is the phase working.
      final construction = loadUnprovable();
      container.read(constructionProvider.notifier).replace(construction);
      final a = named(construction, 'A');
      final b = named(construction, 'B');
      final d = named(construction, 'D');
      final e = named(construction, 'E');
      final notifier = container.read(proverProvider.notifier);

      await notifier.ask(
        questionOf(PredicateKind.coll, [a, e, b]),
        applicationBudget: 2,
      );
      expect(
        (container.read(proverProvider) as ProverAnswered).answer.verdict,
        ProverVerdict.undecided,
        reason: 'that spelling alone is not reached inside the budget',
      );

      await notifier.ask(
        ProverQuestion(PredicateKind.coll, [
          Predicate(PredicateKind.coll, [a, e, b]),
          Predicate(PredicateKind.coll, [a, d, b]),
        ]),
        applicationBudget: 2,
      );

      final state = container.read(proverProvider) as ProverAnswered;
      expect(
        state.answer.verdict,
        ProverVerdict.proved,
        reason:
            'the second spelling is derived, and it is the same '
            'question — which points name a line is the prover\'s business',
      );
      expect(state.answer.proof!.verify(), isEmpty);
    });

    test('asking reuses a complete run instead of starting another', () async {
      final rig = seedVarignon();
      final notifier = container.read(proverProvider.notifier);
      await notifier.prove();
      final firstRun = container.read(proverProvider) as ProverReady;

      await notifier.ask(
        ProverQuestion(PredicateKind.para, [rig.goal.statement]),
      );

      final state = container.read(proverProvider) as ProverAnswered;
      expect(
        identical(state.run!.database, firstRun.database),
        isTrue,
        reason: 'the held run is consulted, not repeated',
      );
      expect(state.run!.applications, firstRun.applications);
    });

    test('askMore does nothing on a settled verdict', () async {
      final rig = seedVarignon();
      final notifier = container.read(proverProvider.notifier);
      await notifier.ask(
        ProverQuestion(PredicateKind.para, [rig.goal.statement]),
      );
      final settled = container.read(proverProvider);

      await notifier.askMore();

      expect(container.read(proverProvider), settled);
    });

    test('a non-Euclidean document refuses the question too', () async {
      final euclidean = container.read(constructionProvider).construction;
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 1));
      for (final o in [a, b, c]) {
        euclidean.add(o);
      }
      final question = questionOf(PredicateKind.coll, [a, b, c]);
      container
          .read(constructionProvider.notifier)
          .replace(
            Construction(
              kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
            ),
          );

      await container.read(proverProvider.notifier).ask(question);

      expect(container.read(proverProvider), isA<ProverRefused>());
    });
  });

  group('the application budget', () {
    test('an exhausted run reports it, keeps its facts, and resumes', () async {
      // Quiescence is not something an arbitrary document owes — the
      // measured `provoleas2.json` is still deriving after 200 000
      // applications — so exhaustion has to be a state a consumer can
      // read and act on, not a failure. Varignon is far too small to
      // exhaust the shipped budget, so the budget comes down to it.
      final rig = seedVarignon();
      final notifier = container.read(proverProvider.notifier);

      await notifier.prove(applicationBudget: 3);

      final partial = container.read(proverProvider) as ProverReady;
      expect(partial.reachedFixpoint, isFalse);
      expect(partial.applications, 3);
      expect(partial.proofOf(rig.goal), isNull);

      await notifier.proveMore();

      final finished = container.read(proverProvider) as ProverReady;
      expect(finished.reachedFixpoint, isTrue);
      expect(
        finished.applications,
        greaterThan(partial.applications),
        reason: 'the resume continues the run rather than restarting it',
      );
      expect(finished.proofOf(rig.goal), isNotNull);
      expect(
        finished.database.facts.toSet(),
        straightRun(rig.construction.objects).facts.toSet(),
        reason: 'a capped-then-resumed run reaches the same fixpoint',
      );
    });

    test('proveMore is a no-op on a run that already finished', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).prove();
      final finished = container.read(proverProvider) as ProverReady;
      expect(finished.reachedFixpoint, isTrue);

      await container.read(proverProvider.notifier).proveMore();

      expect(container.read(proverProvider), same(finished));
    });

    test('proveMore does nothing before anything has been proved', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).proveMore();
      expect(container.read(proverProvider), const ProverIdle());
    });

    test('the shipped budget is far above a real document', () async {
      seedVarignon();
      await container.read(proverProvider.notifier).prove();

      final state = container.read(proverProvider) as ProverReady;
      expect(state.applications, lessThan(proverApplicationBudget));
      expect(state.reachedFixpoint, isTrue);
    });
  });

  group('stopping (Phase 156)', () {
    /// A document whose fixpoint outlives many chunks — ~16 000
    /// applications under the exchange — so a stop lands mid-flight.
    /// Varignon completes inside its first chunk and can never be
    /// stopped at all.
    Construction loadBlowup() => decodeDocument(
      jsonDecode(
            File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
          )
          as Map<String, dynamic>,
    ).construction;

    GeoPoint named(Construction construction, String name) => construction
        .objects
        .whereType<GeoPoint>()
        .firstWhere((point) => point.attributes.name == name);

    /// The uninterrupted control: the same exchange, run straight
    /// through in the domain.
    FactDatabase exchangeRun(Iterable<GeoObject> objects) {
      final all = List.of(objects);
      final filter = DiagramFilter.probe(all);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(all), filter);
      Prover(database: database, filter: filter).run();
      return database;
    }

    test('a stopped run publishes the prefix, and resumes to the '
        'fixpoint', () async {
      container.read(constructionProvider.notifier).replace(loadBlowup());
      final notifier = container.read(proverProvider.notifier);

      // `prove` runs synchronously to its first yield — one chunk — so
      // a stop issued right after it interrupts a run in flight.
      final pending = notifier.prove();
      expect(container.read(proverProvider), isA<ProverRunning>());
      notifier.stop();
      await pending;

      // Cancellation is not supersession: the interrupted run must
      // *publish* its prefix, in the identical shape a spent budget
      // publishes, not drop it the way a superseded run does.
      final stopped = container.read(proverProvider) as ProverReady;
      expect(stopped.reachedFixpoint, isFalse);
      expect(stopped.database.length, greaterThan(0));

      await notifier.proveMore();

      final finished = container.read(proverProvider) as ProverReady;
      expect(finished.reachedFixpoint, isTrue);
      expect(
        finished.database.facts.toSet(),
        exchangeRun(
          container.read(constructionProvider).construction.objects,
        ).facts.toSet(),
        reason: 'stopped-then-resumed lands where an uninterrupted run lands',
      );
    });

    test('a stopped question is undecided, and askMore settles it', () async {
      final construction = loadBlowup();
      container.read(constructionProvider.notifier).replace(construction);
      final notifier = container.read(proverProvider.notifier);
      // True in the figure and out of the table's reach (the Phase 148
      // rig), so an uninterrupted ask would end in `unproved` — a stop
      // must end in `undecided` instead, because an interrupted run has
      // shown nothing about reachability.
      final question = ProverQuestion(PredicateKind.perp, [
        Predicate(PredicateKind.perp, [
          named(construction, 'C'),
          named(construction, 'D'),
          named(construction, 'D'),
          named(construction, 'F'),
        ]),
      ]);

      final pending = notifier.ask(question);
      notifier.stop();
      await pending;

      var state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.undecided);

      await notifier.askMore();

      state = container.read(proverProvider) as ProverAnswered;
      expect(state.answer.verdict, ProverVerdict.unproved);
      expect(state.run!.reachedFixpoint, isTrue);
    });

    test('stop when nothing is running is a no-op, and does not bleed '
        'into the next run', () async {
      seedVarignon();
      final notifier = container.read(proverProvider.notifier);

      notifier.stop();
      expect(container.read(proverProvider), const ProverIdle());

      await notifier.prove();
      expect(
        (container.read(proverProvider) as ProverReady).reachedFixpoint,
        isTrue,
        reason: 'a stale stop flag would end this run at its first pass',
      );
    });
  });

  group('prove resumes (Phase 156)', () {
    test('▶ twice at one revision continues the held engine', () async {
      seedVarignon();
      final notifier = container.read(proverProvider.notifier);

      await notifier.prove(applicationBudget: 3);
      final first = container.read(proverProvider) as ProverReady;
      expect(first.reachedFixpoint, isFalse);
      expect(first.applications, 3);

      await notifier.prove(applicationBudget: 3);

      final second = container.read(proverProvider) as ProverReady;
      expect(
        identical(second.database, first.database),
        isTrue,
        reason: 'no re-probe, no re-seed: the same engine continued',
      );
      expect(
        second.applications,
        6,
        reason: 'cumulative across the two presses — a rebuild would read 3',
      );
    });

    test('▶ after a revision bump rebuilds, as the refresh icon '
        'says', () async {
      seedVarignon();
      final notifier = container.read(proverProvider.notifier);
      await notifier.prove(applicationBudget: 3);
      final first = container.read(proverProvider) as ProverReady;

      container
          .read(constructionProvider)
          .construction
          .add(free('e', 'E', 3, 3));
      await notifier.prove(applicationBudget: 3);

      final second = container.read(proverProvider) as ProverReady;
      expect(identical(second.database, first.database), isFalse);
      expect(
        second.applications,
        3,
        reason: 'a fresh engine starts its count over',
      );
      expect(second.revision, greaterThan(first.revision));
    });

    test('▶ after an answer continues the engine the ask built', () async {
      final rig = seedVarignon();
      final notifier = container.read(proverProvider.notifier);
      await notifier.ask(
        ProverQuestion(PredicateKind.para, [rig.goal.statement]),
        applicationBudget: 3,
      );
      final answered = container.read(proverProvider) as ProverAnswered;
      expect(answered.answer.verdict, ProverVerdict.undecided);

      await notifier.prove();

      final state = container.read(proverProvider) as ProverReady;
      expect(
        identical(state.database, answered.run!.database),
        isTrue,
        reason: 'the ask\'s partial run is the prefix, not waste',
      );
      expect(state.reachedFixpoint, isTrue);
    });
  });
}
