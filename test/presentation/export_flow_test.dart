import 'package:file_picker/file_picker.dart';
// FilePickerPlatform is not re-exported by package:file_picker; overriding
// `instance` with a fake is the plugin's own documented test seam.
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import 'package:regula/presentation/canvas/region_pick_overlay.dart';
import '../wide_window.dart';

/// Captures the export save instead of touching the real platform.
class _FakeFilePicker extends FilePickerPlatform {
  Uint8List? savedBytes;
  String? savedFileName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes = bytes;
    savedFileName = fileName;
    return fileName;
  }
}

/// Big-endian PNG IHDR dimensions — width at bytes 16–19, height 20–23.
({int width, int height}) pngDimensions(Uint8List bytes) => (
  width: ByteData.sublistView(bytes).getUint32(16),
  height: ByteData.sublistView(bytes).getUint32(20),
);

void main() {
  late ProviderContainer container;
  late _FakeFilePicker picker;

  setUp(() {
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    useWideTestWindow(tester);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
  }

  void addPoint() {
    container
        .read(commandStackProvider.notifier)
        .execute(
          AddObjectCommand(FreePoint(id: 'a', position: const Vec2(2, -3))),
        );
    expect(container.read(constructionProvider).construction.length, 1);
  }

  Future<void> openExportDialog(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as PNG…'));
    await tester.pumpAndSettle();
    expect(find.text('Export as PNG'), findsOneWidget);
  }

  /// The dialog's live output line, parsed back to numbers.
  ({int width, int height}) shownOutputSize(WidgetTester tester) {
    final text = tester
        .widget<Text>(find.textContaining('Output: '))
        .data!
        .replaceAll('Output: ', '')
        .replaceAll(' px', '');
    final parts = text.split(' × ');
    return (width: int.parse(parts[0]), height: int.parse(parts[1]));
  }

  testWidgets('File menu export saves a PNG at the canvas size', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint();
    await openExportDialog(tester);
    final canvasSize = tester.getSize(find.byType(GeometryCanvas));
    final shown = shownOutputSize(tester);
    expect(shown.width, canvasSize.width.round());
    expect(shown.height, canvasSize.height.round());

    // The off-screen render round-trips through real engine futures.
    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      await tester.pump();
      // Let the render → encode → save chain complete.
      while (picker.savedBytes == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(picker.savedFileName, 'construction.png');
    expect(picker.savedBytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final dimensions = pngDimensions(picker.savedBytes!);
    expect(dimensions.width, canvasSize.width.round());
    expect(dimensions.height, canvasSize.height.round());
  });

  testWidgets('scale multiplies the displayed and exported size', (
    tester,
  ) async {
    await pumpEditor(tester);
    addPoint();
    await openExportDialog(tester);
    final base = shownOutputSize(tester);
    await tester.tap(find.text('2×'));
    await tester.pumpAndSettle();
    final doubled = shownOutputSize(tester);
    expect(doubled.width, base.width * 2);
    expect(doubled.height, base.height * 2);

    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      await tester.pump();
      while (picker.savedBytes == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final dimensions = pngDimensions(picker.savedBytes!);
    expect(dimensions.width, base.width * 2);
    expect(dimensions.height, base.height * 2);
  });

  testWidgets('the axes & grid checkbox appears with the document toggles and '
      'unticking excludes the layer from the export', (tester) async {
    await pumpEditor(tester);
    addPoint();

    /// Runs one export through the open dialog and returns its bytes.
    Future<Uint8List> export(WidgetTester tester) async {
      picker.savedBytes = null;
      await tester.runAsync(() async {
        await tester.tap(find.text('Export'));
        await tester.pump();
        while (picker.savedBytes == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      return picker.savedBytes!;
    }

    const checkbox = 'Include axes & grid (as shown)';

    // Baseline: toggles off — no checkbox, no layer.
    await openExportDialog(tester);
    expect(
      find.text(checkbox),
      findsNothing,
      reason: 'the checkbox is meaningless while both toggles are off',
    );
    final withoutLayer = await export(tester);

    // Toggles on: the checkbox shows, defaults ticked, and the export
    // changes — the layer rendered.
    container
        .read(documentSettingsProvider.notifier)
        .set(const DocumentSettings(showAxes: true, showGrid: true));
    await tester.pumpAndSettle();
    await openExportDialog(tester);
    expect(find.text(checkbox), findsOneWidget);
    final withLayer = await export(tester);
    expect(
      listEquals(withLayer, withoutLayer),
      isFalse,
      reason: 'axes + grid must render into the export by default',
    );

    // Unticked: byte-identical to the toggles-off baseline.
    await openExportDialog(tester);
    await tester.tap(find.text(checkbox));
    await tester.pumpAndSettle();
    final excluded = await export(tester);
    expect(
      listEquals(excluded, withoutLayer),
      isTrue,
      reason: 'unticking must exclude the layer entirely',
    );
  });

  testWidgets('fit framing is disabled with nothing to frame', (tester) async {
    await pumpEditor(tester);
    await openExportDialog(tester);
    expect(find.text('Nothing visible to frame'), findsOneWidget);
    final fitTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Fit construction'),
        matching: find.byType(ListTile),
      ),
    );
    expect(fitTile.enabled, isFalse);
  });

  testWidgets('region pick round trip: overlay drag reopens the dialog and the '
      'export crops to the marquee', (tester) async {
    await pumpEditor(tester);
    addPoint();
    await openExportDialog(tester);
    await tester.tap(find.text('Select…'));
    await tester.pumpAndSettle();
    // Dialog gone, overlay armed.
    expect(find.text('Export as PNG'), findsNothing);
    expect(find.byType(RegionPickOverlay), findsOneWidget);

    final canvasTopLeft = tester.getTopLeft(find.byType(GeometryCanvas));
    final gesture = await tester.startGesture(
      canvasTopLeft + const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(canvasTopLeft + const Offset(200, 160));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Dialog is back with the region framing selected and sized.
    expect(find.byType(RegionPickOverlay), findsNothing);
    expect(find.text('Export as PNG'), findsOneWidget);
    expect(find.text('100 × 60 px of the window'), findsOneWidget);
    final shown = shownOutputSize(tester);
    expect(shown.width, 100);
    expect(shown.height, 60);

    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      await tester.pump();
      while (picker.savedBytes == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final dimensions = pngDimensions(picker.savedBytes!);
    expect(dimensions.width, 100);
    expect(dimensions.height, 60);
  });

  testWidgets('Esc cancels the region pick back to the dialog', (tester) async {
    await pumpEditor(tester);
    addPoint();
    await openExportDialog(tester);
    await tester.tap(find.text('Select…'));
    await tester.pumpAndSettle();
    expect(find.byType(RegionPickOverlay), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(RegionPickOverlay), findsNothing);
    expect(find.text('Export as PNG'), findsOneWidget);
    // No region was picked, so the region framing stays unavailable.
    expect(find.text('Drag a rectangle on the canvas'), findsOneWidget);
  });

  testWidgets('a sub-threshold drag keeps the overlay armed', (tester) async {
    await pumpEditor(tester);
    addPoint();
    await openExportDialog(tester);
    await tester.tap(find.text('Select…'));
    await tester.pumpAndSettle();

    final canvasTopLeft = tester.getTopLeft(find.byType(GeometryCanvas));
    final gesture = await tester.startGesture(
      canvasTopLeft + const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
    );
    // Past the pan slop so the recognizer accepts, but under minSidePx
    // on the vertical side.
    await gesture.moveTo(canvasTopLeft + const Offset(130, 102));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(RegionPickOverlay), findsOneWidget);
    expect(find.text('Export as PNG'), findsNothing);
  });

  testWidgets('the dialog scrolls instead of overflowing in a short window', (
    tester,
  ) async {
    // Short enough that the dialog's content area cannot hold the
    // options at their natural height; a RenderFlex overflow would fail
    // this test via FlutterError.
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpEditor(tester);
    addPoint();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Export as PNG'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('Ctrl+E opens the export dialog', (tester) async {
    await pumpEditor(tester);
    addPoint();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Export as PNG'), findsOneWidget);
  });
}
