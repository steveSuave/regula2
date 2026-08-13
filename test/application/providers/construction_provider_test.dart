import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('constructionProvider', () {
    test('starts with an empty construction at revision 0', () {
      final state = container.read(constructionProvider);
      expect(state.construction.isEmpty, isTrue);
      expect(state.revision, 0);
    });

    test(
      'a construction mutation bumps the revision and notifies watchers',
      () {
        final notifications = <ConstructionState>[];
        container.listen(constructionProvider, (_, next) {
          notifications.add(next);
        });
        final construction = container.read(constructionProvider).construction;

        construction.add(FreePoint(id: 'a', position: Vec2.zero));

        expect(notifications, hasLength(1));
        expect(notifications.single.revision, 1);
        expect(
          identical(notifications.single.construction, construction),
          isTrue,
          reason: 'revision bumps must keep the same construction instance',
        );

        construction.moveFreePoint('a', const Vec2(1, 1));
        expect(notifications, hasLength(2));
        expect(notifications.last.revision, 2);
      },
    );

    test(
      'replace swaps the construction, resets the revision, resubscribes',
      () {
        final old = container.read(constructionProvider).construction;
        old.add(FreePoint(id: 'a', position: Vec2.zero));
        expect(container.read(constructionProvider).revision, 1);

        final fresh = Construction();
        container.read(constructionProvider.notifier).replace(fresh);

        final state = container.read(constructionProvider);
        expect(identical(state.construction, fresh), isTrue);
        expect(state.revision, 0);

        // The old construction is unhooked; the new one drives revisions.
        old.add(FreePoint(id: 'b', position: Vec2.zero));
        expect(container.read(constructionProvider).revision, 0);
        fresh.add(FreePoint(id: 'c', position: Vec2.zero));
        expect(container.read(constructionProvider).revision, 1);
      },
    );

    test('dispose unsubscribes from the construction', () {
      final disposable = ProviderContainer();
      final construction = disposable.read(constructionProvider).construction;
      disposable.dispose();

      // Were the listener still attached, it would set state on a disposed
      // notifier and throw.
      construction.add(FreePoint(id: 'a', position: Vec2.zero));
    });

    test('dispose after replace unsubscribes from the replacement', () {
      final disposable = ProviderContainer();
      final fresh = Construction();
      disposable.read(constructionProvider.notifier).replace(fresh);
      disposable.dispose();

      fresh.add(FreePoint(id: 'a', position: Vec2.zero));
    });
  });

  group('ConstructionState', () {
    test('equality: same instance and revision', () {
      final c = Construction();
      expect(ConstructionState(c, 1), ConstructionState(c, 1));
      expect(ConstructionState(c, 1), isNot(ConstructionState(c, 2)));
      expect(
        ConstructionState(c, 1),
        isNot(ConstructionState(Construction(), 1)),
      );
    });
  });
}
