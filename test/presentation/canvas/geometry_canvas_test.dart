import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/command_stack_provider.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/application/providers/tool_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/commands/set_geometry_command.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/focal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/tools/delete_tool.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/point_tool.dart';
import 'package:regula/domain/tools/visibility_tool.dart';
import 'package:regula/main.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/geometry_canvas.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';
import 'package:regula/presentation/canvas/label_layout.dart';
import 'package:regula/presentation/panels/conic_icon.dart';
import 'package:regula/presentation/panels/object_kind_label.dart';

import '../../wide_window.dart';

/// End-to-end tool flow: activate the point tool, tap the canvas, see
/// free points appear in the construction, undo/redo them. This is the
/// widget-level counterpart of the Phase 5 web smoke test.
void main() {
  late ProviderContainer container;

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

  int objectCount() => container.read(constructionProvider).construction.length;

  testWidgets('tap with no active tool adds nothing', (tester) async {
    await pumpEditor(tester);

    await tester.tapAt(tester.getCenter(find.byType(GeometryCanvas)));
    await tester.pump();

    expect(objectCount(), 0);
  });

  testWidgets('tapping an angle\'s marker wedge selects the angle', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: const Vec2(150, -100));
    final v = FreePoint(id: 'v', position: const Vec2(100, -100));
    final b = FreePoint(id: 'b', position: const Vec2(100, -50));
    construction
      ..add(a)
      ..add(v)
      ..add(b)
      ..add(VertexAngle(id: 'ang', arm1: a, vertex: v, arm2: b));
    await tester.pump();

    // Mid-sweep on the marker arc: 20 px from the vertex at 45°, which is
    // ~20 px from the vertex point — outside even the touch threshold, so
    // only the wedge geometry can claim this tap.
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(114.1, 85.9));
    await tester.pump();
    expect(container.read(selectionProvider), {'ang'});

    // The vertex itself still belongs to the point.
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    expect(container.read(selectionProvider), {'v'});
  });

  testWidgets('a tapped line mid-collection is haloed, with no marker on it', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: const Vec2(100, -200));
    final b = FreePoint(id: 'b', position: const Vec2(300, -200));
    construction
      ..add(a)
      ..add(b)
      ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b));
    await tester.pump();

    container
        .read(toolProvider.notifier)
        .activate(IntersectionTool(newId: () => 'unused'));
    await tester.pump();

    // Mid-line, 100 px from either endpoint — only the line claims it.
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(200, 200));
    await tester.pump();

    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(GeometryCanvas),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<GeometryPainter>()
        .single;
    expect(painter.previewObjectIds, {
      'l',
    }, reason: 'the consumed line is haloed like a selection');
    expect(
      painter.previewMarkers,
      isEmpty,
      reason: 'no dot+ring marker on an existing object',
    );
  });

  testWidgets('Show/Hide turns the hidden view on: painter dims hidden in, '
      'taps toggle both directions, other modes never reach hidden', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final h = FreePoint(
      id: 'h',
      position: const Vec2(150, -150),
      attributes: const ObjectAttributes(visible: false),
    );
    construction.add(h);
    await tester.pump();

    GeometryPainter painter() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(GeometryCanvas),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<GeometryPainter>()
        .single;
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final onHidden = origin + const Offset(150, 150);

    // Move/select mode: the hidden point is unreachable.
    expect(painter().showHidden, isFalse);
    await tester.tapAt(onHidden);
    await tester.pump();
    expect(container.read(selectionProvider), isEmpty);

    // Hide variant: hidden stays unreachable — taps can only ever hide.
    container.read(toolProvider.notifier).activate(VisibilityTool.hide());
    await tester.pump();
    expect(painter().showHidden, isFalse);
    await tester.tapAt(onHidden);
    await tester.pump();
    expect(h.attributes.visible, isFalse);

    // Show/Hide: the painter dims hidden objects in and a tap re-shows…
    container.read(toolProvider.notifier).activate(VisibilityTool.showHide());
    await tester.pump();
    expect(painter().showHidden, isTrue);
    await tester.tapAt(onHidden);
    await tester.pump();
    expect(h.attributes.visible, isTrue);

    // …and the next tap re-hides.
    await tester.tapAt(onHidden);
    await tester.pump();
    expect(h.attributes.visible, isFalse);

    // Deactivating the tool drops the hidden view with it.
    container.read(toolProvider.notifier).deactivate();
    await tester.pump();
    expect(painter().showHidden, isFalse);
  });

  testWidgets('Hide-tool tap hides the hit object; one undo restores', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    final p = FreePoint(id: 'p', position: const Vec2(100, -100));
    construction.add(p);
    await tester.pump();

    container.read(toolProvider.notifier).activate(VisibilityTool.hide());
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    expect(p.attributes.visible, isFalse);

    container.read(commandStackProvider.notifier).undo();
    expect(p.attributes.visible, isTrue, reason: 'one tap = one undo step');
  });

  testWidgets('point tool: tap to add points, tap a point again is ignored, '
      'undo/redo round-trips', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 150));
    await tester.pump();
    expect(objectCount(), 2);

    // Same spot again: the hit tester reports the existing point and the
    // point tool refuses to stack a coincident one on top.
    await tester.tapAt(origin + const Offset(200, 150));
    await tester.pump();
    expect(objectCount(), 2);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 1);

    await tester.tap(find.byIcon(Icons.redo));
    await tester.pump();
    expect(objectCount(), 2);
  });

  testWidgets(
    'centroid tool via the centers menu: three taps commit one undo unit',
    (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Centroid'));
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(find.byType(GeometryCanvas));
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      await tester.tapAt(origin + const Offset(200, 100));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'nothing is committed until the third vertex lands',
      );

      await tester.tapAt(origin + const Offset(150, 200));
      await tester.pump();
      expect(objectCount(), 4, reason: '3 free points + the centroid');

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'the whole construction step is one undo unit',
      );

      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();
      expect(objectCount(), 4);
    },
  );

  testWidgets(
    'intersection tool via its toolbar button: tap two crossing segments, '
    'get the point where they cross',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      // Two crossing segments via the two-point menu (4 free points + 2
      // segments): horizontal (100,100)–(300,100), vertical (200,40)–(200,160).
      Future<void> buildSegment(Offset from, Offset to) async {
        await tester.tap(find.byIcon(Icons.timeline));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Segment'));
        await tester.pumpAndSettle();
        await tester.tapAt(origin + from);
        await tester.pump();
        await tester.tapAt(origin + to);
        await tester.pump();
      }

      await buildSegment(const Offset(100, 100), const Offset(300, 100));
      await buildSegment(const Offset(200, 40), const Offset(200, 160));
      expect(objectCount(), 6);

      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intersection of two curves'));
      await tester.pumpAndSettle();

      // Taps land on the segments away from their endpoints and from the
      // crossing, so the hit tester reports the segments themselves.
      await tester.tapAt(origin + const Offset(150, 100));
      await tester.pump();
      expect(objectCount(), 6, reason: 'one curve collected, nothing built');

      await tester.tapAt(origin + const Offset(200, 60));
      await tester.pump();
      expect(objectCount(), 7);

      final objects = container
          .read(constructionProvider)
          .construction
          .objects
          .toList();
      final point = objects.last as IntersectionPoint;
      // Default viewport: world origin at the canvas top-left, y-up.
      expect(point.position!.closeTo(const Vec2(200, -100)), isTrue);

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(objectCount(), 6, reason: 'only the intersection point undoes');
    },
  );

  testWidgets(
    'square macro via the shapes menu: two taps commit one undo unit',
    (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Square'));
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(find.byType(GeometryCanvas));
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'nothing is committed until the second corner lands',
      );

      await tester.tapAt(origin + const Offset(200, 100));
      await tester.pump();
      expect(
        objectCount(),
        12,
        reason:
            '2 free points + side + 2 perpendiculars + 2 circles + '
            '2 corners + 3 sides',
      );

      // World is y-up at scale 1: screen (100,100)/(200,100) are world
      // A=(100,-100), B=(200,-100), so the square's derived corners sit
      // one side length above at y=0 (left of the A->B direction).
      final corners = container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<IntersectionPoint>()
          .toList();
      expect(corners.map((c) => c.position), [
        const Vec2(200, 0),
        const Vec2(100, 0),
      ]);

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(objectCount(), 0, reason: 'the whole square is one undo unit');

      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();
      expect(objectCount(), 12);
    },
  );

  testWidgets(
    'parallelogram macro via the shapes menu: three taps, one undo unit',
    (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parallelogram'));
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(find.byType(GeometryCanvas));
      await tester.tapAt(origin + const Offset(100, 200));
      await tester.pump();
      await tester.tapAt(origin + const Offset(200, 200));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'nothing is committed until the third corner lands',
      );

      await tester.tapAt(origin + const Offset(250, 100));
      await tester.pump();
      expect(
        objectCount(),
        10,
        reason: '3 free points + 2 sides + 2 parallels + corner + 2 sides',
      );

      // D = A + (C − B): screen (150, 100).
      final corner = container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<IntersectionPoint>()
          .single;
      expect(corner.position!.x, closeTo(150, 1e-9));
      expect(
        corner.position!.y,
        closeTo(-100, 1e-9),
        reason: 'world is y-up: screen y 100 is world y -100',
      );

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'the whole parallelogram is one undo unit',
      );
    },
  );

  testWidgets(
    'trapezium macro via the shapes menu: three corners plus the D pick',
    (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      final trapeziumItem = find.text('Trapezium');
      await tester.ensureVisible(trapeziumItem);
      await tester.pumpAndSettle();
      await tester.tap(trapeziumItem);
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(find.byType(GeometryCanvas));
      await tester.tapAt(origin + const Offset(100, 200));
      await tester.pump();
      await tester.tapAt(origin + const Offset(200, 200));
      await tester.pump();
      await tester.tapAt(origin + const Offset(250, 100));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'the third corner does not commit — D is still pending',
      );

      await tester.tapAt(origin + const Offset(120, 80));
      await tester.pump();
      expect(
        objectCount(),
        9,
        reason: '3 free points + 2 sides + parallel + D + 2 sides',
      );

      // D = the 4th tap projected onto the horizontal parallel through C.
      final corner = container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<PointOnObject>()
          .single;
      expect(corner.position!.x, closeTo(120, 1e-9));
      expect(
        corner.position!.y,
        closeTo(-100, 1e-9),
        reason: 'projected to C\'s height (y-up world: screen y 100)',
      );

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(objectCount(), 0, reason: 'the whole trapezium is one undo unit');
    },
  );

  testWidgets('undo mid-collection consumes the collected input first', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // Place a point with the point tool.
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    expect(objectCount(), 1);

    // Collect it as a centroid vertex, then undo twice (Phase 59): the
    // first press only drops the pending vertex, the second pops the
    // stack.
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centroid'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 1, reason: 'the stack was not touched');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);

    // Three fresh taps still work and count from scratch.
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(150, 200));
    await tester.pump();
    expect(objectCount(), 4);
  });

  testWidgets(
    'segment via the two-point menu, then a point constrained onto it',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segment'));
      await tester.pumpAndSettle();

      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'first endpoint is only collected, not committed',
      );
      await tester.tapAt(origin + const Offset(300, 100));
      await tester.pump();
      expect(objectCount(), 3, reason: '2 free points + the segment');

      // Constrain a point onto the segment: the smart Point tool glues a
      // tap near the curve (within the 8 px threshold).
      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(200, 103));
      await tester.pump();
      expect(objectCount(), 4);
      expect(
        container
            .read(constructionProvider)
            .construction
            .objects
            .whereType<PointOnObject>()
            .single
            .position,
        const Vec2(200, -100),
        reason: 'the tap projects onto the segment, not a free point at 103',
      );

      // Away from any curve the same tool drops a free point.
      await tester.tapAt(origin + const Offset(200, 300));
      await tester.pump();
      expect(objectCount(), 5);
    },
  );

  testWidgets('perpendicular via the menu: tap the line, tap empty canvas, one '
      'undo unit', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // A horizontal line to be perpendicular to.
    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 100));
    await tester.pump();
    expect(objectCount(), 3, reason: '2 free points + the line');

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perpendicular line'));
    await tester.pumpAndSettle();

    // Tap the line away from its endpoints, then a spot off the line.
    await tester.tapAt(origin + const Offset(200, 102));
    await tester.pump();
    expect(objectCount(), 3, reason: 'the line fills a slot, no commit yet');
    await tester.tapAt(origin + const Offset(150, 250));
    await tester.pump();
    expect(objectCount(), 5, reason: 'new free point + the perpendicular');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 3, reason: 'point + perpendicular undo together');
  });

  testWidgets('angle bisector via the menu: three taps, one undo unit', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angle bisector'));
    await tester.pumpAndSettle();

    await tester.tapAt(origin + const Offset(300, 100)); // arm
    await tester.pump();
    await tester.tapAt(origin + const Offset(100, 100)); // vertex
    await tester.pump();
    expect(objectCount(), 0, reason: 'no commit until the second arm');
    await tester.tapAt(origin + const Offset(100, 300)); // arm
    await tester.pump();
    expect(objectCount(), 4, reason: '3 free points + the bisector');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);
  });

  testWidgets('angle bisector via two segment taps: one object, no points', (
    tester,
  ) async {
    await pumpEditor(tester);
    final construction = container.read(constructionProvider).construction;
    // Two segments meeting at (100, -100) (screen y 100), like an angle
    // drawn earlier: one going right, one going up.
    final v = FreePoint(id: 'v', position: const Vec2(100, -100));
    final a = FreePoint(id: 'a', position: const Vec2(300, -100));
    final b = FreePoint(id: 'b', position: const Vec2(100, -300));
    construction
      ..add(v)
      ..add(a)
      ..add(b)
      ..add(Segment(id: 's1', point1: v, point2: a))
      ..add(Segment(id: 's2', point1: v, point2: b));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angle bisector'));
    await tester.pumpAndSettle();

    // Mid-segment taps, away from every endpoint.
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(200, 100));
    await tester.pump();
    expect(objectCount(), 5, reason: 'the first line fills a slot only');
    await tester.tapAt(origin + const Offset(100, 200));
    await tester.pump();

    expect(objectCount(), 6, reason: 'exactly the bisector — no points');
    final bisector = construction.objects.last;
    expect(objectKindLabel(bisector), 'Angle bisector');
    expect(
      construction.objects.whereType<GeoPoint>().length,
      3,
      reason: 'no glued by-product points on the segments',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 5);
  });

  testWidgets(
    'segment-ratio point via the menu: cancel does nothing, "1/4" builds '
    'the interpolated point',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      // Cancelling the ratio dialog activates nothing.
      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segment-ratio point…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(objectCount(), 0);

      // Fraction input works; two taps commit one undo unit.
      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segment-ratio point…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1/4');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(
        objectCount(),
        0,
        reason: 'first endpoint is only collected, not committed',
      );
      await tester.tapAt(origin + const Offset(300, 100));
      await tester.pump();
      expect(objectCount(), 3, reason: '2 free points + the ratio point');

      // World is y-up with the origin at the canvas top-left, so the taps
      // sit at (100, -100) and (300, -100); t = 1/4 lands at (150, -100).
      final ratioPoint = container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<SegmentRatioPoint>()
          .single;
      expect(ratioPoint.ratio, 0.25);
      expect(ratioPoint.position, const Vec2(150, -100));

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(objectCount(), 0);
    },
  );

  testWidgets(
    'three-point circle via the circles menu: three taps, one undo unit, '
    'and the circles icon (not the lines one) is highlighted',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Circle through three points'));
      await tester.pumpAndSettle();

      // Both menus activate a ThreePointTool; the highlight must follow
      // the builder, so only the circles icon lights up.
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      // The active tint arrives through the ambient IconTheme (see
      // `_ToolGroup`), so read the effective colour, not the property.
      Color? iconColor(IconData icon) {
        final finder = find.byIcon(icon);
        return tester.widget<Icon>(finder).color ??
            IconTheme.of(tester.element(finder)).color;
      }

      expect(iconColor(Icons.circle_outlined), theme.colorScheme.primary);
      expect(iconColor(Icons.timeline), isNot(theme.colorScheme.primary));

      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      await tester.tapAt(origin + const Offset(300, 100));
      await tester.pump();
      expect(objectCount(), 0, reason: 'no commit until the third point');
      await tester.tapAt(origin + const Offset(100, 300));
      await tester.pump();
      expect(objectCount(), 4, reason: '3 free points + the circle');

      // Right angle at the first tap, so the circumcircle is centered on
      // the hypotenuse midpoint (world is y-up: taps sit at y < 0).
      final circle = container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<ThreePointCircle>()
          .single;
      expect(circle.circle!.center.closeTo(const Vec2(200, -200)), isTrue);

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(objectCount(), 0);
    },
  );

  testWidgets('compass via the circles menu: radius from the first two taps, '
      'centered on the third', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compass'));
    await tester.pumpAndSettle();

    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(150, 100));
    await tester.pump();
    expect(objectCount(), 0, reason: 'no commit until the center lands');
    await tester.tapAt(origin + const Offset(300, 300));
    await tester.pump();
    expect(objectCount(), 4, reason: '3 free points + the circle');

    final circle = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<CompassCircle>()
        .single;
    expect(circle.circle!.center.closeTo(const Vec2(300, -300)), isTrue);
    expect(circle.circle!.radius, closeTo(50, 1e-9));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);
  });

  testWidgets('ray via the two-point menu: two taps, one undo unit', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ray'));
    await tester.pumpAndSettle();

    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 200));
    await tester.pump();
    expect(objectCount(), 3, reason: '2 free points + the ray');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);
  });

  testWidgets('arc via the circles menu: three taps, one undo unit', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arc'));
    await tester.pumpAndSettle();

    await tester.tapAt(origin + const Offset(100, 100)); // start
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 180)); // via
    await tester.pump();
    expect(objectCount(), 0, reason: 'no commit until the end point');
    await tester.tapAt(origin + const Offset(300, 100)); // end
    await tester.pump();
    expect(objectCount(), 4, reason: '3 free points + the arc');

    final arc = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<Arc>()
        .single;
    expect(arc.isDefined, isTrue);
    expect(arc.circle!.center.closeTo(const Vec2(200, -77.5)), isTrue);
    expect(
      arc.containsAngle(arc.circle!.angleAt(const Vec2(200, -180))),
      isTrue,
      reason: 'the drawn branch passes the via point',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);
  });

  testWidgets('sector via the circles menu: center, rim (radius + start), '
      'then the angle point', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sector'));
    await tester.pumpAndSettle();

    await tester.tapAt(origin + const Offset(200, 200)); // center
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 200)); // rim
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 100)); // angle point
    await tester.pump();
    expect(objectCount(), 4, reason: '3 free points + the sector');

    final sector = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<Sector>()
        .single;
    expect(sector.circle!.center.closeTo(const Vec2(200, -200)), isTrue);
    expect(sector.circle!.radius, closeTo(100, 1e-9));
    expect(sector.startAngle, closeTo(0, 1e-9));
    expect(
      sector.sweep,
      closeTo(math.pi / 2, 1e-9),
      reason:
          'the third tap is straight up from the center (world '
          'is y-up), a quarter turn CCW from the rim',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);
  });

  testWidgets('vertex angle via the angles menu: three taps, one undo unit, '
      'and the angles icon is highlighted', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.square_foot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angle'));
    await tester.pumpAndSettle();

    // The merged AngleTool — the angles icon must light up, not the
    // lines or circles ones.
    final theme = Theme.of(tester.element(find.byType(AppBar)));
    Color? iconColor(IconData icon) {
      final finder = find.byIcon(icon);
      return tester.widget<Icon>(finder).color ??
          IconTheme.of(tester.element(finder)).color;
    }

    expect(iconColor(Icons.square_foot), theme.colorScheme.primary);
    expect(iconColor(Icons.circle_outlined), isNot(theme.colorScheme.primary));
    expect(iconColor(Icons.timeline), isNot(theme.colorScheme.primary));

    await tester.tapAt(origin + const Offset(300, 100)); // arm
    await tester.pump();
    await tester.tapAt(origin + const Offset(100, 100)); // vertex
    await tester.pump();
    await tester.tapAt(origin + const Offset(100, 10)); // arm
    await tester.pump();
    expect(objectCount(), 4, reason: '3 free points + the angle');

    final angle = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<VertexAngle>()
        .single;
    expect(angle.angle!.vertex.closeTo(const Vec2(100, -100)), isTrue);
    expect(
      angle.angle!.measure,
      closeTo(math.pi / 2, 1e-9),
      reason: 'CCW from the +x arm to the +y arm (world is y-up)',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 0);
  });

  testWidgets('line angle via the angles menu: tap two existing lines, '
      'marks the acute angle at their crossing', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    Future<void> makeLine(Offset from, Offset to) async {
      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Line'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + from);
      await tester.pump();
      await tester.tapAt(origin + to);
      await tester.pump();
    }

    await makeLine(const Offset(100, 100), const Offset(300, 100));
    await makeLine(const Offset(100, 100), const Offset(100, 300));
    expect(
      objectCount(),
      5,
      reason: 'the second line reuses the shared corner point',
    );

    await tester.tap(find.byIcon(Icons.square_foot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angle'));
    await tester.pumpAndSettle();

    await tester.tapAt(origin + const Offset(200, 100)); // horizontal line
    await tester.pump();
    expect(objectCount(), 5, reason: 'no commit until the second line');
    await tester.tapAt(origin + const Offset(100, 200)); // vertical line
    await tester.pump();
    expect(objectCount(), 6);

    final angle = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<LineAngle>()
        .single;
    expect(angle.angle!.vertex.closeTo(const Vec2(100, -100)), isTrue);
    expect(angle.angle!.measure, closeTo(math.pi / 2, 1e-9));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 5, reason: 'only the angle is one undo unit');
  });

  testWidgets(
    'move/select mode: tap selects, shift-tap toggles, empty tap clears',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      // Two points, then back to move/select mode.
      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      await tester.tapAt(origin + const Offset(200, 100));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
      await tester.pump();

      final ids = [
        for (final object
            in container.read(constructionProvider).construction.objects)
          object.id,
      ];
      Set<String> selection() => container.read(selectionProvider);

      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(selection(), {ids[0]});

      // A plain click moves the selection rather than growing it.
      await tester.tapAt(origin + const Offset(200, 100));
      await tester.pump();
      expect(selection(), {ids[1]});

      // Shift-click adds…
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(selection(), {ids[0], ids[1]});

      // …and removes.
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      expect(selection(), {ids[1]});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      // Empty canvas clears (even a shift-click keeps nothing to toggle).
      await tester.tapAt(origin + const Offset(400, 300));
      await tester.pump();
      expect(selection(), isEmpty);
    },
  );

  testWidgets('long-press toggles an object in the selection — the touch '
      'shift-click; empty-canvas long-press keeps the selection', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // Two points, then back to move/select mode.
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 100));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();

    final ids = [
      for (final object
          in container.read(constructionProvider).construction.objects)
        object.id,
    ];
    Set<String> selection() => container.read(selectionProvider);

    Future<void> longPressAt(Offset screen) async {
      final gesture = await tester.startGesture(origin + screen);
      await tester.pump(const Duration(seconds: 1)); // past kLongPressTimeout
      await gesture.up();
      await tester.pump();
    }

    // Tap the first, long-press the second: both selected.
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await longPressAt(const Offset(200, 100));
    expect(selection(), {ids[0], ids[1]});

    // Long-press again removes it (toggle, like shift-click)…
    await longPressAt(const Offset(200, 100));
    expect(selection(), {ids[0]});

    // …and an empty-canvas long-press does NOT clear — that is the plain
    // tap's job; an accidental hold must not drop the selection.
    await longPressAt(const Offset(400, 300));
    expect(selection(), {ids[0]});
  });

  testWidgets('with a tool active a long-press is a slow tap: the tool gets '
      'the input and the selection stays untouched', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // Point tool active: the long-press recognizer must not be in the
    // arena, so a held tap still commits through onTapUp.
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(origin + const Offset(150, 150));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump();

    expect(objectCount(), 1, reason: 'the slow tap still placed the point');
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets('taps while a tool is active never touch the selection', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // A point, selected in move/select mode.
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    final selected = container.read(selectionProvider);
    expect(selected, hasLength(1));

    // Back in the point tool: a tap the tool ignores (the existing
    // point) and one it commits (empty canvas) both leave the
    // selection alone. (`.last`: the open inspector also shows a
    // "Point" kind header, the flyout item is the later one.)
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point').last);
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 200));
    await tester.pump();
    expect(objectCount(), 2);
    expect(container.read(selectionProvider), selected);
  });

  testWidgets('rubber band from empty canvas selects what it encloses; a band '
      'over nothing clears', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 100));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();

    final ids = [
      for (final object
          in container.read(constructionProvider).construction.objects)
        object.id,
    ];
    Set<String> selection() => container.read(selectionProvider);

    // Drag up-left from empty canvas across both points.
    final band = await tester.startGesture(origin + const Offset(350, 250));
    await band.moveTo(origin + const Offset(80, 60));
    await tester.pump();
    await band.up();
    await tester.pump();
    expect(selection(), {ids[0], ids[1]});

    // A band over empty space replaces the selection with nothing.
    final empty = await tester.startGesture(origin + const Offset(400, 300));
    await empty.moveTo(origin + const Offset(500, 400));
    await tester.pump();
    await empty.up();
    await tester.pump();
    expect(selection(), isEmpty);
  });

  testWidgets('under view rotation the band selects what is visually '
      'inside it, not its corners\' world box', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    const state = ViewportState(rotation: math.pi / 4);
    container.read(viewportProvider.notifier).set(state);
    await tester.pump();

    // One point on the band's screen strip, one 80 px below it — the
    // second is outside the band on screen but *inside* the world rect
    // its two drag corners span, which a world-rect test would take.
    const viewport = CanvasViewport(state);
    final construction = container.read(constructionProvider).construction;
    construction
      ..add(
        FreePoint(
          id: 'inside',
          position: viewport.screenToWorld(const Offset(200, 120)),
        ),
      )
      ..add(
        FreePoint(
          id: 'below',
          position: viewport.screenToWorld(const Offset(200, 200)),
        ),
      );
    await tester.pump();

    final band = await tester.startGesture(origin + const Offset(100, 100));
    await band.moveTo(origin + const Offset(300, 140));
    await tester.pump();
    await band.up();
    await tester.pump();

    expect(container.read(selectionProvider), {'inside'});
  });

  testWidgets('shift rubber band adds to the selection instead of replacing', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 100));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();

    final ids = [
      for (final object
          in container.read(constructionProvider).construction.objects)
        object.id,
    ];

    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    expect(container.read(selectionProvider), {ids[0]});

    // Shift-band around only the second point keeps the first selected.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final band = await tester.startGesture(origin + const Offset(390, 160));
    await band.moveTo(origin + const Offset(260, 60));
    await tester.pump();
    await band.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(container.read(selectionProvider), {ids[0], ids[1]});
  });

  testWidgets('drags starting on an object, or with a tool active, do not '
      'rubber band', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();

    // Point tool still active: a drag across the point selects nothing.
    final toolDrag = await tester.startGesture(origin + const Offset(50, 50));
    await toolDrag.moveTo(origin + const Offset(300, 300));
    await tester.pump();
    await toolDrag.up();
    await tester.pump();
    expect(container.read(selectionProvider), isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();

    // Move/select mode, but the drag starts on the point itself: that is
    // a future move-drag, not a band.
    final onObject = await tester.startGesture(origin + const Offset(100, 100));
    await onObject.moveTo(origin + const Offset(300, 300));
    await tester.pump();
    await onObject.up();
    await tester.pump();
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets('dragging a free point moves it; one undo restores it', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();

    FreePoint point() => container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<FreePoint>()
        .single;

    final drag = await tester.startGesture(origin + const Offset(100, 100));
    await drag.moveTo(origin + const Offset(250, 180));
    await tester.pump();
    expect(
      point().position,
      const Vec2(250, -180),
      reason: 'the preview tracks the pointer frame by frame',
    );
    await drag.up();
    await tester.pump();
    expect(point().position, const Vec2(250, -180));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      point().position,
      const Vec2(100, -100),
      reason: 'the whole gesture is one undo unit',
    );
  });

  testWidgets(
    'dragging a segment rigidly translates its endpoints, one undo unit',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segment'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      await tester.tapAt(origin + const Offset(300, 100));
      await tester.pump();
      container.read(toolProvider.notifier).deactivate(); // move/select mode
      await tester.pump();

      List<Vec2> endpoints() => [
        for (final object
            in container
                .read(constructionProvider)
                .construction
                .objects
                .whereType<FreePoint>())
          object.position,
      ];

      // Grab the segment between its endpoints and drag.
      final drag = await tester.startGesture(origin + const Offset(200, 100));
      await drag.moveTo(origin + const Offset(220, 160));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(endpoints(), [
        const Vec2(120, -160),
        const Vec2(320, -160),
      ], reason: 'both defining points shift by the drag delta');

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(endpoints(), [const Vec2(100, -100), const Vec2(300, -100)]);
    },
  );

  testWidgets('a derived point refuses to drag', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Midpoint or center'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 100));
    await tester.pump();
    container.read(toolProvider.notifier).deactivate(); // move/select mode
    await tester.pump();

    // The midpoint sits at (200, 100) on screen; dragging it does nothing
    // (and must not open a rubber band underneath it either).
    final drag = await tester.startGesture(origin + const Offset(200, 100));
    await drag.moveTo(origin + const Offset(300, 250));
    await tester.pump();
    await drag.up();
    await tester.pump();

    final midpoint = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<Midpoint>()
        .single;
    expect(midpoint.position, const Vec2(200, -100));
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets(
    'dragging a point-on-object slides it along its curve, one undo unit',
    (tester) async {
      await pumpEditor(tester);
      final origin = tester.getTopLeft(find.byType(GeometryCanvas));

      // A horizontal segment, then a point constrained onto it.
      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segment'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(100, 100));
      await tester.pump();
      await tester.tapAt(origin + const Offset(300, 100));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.control_point));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Point'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(200, 100));
      await tester.pump();
      container.read(toolProvider.notifier).deactivate(); // move/select mode
      await tester.pump();

      PointOnObject point() => container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<PointOnObject>()
          .single;
      expect(point().position, const Vec2(200, -100));

      // Drag well past the pan slop (~36 px), pulling away from the segment:
      // the point must slide along it, not leave it (and not translate the
      // segment's endpoints).
      final drag = await tester.startGesture(origin + const Offset(200, 100));
      await drag.moveTo(origin + const Offset(260, 220));
      await tester.pump();
      expect(
        point().position,
        const Vec2(260, -100),
        reason: 'the preview projects the pointer onto the carrier',
      );
      await drag.up();
      await tester.pump();
      expect(point().position, const Vec2(260, -100));

      final endpoints = container
          .read(constructionProvider)
          .construction
          .objects
          .whereType<FreePoint>()
          .map((p) => p.position)
          .toList();
      expect(endpoints, [
        const Vec2(100, -100),
        const Vec2(300, -100),
      ], reason: 'sliding the constrained point never moves the curve');

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(
        point().position,
        const Vec2(200, -100),
        reason: 'the whole slide is one undo unit',
      );
    },
  );

  testWidgets('dragging a compass circle moves only its center — the radius '
      'points stay put', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compass'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100)); // radius point 1
    await tester.pump();
    await tester.tapAt(origin + const Offset(150, 100)); // radius point 2
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 200)); // center
    await tester.pump();
    container.read(toolProvider.notifier).deactivate(); // move/select mode
    await tester.pump();

    List<Vec2> freePositions() => [
      for (final object
          in container
              .read(constructionProvider)
              .construction
              .objects
              .whereType<FreePoint>())
        object.position,
    ];

    // Grab the rim (radius 50, right of the center) and drag.
    final drag = await tester.startGesture(origin + const Offset(350, 200));
    await drag.moveTo(origin + const Offset(380, 260));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(freePositions(), [
      const Vec2(100, -100),
      const Vec2(150, -100),
      const Vec2(330, -260),
    ], reason: 'only the center translates; the radius pair is a measurement');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(freePositions(), [
      const Vec2(100, -100),
      const Vec2(150, -100),
      const Vec2(300, -200),
    ], reason: 'the whole drag is one undo unit');
  });

  testWidgets('dragging a circumcircle vertex recomputes the circle, and undo '
      'restores it', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Circle through three points'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 250));
    await tester.pump();
    container.read(toolProvider.notifier).deactivate(); // move/select mode
    await tester.pump();

    ThreePointCircle circle() => container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<ThreePointCircle>()
        .single;
    final centerBefore = circle().circle!.center;

    // Drag the apex vertex; the circumcircle must track it live and land
    // equidistant from all three vertices after the gesture.
    final drag = await tester.startGesture(origin + const Offset(200, 250));
    await drag.moveTo(origin + const Offset(200, 320));
    await tester.pump();
    expect(
      circle().circle!.center,
      isNot(centerBefore),
      reason: 'the preview recomputes dependents frame by frame',
    );
    await drag.up();
    await tester.pump();

    final moved = circle().circle!;
    for (final vertex in const [
      Vec2(100, -100),
      Vec2(300, -100),
      Vec2(200, -320),
    ]) {
      expect(
        moved.center.distanceTo(vertex),
        closeTo(moved.radius, defaultEpsilon),
      );
    }

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(
      circle().circle!.center.closeTo(centerBefore),
      isTrue,
      reason: 'undoing the drag restores the dependent too',
    );
  });

  testWidgets('double-clicking the active group icon deactivates the tool and '
      'stops point placement', (tester) async {
    await pumpEditor(tester);
    final toolButton = find.byIcon(Icons.control_point);

    await tester.tap(toolButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    await tester.tapAt(origin + const Offset(50, 50));
    await tester.pump();
    expect(objectCount(), 1);

    // Double-click the highlighted group icon: the tool deactivates and
    // the flyout must not open.
    await tester.tap(toolButton);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(toolButton);
    await tester.pumpAndSettle();
    expect(find.text('Point'), findsNothing, reason: 'no menu opened');

    await tester.tapAt(origin + const Offset(150, 50));
    await tester.pump();
    expect(objectCount(), 1, reason: 'move/select mode places nothing');
  });

  testWidgets('plain scroll pans the canvas — content moves against the '
      'delta, scale untouched', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final cursor = origin + const Offset(240, 180);
    final before = CanvasViewport(container.read(viewportProvider));
    final fixedWorld = before.screenToWorld(cursor - origin);
    final screenBefore = before.worldToScreen(fixedWorld);

    // Wheel down + right: the camera moves with the delta, so content
    // scrolls up and left like a document.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    await tester.sendEventToBinding(pointer.scroll(const Offset(40, 100)));
    await tester.pump();

    final after = CanvasViewport(container.read(viewportProvider));
    expect(after.state.scale, 1, reason: 'plain scroll never zooms');
    final screenAfter = after.worldToScreen(fixedWorld);
    expect(screenAfter.dx - screenBefore.dx, closeTo(-40, 1e-9));
    expect(screenAfter.dy - screenBefore.dy, closeTo(-100, 1e-9));

    // Scrolling back restores the exact original pan.
    await tester.sendEventToBinding(pointer.scroll(const Offset(-40, -100)));
    await tester.pump();
    expect(container.read(viewportProvider).pan, before.state.pan);
  });

  testWidgets('Ctrl + scroll zooms about the cursor', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final cursor = origin + const Offset(240, 180);
    final before = CanvasViewport(container.read(viewportProvider));
    final fixedWorld = before.screenToWorld(cursor - origin);

    // Scroll up (negative dy) with Ctrl held = zoom in.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();

    final after = CanvasViewport(container.read(viewportProvider));
    expect(
      after.state.scale,
      closeTo(math.exp(100 * GeometryCanvas.scrollZoomPerPixel), 1e-9),
    );
    final focalAfter = after.worldToScreen(fixedWorld);
    expect(
      focalAfter.dx,
      closeTo(cursor.dx - origin.dx, 1e-6),
      reason: 'the world point under the cursor must not move',
    );
    expect(
      focalAfter.dy,
      closeTo(cursor.dy - origin.dy, 1e-6),
      reason: 'the world point under the cursor must not move',
    );

    // Scrolling back down by the same amount restores 100 % exactly
    // (exponential mapping is symmetric).
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(container.read(viewportProvider).scale, closeTo(1, 1e-9));
  });

  testWidgets('a PointerScaleEvent (browser trackpad pinch) zooms about '
      'the cursor', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final cursor = origin + const Offset(240, 180);
    final before = CanvasViewport(container.read(viewportProvider));
    final fixedWorld = before.screenToWorld(cursor - origin);

    await tester.sendEventToBinding(
      PointerScaleEvent(position: cursor, scale: 1.25),
    );
    await tester.pump();

    final after = CanvasViewport(container.read(viewportProvider));
    expect(after.state.scale, closeTo(1.25, 1e-9));
    final focalAfter = after.worldToScreen(fixedWorld);
    expect(
      focalAfter.dx,
      closeTo(cursor.dx - origin.dx, 1e-6),
      reason: 'the world point under the cursor must not move',
    );
    expect(
      focalAfter.dy,
      closeTo(cursor.dy - origin.dy, 1e-6),
      reason: 'the world point under the cursor must not move',
    );
  });

  testWidgets('scroll pan works with a tool active and adds nothing', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();

    final cursor = tester.getCenter(find.byType(GeometryCanvas));
    final panBefore = container.read(viewportProvider).pan;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
    await tester.pump();

    expect(container.read(viewportProvider).pan, isNot(panBefore));
    expect(container.read(viewportProvider).scale, 1);
    expect(objectCount(), 0);
  });

  testWidgets('Alt+scroll rotates about the cursor without zooming; a '
      'deliberate angle survives the quiet period', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final cursor = origin + const Offset(240, 180);
    final fixedWorld = const CanvasViewport(ViewportState())
        .screenToWorld(cursor - origin);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    final after = CanvasViewport(container.read(viewportProvider));
    expect(
      after.state.rotation,
      closeTo(0.6, 1e-9),
      reason: 'scroll-up must turn counterclockwise at 0.003 rad/px',
    );
    expect(after.state.scale, 1, reason: 'Alt+scroll never zooms');
    final focalAfter = after.worldToScreen(fixedWorld);
    expect(
      focalAfter.dx,
      closeTo(cursor.dx - origin.dx, 1e-6),
      reason: 'the world point under the cursor must not move',
    );
    expect(
      focalAfter.dy,
      closeTo(cursor.dy - origin.dy, 1e-6),
      reason: 'the world point under the cursor must not move',
    );

    // Quiet period passes: 0.6 rad is a deliberate angle, no snap.
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(viewportProvider).rotation, closeTo(0.6, 1e-9));
    expect(objectCount(), 0);
  });

  testWidgets('a nearly-level Alt+scroll snaps straight after the wheel '
      'quiet period', (tester) async {
    await pumpEditor(tester);
    final cursor = tester.getCenter(find.byType(GeometryCanvas));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    // 10 px → 0.03 rad ≈ 1.7°, inside the 2° snap.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -10)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(
      container.read(viewportProvider).rotation,
      closeTo(0.03, 1e-9),
      reason: 'the angle applies immediately, snap comes later',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(viewportProvider).rotation,
      0,
      reason: 'close enough to straight is straight',
    );
  });

  testWidgets('a trackpad pan-zoom twist rotates the view (native '
      'desktop path)', (tester) async {
    await pumpEditor(tester);
    final center = tester.getCenter(find.byType(GeometryCanvas));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center);
    await tester.pump();
    // Cumulative rotation samples like macOS reports them: clockwise-
    // positive on screen, so a negative stream turns the view CCW.
    for (var step = 1; step <= 5; step++) {
      await gesture.panZoomUpdate(center, rotation: -0.1 * step);
      await tester.pump();
    }
    await gesture.panZoomEnd();
    await tester.pump();

    final state = container.read(viewportProvider);
    expect(
      state.rotation,
      greaterThan(0.2),
      reason: 'pan-zoom rotation must reach the twist gate',
    );
    expect(state.rotation, lessThanOrEqualTo(0.5));
    expect(state.scale, closeTo(1, 1e-9));
    expect(container.read(selectionProvider), isEmpty);
    expect(objectCount(), 0);
  });

  testWidgets('the compass chip floats on the canvas top-right while '
      'rotated and levels the view about the canvas center', (tester) async {
    await pumpEditor(tester);
    const compass = ValueKey('compass-button');
    expect(
      find.byKey(compass),
      findsNothing,
      reason: 'a level view shows no compass',
    );

    const rotated = ViewportState(pan: Vec2(3, 4), scale: 2, rotation: 0.5);
    container.read(viewportProvider.notifier).set(rotated);
    await tester.pump();
    expect(find.byKey(compass), findsOneWidget);

    // Phase 60: the chip sits on the canvas (map-app convention), inset
    // from its top-right corner, with a live degrees readout.
    final canvasRect = tester.getRect(find.byType(GeometryCanvas));
    final chipRect = tester.getRect(find.byKey(compass));
    expect(
      chipRect.top,
      canvasRect.top + 12,
      reason: 'the compass floats over the canvas, not the app bar',
    );
    expect(chipRect.right, canvasRect.right - 12);
    expect(chipRect.left, greaterThan(canvasRect.left));
    expect(chipRect.bottom, lessThan(canvasRect.bottom));
    expect(
      find.descendant(of: find.byKey(compass), matching: find.text('29°')),
      findsOneWidget,
      reason: '0.5 rad reads as 29°',
    );

    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final centerLocal = tester.getCenter(find.byType(GeometryCanvas)) - origin;
    final centerWorld = const CanvasViewport(rotated)
        .screenToWorld(centerLocal);

    await tester.tap(find.byKey(compass));
    await tester.pump();

    final leveled = container.read(viewportProvider);
    expect(leveled.rotation, 0);
    expect(leveled.scale, 2, reason: 'leveling never rezooms');
    final centerAfter = CanvasViewport(leveled).worldToScreen(centerWorld);
    expect(
      centerAfter.dx,
      closeTo(centerLocal.dx, 1e-6),
      reason: 'the view pivots about the canvas center',
    );
    expect(
      centerAfter.dy,
      closeTo(centerLocal.dy, 1e-6),
      reason: 'the view pivots about the canvas center',
    );
    expect(
      find.byKey(compass),
      findsNothing,
      reason: 'level again — the compass retires',
    );
  });

  testWidgets('pinch zooms about the fingers, and never rubber-bands', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final focal = tester.getCenter(find.byType(GeometryCanvas));
    final fixedWorld = const CanvasViewport(ViewportState())
        .screenToWorld(focal - origin);

    // Two fingers 80 px apart spreading to 200 px in small alternating
    // steps (real pinches interleave per-finger moves the same way; big
    // single moves would skew the focal point mid-gesture).
    final g1 = await tester.createGesture();
    await g1.down(focal - const Offset(40, 0));
    final g2 = await tester.createGesture();
    await g2.down(focal + const Offset(40, 0));
    await tester.pump();
    for (var step = 0; step < 10; step++) {
      await g1.moveBy(const Offset(-6, 0));
      await g2.moveBy(const Offset(6, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    final after = CanvasViewport(container.read(viewportProvider));
    // Exact factor depends on where the recognizer's slop ran out, but a
    // 80→200 px spread must land solidly past 2× and pin the focal point
    // to within the slop the baseline swallowed.
    expect(after.state.scale, greaterThan(1.5));
    expect(after.state.scale, lessThan(3.0));
    final focalWorldOnScreen = after.worldToScreen(fixedWorld);
    expect(
      (focalWorldOnScreen - (focal - origin)).distance,
      lessThan(10),
      reason: 'the world point between the fingers must stay put',
    );
    expect(
      container.read(selectionProvider),
      isEmpty,
      reason: 'a pinch must not open a rubber band',
    );
    expect(objectCount(), 0);
  });

  testWidgets('two-finger twist rotates the view counterclockwise, '
      'pinning the focal point', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final center = tester.getCenter(find.byType(GeometryCanvas));
    final fixedWorld = const CanvasViewport(ViewportState())
        .screenToWorld(center - origin);

    // Fingers 100 px above/below the center walking a quarter circle
    // counterclockwise on screen (decreasing screen angle φ — screen y
    // is down, so increasing φ would be visually clockwise).
    Offset finger(double phi) =>
        center + Offset(100 * math.cos(phi), 100 * math.sin(phi));
    final g1 = await tester.createGesture();
    await g1.down(finger(-math.pi / 2));
    final g2 = await tester.createGesture();
    await g2.down(finger(math.pi / 2));
    await tester.pump();
    const steps = 12;
    for (var step = 1; step <= steps; step++) {
      final delta = -(math.pi / 2) * step / steps;
      await g1.moveTo(finger(-math.pi / 2 + delta));
      await g2.moveTo(finger(math.pi / 2 + delta));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    final after = CanvasViewport(container.read(viewportProvider));
    // A quarter turn minus what arming rebaselined away (~0.1 rad plus
    // recognizer slop): solidly positive (counterclockwise), short of π/2.
    expect(after.state.rotation, greaterThan(1.0));
    expect(after.state.rotation, lessThanOrEqualTo(math.pi / 2 + 0.01));
    expect(
      after.state.scale,
      closeTo(1, 0.01),
      reason: 'fingers kept their span — a twist must not zoom',
    );
    final focalAfter = after.worldToScreen(fixedWorld);
    expect(
      (focalAfter - (center - origin)).distance,
      lessThan(10),
      reason: 'the world point between the fingers must stay put',
    );
    expect(
      container.read(selectionProvider),
      isEmpty,
      reason: 'a twist must not open a rubber band',
    );
    expect(objectCount(), 0);
  });

  testWidgets('a small twist never arms — plain pinches cannot drift '
      'the angle', (tester) async {
    await pumpEditor(tester);
    final center = tester.getCenter(find.byType(GeometryCanvas));

    // ~4.6° total (0.08 rad), below the 0.1 rad arming threshold, walked
    // in steps like a wobbly pinch would.
    Offset finger(double phi) =>
        center + Offset(100 * math.cos(phi), 100 * math.sin(phi));
    final g1 = await tester.createGesture();
    await g1.down(finger(-math.pi / 2));
    final g2 = await tester.createGesture();
    await g2.down(finger(math.pi / 2));
    await tester.pump();
    for (var step = 1; step <= 4; step++) {
      final delta = -0.08 * step / 4;
      await g1.moveTo(finger(-math.pi / 2 + delta));
      await g2.moveTo(finger(math.pi / 2 + delta));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    expect(
      container.read(viewportProvider).rotation,
      0,
      reason: 'an unarmed twist must leave the view exactly level',
    );
  });

  testWidgets('mouse pointers never twist — rotation is touch-only', (
    tester,
  ) async {
    await pumpEditor(tester);
    final center = tester.getCenter(find.byType(GeometryCanvas));

    Offset finger(double phi) =>
        center + Offset(100 * math.cos(phi), 100 * math.sin(phi));
    final g1 = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g1.down(finger(-math.pi / 2));
    final g2 = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g2.down(finger(math.pi / 2));
    await tester.pump();
    const steps = 12;
    for (var step = 1; step <= steps; step++) {
      final delta = -(math.pi / 2) * step / steps;
      await g1.moveTo(finger(-math.pi / 2 + delta));
      await g2.moveTo(finger(math.pi / 2 + delta));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    expect(container.read(viewportProvider).rotation, 0);
  });

  testWidgets('two-finger drag pans without zooming or banding', (
    tester,
  ) async {
    await pumpEditor(tester);
    final center = tester.getCenter(find.byType(GeometryCanvas));
    final before = container.read(viewportProvider);

    // Fingers separated *perpendicular* to the drag: sequential
    // per-finger moves then barely disturb the span (√(200²+10²) ≈ 200),
    // so no incidental zoom sneaks into the baseline.
    final g1 = await tester.createGesture();
    await g1.down(center - const Offset(0, 100));
    final g2 = await tester.createGesture();
    await g2.down(center + const Offset(0, 100));
    await tester.pump();
    for (var step = 0; step < 8; step++) {
      await g1.moveBy(const Offset(10, 0));
      await g2.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    final after = container.read(viewportProvider);
    // Content follows the fingers rightward: the world point at the
    // canvas origin moves left. The pan-slop the recognizer swallows
    // before accepting keeps the exact distance from being 80/scale.
    expect(after.pan.x, lessThan(before.pan.x - 30));
    expect(after.pan.y, closeTo(before.pan.y, 1));
    expect(after.scale, closeTo(1, 0.01));
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets('space-drag pans exactly, even over an object', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(150, 150));
    await tester.pump();
    container.read(toolProvider.notifier).deactivate();
    await tester.pump();
    final point = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<FreePoint>()
        .single;
    final positionBefore = point.position;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final gesture = await tester.startGesture(origin + const Offset(150, 150));
    // First move wins the arena and baselines the pan; the second is the
    // measured, exact displacement.
    await gesture.moveTo(origin + const Offset(180, 160));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(240, 130));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    final after = container.read(viewportProvider);
    // (+60, -30) screen at scale 1: world-at-origin shifts (-60, -30)
    // (screen y-down, world y-up).
    expect(after.pan.x, closeTo(-60, 1e-6));
    expect(after.pan.y, closeTo(-30, 1e-6));
    expect(after.scale, 1);
    expect(
      point.position,
      positionBefore,
      reason: 'space-drag pans the viewport, never the grabbed object',
    );
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets('fit frames the construction keeping the view angle; reset '
      'restores the default view', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 200));
    await tester.pump();

    // Wander off *rotated*, so fit demonstrably recovers the
    // construction — and (Phase 61) demonstrably keeps the angle.
    container
        .read(viewportProvider.notifier)
        .set(
          const ViewportState(pan: Vec2(5000, 5000), scale: 7, rotation: 0.9),
        );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fit_screen));
    await tester.pump();
    final canvasSize = tester.getSize(find.byType(GeometryCanvas));
    final fitted = CanvasViewport(container.read(viewportProvider));
    expect(
      fitted.state.rotation,
      0.9,
      reason: 'fit frames, the compass levels — the angle is kept',
    );
    final points = container
        .read(constructionProvider)
        .construction
        .objects
        .whereType<FreePoint>()
        .toList();
    final onScreen = points
        .map((p) => fitted.worldToScreen(p.position))
        .toList();
    for (final screen in onScreen) {
      expect(screen.dx, inInclusiveRange(0, canvasSize.width));
      expect(screen.dy, inInclusiveRange(0, canvasSize.height));
    }
    final midpointOnScreen = (onScreen[0] + onScreen[1]) / 2;
    expect(midpointOnScreen.dx, closeTo(canvasSize.width / 2, 1e-6));
    expect(midpointOnScreen.dy, closeTo(canvasSize.height / 2, 1e-6));

    await tester.tap(find.byIcon(Icons.filter_center_focus));
    await tester.pump();
    expect(container.read(viewportProvider), const ViewportState());
  });

  testWidgets('a second finger mid-band cancels the band instead of '
      'committing it', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(200, 200));
    await tester.pump();
    container.read(toolProvider.notifier).deactivate();
    await tester.pump();

    // Band from empty canvas grows to enclose the point…
    final g1 = await tester.startGesture(origin + const Offset(100, 100));
    await g1.moveTo(origin + const Offset(300, 300));
    await tester.pump();
    // …then a second finger lands: the gesture pivots to navigation and
    // the half-built band must evaporate, not select.
    final g2 = await tester.createGesture();
    await g2.down(origin + const Offset(320, 100));
    await tester.pump();
    await g1.moveBy(const Offset(15, 0));
    await g2.moveBy(const Offset(15, 0));
    await tester.pump();
    await g1.up();
    await g2.up();
    await tester.pump();

    expect(container.read(selectionProvider), isEmpty);
  });

  // ── Label dragging (Phase 17) ────────────────────────────────────

  /// A named free point whose label (default offset (6, −18), 12 px
  /// text) sits around local (106…, 82…) for a point at (100, 100).
  FreePoint addNamedPoint() {
    final point = FreePoint(
      id: 'a',
      position: const Vec2(100, -100),
      attributes: const ObjectAttributes(name: 'A'),
    );
    container.read(constructionProvider).construction.add(point);
    return point;
  }

  testWidgets('dragging a label stores its offset — one undo unit', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final point = addNamedPoint();
    await tester.pump();

    // Grab inside the label's text rect, well clear of the point's own
    // 8 px hit radius; the move must beat the recognizer's pan slop.
    final drag = await tester.startGesture(origin + const Offset(110, 88));
    await drag.moveTo(origin + const Offset(140, 118));
    await tester.pump();
    expect(
      point.attributes.labelDx,
      6,
      reason: 'the preview must not mutate the construction per frame',
    );
    await drag.up();
    await tester.pump();

    expect(point.attributes.labelDx, 36);
    expect(point.attributes.labelDy, 12);
    expect(
      point.position,
      const Vec2(100, -100),
      reason: 'a label drag never moves the object',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(point.attributes.labelDx, 6);
    expect(point.attributes.labelDy, -18);
  });

  testWidgets('a measurement text dragged off its anchor stays tappable '
      '(Phase 38)', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: const Vec2(100, -100));
    final b = FreePoint(id: 'b', position: const Vec2(200, -100));
    // Text offset near the 40 px clamp: the anchor at local (150, 100)
    // is well outside any hit threshold of the tap below.
    final distance = DistanceMeasurement(
      id: 'd',
      point1: a,
      point2: b,
      attributes: const ObjectAttributes(labelDx: 0, labelDy: -38),
    );
    construction
      ..add(a)
      ..add(b)
      ..add(distance);
    await tester.pump();

    // Inside the text rect (top-left local (150, 62), 12 px line).
    await tester.tapAt(origin + const Offset(160, 68));
    await tester.pump();
    expect(container.read(selectionProvider), {
      'd',
    }, reason: 'the text is the measurement\'s body');

    // An empty tap still clears — the text rect is not sticky.
    await tester.tapAt(origin + const Offset(400, 300));
    await tester.pump();
    expect(container.read(selectionProvider), isEmpty);

    // And a tap at the world anchor selects through the hit tester's
    // measurement tier even with the text far away.
    await tester.tapAt(origin + const Offset(150, 100));
    await tester.pump();
    expect(container.read(selectionProvider), {'d'});

    // Dragging the text rides the generic label drag: one
    // ChangeAttributesCommand, one undo restores the offset. The 40 px
    // move beats the recognizer's pan slop.
    final drag = await tester.startGesture(origin + const Offset(160, 68));
    await drag.moveTo(origin + const Offset(160, 108));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(
      distance.attributes.labelDy,
      2,
      reason: '-38 start offset + 40 px drag down',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(distance.attributes.labelDy, -38);
  });

  testWidgets('a label drag clamps to the max offset radius', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final point = addNamedPoint();
    await tester.pump();

    final drag = await tester.startGesture(origin + const Offset(110, 88));
    await drag.moveTo(origin + const Offset(400, 88));
    await tester.pump();
    await drag.up();
    await tester.pump();

    final offset = Offset(point.attributes.labelDx, point.attributes.labelDy);
    expect(
      offset.distance,
      moreOrLessEquals(GeometryCanvas.labelOffsetMaxPx, epsilon: 0.001),
    );
  });

  testWidgets('a cancelled label drag rolls back without a command', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final point = addNamedPoint();
    await tester.pump();

    final drag = await tester.startGesture(origin + const Offset(110, 88));
    await drag.moveTo(origin + const Offset(140, 118));
    await tester.pump();
    await drag.cancel();
    await tester.pump();

    expect(point.attributes.labelDx, 6);
    expect(point.attributes.labelDy, -18);
    final undoIcon = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo),
    );
    expect(
      undoIcon.onPressed,
      isNull,
      reason: 'nothing was committed, so there is nothing to undo',
    );
  });

  testWidgets('labels are not draggable while a tool is active', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final point = addNamedPoint();
    container
        .read(toolProvider.notifier)
        .activate(PointTool(newId: () => 'unused'));
    await tester.pump();

    final drag = await tester.startGesture(origin + const Offset(110, 88));
    await drag.moveTo(origin + const Offset(140, 118));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(point.attributes.labelDx, 6);
    expect(point.attributes.labelDy, -18);
  });

  // ── Show-value labels (Phase 35) ─────────────────────────────────

  /// A horizontal 100-unit segment with `showValue` on, between free
  /// points at world (100, −100) and (200, −100); its value label
  /// ('100.00', anchored at the midpoint) sits around local (156…, 82…).
  Segment addMeasuredSegment() {
    final construction = container.read(constructionProvider).construction;
    final a = FreePoint(id: 'a', position: const Vec2(100, -100));
    final b = FreePoint(id: 'b', position: const Vec2(200, -100));
    final segment = Segment(
      id: 's',
      point1: a,
      point2: b,
      attributes: const ObjectAttributes(showValue: true),
    );
    construction
      ..add(a)
      ..add(b)
      ..add(segment);
    return segment;
  }

  testWidgets('dragging an endpoint live-updates the painted value', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final segment = addMeasuredSegment();
    await tester.pump();
    expect(labelText(segment), '100.00');

    final drag = await tester.startGesture(origin + const Offset(200, 100));
    await drag.moveTo(origin + const Offset(250, 100));
    await tester.pump();
    expect(
      labelText(segment),
      '150.00',
      reason: 'the value follows the drag preview frame by frame',
    );
    await drag.up();
    await tester.pump();
    expect(labelText(segment), '150.00');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(labelText(segment), '100.00');
  });

  testWidgets('a value-only label is draggable like a name label', (
    tester,
  ) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final segment = addMeasuredSegment();
    await tester.pump();

    // Grab inside the value text's rect — 12 px above the segment
    // itself, outside its 8 px hit threshold, so only the label rect
    // can claim this pan.
    final drag = await tester.startGesture(origin + const Offset(170, 88));
    await drag.moveTo(origin + const Offset(200, 118));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(segment.attributes.labelDx, 36);
    expect(segment.attributes.labelDy, 12);
    expect(
      segment.start,
      const Vec2(100, -100),
      reason: 'a label drag never moves the object',
    );
  });

  testWidgets('tapping a conic with the point tool glues a point to it '
      '(Phase 132)', (tester) async {
    // On the code before Phase 132 this threw `ArgumentError: Cannot
    // project onto an undefined curve`: the hit tester has reported
    // general conics since Phase 119, `resolvePoint` glue-probes every
    // hit curve, and `PointOnObject.near` had no branch for a conic with
    // no `CircleEq`. So the crash was reachable with two tools and six
    // taps, and nothing in the suite went near it.
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byType(ConicIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conic through five points'));
    await tester.pumpAndSettle();
    const taps = [
      Offset(120, 200),
      Offset(220, 120),
      Offset(340, 160),
      Offset(300, 280),
      Offset(160, 300),
    ];
    for (final tap in taps) {
      await tester.tapAt(origin + tap);
      await tester.pump();
    }
    expect(objectCount(), 6);

    await tester.tap(find.byIcon(Icons.control_point));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Point'));
    await tester.pumpAndSettle();
    // A tap on the conic's ink, between two of the defining points.
    await tester.tapAt(origin + const Offset(170, 145));
    await tester.pump();

    expect(objectCount(), 7);
    final construction = container.read(constructionProvider).construction;
    final glued = construction.objects.whereType<PointOnObject>().single;
    expect(glued.curve, isA<FivePointConic>());
    expect(glued.isDefined, isTrue);
    final conic = (glued.curve as FivePointConic).conic!;
    expect(
      conic.evaluate(glued.projPoint!).abs,
      lessThan(1e-6),
      reason: 'the glued point sits on the conic, not merely near it',
    );
  });

  testWidgets('the rhombus macro builds and drags in a hyperbolic '
      'document (Phase 138)', (tester) async {
    // The session-level counterpart of the engine tests: `availableUnder`
    // is checked in `collectVertex`, the figure is built by the *command*
    // path, and the third tap is position-only — none of which an engine
    // test exercises. Every one of these taps was refused before this
    // phase.
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    container
        .read(commandStackProvider.notifier)
        .execute(
          SetGeometryCommand(
            // A disc wide enough to hold the canvas: the radius is a
            // chart scale (Phase 131), and an empty document has no
            // figure to fit one to.
            const DocumentKernel(
              metric: FundamentalConic.hyperbolic,
              radius: 1000,
            ),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.crop_square));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rhombus'));
    await tester.pumpAndSettle();

    for (final tap in const [
      Offset(200, 260),
      Offset(300, 260),
      Offset(300, 160),
    ]) {
      await tester.tapAt(origin + tap);
      await tester.pump();
    }

    final construction = container.read(constructionProvider).construction;
    final absolute = construction.kernel.absolute;
    final corners = [
      for (final o in construction.objects)
        if (o is GeoPoint && o.attributes.visible) o,
    ];
    expect(corners, hasLength(4), reason: 'A, B, C and D all committed');
    expect(corners.last, isA<ReflectedPoint>());

    double side(GeoPoint p, GeoPoint q) =>
        distanceBetween(absolute, p.projPoint!, q.projPoint!)!;
    void expectEquilateral(String when) {
      final target = side(corners[0], corners[1]);
      for (final pair in [
        (corners[1], corners[2]),
        (corners[2], corners[3]),
        (corners[3], corners[0]),
      ]) {
        expect(side(pair.$1, pair.$2), closeTo(target, 1e-9), reason: when);
      }
    }

    expectEquilateral('as stamped');

    // A glued corner on a CK compass circle can actually be dragged, and
    // the gesture is one undo unit. The *continuity* of D across the flat
    // configuration is not what this pins — a screen-length drag does not
    // reach it, and the equilateral check could not see it if it did
    // (D ≡ B is equilateral too). That is the engine test's 600-sample
    // sweep, in `rhombus_macro_tool_test.dart`.
    //
    // C is the tap *projected* onto its compass circle, so the grab goes
    // where the point actually is rather than where the tap was.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deactivate
    await tester.pump();
    final viewport = CanvasViewport(container.read(viewportProvider));
    final before = corners[2].position!;
    final drag = await tester.startGesture(
      origin + viewport.worldToScreen(before),
    );
    for (final step in const [
      Offset(240, 150),
      Offset(190, 210),
      Offset(200, 300),
      Offset(280, 350),
    ]) {
      await drag.moveTo(origin + step);
      await tester.pump();
      expectEquilateral('mid-drag at $step');
    }
    await drag.up();
    await tester.pumpAndSettle();

    expectEquilateral('after the drag');
    expect(corners[2].position, isNot(before), reason: 'C actually moved');

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(
      corners[2].position,
      before,
      reason: 'the whole gesture is one undo unit',
    );
    expectEquilateral('after the undo');
  });

  testWidgets('the conic tool: five taps build one conic through them, '
      'in one undo unit (Phase 120)', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byType(ConicIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conic through five points'));
    await tester.pumpAndSettle();

    // Five screen points on an ellipse, tapped in no particular order —
    // five points determine the same conic however they arrive.
    const taps = [
      Offset(120, 200),
      Offset(220, 120),
      Offset(340, 160),
      Offset(300, 280),
      Offset(160, 300),
    ];
    for (final tap in taps) {
      await tester.tapAt(origin + tap);
      await tester.pump();
    }

    expect(objectCount(), 6, reason: 'five free points and the conic');
    final construction = container.read(constructionProvider).construction;
    final conic = construction.objects.last as FivePointConic;
    expect(conic.isDefined, isTrue);
    final shape = ConicShape.of(conic.conic!);
    for (final point in conic.points) {
      expect(shape.distanceTo(point.position!), lessThan(1e-9));
    }

    container.read(commandStackProvider.notifier).undo();
    expect(objectCount(), 0, reason: 'the whole step is one undo unit');
  });

  testWidgets('the Conics group: a parabola from a focus and a directrix '
      '(Phase 120b)', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // A vertical directrix, then the parabola tool over it and a focus.
    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(120, 80));
    await tester.pump();
    await tester.tapAt(origin + const Offset(120, 320));
    await tester.pump();
    expect(objectCount(), 3);

    await tester.tap(find.byType(ConicIcon));
    await tester.pumpAndSettle();
    // `ToolMenuRow` puts the parenthesized explanation on its own
    // dimmed line, so the tappable text is the bare name.
    await tester.tap(find.text('Parabola'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(260, 200));
    await tester.pump();
    await tester.tapAt(origin + const Offset(120, 200));
    await tester.pump();

    expect(objectCount(), 5, reason: 'the focus and the parabola');
    final construction = container.read(constructionProvider).construction;
    final parabola = construction.objects.last as FocalConic;
    expect(parabola.eccentricity, 1);
    expect(parabola.isDefined, isTrue);
    expect(ConicShape.of(parabola.conic!).kind, ConicClass.parabola);

    container.read(commandStackProvider.notifier).undo();
    expect(objectCount(), 3, reason: 'the whole step is one undo unit');
  });

  testWidgets('the Conics group: an ellipse from two foci and a point '
      '(Phase 120b)', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    await tester.tap(find.byType(ConicIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ellipse'));
    await tester.pumpAndSettle();
    for (final tap in const [
      Offset(160, 200),
      Offset(280, 200),
      Offset(340, 260),
    ]) {
      await tester.tapAt(origin + tap);
      await tester.pump();
    }

    expect(objectCount(), 4);
    final construction = container.read(constructionProvider).construction;
    final ellipse = construction.objects.last as BifocalConic;
    expect(ellipse.difference, isFalse);
    expect(ConicShape.of(ellipse.conic!).kind, ConicClass.ellipse);
    // It passes through the third tap, and not through the foci.
    final shape = ConicShape.of(ellipse.conic!);
    expect(shape.distanceTo(ellipse.point.position!), lessThan(1e-9));
    expect(shape.distanceTo(ellipse.focus1.position!), greaterThan(1e-6));
  });

  testWidgets('G L then tap a circle, then a line: the whole circle '
      'reflects as one undo unit', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));

    // A circle with center (150, 150) and rim (200, 150) — radius 50.
    await tester.tap(find.byIcon(Icons.circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(150, 150));
    await tester.pump();
    await tester.tapAt(origin + const Offset(200, 150));
    await tester.pump();

    // A horizontal mirror line 100 px below the circle's center.
    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(100, 250));
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 250));
    await tester.pump();
    expect(objectCount(), 6);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();

    // Transformee first: the circle's leftmost rim point, clear of its
    // defining points; then the mirror.
    await tester.tapAt(origin + const Offset(100, 150));
    await tester.pump();
    expect(objectCount(), 6, reason: 'nothing commits until the mirror lands');
    await tester.tapAt(origin + const Offset(250, 250));
    await tester.pump();

    expect(objectCount(), 9, reason: '2 image points + the image circle');
    final objects = container
        .read(constructionProvider)
        .construction
        .objects
        .toList();
    final source = objects[2] as CircleCenterPoint;
    final image = objects.last as CircleCenterPoint;
    expect(image.center, isA<ReflectedPoint>());
    expect(image.circle!.radius, closeTo(source.circle!.radius, 1e-9));
    expect(
      image.circle!.center.closeTo(
        source.circle!.center + const Vec2(0, -200),
        1e-9,
      ),
      isTrue,
      reason: 'mirrored across the line 100 px below the center',
    );

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(objectCount(), 6, reason: 'the image is one undo unit');
  });

  testWidgets('pointer-kind hit threshold: a tap 12 px from a point '
      'selects on touch but misses with a mouse', (tester) async {
    await pumpEditor(tester);
    final origin = tester.getTopLeft(find.byType(GeometryCanvas));
    final world = CanvasViewport(container.read(viewportProvider))
        .screenToWorld(const Offset(200, 200));
    container
        .read(constructionProvider)
        .construction
        .add(FreePoint(id: 'a', position: world));
    await tester.pump();

    final nearby = origin + const Offset(212, 200);
    await tester.tapAt(nearby, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(
      container.read(selectionProvider),
      isEmpty,
      reason: '12 px is outside the 8-px mouse radius',
    );

    await tester.tapAt(nearby, kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(container.read(selectionProvider), {
      'a',
    }, reason: '12 px is inside the 16-px touch radius');
  });

  group('DeleteTool taps (Phase 41)', () {
    late Offset origin;

    /// A segment over two free points; the endpoints sit 200 px apart so
    /// taps can unambiguously reach a point, the segment middle, or
    /// empty canvas.
    Future<void> pumpSegmentScene(WidgetTester tester) async {
      await pumpEditor(tester);
      origin = tester.getTopLeft(find.byType(GeometryCanvas));
      final construction = container.read(constructionProvider).construction;
      final a = FreePoint(id: 'a', position: const Vec2(100, -200));
      final b = FreePoint(id: 'b', position: const Vec2(300, -200));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b));
      container.read(toolProvider.notifier).activate(const DeleteTool());
      await tester.pump();
    }

    bool has(String id) =>
        container.read(constructionProvider).construction.contains(id);

    testWidgets('a self-contained object deletes instantly — no dialog, '
        'one undo restores', (tester) async {
      await pumpSegmentScene(tester);

      // Mid-segment, 100 px from either endpoint — only the segment
      // claims it, and nothing depends on a segment.
      await tester.tapAt(origin + const Offset(200, 200));
      await tester.pumpAndSettle();

      expect(find.text('Delete dependent objects too?'), findsNothing);
      expect(has('s'), isFalse);
      expect(has('a'), isTrue);
      expect(has('b'), isTrue);

      container.read(commandStackProvider.notifier).undo();
      expect(has('s'), isTrue);
      expect(
        container.read(commandStackProvider).canUndo,
        isFalse,
        reason: 'one tap = one undo step',
      );
    });

    testWidgets('a cascading tap asks first; Cancel leaves everything and '
        'an empty undo stack', (tester) async {
      await pumpSegmentScene(tester);

      await tester.tapAt(origin + const Offset(100, 200));
      await tester.pumpAndSettle();
      expect(find.text('Delete dependent objects too?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(has('a'), isTrue);
      expect(has('s'), isTrue);
      expect(container.read(commandStackProvider).canUndo, isFalse);
      expect(
        container.read(toolProvider).tool,
        isA<DeleteTool>(),
        reason: 'a cancelled dialog keeps delete mode active',
      );
    });

    testWidgets('confirming a cascading tap removes hit and dependents in '
        'one undo step', (tester) async {
      await pumpSegmentScene(tester);

      await tester.tapAt(origin + const Offset(100, 200));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pumpAndSettle();

      expect(has('a'), isFalse);
      expect(has('s'), isFalse);
      expect(has('b'), isTrue);

      container.read(commandStackProvider.notifier).undo();
      expect(has('a'), isTrue);
      expect(has('s'), isTrue);
      expect(
        container.read(commandStackProvider).canUndo,
        isFalse,
        reason: 'the cascade rode one command',
      );
    });

    testWidgets('an empty tap deletes nothing and never retargets the '
        'selection', (tester) async {
      await pumpSegmentScene(tester);
      container.read(selectionProvider.notifier).select('b');

      await tester.tapAt(origin + const Offset(500, 400));
      await tester.pumpAndSettle();

      expect(objectCount(), 3);
      expect(container.read(selectionProvider), {
        'b',
      }, reason: 'the active tool owns the tap; no selection clear');
      expect(container.read(commandStackProvider).canUndo, isFalse);
    });
  });
}
