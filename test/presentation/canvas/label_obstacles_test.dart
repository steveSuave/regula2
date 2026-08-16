import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/label_obstacles.dart';

import '../../projective_stubs.dart';

void main() {
  const viewport = CanvasViewport(ViewportState());
  const canvasSize = Size(800, 600);

  test('points, segment and labels land with their owners', () {
    final construction = Construction();
    final a = FreePoint(
      id: 'a',
      position: const Vec2(0, 0),
      attributes: const ObjectAttributes(name: 'A'),
    );
    final b = FreePoint(
      id: 'b',
      position: const Vec2(3, 4),
      attributes: const ObjectAttributes(name: 'B'),
    );
    final s = Segment(
      id: 's',
      point1: a,
      point2: b,
      attributes: const ObjectAttributes(showValue: true),
    );
    construction
      ..add(a)
      ..add(b)
      ..add(s);

    final scene = buildDeclutterScene(construction, viewport, canvasSize);
    expect(scene.rects.map((r) => r.ownerId), ['a', 'b']);
    expect(scene.capsules.map((c) => c.ownerId), ['s']);
    // Both named points and the segment's value paint labels.
    expect(scene.labels.map((l) => l.id), ['a', 'b', 's']);
  });

  test('hidden and undefined objects contribute nothing', () {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(3, 4));
    final hidden = Segment(
      id: 's',
      point1: a,
      point2: b,
      attributes: const ObjectAttributes(visible: false, showValue: true),
    );
    // A degenerate angle (arm on the vertex) is undefined.
    final undefined = VertexAngle(
      id: 'v',
      arm1: a,
      vertex: a,
      arm2: b,
      attributes: const ObjectAttributes(showValue: true),
    );
    construction
      ..add(a)
      ..add(b)
      ..add(hidden)
      ..add(undefined);

    final scene = buildDeclutterScene(construction, viewport, canvasSize);
    expect(scene.capsules, isEmpty);
    expect(scene.labels, isEmpty);
    expect(scene.rects.length, 2, reason: 'only the point dots remain');
  });

  test('a measurement is a label but no geometry', () {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(3, 4));
    final d = DistanceMeasurement(id: 'd', point1: a, point2: b);
    construction
      ..add(a)
      ..add(b)
      ..add(d);

    final scene = buildDeclutterScene(construction, viewport, canvasSize);
    expect(scene.capsules, isEmpty);
    expect(scene.labels.map((l) => l.id), ['d']);
  });

  test('angle markers: square edges, or spokes plus rim chords', () {
    final construction = Construction();
    final east = FreePoint(id: 'e', position: const Vec2(5, 0));
    final origin = FreePoint(id: 'o', position: const Vec2(0, 0));
    final north = FreePoint(id: 'n', position: const Vec2(0, 7));
    final diagonal = FreePoint(id: 'd', position: const Vec2(5, 5));
    final right = VertexAngle(
      id: 'right',
      arm1: east,
      vertex: origin,
      arm2: north,
    );
    final acute = VertexAngle(
      id: 'acute',
      arm1: east,
      vertex: origin,
      arm2: diagonal,
    );
    construction
      ..add(east)
      ..add(origin)
      ..add(north)
      ..add(diagonal)
      ..add(right)
      ..add(acute);

    final scene = buildDeclutterScene(construction, viewport, canvasSize);
    final rightCapsules = scene.capsules
        .where((c) => c.ownerId == 'right')
        .length;
    final acuteCapsules = scene.capsules
        .where((c) => c.ownerId == 'acute')
        .length;
    expect(rightCapsules, 4, reason: 'the right-angle square has 4 edges');
    // 45° at ≤ 30° steps → 2 steps: 3 spokes + 2 rim chords.
    expect(acuteCapsules, 5);
  });

  group('conic obstacles (Phase 119)', () {
    const centred = CanvasViewport(ViewportState(pan: Vec2(-400, 300)));

    test('a hyperbola contributes one capsule chain per visible branch', () {
      final construction = Construction()
        ..add(
          StubProjectiveConic(
            ConicMatrix.coefficients(1 / 10000, 0, -1 / 10000, 0, 0, -1),
            id: 'k',
          ),
        );
      final scene = buildDeclutterScene(construction, centred, canvasSize);
      expect(scene.capsules, isNotEmpty);
      expect(scene.capsules.every((c) => c.ownerId == 'k'), isTrue);
      // Every capsule sits on one side or the other, never spanning the
      // gap between the branches — that gap is where a label may go.
      final leftish = scene.capsules.where((c) => c.a.dx < 400).length;
      expect(leftish, greaterThan(0));
      expect(leftish, lessThan(scene.capsules.length));
    });

    test('a circle-shaped conic keeps the circle obstacle', () {
      final construction = Construction()
        ..add(
          StubProjectiveConic(
            ConicMatrix.coefficients(1, 0, 1, 0, 0, -10000),
            id: 'k',
          ),
        );
      final scene = buildDeclutterScene(construction, centred, canvasSize);
      // The circle arm emits a 12–48-gon; the ends meet, so the chain is
      // closed.
      expect(scene.capsules.length, inInclusiveRange(12, 48));
      expect(
        (scene.capsules.first.a - scene.capsules.last.b).distance,
        lessThan(1e-6),
      );
    });

    test('an off-screen conic is no obstacle', () {
      final construction = Construction()
        ..add(
          StubProjectiveConic(
            ConicMatrix.coefficients(1, 0, 4, -20000, 0, 1e8 - 100),
            id: 'k',
          ),
        );
      final scene = buildDeclutterScene(construction, centred, canvasSize);
      expect(scene.capsules, isEmpty);
    });
  });
}
