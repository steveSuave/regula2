import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  late ProviderContainer container;
  late Construction construction;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    construction = container.read(constructionProvider).construction;
  });

  group('selectionProvider', () {
    test('starts empty; select / toggle / clear behave like a set', () {
      final notifier = container.read(selectionProvider.notifier);
      expect(container.read(selectionProvider), isEmpty);

      notifier.select('a');
      expect(container.read(selectionProvider), {'a'});

      notifier.select('b');
      expect(container.read(selectionProvider), {
        'b',
      }, reason: 'plain select is exclusive');

      notifier.toggle('a');
      expect(container.read(selectionProvider), {'a', 'b'});

      notifier.toggle('b');
      expect(container.read(selectionProvider), {'a'});

      notifier.clear();
      expect(container.read(selectionProvider), isEmpty);
    });

    test('selectMany replaces the selection, or unions when additive', () {
      final notifier = container.read(selectionProvider.notifier);

      notifier.selectMany(['a', 'b']);
      expect(container.read(selectionProvider), {'a', 'b'});

      notifier.selectMany(['b', 'c'], additive: true);
      expect(container.read(selectionProvider), {'a', 'b', 'c'});

      notifier.selectMany(['d']);
      expect(container.read(selectionProvider), {'d'});

      notifier.selectMany([]);
      expect(
        container.read(selectionProvider),
        isEmpty,
        reason: 'an empty band clears a non-additive selection',
      );
    });

    test('selectAll selects every object in the construction', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Midpoint(id: 'm', point1: a, point2: b));

      container.read(selectionProvider.notifier).selectAll();
      expect(container.read(selectionProvider), {'a', 'b', 'm'});
    });

    test(
      'deleting objects prunes them (and their dependents) from selection',
      () {
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(2, 0));
        construction
          ..add(a)
          ..add(b)
          ..add(Midpoint(id: 'm', point1: a, point2: b));
        container.read(selectionProvider.notifier).selectAll();

        construction.removeWithDependents('b');

        expect(container.read(selectionProvider), {'a'});
      },
    );

    test('replacing the construction drops the now-stale selection', () {
      construction.add(FreePoint(id: 'a', position: Vec2.zero));
      container.read(selectionProvider.notifier).select('a');

      container.read(constructionProvider.notifier).replace(Construction());

      expect(container.read(selectionProvider), isEmpty);
    });

    test('watchers are not notified when the selection is set-equal', () {
      construction.add(FreePoint(id: 'a', position: Vec2.zero));
      final notifier = container.read(selectionProvider.notifier);
      notifier.select('a');

      final notifications = <Set<String>>[];
      container.listen(selectionProvider, (_, next) {
        notifications.add(next);
      });

      notifier.select('a'); // same selection
      // An unrelated mutation triggers a prune that removes nothing.
      construction.moveFreePoint('a', const Vec2(1, 1));

      expect(notifications, isEmpty);
    });
  });
}
