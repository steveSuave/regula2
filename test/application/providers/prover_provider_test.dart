import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/prover_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
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
    ProverEngine(database: database, filter: filter).run();
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
      expect(seen.whereType<ProverRunning>(), hasLength(1));
      await pending;

      expect(seen.last, isA<ProverReady>());
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
}
