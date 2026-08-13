import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/export/png_exporter.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';

const red = ui.Color(0xFFFF0000);
const white = ui.Color(0xFFFFFFFF);
const blue = ui.Color(0xFF0000FF);

/// A single red point at world (0, 0), which the [pointViewport] below
/// puts at screen (5, 5) — dot radius 4 px (the attribute default), so
/// (5, 5) is inside the dot and the far corner is well clear of it.
Construction pointScene() {
  final construction = Construction();
  construction.add(
    FreePoint(
      id: 'p',
      position: Vec2.zero,
      attributes: const ObjectAttributes(colorArgb: 0xFFFF0000),
    ),
  );
  return construction;
}

const pointViewport = ViewportState(pan: Vec2(-5, 5), scale: 1);

Future<ui.Color> pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    data!.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('renderConstructionImage', () {
    test('output dimensions are logical size times pixel ratio', () async {
      final image = await renderConstructionImage(
        pointScene(),
        viewport: pointViewport,
        logicalSize: const ui.Size(20, 16),
        pixelRatio: 2,
        defaultColor: blue,
      );
      expect(image.width, 40);
      expect(image.height, 32);
      image.dispose();
    });

    test('rejects an empty output rectangle', () {
      expect(
        () => renderConstructionImage(
          pointScene(),
          viewport: pointViewport,
          logicalSize: ui.Size.zero,
          defaultColor: blue,
        ),
        throwsArgumentError,
      );
    });

    test('draws the object at its screen position in its own color', () async {
      final image = await renderConstructionImage(
        pointScene(),
        viewport: pointViewport,
        logicalSize: const ui.Size(20, 16),
        background: white,
        defaultColor: blue,
      );
      expect(await pixelAt(image, 5, 5), red);
      image.dispose();
    });

    test(
      'hidden objects never render — not even dimmed (the Show/Hide '
      'view is tool-scoped and the exporter builds its own painter)',
      () async {
        final construction = pointScene();
        construction.setAttributes(
          'p',
          const ObjectAttributes(colorArgb: 0xFFFF0000, visible: false),
        );
        final image = await renderConstructionImage(
          construction,
          viewport: pointViewport,
          logicalSize: const ui.Size(20, 16),
          background: white,
          defaultColor: blue,
        );
        expect(await pixelAt(image, 5, 5), white);
        image.dispose();
      },
    );

    test(
      'no background leaves everything off the geometry transparent',
      () async {
        final image = await renderConstructionImage(
          pointScene(),
          viewport: pointViewport,
          logicalSize: const ui.Size(20, 16),
          defaultColor: blue,
        );
        expect((await pixelAt(image, 18, 14)).a, 0);
        // The geometry itself still renders over the transparent ground.
        expect(await pixelAt(image, 5, 5), red);
        image.dispose();
      },
    );

    test('background fills every non-geometry pixel', () async {
      final image = await renderConstructionImage(
        pointScene(),
        viewport: pointViewport,
        logicalSize: const ui.Size(20, 16),
        background: white,
        defaultColor: blue,
      );
      expect(await pixelAt(image, 18, 14), white);
      expect(await pixelAt(image, 0, 0), white);
      image.dispose();
    });

    test('pixel ratio scales positions with the geometry', () async {
      final image = await renderConstructionImage(
        pointScene(),
        viewport: pointViewport,
        logicalSize: const ui.Size(20, 16),
        pixelRatio: 4,
        background: white,
        defaultColor: blue,
      );
      // The dot center lands at 4× its logical position.
      expect(await pixelAt(image, 20, 20), red);
      // The dot radius scaled too (4 logical px → 16 physical), so a
      // pixel 10 px out is still red and one 20 px out is background.
      expect(await pixelAt(image, 30, 20), red);
      expect(await pixelAt(image, 41, 20), white);
      image.dispose();
    });

    test('objects with no explicit color take the default color', () async {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(2, 0));
      final b = FreePoint(id: 'b', position: const Vec2(8, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b));
      final image = await renderConstructionImage(
        construction,
        viewport: const ViewportState(pan: Vec2(0, 5), scale: 1),
        logicalSize: const ui.Size(10, 10),
        background: white,
        defaultColor: blue,
      );
      // Segment midpoint at screen (5, 5).
      expect(await pixelAt(image, 5, 5), blue);
      image.dispose();
    });

    // Phase 36: with [pointViewport] the world origin sits at screen
    // (5, 5). At scale 1 the grid step is 50, so the only on-screen grid
    // lines are the two through the origin — the same positions the axes
    // take. Strokes land between pixel centers (antialiased), so the
    // probes check "no longer pure background" rather than exact colors.
    group('axes & grid layer', () {
      const probeSize = ui.Size(20, 16);

      test(
        'off by default: the export is untouched by document toggles',
        () async {
          final image = await renderConstructionImage(
            pointScene(),
            viewport: pointViewport,
            logicalSize: probeSize,
            background: white,
            defaultColor: blue,
          );
          expect(
            await pixelAt(image, 5, 0),
            white,
            reason: 'no vertical grid line/axis without the flags',
          );
          expect(await pixelAt(image, 0, 5), white);
          image.dispose();
        },
      );

      test('showGrid paints grid lines, showAxes paints the axes', () async {
        for (final flags in const [
          (showAxes: false, showGrid: true),
          (showAxes: true, showGrid: false),
        ]) {
          final image = await renderConstructionImage(
            pointScene(),
            viewport: pointViewport,
            logicalSize: probeSize,
            background: white,
            defaultColor: blue,
            showAxes: flags.showAxes,
            showGrid: flags.showGrid,
          );
          expect(
            (await pixelAt(image, 5, 0)) == white,
            isFalse,
            reason:
                'the vertical line through the origin must paint '
                'under $flags',
          );
          expect(
            (await pixelAt(image, 0, 5)) == white,
            isFalse,
            reason:
                'the horizontal line through the origin must paint '
                'under $flags',
          );
          expect(
            await pixelAt(image, 0, 0),
            white,
            reason: 'pixels off both lines stay background under $flags',
          );
          image.dispose();
        }
      });
    });
  });

  group('encodePng', () {
    test('emits the PNG signature', () async {
      final image = await renderConstructionImage(
        pointScene(),
        viewport: pointViewport,
        logicalSize: const ui.Size(20, 16),
        defaultColor: blue,
      );
      final bytes = await encodePng(image);
      image.dispose();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group('framings', () {
    test('currentViewFraming passes the viewport through', () {
      const state = ViewportState(pan: Vec2(3, 7), scale: 2);
      final framing = currentViewFraming(state, const ui.Size(100, 50));
      expect(framing.viewport, state);
      expect(framing.logicalSize, const ui.Size(100, 50));
    });

    test('fitConstructionFraming is null with nothing visible', () {
      expect(fitConstructionFraming(const [], const ui.Size(100, 50)), isNull);
    });

    test('fitConstructionFraming frames at the canvas size', () {
      final framing = fitConstructionFraming(
        pointScene().objects,
        const ui.Size(100, 50),
      );
      expect(framing, isNotNull);
      expect(framing!.logicalSize, const ui.Size(100, 50));
    });

    test('regionFraming keeps the scale and re-anchors the pan', () {
      // World (10, -20) sits at screen (10, 20) under the identity view.
      const state = ViewportState();
      final framing = regionFraming(state, const ui.Rect.fromLTWH(8, 18, 6, 6));
      expect(framing.viewport.scale, 1);
      expect(framing.viewport.pan, const Vec2(8, -18));
      expect(framing.logicalSize, const ui.Size(6, 6));
    });

    test('framings under view rotation: current and region carry it, '
        'fit exports unrotated', () {
      const rotated = ViewportState(pan: Vec2(3, 7), scale: 2, rotation: 0.6);

      final current = currentViewFraming(rotated, const ui.Size(100, 50));
      expect(current.viewport.rotation, 0.6);

      final region = regionFraming(
        rotated,
        const ui.Rect.fromLTWH(8, 18, 6, 6),
      );
      expect(region.viewport.rotation, 0.6);
      expect(region.viewport.scale, 2);
      // The pan solve holds at any angle: the marquee corner's world
      // point must sit at the output origin.
      final corner = CanvasViewport(region.viewport).worldToScreen(
        CanvasViewport(rotated).screenToWorld(const ui.Offset(8, 18)),
      );
      expect(corner.dx, closeTo(0, 1e-9));
      expect(corner.dy, closeTo(0, 1e-9));

      final fit = fitConstructionFraming(
        pointScene().objects,
        const ui.Size(100, 50),
      );
      expect(
        fit!.viewport.rotation,
        0,
        reason: 'fit framing always exports level',
      );
    });

    test('regionFraming exports exactly the marquee contents', () async {
      // Red dot at world (10, -20) = screen (10, 20); the region starts
      // at (8, 18), so the dot must land at (2, 2) in the output.
      final construction = Construction();
      construction.add(
        FreePoint(
          id: 'p',
          position: const Vec2(10, -20),
          attributes: const ObjectAttributes(colorArgb: 0xFFFF0000),
        ),
      );
      final framing = regionFraming(
        const ViewportState(),
        const ui.Rect.fromLTWH(8, 18, 12, 10),
      );
      final image = await renderConstructionImage(
        construction,
        viewport: framing.viewport,
        logicalSize: framing.logicalSize,
        background: white,
        defaultColor: blue,
      );
      expect(image.width, 12);
      expect(image.height, 10);
      expect(await pixelAt(image, 2, 2), red);
      expect(await pixelAt(image, 11, 9), white);
      image.dispose();
    });
  });
}
