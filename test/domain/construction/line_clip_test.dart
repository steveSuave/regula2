import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/line_clip.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/math/vec2.dart';

const clip1 = ObjectAttributes(lineClip: 1);
const clip2 = ObjectAttributes(lineClip: 2);
const hidden2 = ObjectAttributes(visible: false);

FreePoint point(String id, double x, double y, {bool visible = true}) =>
    FreePoint(
      id: id,
      position: Vec2(x, y),
      attributes: visible ? const ObjectAttributes() : hidden2,
    );

/// Order-blind endpoint match: the span's ends carry no orientation.
void expectSpan(({Vec2 start, Vec2 end})? span, Vec2 a, Vec2 b) {
  expect(span, isNotNull);
  final ends = [span!.start, span.end];
  expect(
    ends.any((e) => e.closeTo(a)) && ends.any((e) => e.closeTo(b)),
    isTrue,
    reason: 'expected span {$a, $b}, got {${span.start}, ${span.end}}',
  );
}

void main() {
  group('mode 0 and non-modes', () {
    test('default (0) is always null', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expect(lineClipSpan([a, b, line], line), isNull);
    });

    test('an undefined line is null in every mode', () {
      final a = point('a', 0, 0);
      final b = point('b', 0, 0); // coincident — line undefined
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      expect(line.isDefined, isFalse);
      expect(lineClipSpan([a, b, line], line), isNull);
    });

    test('a segment ignores lineClip entirely', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final seg = Segment(id: 's', point1: a, point2: b, attributes: clip2);
      expect(lineClipSpan([a, b, seg], seg), isNull);
    });
  });

  group('mode 1 — defining points', () {
    test('LineThroughTwoPoints clips to its defining pair', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip1,
      );
      expectSpan(lineClipSpan([a, b, line], line), Vec2(0, 0), Vec2(4, 0));
    });

    test('hidden defining points still clip in mode 1', () {
      final a = point('a', 0, 0, visible: false);
      final b = point('b', 4, 0, visible: false);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip1,
      );
      expectSpan(lineClipSpan([a, b, line], line), Vec2(0, 0), Vec2(4, 0));
    });

    test('mode 1 on a kind without an on-carrier defining pair is null', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 1, 3);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final perp = PerpendicularLine(
        id: 'p',
        through: c,
        reference: line,
        attributes: clip1,
      );
      expect(lineClipSpan([a, b, c, line, perp], perp), isNull);

      final ray = Ray(id: 'r', origin: a, through: b, attributes: clip1);
      expect(lineClipSpan([a, b, ray], ray), isNull);
    });
  });

  group('mode 2 — incident-point span on lines', () {
    test('defining pair alone spans the pair', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      expectSpan(lineClipSpan([a, b, line], line), Vec2(0, 0), Vec2(4, 0));
    });

    test('a glued point beyond the pair extends the span', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      final glued = PointOnObject.near(
        id: 'g',
        curve: line,
        position: Vec2(7, 0),
      );
      expectSpan(
        lineClipSpan([a, b, line, glued], line),
        Vec2(0, 0),
        Vec2(7, 0),
      );
    });

    test('an intersection point parenting the line counts', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      // Circle centered at (10, 0) through (7, 0): crosses the x-axis at
      // (7, 0) and (13, 0), both beyond the defining pair.
      final center = point('c', 10, 0);
      final rim = point('rim', 7, 0);
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final cross = IntersectionPoint(
        id: 'x',
        curve1: line,
        curve2: circle,
        branchIndex: 1,
      );
      expectSpan(
        lineClipSpan([a, b, line, center, rim, circle, cross], line),
        Vec2(0, 0),
        Vec2(13, 0),
      );
    });

    test('a hidden incident point never stretches the clip', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      final glued = PointOnObject.near(
        id: 'g',
        curve: line,
        position: Vec2(7, 0),
      )..attributes = hidden2;
      expectSpan(
        lineClipSpan([a, b, line, glued], line),
        Vec2(0, 0),
        Vec2(4, 0),
      );
    });

    test('hidden defining points drop out of the mode-2 span', () {
      final a = point('a', 0, 0, visible: false);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      final glued = PointOnObject.near(
        id: 'g',
        curve: line,
        position: Vec2(7, 0),
      );
      expectSpan(
        lineClipSpan([a, b, line, glued], line),
        Vec2(4, 0),
        Vec2(7, 0),
      );
    });

    test('fewer than two incident points stays infinite', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 1, 3);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      // A parallel's only on-carrier defining point is `through`.
      final par = ParallelLine(
        id: 'p',
        through: c,
        reference: line,
        attributes: clip2,
      );
      expect(lineClipSpan([a, b, c, line, par], par), isNull);

      // A perpendicular bisector has none at all.
      final pbis = PerpendicularBisectorLine(
        id: 'pb',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      expect(lineClipSpan([a, b, line, pbis], pbis), isNull);
    });

    test('a parallel with a glued point gains a span', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 1, 3);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final par = ParallelLine(
        id: 'p',
        through: c,
        reference: line,
        attributes: clip2,
      );
      final glued = PointOnObject.near(
        id: 'g',
        curve: par,
        position: Vec2(6, 3),
      );
      expectSpan(
        lineClipSpan([a, b, c, line, par, glued], par),
        Vec2(1, 3),
        Vec2(6, 3),
      );
    });

    test('coincident incident points give no span', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final par = ParallelLine(
        id: 'p',
        through: point('c', 1, 3),
        reference: line,
        attributes: clip2,
      );
      // Glued exactly onto the through point: two incident points, zero
      // width — treated as infinite rather than a degenerate dot.
      final glued = PointOnObject.near(
        id: 'g',
        curve: par,
        position: Vec2(1, 3),
      );
      expect(lineClipSpan([a, b, line, par, glued], par), isNull);
    });
  });

  group('mode 2 — derived incidences (Phase 44b)', () {
    // Two crossing lines through freely-placed points, their crossing,
    // and the tapped-wedge bisector — the provoleas shape.
    (List<GeoObject>, TwoLineBisectorLine, IntersectionPoint) bisectorScene({
      bool swapCrossingParents = false,
      bool crossingVisible = true,
    }) {
      final a = point('a', -4, 0);
      final b = point('b', 4, 0);
      final c = point('c', 0, -4);
      final d = point('d', 0, 4);
      final l1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: c, point2: d);
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: swapCrossingParents ? l2 : l1,
        curve2: swapCrossingParents ? l1 : l2,
        branchIndex: 0,
        attributes: crossingVisible ? null : hidden2,
      );
      final bisector = TwoLineBisectorLine(
        id: 'bis',
        line1: l1,
        line2: l2,
        branch: 0,
        attributes: clip2,
      );
      return ([a, b, c, d, l1, l2, crossing, bisector], bisector, crossing);
    }

    test('the crossing of the parent lines counts, either parent order', () {
      for (final swapped in [false, true]) {
        final (objects, bisector, crossing) = bisectorScene(
          swapCrossingParents: swapped,
        );
        final glued = PointOnObject.near(
          id: 'g',
          curve: bisector,
          position: const Vec2(3, 3),
        );
        expectSpan(
          lineClipSpan([...objects, glued], bisector),
          crossing.position!,
          glued.position!,
        );
      }
    });

    test('the crossing alone is one incident point — still infinite', () {
      final (objects, bisector, _) = bisectorScene();
      expect(lineClipSpan(objects, bisector), isNull);
    });

    test('a hidden crossing does not count', () {
      final (objects, bisector, _) = bisectorScene(crossingVisible: false);
      final glued = PointOnObject.near(
        id: 'g',
        curve: bisector,
        position: const Vec2(3, 3),
      );
      expect(lineClipSpan([...objects, glued], bisector), isNull);
    });

    test('a crossing of different lines never counts', () {
      final (objects, bisector, _) = bisectorScene();
      final l1 = objects[4] as LineThroughTwoPoints;
      final e = point('e', -4, 4);
      final f = point('f', 4, -4);
      final other = LineThroughTwoPoints(id: 'l3', point1: e, point2: f);
      // l1 ∩ other = the origin — geometrically ON the bisector — but the
      // parent pair is {l1, other}, not {l1, l2}: coincidence-by-figure
      // is exactly what derived incidence must not count.
      final otherCrossing = IntersectionPoint(
        id: 'x2',
        curve1: l1,
        curve2: other,
        branchIndex: 0,
      );
      final glued = PointOnObject.near(
        id: 'g',
        curve: bisector,
        position: const Vec2(3, 3),
      );
      // Only the glued point is incident; one point → infinite.
      expect(
        lineClipSpan([
          ...objects.where((o) => o.id != 'x'),
          e,
          f,
          other,
          otherCrossing,
          glued,
        ], bisector),
        isNull,
      );
    });

    test('the midpoint of a perpendicular bisector\'s pair counts, either '
        'order', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      for (final swapped in [false, true]) {
        final mid = Midpoint(
          id: 'm',
          point1: swapped ? b : a,
          point2: swapped ? a : b,
        );
        final pbis = PerpendicularBisectorLine(
          id: 'pb',
          point1: a,
          point2: b,
          attributes: clip2,
        );
        final glued = PointOnObject.near(
          id: 'g',
          curve: pbis,
          position: const Vec2(2, 5),
        );
        expectSpan(
          lineClipSpan([a, b, mid, pbis, glued], pbis),
          const Vec2(2, 0),
          const Vec2(2, 5),
        );
      }
    });

    test('a midpoint of different points never counts', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final c = point('c', 0, 4);
      final mid = Midpoint(id: 'm', point1: a, point2: c);
      final pbis = PerpendicularBisectorLine(
        id: 'pb',
        point1: a,
        point2: b,
        attributes: clip2,
      );
      final glued = PointOnObject.near(
        id: 'g',
        curve: pbis,
        position: const Vec2(2, 5),
      );
      expect(lineClipSpan([a, b, c, mid, pbis, glued], pbis), isNull);
    });
  });

  group('mode 2 — ray far-end clamp', () {
    test('clamps the far end at the outermost incident point ahead', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final ray = Ray(id: 'r', origin: a, through: b, attributes: clip2);
      final glued = PointOnObject.near(
        id: 'g',
        curve: ray,
        position: Vec2(9, 0),
      );
      expectSpan(lineClipSpan([a, b, ray, glued], ray), Vec2(0, 0), Vec2(9, 0));
    });

    test('with only the defining points the through point clamps', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final ray = Ray(id: 'r', origin: a, through: b, attributes: clip2);
      expectSpan(lineClipSpan([a, b, ray], ray), Vec2(0, 0), Vec2(4, 0));
    });

    test('incident points behind the origin are ignored', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0);
      final ray = Ray(id: 'r', origin: a, through: b, attributes: clip2);
      // Behind the origin on the carrier (negative side).
      final behind = PointOnObject.near(
        id: 'g',
        curve: ray,
        position: Vec2(-5, 0),
      );
      expectSpan(
        lineClipSpan([a, b, ray, behind], ray),
        Vec2(0, 0),
        Vec2(4, 0),
      );
    });

    test('no visible incident point ahead leaves the ray unclamped', () {
      final a = point('a', 0, 0);
      final b = point('b', 4, 0, visible: false);
      final ray = Ray(id: 'r', origin: a, through: b, attributes: clip2);
      final behind = PointOnObject.near(
        id: 'g',
        curve: ray,
        position: Vec2(-5, 0),
      );
      expect(lineClipSpan([a, b, ray, behind], ray), isNull);

      // The hidden origin does not clamp anything either way: it is the
      // ray's own endpoint, not a clip contributor.
      expect(lineClipSpan([a, b, ray], ray), isNull);
    });
  });
}
