import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/presentation/canvas/canvas_hit_tester.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';

import '../../projective_stubs.dart';

void main() {
  const tester = CanvasHitTester();
  const threshold = 0.5;

  GeoObject? hit(Construction construction, Vec2 point) =>
      tester.hitTest(construction.objects, point, threshold);

  group('CanvasHitTester', () {
    test('returns null on an empty construction or when nothing is near', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      expect(hit(Construction(), Vec2.zero), isNull);
      expect(hit(construction, const Vec2(10, 10)), isNull);
    });

    test('picks the closest point within the threshold', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero))
        ..add(FreePoint(id: 'b', position: const Vec2(0.6, 0)));

      expect(hit(construction, const Vec2(0.4, 0))?.id, 'b');
      expect(hit(construction, const Vec2(0.1, 0))?.id, 'a');
    });

    test('a point in range beats a closer line', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(FreePoint(id: 'p', position: const Vec2(5, 0.4)));

      // Tap sits on the line (distance 0) and 0.4 from the point: the
      // point still wins on priority.
      expect(hit(construction, const Vec2(5, 0))?.id, 'p');
    });

    test('infinite line is hit far beyond its defining points', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b));

      expect(hit(construction, const Vec2(100, 0.3))?.id, 'l');
    });

    test('segment is only hit within its extent', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b));

      expect(hit(construction, const Vec2(0.5, 0.3))?.id, 's');
      expect(
        hit(construction, const Vec2(3, 0.3)),
        isNull,
        reason: 'past the endpoint the carrier line must not count',
      );
    });

    test('ray is hit beyond its through point but not behind its origin', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Ray(id: 'r', origin: a, through: b));

      expect(
        hit(construction, const Vec2(100, 0.3))?.id,
        'r',
        reason: 'a ray extends past its through point',
      );
      expect(
        hit(construction, const Vec2(-3, 0.3)),
        isNull,
        reason: 'behind the origin the carrier line must not count',
      );
    });

    test('arc is only hit on its branch of the carrier', () {
      // The defining points are hidden so they can't win on priority —
      // this test is about the arc's own distance logic.
      const hidden = ObjectAttributes(visible: false);
      final construction = Construction();
      final s = FreePoint(
        id: 's',
        position: const Vec2(1, 0),
        attributes: hidden,
      );
      final v = FreePoint(
        id: 'v',
        position: const Vec2(0, 1),
        attributes: hidden,
      );
      final e = FreePoint(
        id: 'e',
        position: const Vec2(-1, 0),
        attributes: hidden,
      );
      construction
        ..add(s)
        ..add(v)
        ..add(e)
        ..add(Arc(id: 'arc', start: s, via: v, end: e));

      expect(hit(construction, const Vec2(0, 1.3))?.id, 'arc');
      expect(
        hit(construction, const Vec2(0, -1.3)),
        isNull,
        reason: 'the far branch of the carrier must not count',
      );
      expect(
        hit(construction, const Vec2(-1, -0.4))?.id,
        'arc',
        reason: 'just past an endpoint the endpoint distance rules',
      );
      expect(
        hit(construction, const Vec2(-1.2, -1.2)),
        isNull,
        reason: 'far from both the branch and the endpoints',
      );
    });

    test('sector is hit on its outline: arc branch and both radius edges', () {
      // Hidden defining points, as in the arc test: outline logic only.
      const hidden = ObjectAttributes(visible: false);
      final construction = Construction();
      final c = FreePoint(id: 'c', position: Vec2.zero, attributes: hidden);
      final s = FreePoint(
        id: 's',
        position: const Vec2(2, 0),
        attributes: hidden,
      );
      final e = FreePoint(
        id: 'e',
        position: const Vec2(0, 5),
        attributes: hidden,
      );
      construction
        ..add(c)
        ..add(s)
        ..add(e)
        // Quarter wedge of radius 2 in the first quadrant.
        ..add(Sector(id: 'w', center: c, start: s, end: e));

      expect(
        hit(construction, const Vec2(1.7, 1.7))?.id,
        'w',
        reason: 'near the arc branch',
      );
      expect(
        hit(construction, const Vec2(1, 0.3))?.id,
        'w',
        reason: 'near the start radius edge',
      );
      expect(
        hit(construction, const Vec2(0.3, 1))?.id,
        'w',
        reason: 'near the end radius edge — at radius 2, not at end',
      );
      expect(
        hit(construction, const Vec2(0.7, 0.7)),
        isNull,
        reason: 'inside the pie but far from the outline',
      );
      expect(
        hit(construction, const Vec2(1.4, -1.4)),
        isNull,
        reason: 'on the carrier but outside the sweep',
      );
    });

    test('circle is hit near its boundary, not near its center', () {
      final construction = Construction();
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(5, 0));
      construction
        ..add(center)
        ..add(rim)
        ..add(CircleCenterPoint(id: 'k', center: center, onCircle: rim));

      expect(hit(construction, const Vec2(0, 5.2))?.id, 'k');
      expect(
        hit(construction, const Vec2(2, 2)),
        isNull,
        reason: 'inside the disc but far from the boundary',
      );
    });

    test('angle is picked at its vertex, and anything else there wins', () {
      const hidden = ObjectAttributes(visible: false);
      final construction = Construction();
      final a = FreePoint(
        id: 'a',
        position: const Vec2(3, 0),
        attributes: hidden,
      );
      final v = FreePoint(id: 'v', position: Vec2.zero, attributes: hidden);
      final b = FreePoint(
        id: 'b',
        position: const Vec2(0, 3),
        attributes: hidden,
      );
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(VertexAngle(id: 'g', arm1: a, vertex: v, arm2: b));

      expect(hit(construction, const Vec2(0.2, 0.2))?.id, 'g');
      expect(
        hit(construction, const Vec2(1.5, 1.5)),
        isNull,
        reason: 'only the vertex is pickable',
      );

      construction.add(FreePoint(id: 'p', position: Vec2.zero));
      expect(
        hit(construction, const Vec2(0.2, 0.2))?.id,
        'p',
        reason: 'angles have the lowest priority',
      );
    });

    test('with worldPerPx the angle is picked on its marker wedge', () {
      const hidden = ObjectAttributes(visible: false);
      final construction = Construction();
      final a = FreePoint(
        id: 'a',
        position: const Vec2(3, 0),
        attributes: hidden,
      );
      final v = FreePoint(id: 'v', position: Vec2.zero, attributes: hidden);
      final b = FreePoint(
        id: 'b',
        position: const Vec2(0, 3),
        attributes: hidden,
      );
      final angle = VertexAngle(
        id: 'g',
        arm1: a,
        vertex: v,
        arm2: b,
        attributes: const ObjectAttributes(angleMarkerRadius: 20),
      );
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(angle);

      // Marker radius pinned to 20 px at 0.1 world/px = 2 world units.
      GeoObject? wedgeHit(Vec2 p) =>
          tester.hitTest(construction.objects, p, threshold, worldPerPx: 0.1);

      expect(
        wedgeHit(const Vec2(1.4, 1.4))?.id,
        'g',
        reason: 'on the arc mid-sweep (|p| ≈ 1.98 vs radius 2)',
      );
      expect(
        wedgeHit(const Vec2(1, 0))?.id,
        'g',
        reason: 'on a straight wedge edge inside the marker',
      );
      expect(
        wedgeHit(const Vec2(0.2, 0.2))?.id,
        'g',
        reason: 'the vertex stays pickable — the edges start there',
      );
      expect(
        wedgeHit(const Vec2(1.4, -1.4)),
        isNull,
        reason: 'same distance from the vertex but outside the sweep',
      );
      expect(
        wedgeHit(const Vec2(0.9, 0.9)),
        isNull,
        reason: 'the wedge interior is not the outline',
      );

      angle.attributes = angle.attributes.copyWith(angleMarkerRadius: 36);
      expect(
        wedgeHit(const Vec2(2.5, 2.5))?.id,
        'g',
        reason: 'the wedge tracks the per-object marker radius (3.6)',
      );
    });

    test('polygon: empty interior selects it, anything drawn inside wins', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(8, 0));
      final c = FreePoint(id: 'c', position: const Vec2(8, 6));
      final d = FreePoint(id: 'd', position: const Vec2(0, 6));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(d)
        ..add(Polygon(id: 'poly', vertices: [a, b, c, d]))
        ..add(FreePoint(id: 'p', position: const Vec2(4, 3)));

      expect(
        hit(construction, const Vec2(2, 2))?.id,
        'poly',
        reason: 'an empty interior tap selects the region (distance 0)',
      );
      expect(
        hit(construction, const Vec2(4, 3.2))?.id,
        'p',
        reason: 'a point inside the region wins on priority',
      );
      expect(
        hit(construction, Vec2.zero)?.id,
        'a',
        reason: 'the vertex point wins at the vertex',
      );
      expect(
        hit(construction, const Vec2(4, -0.3))?.id,
        'poly',
        reason: 'outside, the nearest edge decides within the threshold',
      );
      expect(
        hit(construction, const Vec2(4, -0.7)),
        isNull,
        reason: 'outside and beyond the threshold',
      );
    });

    test('polygon: a contained angle marker beats the interior', () {
      const hidden = ObjectAttributes(visible: false);
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(8, 0));
      final c = FreePoint(id: 'c', position: const Vec2(8, 6));
      final d = FreePoint(id: 'd', position: const Vec2(0, 6));
      final arm1 = FreePoint(
        id: 'm',
        position: const Vec2(7, 3),
        attributes: hidden,
      );
      final v = FreePoint(
        id: 'v',
        position: const Vec2(4, 3),
        attributes: hidden,
      );
      final arm2 = FreePoint(
        id: 'n',
        position: const Vec2(4, 6),
        attributes: hidden,
      );
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(d)
        ..add(Polygon(id: 'poly', vertices: [a, b, c, d]))
        ..add(arm1)
        ..add(v)
        ..add(arm2)
        ..add(
          VertexAngle(
            id: 'g',
            arm1: arm1,
            vertex: v,
            arm2: arm2,
            attributes: const ObjectAttributes(angleMarkerRadius: 20),
          ),
        );

      // Marker radius pinned to 20 px at 0.1 world/px = 2 world units: the
      // tap sits on the marker arc, inside the polygon, away from points.
      final onWedge = tester.hitTest(
        construction.objects,
        const Vec2(5.4, 4.4),
        threshold,
        worldPerPx: 0.1,
      );
      expect(
        onWedge?.id,
        'g',
        reason: 'the angle marker outranks the interior it sits in',
      );
    });

    test('invisible and undefined objects are never hit', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(
        id: 'b',
        position: Vec2.zero, // coincides with a → line undefined
      );
      final hidden = FreePoint(
        id: 'h',
        position: const Vec2(3, 3),
        attributes: const ObjectAttributes(visible: false),
      );
      construction
        ..add(a)
        ..add(b)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(hidden);

      expect(hit(construction, const Vec2(3, 3)), isNull);
      expect(hit(construction, const Vec2(0.2, 0)), isNot(hasId('l')));
    });

    test('includeHidden hits hidden objects, but never undefined ones', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(
        id: 'b',
        position: Vec2.zero, // coincides with a → line undefined
      );
      construction
        ..add(a)
        ..add(b)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(
          FreePoint(
            id: 'h',
            position: const Vec2(3, 3),
            attributes: const ObjectAttributes(visible: false),
          ),
        );

      GeoObject? hitIncludingHidden(Vec2 point) => tester.hitTest(
        construction.objects,
        point,
        threshold,
        includeHidden: true,
      );
      expect(
        hitIncludingHidden(const Vec2(3, 3))?.id,
        'h',
        reason: 'the Show/Hide tool must reach hidden objects',
      );
      expect(
        hitIncludingHidden(const Vec2(0.2, 0)),
        isNot(hasId('l')),
        reason: 'undefined stays unhittable regardless',
      );
    });

    test('coincident points: the later (topmost) one wins', () {
      final construction = Construction()
        ..add(FreePoint(id: 'under', position: Vec2.zero))
        ..add(FreePoint(id: 'over', position: Vec2.zero));

      expect(hit(construction, const Vec2(0.1, 0))?.id, 'over');
    });
  });

  group('hitTestAll', () {
    List<String> allIds(Construction construction, Vec2 point) => [
      for (final object in tester.hitTestAll(
        construction.objects,
        point,
        threshold,
      ))
        object.id,
    ];

    test('returns every in-threshold object, best first', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      final c = FreePoint(id: 'c', position: const Vec2(5, -10));
      final d = FreePoint(id: 'd', position: const Vec2(5, 10));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(d)
        ..add(LineThroughTwoPoints(id: 'h', point1: a, point2: b))
        ..add(LineThroughTwoPoints(id: 'v', point1: c, point2: d))
        ..add(FreePoint(id: 'p', position: const Vec2(5, 0.4)));

      // Tap near the crossing of h and v: the point wins on priority, the
      // vertical line is closer than the horizontal one.
      expect(allIds(construction, const Vec2(5, 0.2)), ['p', 'v', 'h']);
      expect(allIds(construction, const Vec2(20, 20)), isEmpty);
    });

    test('excludes invisible and undefined objects', () {
      final construction = Construction()
        ..add(
          FreePoint(
            id: 'h',
            position: Vec2.zero,
            attributes: const ObjectAttributes(visible: false),
          ),
        );

      expect(allIds(construction, Vec2.zero), isEmpty);
    });

    test('hitTest is exactly the first hitTestAll entry', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b));

      for (final tap in const [Vec2(5, 0.2), Vec2(0.1, 0), Vec2(20, 20)]) {
        final all = tester.hitTestAll(construction.objects, tap, threshold);
        expect(
          tester.hitTest(construction.objects, tap, threshold),
          all.firstOrNull,
        );
      }
    });

    test('exact ties go to the object added latest (topmost)', () {
      final construction = Construction()
        ..add(FreePoint(id: 'under', position: Vec2.zero))
        ..add(FreePoint(id: 'over', position: Vec2.zero));

      expect(allIds(construction, const Vec2(0.1, 0)), ['over', 'under']);
    });
  });

  group('objectsInRect', () {
    List<String> inRect(Construction construction, Vec2 c1, Vec2 c2) => [
      for (final object in tester.objectsInRect(construction.objects, c1, c2))
        object.id,
    ];

    test('points: wholly-inside rule, corners in either order', () {
      final construction = Construction()
        ..add(FreePoint(id: 'in', position: const Vec2(1, 1)))
        ..add(FreePoint(id: 'out', position: const Vec2(5, 5)));

      expect(inRect(construction, Vec2.zero, const Vec2(2, 2)), ['in']);
      expect(
        inRect(construction, const Vec2(2, 2), Vec2.zero),
        ['in'],
        reason: 'a band dragged up-left spans the same rect',
      );
    });

    test('segment needs both endpoints inside; lines and rays never fit', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(3, 1));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b))
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(Ray(id: 'r', origin: a, through: b));

      expect(
        inRect(construction, Vec2.zero, const Vec2(4, 2)),
        ['a', 'b', 's'],
        reason: 'the infinite carriers escape any finite band',
      );
      expect(
        inRect(construction, Vec2.zero, const Vec2(2, 2)),
        ['a'],
        reason: 'a band crossing the segment does not take it',
      );
    });

    test('circle needs its full disc bounds inside', () {
      final construction = Construction();
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final rim = FreePoint(id: 'p', position: const Vec2(2, 0));
      construction
        ..add(center)
        ..add(rim)
        ..add(CircleCenterPoint(id: 'k', center: center, onCircle: rim));

      expect(
        inRect(construction, const Vec2(-2.1, -2.1), const Vec2(2.1, 2.1)),
        ['c', 'p', 'k'],
      );
      expect(
        inRect(construction, const Vec2(-1, -2.1), const Vec2(2.1, 2.1)),
        ['c', 'p'],
        reason:
            'the disc pokes past x = -1 even though no defining '
            'point does',
      );
    });

    test('arc is measured by its branch, not the carrier circle', () {
      final construction = Construction();
      final start = FreePoint(id: 's', position: const Vec2(4, -3));
      final via = FreePoint(id: 'v', position: const Vec2(5, 0));
      final end = FreePoint(id: 'e', position: const Vec2(4, 3));
      construction
        ..add(start)
        ..add(via)
        ..add(end)
        ..add(Arc(id: 'arc', start: start, via: via, end: end));

      // Carrier is the radius-5 circle about the origin; the branch stays
      // in x ∈ [4, 5], y ∈ [-3, 3].
      expect(
        inRect(construction, const Vec2(3.9, -3.1), const Vec2(5.1, 3.1)),
        ['s', 'v', 'e', 'arc'],
      );
      expect(
        inRect(construction, const Vec2(4.5, -3.1), const Vec2(5.1, 3.1)),
        ['v'],
        reason: 'endpoints out → arc out',
      );
    });

    test('sector counts its center and rim extremes', () {
      final construction = Construction();
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(5, 0));
      final angle = FreePoint(id: 'a', position: const Vec2(0, 2));
      construction
        ..add(center)
        ..add(rim)
        ..add(angle)
        ..add(Sector(id: 'w', center: center, start: rim, end: angle));

      // Quarter wedge: x, y ∈ [0, 5].
      expect(
        inRect(construction, const Vec2(-0.1, -0.1), const Vec2(5.1, 5.1)),
        ['c', 'r', 'a', 'w'],
      );
      expect(
        inRect(construction, const Vec2(0.5, -0.1), const Vec2(5.1, 5.1)),
        ['r'],
        reason: 'center out → wedge out',
      );
    });

    test('an angle is banded by its vertex alone', () {
      final construction = Construction();
      final arm1 = FreePoint(id: 'a1', position: const Vec2(9, 0));
      final vertex = FreePoint(id: 'v', position: Vec2.zero);
      final arm2 = FreePoint(id: 'a2', position: const Vec2(0, 9));
      construction
        ..add(arm1)
        ..add(vertex)
        ..add(arm2)
        ..add(VertexAngle(id: 'g', arm1: arm1, vertex: vertex, arm2: arm2));

      expect(
        inRect(construction, const Vec2(-1, -1), const Vec2(1, 1)),
        ['v', 'g'],
        reason: 'the marker is screen-sized; the arms are not the angle',
      );
    });

    test('polygon needs every vertex inside the band', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(Polygon(id: 'poly', vertices: [a, b, c]));

      List<String> banded(Vec2 corner1, Vec2 corner2) => [
        for (final object in tester.objectsInRect(
          construction.objects,
          corner1,
          corner2,
        ))
          object.id,
      ];

      expect(
        banded(const Vec2(-1, -1), const Vec2(5, 4)),
        contains('poly'),
        reason: 'every vertex inside — the polygon is taken',
      );
      expect(
        banded(const Vec2(-1, -1), const Vec2(5, 2)),
        isNot(contains('poly')),
        reason: 'the apex sticks out — merely crossed, not taken',
      );
    });

    test('invisible and undefined objects are never banded', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // line undefined
      construction
        ..add(a)
        ..add(b)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(
          FreePoint(
            id: 'h',
            position: const Vec2(1, 1),
            attributes: const ObjectAttributes(visible: false),
          ),
        );

      expect(inRect(construction, const Vec2(-2, -2), const Vec2(2, 2)), [
        'a',
        'b',
      ]);
    });
  });

  group('objectsContainedIn under a rotated frame (Phase 43)', () {
    // A screen band at view rotation θ: the same predicate the canvas
    // builds — inclusive containment of worldToScreen in the band rect —
    // with the band frame's +x direction at world angle −θ.
    const rotation = math.pi / 4;
    const viewport = CanvasViewport(ViewportState(rotation: rotation));
    // A thin horizontal screen strip: 100 px long, 20 px tall. In world
    // space that is a 45°-rotated strip through the origin.
    const band = Rect.fromLTRB(0, -10, 100, 10);
    bool within(Vec2 world) {
      final screen = viewport.worldToScreen(world);
      return screen.dx >= band.left &&
          screen.dx <= band.right &&
          screen.dy >= band.top &&
          screen.dy <= band.bottom;
    }

    List<String> banded(Construction construction) => [
      for (final object in tester.objectsContainedIn(
        construction.objects,
        within,
        cardinalAngle: -rotation,
      ))
        object.id,
    ];

    test('a point is judged by the band, not the band corners\' world '
        'bounds', () {
      final construction = Construction()
        ..add(
          FreePoint(
            id: 'in',
            position: viewport.screenToWorld(const Offset(50, 0)),
          ),
        )
        // 40 px off the strip on screen — outside the band, but well
        // inside the axis-aligned world box its corners span, which is
        // what a world-rect test would wrongly use.
        ..add(
          FreePoint(
            id: 'out',
            position: viewport.screenToWorld(const Offset(50, 40)),
          ),
        );

      expect(banded(construction), ['in']);
    });

    test('circle extremes are measured along the band\'s own axes', () {
      Construction circleOfRadius(double radius) {
        final construction = Construction();
        final centerWorld = viewport.screenToWorld(const Offset(50, 0));
        final center = FreePoint(id: 'c', position: centerWorld);
        final rim = FreePoint(id: 'r', position: centerWorld + Vec2(radius, 0));
        return construction
          ..add(center)
          ..add(rim)
          ..add(CircleCenterPoint(id: 'k', center: center, onCircle: rim));
      }

      expect(
        banded(circleOfRadius(9.5)),
        contains('k'),
        reason: 'a 9.5-radius disc fits the 20-px strip',
      );
      // The touching points lie along the band's normal — at *world*
      // cardinals the extremes sit only ~7.4 px off-axis and would
      // wrongly pass.
      expect(
        banded(circleOfRadius(10.5)),
        isNot(contains('k')),
        reason: 'a 10.5-radius disc pokes through both strip edges',
      );
    });
  });

  group('locus hits (Phase 39)', () {
    test('the polyline of consecutive samples is hit, gaps are not', () {
      final locus = _StubLocus(
        id: 'loc',
        samples: const [
          Vec2(0, 0), Vec2(4, 0), null, Vec2(8, 0), Vec2(12, 0), //
        ],
      );
      expect(tester.hitTest([locus], const Vec2(2, 0.3), threshold)?.id, 'loc');
      expect(tester.hitTest([locus], const Vec2(9, 0.3), threshold)?.id, 'loc');
      expect(
        tester.hitTest([locus], const Vec2(6, 0), threshold),
        isNull,
        reason: 'the gap between runs is not a segment',
      );
    });

    test('an isolated sample and an all-gap locus are unreachable', () {
      final isolated = _StubLocus(
        id: 'iso',
        samples: const [null, Vec2(4, 0), null],
      );
      final allGap = _StubLocus(id: 'gap', samples: const [null, null]);
      expect(
        tester.hitTest([isolated], const Vec2(4, 0), threshold),
        isNull,
        reason: 'a lone sample draws no ink to hit',
      );
      expect(tester.hitTest([allGap], Vec2.zero, threshold), isNull);
    });

    test('a point in range beats the locus polyline under it', () {
      final locus = _StubLocus(
        id: 'loc',
        samples: const [Vec2(0, 0), Vec2(10, 0)],
      );
      final point = FreePoint(id: 'p', position: const Vec2(5, 0.4));
      expect(
        tester.hitTest([locus, point], const Vec2(5, 0), threshold)?.id,
        'p',
        reason: 'loci sit at the lines tier, below points',
      );
    });

    test('band-select needs every recorded sample inside, and some ink', () {
      final withGap = _StubLocus(
        id: 'loc',
        samples: const [
          Vec2(1, 1), Vec2(2, 1), null, Vec2(3, 1), //
        ],
      );
      final allGap = _StubLocus(id: 'gap', samples: const [null, null]);
      List<String> banded(Vec2 c1, Vec2 c2) => [
        for (final object in tester.objectsInRect([withGap, allGap], c1, c2))
          object.id,
      ];
      expect(
        banded(Vec2.zero, const Vec2(4, 2)),
        ['loc'],
        reason: 'gaps are fine, an all-gap locus is never banded',
      );
      expect(
        banded(Vec2.zero, const Vec2(2.5, 2)),
        isEmpty,
        reason: 'one sample outside and the locus is merely crossed',
      );
    });
  });

  group('line clipping (Phase 44)', () {
    Construction clippedLine(int lineClip) {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(
          LineThroughTwoPoints(
            id: 'l',
            point1: a,
            point2: b,
            attributes: ObjectAttributes(lineClip: lineClip),
          ),
        );
      return construction;
    }

    test('mode 0 hits far beyond the defining points', () {
      expect(hit(clippedLine(0), const Vec2(50, 0.2))?.id, 'l');
    });

    test('a tap beyond the clipped extent misses', () {
      for (final mode in [1, 2]) {
        final construction = clippedLine(mode);
        expect(
          hit(construction, const Vec2(50, 0.2)),
          isNull,
          reason: 'mode $mode: beyond the span is not drawn',
        );
        expect(
          hit(construction, const Vec2(2, 0.2))?.id,
          'l',
          reason: 'mode $mode: within the span still hits',
        );
        // Just past an endpoint the clamp measures to the endpoint —
        // segment semantics — but the defining point sits there and wins
        // on priority, exactly like tapping a segment's end.
        expect(
          hit(construction, const Vec2(4.3, 0))?.id,
          'b',
          reason: 'mode $mode: the endpoint point wins at the clip edge',
        );
      }
    });

    test('a hidden incident point does not stretch the hit target', () {
      final construction = clippedLine(2);
      final line = construction.objects.last as LineThroughTwoPoints;
      construction.add(
        PointOnObject.near(id: 'g', curve: line, position: const Vec2(8, 0))
          ..attributes = const ObjectAttributes(visible: false),
      );
      expect(hit(construction, const Vec2(7, 0.2)), isNull);
    });

    test('a visible incident point extends the hit target', () {
      final construction = clippedLine(2);
      final line = construction.objects.last as LineThroughTwoPoints;
      construction.add(
        PointOnObject.near(id: 'g', curve: line, position: const Vec2(8, 0)),
      );
      expect(hit(construction, const Vec2(7, 0.2))?.id, 'l');
    });

    test('a clipped ray misses past its far clamp', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(
          Ray(
            id: 'r',
            origin: a,
            through: b,
            attributes: const ObjectAttributes(lineClip: 2),
          ),
        );
      expect(hit(construction, const Vec2(2, 0.2))?.id, 'r');
      expect(
        hit(construction, const Vec2(50, 0.2)),
        isNull,
        reason: 'the far end clamps at the through point',
      );
    });

    test('intersections beyond the clipped extent are still computed', () {
      // The clip is display + hit only: the carrier stays infinite for
      // intersection math, so a crossing outside the drawn span exists.
      final construction = clippedLine(1);
      final line = construction.objects.last as LineThroughTwoPoints;
      final center = FreePoint(id: 'c', position: const Vec2(10, 0));
      final rim = FreePoint(id: 'rim', position: const Vec2(10, 2));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final cross = IntersectionPoint(
        id: 'x',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
      );
      construction
        ..add(center)
        ..add(rim)
        ..add(circle)
        ..add(cross);
      expect(cross.isDefined, isTrue);
      expect(cross.position!.x, closeTo(8, 1e-9));
      // …and the intersection point itself is hit-testable out there.
      expect(hit(construction, const Vec2(8, 0.2))?.id, 'x');
    });
  });

  group('conics (Phase 119)', () {
    // x²/4 + y²/9 = 1 — a genuine ellipse, so `circle` is null and the
    // conic arm decides both distance and containment.
    ConicMatrix ellipse() =>
        ConicMatrix.coefficients(1 / 4, 0, 1 / 9, 0, 0, -1);
    // x² − y² = 1.
    ConicMatrix hyperbola() => ConicMatrix.coefficients(1, 0, -1, 0, 0, -1);

    Construction sceneOf(ConicMatrix conic) =>
        Construction()..add(StubProjectiveConic(conic, id: 'k'));

    test('an ellipse is picked on its rim, not at its centre', () {
      final construction = sceneOf(ellipse());
      expect(hit(construction, const Vec2(2, 0))?.id, 'k');
      expect(hit(construction, const Vec2(0, 3))?.id, 'k');
      expect(hit(construction, const Vec2(2.6, 0)), isNull);
      expect(
        hit(construction, Vec2.zero),
        isNull,
        reason: 'the interior is not the ink — a conic is a curve',
      );
    });

    test('a hyperbola is picked on either arm', () {
      final construction = sceneOf(hyperbola());
      expect(hit(construction, const Vec2(1, 0))?.id, 'k');
      expect(hit(construction, const Vec2(-1, 0))?.id, 'k');
      expect(
        hit(construction, Vec2.zero),
        isNull,
        reason: 'between the branches, one unit from each vertex',
      );
    });

    test('a degenerate conic is picked on its lines', () {
      // y = ±x.
      final construction = sceneOf(ConicMatrix.coefficients(1, 0, -1, 0, 0, 0));
      expect(hit(construction, const Vec2(3, 3))?.id, 'k');
      expect(hit(construction, const Vec2(3, -3))?.id, 'k');
      expect(hit(construction, const Vec2(3, 0)), isNull);
    });

    test('a point on the conic outranks it', () {
      final construction = sceneOf(ellipse())
        ..add(FreePoint(id: 'p', position: const Vec2(2, 0)));
      expect(hit(construction, const Vec2(2, 0))?.id, 'p');
      expect(
        tester
            .hitTestAll(construction.objects, const Vec2(2, 0), threshold)
            .map((o) => o.id),
        ['p', 'k'],
        reason: 'points beat circles, and a conic is picked like a circle',
      );
    });

    test('band selection takes an ellipse only when it fits', () {
      final construction = sceneOf(ellipse());
      expect(
        tester
            .objectsInRect(
              construction.objects,
              const Vec2(-2, -3),
              const Vec2(2, 3),
            )
            .map((o) => o.id),
        ['k'],
        reason: 'the band is exactly the semi-axes box',
      );
      expect(
        tester.objectsInRect(
          construction.objects,
          const Vec2(-1.99, -3),
          const Vec2(2, 3),
        ),
        isEmpty,
      );
    });

    test('an unbounded conic is never band-selected', () {
      final construction = sceneOf(hyperbola());
      expect(
        tester.objectsInRect(
          construction.objects,
          const Vec2(-1e9, -1e9),
          const Vec2(1e9, 1e9),
        ),
        isEmpty,
        reason: 'no band contains a curve that runs to infinity',
      );
    });

    test('a rotated band measures the ellipse along its own axes', () {
      final construction = sceneOf(ellipse());
      // The band frame at 45°: the ellipse's extent along that diagonal is
      // √(a²cos² + b²sin²) = √(2 + 4.5) = √6.5 either way.
      const half = math.sqrt2 / 2;
      final reach = math.sqrt(6.5);
      List<GeoObject> inBand(double slack) =>
          tester.objectsContainedIn(construction.objects, (p) {
            final u = (p.x + p.y) * half;
            final v = (p.y - p.x) * half;
            return u.abs() <= reach + slack && v.abs() <= reach + slack;
          }, cardinalAngle: math.pi / 4);
      expect(inBand(1e-6).map((o) => o.id), ['k']);
      expect(inBand(-1e-3), isEmpty);
    });
  });
}

Matcher hasId(String id) => isA<GeoObject>().having((o) => o.id, 'id', id);

/// A [GeoLocus] with hand-picked samples: the hit tester consumes the
/// kind accessor only, so tests can spell out runs and gaps directly
/// instead of arranging a construction that produces them.
class _StubLocus extends GeoLocus {
  _StubLocus({required super.id, required List<Vec2?>? samples})
    : _samples = samples;

  final List<Vec2?>? _samples;

  @override
  List<Vec2?>? get samples => _samples;

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {}
}
