import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
// FilePickerPlatform is not re-exported by package:file_picker; overriding
// `instance` with a fake is the plugin's own documented test seam.
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import '../wide_window.dart';

/// Captures saves and replays canned open results instead of touching the
/// real platform (whose method channel does not exist under flutter_test).
class _FakeFilePicker extends FilePickerPlatform {
  Uint8List? savedBytes;
  String? savedFileName;
  FilePickerResult? openResult;

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

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    return openResult;
  }
}

FilePickerResult _fileWithBytes(List<int> bytes) => FilePickerResult([
  PlatformFile(
    name: 'construction.rgl',
    size: bytes.length,
    bytes: Uint8List.fromList(bytes),
  ),
]);

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

  /// Opens the file menu and taps [item].
  Future<void> tapFileMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  /// Two points and their midpoint, added through commands like real edits.
  void buildSmallConstruction() {
    final construction = container.read(constructionProvider).construction;
    final stack = container.read(commandStackProvider.notifier);
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 2));
    stack.execute(AddObjectCommand(a));
    stack.execute(AddObjectCommand(b));
    stack.execute(AddObjectCommand(Midpoint(id: 'm', point1: a, point2: b)));
    expect(construction.length, 3);
  }

  testWidgets('Save hands the encoded document to the platform', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    const viewport = ViewportState(pan: Vec2(-3, 4), scale: 2);
    container.read(viewportProvider.notifier).set(viewport);
    const settings = DocumentSettings(showAxes: true, showGrid: true);
    container.read(documentSettingsProvider.notifier).set(settings);

    await tapFileMenu(tester, 'Save…');

    expect(picker.savedFileName, 'construction.rgl');
    final saved = decodeDocument(
      jsonDecode(utf8.decode(picker.savedBytes!)) as Map<String, dynamic>,
    );
    expect(
      [for (final object in saved.construction.objects) object.id],
      ['a', 'b', 'm'],
    );
    expect(saved.viewport, viewport);
    expect(saved.settings, settings);
  });

  testWidgets('Open replaces the construction and viewport, drops undo', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();

    final incoming = Construction()
      ..add(FreePoint(id: 'x', position: const Vec2(1, 1)));
    const incomingViewport = ViewportState(pan: Vec2(5, 5), scale: 0.5);
    const incomingSettings = DocumentSettings(showGrid: true);
    picker.openResult = _fileWithBytes(
      utf8.encode(
        jsonEncode(
          encodeDocument(
            incoming,
            viewport: incomingViewport,
            settings: incomingSettings,
          ),
        ),
      ),
    );

    await tapFileMenu(tester, 'Open…');

    final construction = container.read(constructionProvider).construction;
    expect([for (final object in construction.objects) object.id], ['x']);
    expect(container.read(viewportProvider), incomingViewport);
    expect(container.read(documentSettingsProvider), incomingSettings);
    expect(container.read(commandStackProvider).canUndo, isFalse);
  });

  testWidgets('a cancelled Open changes nothing', (tester) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    picker.openResult = null;

    await tapFileMenu(tester, 'Open…');

    expect(container.read(constructionProvider).construction.length, 3);
    expect(container.read(commandStackProvider).canUndo, isTrue);
  });

  testWidgets('a malformed file shows one error dialog and changes nothing', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    picker.openResult = _fileWithBytes(utf8.encode('not json at all'));

    await tapFileMenu(tester, 'Open…');

    expect(find.text('Could not open file'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(container.read(constructionProvider).construction.length, 3);
  });

  testWidgets(
    'a file with an unknown object type shows the offending id in the '
    'error dialog',
    (tester) async {
      await pumpEditor(tester);
      picker.openResult = _fileWithBytes(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'version': 1,
            'objects': [
              <String, dynamic>{
                'id': 'weird',
                'type': 'KleinBottle',
                'parents': <String>[],
              },
            ],
          }),
        ),
      );

      await tapFileMenu(tester, 'Open…');

      expect(find.text('Could not open file'), findsOneWidget);
      expect(find.textContaining('weird'), findsOneWidget);
    },
  );

  testWidgets('New on a non-empty construction asks first; Cancel keeps it', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();

    await tapFileMenu(tester, 'New');
    expect(find.text('New construction'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(container.read(constructionProvider).construction.length, 3);
  });

  testWidgets('New > Discard clears and centers the world origin', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    container
        .read(documentSettingsProvider.notifier)
        .set(const DocumentSettings(showAxes: true, showGrid: true));

    await tapFileMenu(tester, 'New');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(container.read(constructionProvider).construction.isEmpty, isTrue);
    expect(container.read(commandStackProvider).canUndo, isFalse);
    expect(container.read(documentSettingsProvider), const DocumentSettings());

    final canvasSize = tester.getSize(find.byType(GeometryCanvas));
    final viewport = CanvasViewport(container.read(viewportProvider));
    expect(viewport.state.scale, 1);
    final originOnScreen = viewport.worldToScreen(Vec2.zero);
    expect(originOnScreen.dx, moreOrLessEquals(canvasSize.width / 2));
    expect(originOnScreen.dy, moreOrLessEquals(canvasSize.height / 2));
  });

  testWidgets('New on an empty construction skips the confirmation', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tapFileMenu(tester, 'New');

    expect(find.text('New construction'), findsNothing);
    expect(container.read(constructionProvider).construction.isEmpty, isTrue);
  });
}
