import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';

void main() {
  group('CanvasViewport', () {
    test('identity state maps world origin to screen origin, y flipped', () {
      const viewport = CanvasViewport(ViewportState());

      expect(viewport.worldToScreen(Vec2.zero), Offset.zero);
      expect(
        viewport.worldToScreen(const Vec2(3, 2)),
        const Offset(3, -2),
        reason:
            'world y-up: positive world y is above the origin, i.e. '
            'negative screen y',
      );
    });

    test('pan places its world point at the canvas origin', () {
      const viewport = CanvasViewport(ViewportState(pan: Vec2(10, 20)));

      expect(viewport.worldToScreen(const Vec2(10, 20)), Offset.zero);
      expect(viewport.worldToScreen(const Vec2(11, 19)), const Offset(1, 1));
    });

    test('scale multiplies screen distances', () {
      const viewport = CanvasViewport(ViewportState(scale: 2));

      expect(viewport.worldToScreen(const Vec2(1, -1)), const Offset(2, 2));
      expect(viewport.worldToScreenLength(3), 6);
      expect(viewport.screenToWorldLength(8), 4);
    });

    test('zoomedAbout scales while pinning the focal world point', () {
      const viewport = CanvasViewport(
        ViewportState(pan: Vec2(-4, 7.5), scale: 2.5),
      );
      const focal = Offset(320, 240);
      final fixedWorld = viewport.screenToWorld(focal);

      for (final factor in [2.0, 0.5, 1.25, 0.9]) {
        final zoomed = CanvasViewport(viewport.zoomedAbout(focal, factor));
        expect(zoomed.state.scale, closeTo(2.5 * factor, 1e-12));
        final focalAfter = zoomed.worldToScreen(fixedWorld);
        expect(
          focalAfter.dx,
          closeTo(focal.dx, 1e-9),
          reason: 'factor $factor moved the focal point',
        );
        expect(
          focalAfter.dy,
          closeTo(focal.dy, 1e-9),
          reason: 'factor $factor moved the focal point',
        );
      }
    });

    test('zoomedAbout in then out restores the original state', () {
      const viewport = CanvasViewport(
        ViewportState(pan: Vec2(3, -2), scale: 1.5),
      );
      const focal = Offset(100, 50);

      final there = CanvasViewport(viewport.zoomedAbout(focal, 2));
      final back = there.zoomedAbout(focal, 0.5);
      expect(back.scale, closeTo(1.5, 1e-12));
      expect(
        back.pan.closeTo(viewport.state.pan),
        isTrue,
        reason: 'round trip drifted the pan: ${back.pan}',
      );
    });

    test('zoomedAbout clamps the scale and no-ops at the bounds', () {
      const viewport = CanvasViewport(ViewportState(scale: 1));
      const focal = Offset(50, 50);

      final floored = viewport.zoomedAbout(focal, 1e-9);
      expect(floored.scale, CanvasViewport.minScale);
      final ceiled = viewport.zoomedAbout(focal, 1e9);
      expect(ceiled.scale, CanvasViewport.maxScale);

      // Already at a bound: further zoom out must not creep the pan.
      final atFloor = CanvasViewport(floored);
      expect(
        atFloor.zoomedAbout(focal, 0.5),
        floored,
        reason: 'clamped zoom must return the state unchanged',
      );
    });

    test('pannedByScreen shifts content with the pointer, scale untouched', () {
      const viewport = CanvasViewport(
        ViewportState(pan: Vec2(10, -5), scale: 2),
      );
      const world = Vec2(12, -8);
      final before = viewport.worldToScreen(world);

      final panned = CanvasViewport(
        viewport.pannedByScreen(const Offset(30, -14)),
      );
      expect(panned.state.scale, 2);
      final after = panned.worldToScreen(world);
      expect(
        after - before,
        const Offset(30, -14),
        reason: 'every world point moves by exactly the screen delta',
      );
    });

    test('screenToWorld inverts worldToScreen', () {
      const viewport = CanvasViewport(
        ViewportState(pan: Vec2(-4, 7.5), scale: 2.5),
      );
      const points = [Vec2.zero, Vec2(1, 1), Vec2(-3.25, 12), Vec2(100, -0.5)];

      for (final world in points) {
        final roundTrip = viewport.screenToWorld(viewport.worldToScreen(world));
        expect(
          roundTrip.closeTo(world),
          isTrue,
          reason: '$world did not survive the round trip: $roundTrip',
        );
      }
    });
  });

  group('CanvasViewport rotation', () {
    test('positive rotation turns content counterclockwise on screen', () {
      // A quarter turn about the canvas origin (pan = world origin):
      // "right of origin" must land "above origin" — screen y negative.
      final viewport = CanvasViewport(ViewportState(rotation: math.pi / 2));

      final right = viewport.worldToScreen(const Vec2(1, 0));
      expect(right.dx, closeTo(0, 1e-12));
      expect(right.dy, closeTo(-1, 1e-12));

      final up = viewport.worldToScreen(const Vec2(0, 1));
      expect(up.dx, closeTo(-1, 1e-12));
      expect(up.dy, closeTo(0, 1e-12));
    });

    test('pan stays the world point at the canvas origin at any angle', () {
      for (final rotation in [0.3, -1.2, math.pi, 5.0]) {
        final viewport = CanvasViewport(
          ViewportState(pan: const Vec2(10, 20), scale: 2, rotation: rotation),
        );
        final origin = viewport.worldToScreen(const Vec2(10, 20));
        expect(
          origin.dx,
          closeTo(0, 1e-12),
          reason: 'rotation $rotation moved the origin',
        );
        expect(
          origin.dy,
          closeTo(0, 1e-12),
          reason: 'rotation $rotation moved the origin',
        );
      }
    });

    test('screenToWorld inverts worldToScreen at non-zero rotation', () {
      const points = [Vec2.zero, Vec2(1, 1), Vec2(-3.25, 12), Vec2(100, -0.5)];
      for (final rotation in [0.1, -0.7, math.pi / 3, 2.9, -math.pi]) {
        final viewport = CanvasViewport(
          ViewportState(
            pan: const Vec2(-4, 7.5),
            scale: 2.5,
            rotation: rotation,
          ),
        );
        for (final world in points) {
          final roundTrip = viewport.screenToWorld(
            viewport.worldToScreen(world),
          );
          expect(
            roundTrip.closeTo(world),
            isTrue,
            reason:
                '$world at rotation $rotation did not survive the '
                'round trip: $roundTrip',
          );
        }
      }
    });

    test('rotation preserves screen distances, so length helpers hold', () {
      final viewport = CanvasViewport(
        const ViewportState(pan: Vec2(3, -2), scale: 2.5, rotation: 0.8),
      );
      const a = Vec2(1, 4);
      const b = Vec2(-2, 0);

      final screenDistance =
          (viewport.worldToScreen(a) - viewport.worldToScreen(b)).distance;
      expect(
        screenDistance,
        closeTo(viewport.worldToScreenLength((a - b).norm), 1e-9),
        reason: 'a rotated view must not change on-screen lengths',
      );
    });

    test('pinning honours rotation and still pins the world point', () {
      const world = Vec2(6, -3);
      const focal = Offset(200, 150);
      for (final rotation in [0.0, 0.4, -2.1, math.pi / 2]) {
        final state = CanvasViewport.pinning(
          world: world,
          focal: focal,
          scale: 2,
          rotation: rotation,
        );
        expect(state.rotation, rotation);
        final pinned = CanvasViewport(state).screenToWorld(focal);
        expect(
          pinned.closeTo(world),
          isTrue,
          reason:
              'rotation $rotation: focal resolves to $pinned, '
              'not $world',
        );
      }
    });

    test('zoomedAbout preserves rotation and the focal pin', () {
      final viewport = CanvasViewport(
        const ViewportState(pan: Vec2(-4, 7.5), scale: 2.5, rotation: 1.1),
      );
      const focal = Offset(320, 240);
      final fixedWorld = viewport.screenToWorld(focal);

      final zoomed = CanvasViewport(viewport.zoomedAbout(focal, 1.5));
      expect(zoomed.state.rotation, 1.1);
      expect(zoomed.state.scale, closeTo(3.75, 1e-12));
      final focalAfter = zoomed.worldToScreen(fixedWorld);
      expect(focalAfter.dx, closeTo(focal.dx, 1e-9));
      expect(focalAfter.dy, closeTo(focal.dy, 1e-9));
    });

    test('worldToScreenAngle matches where worldToScreen puts rim points', () {
      final viewport = CanvasViewport(
        const ViewportState(pan: Vec2(2, 1), scale: 3, rotation: 0.9),
      );
      const center = Vec2(5, -1);
      const radius = 2.0;
      final centerScreen = viewport.worldToScreen(center);
      for (final worldAngle in [0.0, 1.0, -2.4, math.pi]) {
        final rim = viewport.worldToScreen(
          center + Vec2(math.cos(worldAngle), math.sin(worldAngle)) * radius,
        );
        final screenAngle = viewport.worldToScreenAngle(worldAngle);
        final expected =
            centerScreen +
            Offset(math.cos(screenAngle), math.sin(screenAngle)) *
                viewport.worldToScreenLength(radius);
        expect(
          (rim - expected).distance,
          lessThan(1e-9),
          reason:
              'world angle $worldAngle: rim point and screen angle '
              'disagree',
        );
      }
    });

    test('worldToScreenDirection rotates and flips, preserving length', () {
      final viewport = CanvasViewport(
        const ViewportState(scale: 4, rotation: math.pi / 2),
      );
      // At a quarter turn CCW, world +x shows as screen up, world +y as
      // screen left; scale never applies to directions.
      final xImage = viewport.worldToScreenDirection(const Vec2(1, 0));
      expect(xImage.dx, closeTo(0, 1e-12));
      expect(xImage.dy, closeTo(-1, 1e-12));
      final yImage = viewport.worldToScreenDirection(const Vec2(0, 1));
      expect(yImage.dx, closeTo(-1, 1e-12));
      expect(yImage.dy, closeTo(0, 1e-12));
    });

    test('pannedByScreen shifts content by the delta at non-zero rotation', () {
      final viewport = CanvasViewport(
        const ViewportState(pan: Vec2(10, -5), scale: 2, rotation: -0.6),
      );
      const world = Vec2(12, -8);
      final before = viewport.worldToScreen(world);

      final panned = CanvasViewport(
        viewport.pannedByScreen(const Offset(30, -14)),
      );
      expect(panned.state.scale, 2);
      expect(panned.state.rotation, -0.6);
      final after = panned.worldToScreen(world);
      expect(
        after.dx - before.dx,
        closeTo(30, 1e-9),
        reason: 'content must follow the screen delta at any angle',
      );
      expect(
        after.dy - before.dy,
        closeTo(-14, 1e-9),
        reason: 'content must follow the screen delta at any angle',
      );
    });
  });

  group('visibleWorldBox', () {
    const size = Size(800, 600);

    test('unrotated, it is exactly the canvas in world units', () {
      const viewport = CanvasViewport(ViewportState(pan: Vec2(-400, 300)));
      final box = viewport.visibleWorldBox(size);
      expect(box.min.x, closeTo(-400, 1e-9));
      expect(box.max.x, closeTo(400, 1e-9));
      expect(box.min.y, closeTo(-300, 1e-9));
      expect(box.max.y, closeTo(300, 1e-9));
    });

    test('scale shrinks the world it covers', () {
      const viewport = CanvasViewport(
        ViewportState(pan: Vec2(-40, 30), scale: 10),
      );
      final box = viewport.visibleWorldBox(size);
      expect(box.max.x - box.min.x, closeTo(80, 1e-9));
      expect(box.max.y - box.min.y, closeTo(60, 1e-9));
    });

    test('the margin grows it by that many screen pixels', () {
      const viewport = CanvasViewport(ViewportState(scale: 2));
      final plain = viewport.visibleWorldBox(size);
      final grown = viewport.visibleWorldBox(size, margin: 8);
      expect(grown.min.x, closeTo(plain.min.x - 4, 1e-9));
      expect(grown.max.x, closeTo(plain.max.x + 4, 1e-9));
      expect(grown.min.y, closeTo(plain.min.y - 4, 1e-9));
      expect(grown.max.y, closeTo(plain.max.y + 4, 1e-9));
    });

    test('under rotation it encloses every visible point', () {
      const viewport = CanvasViewport(
        ViewportState(pan: Vec2(-400, 300), rotation: 0.7),
      );
      final box = viewport.visibleWorldBox(size);
      // A rotated view is not axis-aligned, so the box is a superset —
      // which is what a clip bound for an unbounded curve needs to be.
      for (var i = 0; i <= 20; i++) {
        for (var j = 0; j <= 20; j++) {
          final world = viewport.screenToWorld(
            Offset(size.width * i / 20, size.height * j / 20),
          );
          expect(world.x, inInclusiveRange(box.min.x, box.max.x));
          expect(world.y, inInclusiveRange(box.min.y, box.max.y));
        }
      }
      expect(
        (box.max.x - box.min.x) * (box.max.y - box.min.y),
        greaterThan(size.width * size.height),
        reason: 'strictly a superset at a nonzero angle',
      );
    });
  });
}
