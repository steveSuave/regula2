import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../domain/construction/construction.dart';
import '../providers/document_settings_provider.dart';
import '../providers/viewport_provider.dart';
import 'construction_codec.dart';

/// File name offered by the save dialog (and used verbatim by the web
/// download). `.rgl` is regula's own extension; the content is still
/// ordinary JSON.
const String defaultConstructionFileName = 'construction.rgl';

/// MIME type stamped on a saved `.rgl`. The save dialog takes a MIME type
/// rather than an extension list since file_picker 12, and the content is
/// still ordinary JSON.
const String _constructionMimeType = 'application/json';

/// `json` stays accepted on open so files saved before the `.rgl` rename
/// remain openable.
const List<String> _openExtensions = ['rgl', 'json'];

/// Serializes [construction] + [viewport] + [settings] and hands the bytes
/// to the platform's save dialog (a download on the web). Completes when
/// the dialog does; a cancelled dialog is not an error.
Future<void> saveConstructionFile(
  Construction construction, {
  required ViewportState viewport,
  DocumentSettings settings = const DocumentSettings(),
}) async {
  final json = encodeDocument(
    construction,
    viewport: viewport,
    settings: settings,
  );
  final bytes = Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
  );
  await FilePicker.saveFile(
    dialogTitle: 'Save construction',
    fileName: defaultConstructionFileName,
    mimeType: _constructionMimeType,
    bytes: bytes,
  );
}

/// File name offered for a PNG export.
const String defaultExportPngFileName = 'construction.png';

/// Hands already-encoded PNG [bytes] to the platform's save dialog (a
/// download on the web). Completes when the dialog does; a cancelled
/// dialog is not an error.
Future<void> savePngBytes(Uint8List bytes) async {
  await FilePicker.saveFile(
    dialogTitle: 'Export as PNG',
    fileName: defaultExportPngFileName,
    mimeType: 'image/png',
    bytes: bytes,
  );
}

/// Shows the platform's open dialog and decodes the picked file.
///
/// Returns null when the user cancels. Throws [FormatException] for
/// anything wrong with the file itself — invalid UTF-8, invalid JSON, or
/// a document [decodeDocument] rejects — so callers show one dialog for
/// any bad file.
Future<DecodedDocument?> openConstructionFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Open construction',
    type: FileType.custom,
    allowedExtensions: _openExtensions,
  );
  if (file == null) {
    return null;
  }
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } on Exception {
    // The picked file exists but could not be read back — an unreadable
    // path, a revoked content URI, a failed blob fetch. That is still
    // "something wrong with the file", so it joins the one dialog.
    throw const FormatException('Could not read the selected file');
  }
  final Object? json = jsonDecode(utf8.decode(bytes));
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Not a construction file');
  }
  return decodeDocument(json);
}
