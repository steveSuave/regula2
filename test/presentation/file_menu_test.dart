import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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
  String? savedMimeType;
  PlatformFile? openResult;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    void Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedBytes = bytes;
    savedFileName = fileName;
    savedMimeType = mimeType;
    return Uri.file(fileName);
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return openResult;
  }
}

/// A picked file backed by in-memory bytes. [PlatformFile] is abstract as
/// of file_picker 12 — the picked file is read back through
/// `readAsBytes()` instead of arriving with its bytes attached — so the
/// canned open result is a real subclass, not a constructor call.
base class _FakePickedFile extends PlatformFile {
  _FakePickedFile(this.bytes, {this.readFails = false});

  final Uint8List bytes;

  /// Makes the read fail the way an unreadable path or a revoked content
  /// URI does, which is the only way an open can fail now that a picked
  /// file no longer carries its bytes.
  final bool readFails;

  @override
  String get name => 'construction.rgl';

  @override
  Uri get uri => Uri.file(name);

  @override
  Never get xFile => throw UnimplementedError('unused by these tests');

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async {
    if (readFails) {
      throw const FileSystemException('could not read');
    }
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

PlatformFile _fileWithBytes(List<int> bytes) =>
    _FakePickedFile(Uint8List.fromList(bytes));

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
    // A well-formed document says nothing. The report exists so the one
    // that needed repairing is not silent; an unconditional notice on
    // every open would train the user to dismiss it (Phase 126e).
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Open reports what the reader had to repair', (tester) async {
    // The decoder has computed this list since Phase 120c and nothing
    // has ever displayed it — a silent repair is how the reported
    // document accumulated points nobody could account for in the first
    // place. Two points share a crossing here, and a third has nowhere
    // left to go: a line and a circle have exactly two.
    await pumpEditor(tester);
    picker.openResult = _fileWithBytes(
      utf8.encode(jsonEncode(_documentWithThreeStackedPoints)),
    );

    await tapFileMenu(tester, 'Open…');

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('was stacked on a crossing another point'),
      findsOneWidget,
    );
    expect(
      // Named rather than counted (Phase 131), and the id is the fallback
      // for a point the file never named — which is what the object tree
      // shows for it too.
      find.textContaining('deleting point p3 is the only fix'),
      findsOneWidget,
    );
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

  testWidgets('a file that cannot be read shows the same one dialog', (
    tester,
  ) async {
    await pumpEditor(tester);
    buildSmallConstruction();
    picker.openResult = _FakePickedFile(Uint8List(0), readFails: true);

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

/// A pre-120c document: a line and a circle, and *three* intersection
/// points all claiming branch 1. The reader moves one to the free
/// crossing and has nowhere to put the third.
const Map<String, dynamic> _documentWithThreeStackedPoints = {
  'version': 1,
  'viewport': {
    'pan': [0, 0],
    'scale': 1,
    'rotation': 0,
  },
  'objects': [
    {
      'id': 'o',
      'type': 'FreePoint',
      'parents': <String>[],
      'params': {'x': 0, 'y': 0},
    },
    {
      'id': 'x',
      'type': 'FreePoint',
      'parents': <String>[],
      'params': {'x': 4, 'y': 0},
    },
    {
      'id': 'y',
      'type': 'FreePoint',
      'parents': <String>[],
      'params': {'x': 0, 'y': 4},
    },
    {
      'id': 'l',
      'type': 'LineThroughTwoPoints',
      'parents': ['o', 'x'],
      'params': <String, dynamic>{},
    },
    {
      'id': 'k',
      'type': 'CircleCenterPoint',
      'parents': ['o', 'y'],
      'params': <String, dynamic>{},
    },
    {
      'id': 'p1',
      'type': 'IntersectionPoint',
      'parents': ['l', 'k'],
      'params': {'branchIndex': 1},
    },
    {
      'id': 'p2',
      'type': 'IntersectionPoint',
      'parents': ['l', 'k'],
      'params': {'branchIndex': 1},
    },
    {
      'id': 'p3',
      'type': 'IntersectionPoint',
      'parents': ['l', 'k'],
      'params': {'branchIndex': 1},
    },
  ],
};
