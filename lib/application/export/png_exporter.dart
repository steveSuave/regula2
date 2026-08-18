import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../domain/construction/construction.dart';
import '../../domain/construction/geo_object.dart';
import '../../presentation/canvas/canvas_viewport.dart';
import '../../presentation/canvas/fit_viewport.dart';
import '../../presentation/canvas/geometry_painter.dart';
import '../providers/viewport_provider.dart';

/// One export framing resolved to numbers: the viewport that maps world
/// coordinates onto the output and the output's size in logical pixels
/// (the physical pixel size is this times the export's pixel ratio).
///
/// Export is a read-only view operation — no `Command`, not undoable,
/// nothing in the save format (PLAN "Export"). This file orchestrates the
/// presentation layer's painter, so like the painter it sits outside
/// `domain/`; the layer rule (domain imports no Flutter) is untouched.
typedef ExportFraming = ({ViewportState viewport, ui.Size logicalSize});

/// Frames exactly what the canvas shows: the live viewport over the full
/// canvas size.
ExportFraming currentViewFraming(ViewportState viewport, ui.Size canvasSize) =>
    (viewport: viewport, logicalSize: canvasSize);

/// Frames every visible object centered with the standard fit margin,
/// like the app bar's Fit button. Null when nothing is visible to frame
/// (callers fall back to [currentViewFraming]).
ExportFraming? fitConstructionFraming(
  Iterable<GeoObject> objects,
  ui.Size canvasSize,
) {
  final fitted = fittedViewport(objects, canvasSize);
  if (fitted == null) {
    return null;
  }
  return (viewport: fitted, logicalSize: canvasSize);
}

/// Frames a user-dragged [region] of the canvas (screen coordinates):
/// same scale and view rotation, pan moved so the region's top-left
/// corner becomes the output origin — what's inside the marquee is
/// exactly what exports, at the angle the user sees it.
ExportFraming regionFraming(ViewportState viewport, ui.Rect region) {
  final transform = CanvasViewport(viewport);
  return (
    viewport: ViewportState(
      pan: transform.screenToWorld(region.topLeft),
      scale: viewport.scale,
      rotation: viewport.rotation,
    ),
    logicalSize: region.size,
  );
}

/// Renders [construction] off-screen through the real [GeometryPainter] —
/// never a widget screenshot, so no UI chrome (selection halos,
/// in-progress markers, band rectangle) can leak into the export and any
/// resolution works.
///
/// [background] fills the output first; null leaves it transparent.
/// [defaultColor] colors objects with no explicit color (the theme
/// primary on screen). The caller owns the returned image and must
/// [ui.Image.dispose] it.
Future<ui.Image> renderConstructionImage(
  Construction construction, {
  required ViewportState viewport,
  required ui.Size logicalSize,
  double pixelRatio = 1,
  ui.Color? background,
  required ui.Color defaultColor,
  bool showAxes = false,
  bool showGrid = false,
  ui.Color axisColor = const ui.Color(0xFF757575),
  ui.Color gridColor = const ui.Color(0xFFE3E6EA),
  ui.Color absoluteColor = const ui.Color(0xFFB26A00),
  ui.Color absoluteOutsideColor = const ui.Color(0x40B26A00),
}) async {
  final width = (logicalSize.width * pixelRatio).round();
  final height = (logicalSize.height * pixelRatio).round();
  if (width <= 0 || height <= 0) {
    throw ArgumentError.value(
      logicalSize,
      'logicalSize',
      'export size must be positive',
    );
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // The painter works in logical pixels; the scale turns them into the
  // requested output resolution (strokes and labels scale up with it,
  // like a Hi-DPI screen would render them).
  canvas.scale(pixelRatio);
  if (background != null) {
    canvas.drawRect(
      ui.Offset.zero & logicalSize,
      ui.Paint()..color = background,
    );
  }
  GeometryPainter(
    construction: construction,
    viewport: CanvasViewport(viewport),
    // The painter only reads the revision in shouldRepaint; a one-shot
    // paint never repaints.
    revision: 0,
    defaultColor: defaultColor,
    // Unused with an empty selection, but the painter requires it.
    selectionColor: defaultColor,
    showAxes: showAxes,
    showGrid: showGrid,
    axisColor: axisColor,
    gridColor: gridColor,
    absoluteColor: absoluteColor,
    absoluteOutsideColor: absoluteOutsideColor,
  ).paint(canvas, logicalSize);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// PNG-encodes [image]. Throws [StateError] if the engine cannot encode
/// (out of memory — there is no partial failure mode).
Future<Uint8List> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('PNG encoding failed');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// [renderConstructionImage] + [encodePng] in one call, disposing the
/// intermediate image.
Future<Uint8List> exportConstructionPng(
  Construction construction, {
  required ViewportState viewport,
  required ui.Size logicalSize,
  double pixelRatio = 1,
  ui.Color? background,
  required ui.Color defaultColor,
  bool showAxes = false,
  bool showGrid = false,
  ui.Color axisColor = const ui.Color(0xFF757575),
  ui.Color gridColor = const ui.Color(0xFFE3E6EA),
  ui.Color absoluteColor = const ui.Color(0xFFB26A00),
  ui.Color absoluteOutsideColor = const ui.Color(0x40B26A00),
}) async {
  final image = await renderConstructionImage(
    construction,
    viewport: viewport,
    logicalSize: logicalSize,
    pixelRatio: pixelRatio,
    background: background,
    defaultColor: defaultColor,
    showAxes: showAxes,
    showGrid: showGrid,
    axisColor: axisColor,
    gridColor: gridColor,
    absoluteColor: absoluteColor,
    absoluteOutsideColor: absoluteOutsideColor,
  );
  try {
    return await encodePng(image);
  } finally {
    image.dispose();
  }
}
