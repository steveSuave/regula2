import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/document_settings_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('documentSettingsProvider', () {
    test('defaults to axes and grid off', () {
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(),
      );
      expect(container.read(documentSettingsProvider).showAxes, isFalse);
      expect(container.read(documentSettingsProvider).showGrid, isFalse);
    });

    test('toggleAxes and toggleGrid flip independently', () {
      final notifier = container.read(documentSettingsProvider.notifier);
      notifier.toggleAxes();
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(showAxes: true),
      );

      notifier.toggleGrid();
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(showAxes: true, showGrid: true),
      );

      notifier.toggleAxes();
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(showGrid: true),
      );
    });

    test('toggleSnapToGrid flips alone — independent of showGrid', () {
      final notifier = container.read(documentSettingsProvider.notifier);
      notifier.toggleSnapToGrid();
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(snapToGrid: true),
        reason: 'snapping with the grid hidden is a valid choice',
      );

      notifier.toggleGrid();
      notifier.toggleSnapToGrid();
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(showGrid: true),
      );
    });

    test('set replaces wholesale; reset restores defaults', () {
      final notifier = container.read(documentSettingsProvider.notifier);
      notifier.set(const DocumentSettings(showAxes: true, showGrid: true));
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(showAxes: true, showGrid: true),
      );

      notifier.reset();
      expect(
        container.read(documentSettingsProvider),
        const DocumentSettings(),
      );
    });
  });

  group('DocumentSettings', () {
    test('value equality', () {
      expect(
        const DocumentSettings(showAxes: true),
        const DocumentSettings(showAxes: true),
      );
      expect(
        const DocumentSettings(showAxes: true),
        isNot(const DocumentSettings(showGrid: true)),
      );
      expect(
        const DocumentSettings(),
        isNot(const DocumentSettings(showAxes: true)),
      );
    });
  });
}
