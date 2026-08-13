import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/move_free_point_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('commandStackProvider', () {
    test('execute applies the command to the shared construction', () {
      container
          .read(commandStackProvider.notifier)
          .execute(AddObjectCommand(FreePoint(id: 'a', position: Vec2.zero)));

      final construction = container.read(constructionProvider).construction;
      expect(construction.contains('a'), isTrue);
      expect(container.read(commandStackProvider), (
        canUndo: true,
        canRedo: false,
      ));
    });

    test('undo/redo round-trip through the provider', () {
      final notifier = container.read(commandStackProvider.notifier);
      notifier
        ..execute(AddObjectCommand(FreePoint(id: 'a', position: Vec2.zero)))
        ..execute(
          MoveFreePointCommand(
            pointId: 'a',
            from: Vec2.zero,
            to: const Vec2(2, 3),
          ),
        );
      final construction = container.read(constructionProvider).construction;
      expect((construction.byId('a')! as FreePoint).position, const Vec2(2, 3));

      notifier.undo();
      expect((construction.byId('a')! as FreePoint).position, Vec2.zero);
      expect(container.read(commandStackProvider), (
        canUndo: true,
        canRedo: true,
      ));

      notifier.undo();
      expect(construction.isEmpty, isTrue);
      expect(container.read(commandStackProvider), (
        canUndo: false,
        canRedo: true,
      ));

      notifier
        ..redo()
        ..redo();
      expect((construction.byId('a')! as FreePoint).position, const Vec2(2, 3));
      expect(container.read(commandStackProvider), (
        canUndo: true,
        canRedo: false,
      ));
    });

    test('watchers are only notified when the flags actually change', () {
      final notifications = <UndoRedoState>[];
      container.listen(commandStackProvider, (_, next) {
        notifications.add(next);
      });

      final notifier = container.read(commandStackProvider.notifier);
      notifier.execute(
        AddObjectCommand(FreePoint(id: 'a', position: Vec2.zero)),
      );
      // Second execute leaves (canUndo: true, canRedo: false) unchanged.
      notifier.execute(
        AddObjectCommand(FreePoint(id: 'b', position: Vec2.zero)),
      );

      expect(notifications, [(canUndo: true, canRedo: false)]);
    });

    test('undo/redo with no history throw StateError', () {
      final notifier = container.read(commandStackProvider.notifier);
      expect(notifier.undo, throwsStateError);
      expect(notifier.redo, throwsStateError);
    });

    test('a failed execute records nothing', () {
      final notifier = container.read(commandStackProvider.notifier);
      expect(
        () => notifier.execute(
          MoveFreePointCommand(
            pointId: 'ghost',
            from: Vec2.zero,
            to: const Vec2(1, 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(container.read(commandStackProvider), (
        canUndo: false,
        canRedo: false,
      ));
    });

    test('history survives construction mutations (revision bumps)', () {
      final notifier = container.read(commandStackProvider.notifier);
      notifier.execute(
        AddObjectCommand(FreePoint(id: 'a', position: Vec2.zero)),
      );
      // Direct mutation (the drag-preview carve-out) bumps the revision.
      container
          .read(constructionProvider)
          .construction
          .moveFreePoint('a', const Vec2(5, 5));

      expect(container.read(commandStackProvider).canUndo, isTrue);
    });

    test('replacing the construction rebuilds the stack and drops history', () {
      container
          .read(commandStackProvider.notifier)
          .execute(AddObjectCommand(FreePoint(id: 'a', position: Vec2.zero)));
      expect(container.read(commandStackProvider).canUndo, isTrue);

      final fresh = Construction();
      container.read(constructionProvider.notifier).replace(fresh);

      expect(container.read(commandStackProvider), (
        canUndo: false,
        canRedo: false,
      ));

      // New commands act on the replacement construction.
      container
          .read(commandStackProvider.notifier)
          .execute(AddObjectCommand(FreePoint(id: 'b', position: Vec2.zero)));
      expect(fresh.contains('b'), isTrue);
    });
  });
}
