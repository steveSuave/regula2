import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';

/// Phase 136: a locus arm that runs off to infinity must not go into the
/// `Path` that draws the visible curve.
///
/// `GeoLocus.coreSamples` has existed since Phase 39f because the
/// viewport fitter and the label anchor could not use the raw samples —
/// a line-host locus sweeps its whole carrier, so a diverging arm
/// reaches astronomically far out. The painter was the last reader still
/// handing them to the rasterizer whole: every sample went into one
/// unclipped `Path`, including `no-locus.rgl`'s at 1e9, which at the
/// document's own zoom is a *screen* coordinate of 2.7e10.
///
/// The tests below assert ink, which is the property that matters and is
/// the one that was missing. They are deliberately VM tests: the fix
/// makes the drawn geometry independent of what any rasterizer does with
/// an extreme coordinate, which is the formulation `CLAUDE.md` asks for
/// over pinning a platform's tolerance in `test/web/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(986, 620);

  Construction load() {
    final json =
        jsonDecode(File('test/fixtures/no-locus.rgl').readAsStringSync())
            as Map<String, dynamic>;
    return decodeDocument(json).construction;
  }

  /// Painted pixels with the locus shown, minus the same scene without
  /// it — the locus's own ink, at the document's saved viewport.
  Future<int> locusInk(Construction construction) async {
    final locus = construction.objects.whereType<Locus>().single;

    Future<int> painted({required bool showLocus}) async {
      locus.attributes = locus.attributes.copyWith(visible: showLocus);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & size);
      GeometryPainter(
        construction: construction,
        viewport: CanvasViewport(
          const ViewportState(
            pan: Vec2(-30.956805385851762, 17.97771203765499),
            scale: 27.419357069815742,
          ),
        ),
        revision: 0,
        defaultColor: const Color(0xFF66AAFF),
        selectionColor: const Color(0xFFCC5522),
        selectedIds: const <String>{},
        previewMarkers: const [],
        showAxes: false,
        showGrid: false,
        axisColor: const Color(0xFF888888),
        gridColor: const Color(0xFFDDDDDD),
      ).paint(canvas, size);
      final image = await recorder.endRecording().toImage(986, 620);
      final data = (await image.toByteData())!;
      var count = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i + 3) > 16) count++;
      }
      return count;
    }

    final without = await painted(showLocus: false);
    final with_ = await painted(showLocus: true);
    return with_ - without;
  }

  test('the reported document draws its locus wherever F stands', () async {
    // Past t = 0 and t = -8 the arm reaches 1e9 (Phase 135 made the far
    // stretch the true curve instead of the bounded x-axis), and that
    // sample used to share a `Path` with the loop the user is looking at.
    for (final t in [-6.252881689952558, -2.0, 1.0, 4.0, -10.0, -14.0]) {
      final construction = load();
      final f = construction.objects.whereType<PointOnObject>().single;
      construction.setPointOnObjectParameter(f.id, t);
      expect(
        await locusInk(construction),
        greaterThan(1000),
        reason: 'the locus drew nothing at t = $t',
      );
    }
  });

  test('and the samples it is drawn from really do reach that far', () {
    // Guards the test above from quietly stopping to exercise anything:
    // if the sweep ever stops producing an astronomical arm, the clip is
    // no longer under test and this says so.
    final construction = load();
    final locus = construction.objects.whereType<Locus>().single;
    var farthest = 0.0;
    for (final sample in locus.samples!) {
      if (sample == null) continue;
      final magnitude = sample.x.abs() > sample.y.abs()
          ? sample.x.abs()
          : sample.y.abs();
      if (magnitude > farthest) farthest = magnitude;
    }
    expect(farthest, greaterThan(1e6));
  });

  // The *untrimmed* path — a locus that fits on screen, where the clip
  // must change nothing at all — is pinned by `locus_light.png` and
  // `locus_dark.png`, which stayed byte-identical through this change.
  // There is no zoom that tests it on this document: swallowing a 1e9
  // arm needs a scale at which the whole figure is sub-pixel.
}
