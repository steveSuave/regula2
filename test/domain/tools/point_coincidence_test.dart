import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/point_coincidence.dart';

void main() {
  var nextId = 0;
  String newId() => 'p${nextId++}';

  setUp(() => nextId = 0);

  /// The private macro-style chain completing a parallelogram over
  /// (p1, p2, p3): the fourth corner p1 + p3 − p2 as an intersection of
  /// two parallels, none of it added to any construction — exactly what
  /// `ParallelogramMacroTool.buildObjects` holds when dedup runs.
  IntersectionPoint fourthCorner(GeoPoint p1, GeoPoint p2, GeoPoint p3) {
    final side1 = Segment(id: newId(), point1: p1, point2: p2);
    final side2 = Segment(id: newId(), point1: p2, point2: p3);
    return IntersectionPoint(
      id: newId(),
      curve1: ParallelLine(id: newId(), through: p3, reference: side1),
      curve2: ParallelLine(id: newId(), through: p1, reference: side2),
      branchIndex: 0,
    );
  }

  /// A quadrilateral of four free points with all four side midpoints,
  /// in a `Construction`.
  ({
    Construction construction,
    List<FreePoint> corners,
    Midpoint mAB,
    Midpoint mBC,
    Midpoint mCD,
    Midpoint mDA,
  })
  varignonQuad() {
    final a = FreePoint(id: newId(), position: const Vec2(0, 0));
    final b = FreePoint(id: newId(), position: const Vec2(6, 1));
    final c = FreePoint(id: newId(), position: const Vec2(7, 5));
    final d = FreePoint(id: newId(), position: const Vec2(1, 4));
    final mAB = Midpoint(id: newId(), point1: a, point2: b);
    final mBC = Midpoint(id: newId(), point1: b, point2: c);
    final mCD = Midpoint(id: newId(), point1: c, point2: d);
    final mDA = Midpoint(id: newId(), point1: d, point2: a);
    final construction = Construction();
    for (final object in [a, b, c, d, mAB, mBC, mCD, mDA]) {
      construction.add(object);
    }
    return (
      construction: construction,
      corners: [a, b, c, d],
      mAB: mAB,
      mBC: mBC,
      mCD: mCD,
      mDA: mDA,
    );
  }

  group('coincidentExistingPoint', () {
    test('finds the fourth midpoint under the Varignon parallelogram', () {
      final quad = varignonQuad();
      // By Varignon the corner completing (mBC, mAB, mDA) is exactly mCD,
      // for every position of the four free corners.
      final candidate = fourthCorner(quad.mBC, quad.mAB, quad.mDA);

      expect(
        coincidentExistingPoint(quad.construction.objects, candidate),
        same(quad.mCD),
      );
    });

    test('rejects a free point parked at the corner by accident', () {
      final a = FreePoint(id: newId(), position: const Vec2(0, 0));
      final b = FreePoint(id: newId(), position: const Vec2(4, 0));
      final c = FreePoint(id: newId(), position: const Vec2(5, 2));
      // The corner completing (a, b, c) is a + c − b = (1, 2); park an
      // unrelated free point exactly there.
      final stray = FreePoint(id: newId(), position: const Vec2(1, 2));
      final construction = Construction();
      for (final object in [a, b, c, stray]) {
        construction.add(object);
      }
      final candidate = fourthCorner(a, b, c);
      expect(candidate.position, const Vec2(1, 2));

      expect(
        coincidentExistingPoint(construction.objects, candidate),
        isNull,
        reason:
            'the stray point has its own degree of freedom — probing '
            'its position separates it from the corner',
      );
    });

    test('rejects a glued point parked at the corner by accident', () {
      final a = FreePoint(id: newId(), position: const Vec2(0, 0));
      final b = FreePoint(id: newId(), position: const Vec2(4, 0));
      final c = FreePoint(id: newId(), position: const Vec2(5, 2));
      final host = LineThroughTwoPoints(
        id: newId(),
        point1: FreePoint(id: newId(), position: const Vec2(1, -3)),
        point2: FreePoint(id: newId(), position: const Vec2(1, 7)),
      );
      final parked = PointOnObject.near(
        id: newId(),
        curve: host,
        position: const Vec2(1, 2),
      );
      final construction = Construction();
      for (final object in [a, b, c, ...host.parents, host, parked]) {
        construction.add(object);
      }
      expect(parked.position, const Vec2(1, 2));

      expect(
        coincidentExistingPoint(construction.objects, fourthCorner(a, b, c)),
        isNull,
        reason:
            'the glued point rides an independent parameter — probing '
            'it slides it off the corner',
      );
    });

    test('never matches an invisible point', () {
      final quad = varignonQuad();
      quad.construction.setAttributes(
        quad.mCD.id,
        const ObjectAttributes(visible: false),
      );

      expect(
        coincidentExistingPoint(
          quad.construction.objects,
          fourthCorner(quad.mBC, quad.mAB, quad.mDA),
        ),
        isNull,
      );
    });

    test('an undefined candidate matches nothing', () {
      final a = FreePoint(id: newId(), position: const Vec2(0, 0));
      final b = FreePoint(id: newId(), position: const Vec2(2, 0));
      final c = FreePoint(id: newId(), position: const Vec2(4, 0));
      final construction = Construction();
      for (final object in [a, b, c]) {
        construction.add(object);
      }
      final candidate = fourthCorner(a, b, c);
      expect(
        candidate.position,
        isNull,
        reason: 'collinear inputs leave the parallels parallel',
      );

      expect(coincidentExistingPoint(construction.objects, candidate), isNull);
    });

    test('restores every root and recomputes everything bit-exactly', () {
      final quad = varignonQuad();
      // Glue a point exactly onto mCD (side CD passes through it) so it is
      // screened in as a match and probed out — its parameter must be
      // perturbed and then restored.
      final host = LineThroughTwoPoints(
        id: newId(),
        point1: quad.corners[2],
        point2: quad.corners[3],
      );
      final glued = PointOnObject.near(
        id: newId(),
        curve: host,
        position: quad.mCD.position!,
      );
      quad.construction.add(host);
      quad.construction.add(glued);

      final positionsBefore = {
        for (final object in quad.construction.objects)
          if (object is GeoPoint) object.id: object.position,
      };
      final parameterBefore = glued.parameter;

      final candidate = fourthCorner(quad.mBC, quad.mAB, quad.mDA);
      final candidatePositionBefore = candidate.position;
      expect(
        coincidentExistingPoint(quad.construction.objects, candidate),
        same(quad.mCD),
      );

      expect(glued.parameter, parameterBefore);
      expect(candidate.position, candidatePositionBefore);
      for (final object in quad.construction.objects) {
        if (object is GeoPoint) {
          expect(
            object.position,
            positionsBefore[object.id],
            reason: '${object.id} must be restored exactly',
          );
        }
      }
    });

    test('reproduces the reported parallelogram-double-point case', () {
      // parallelogram-double-point.json, verbatim: parallelogram ABCD
      // with D glued to the parallel through C, all four side midpoints,
      // then the macro over (mCB, mBA, mAD) — whose corner is mDC.
      final a = FreePoint(
        id: 'A',
        position: const Vec2(957.2200329233128, -530.4603883821543),
      );
      final b = FreePoint(
        id: 'B',
        position: const Vec2(495.2841349291143, -544.1970927151748),
      );
      final c = FreePoint(
        id: 'C',
        position: const Vec2(569.9285617029774, -324.6115666414743),
      );
      final sideAB = Segment(id: newId(), point1: a, point2: b);
      final parallel = ParallelLine(id: newId(), through: c, reference: sideAB);
      final d = PointOnObject(
        id: 'D',
        curve: parallel,
        parameter: -825.2573979672244,
      );
      final mDC = Midpoint(id: newId(), point1: d, point2: c);
      final mBA = Midpoint(id: newId(), point1: b, point2: a);
      final mCB = Midpoint(id: newId(), point1: c, point2: b);
      final mAD = Midpoint(id: newId(), point1: a, point2: d);
      final construction = Construction();
      for (final object in [a, b, c, sideAB, parallel, d, mDC, mBA, mCB, mAD]) {
        construction.add(object);
      }

      expect(
        coincidentExistingPoint(
          construction.objects,
          fourthCorner(mCB, mBA, mAD),
        ),
        same(mDC),
        reason:
            'D rides a glued parameter shared by both definitions — '
            'the coincidence survives its perturbation too',
      );
    });

    test('two points at the same point at infinity are not merged '
        '(Phase 121)', () {
      // The meet of two parallels is a genuine projective point, and two
      // pairs of parallels in the same direction meet at the *same* one —
      // so a projective-aware dedup would have to call these coincident.
      // This one deliberately does not: it screens on the chart position,
      // an off-chart point has none, and every uncertain outcome here
      // resolves to keeping the new point.
      final a = FreePoint(id: newId(), position: const Vec2(0, 0));
      final b = FreePoint(id: newId(), position: const Vec2(1, 0));
      final c = FreePoint(id: newId(), position: const Vec2(0, 3));
      final d = FreePoint(id: newId(), position: const Vec2(0, 7));
      final base = LineThroughTwoPoints(id: newId(), point1: a, point2: b);
      final par1 = ParallelLine(id: newId(), through: c, reference: base);
      final par2 = ParallelLine(id: newId(), through: d, reference: base);
      final atInfinity = IntersectionPoint(
        id: newId(),
        curve1: base,
        curve2: par1,
        branchIndex: 0,
      );
      final construction = Construction();
      for (final object in [a, b, c, d, base, par1, par2, atInfinity]) {
        construction.add(object);
      }
      expect(atInfinity.projPoint, isNotNull);
      expect(atInfinity.position, isNull, reason: 'off the affine chart');

      final twin = IntersectionPoint(
        id: newId(),
        curve1: base,
        curve2: par2,
        branchIndex: 0,
      );
      expect(twin.projPoint, isNotNull);
      expect(coincidentExistingPoint(construction.objects, twin), isNull);
    });

    test('returns null immediately when nothing is close', () {
      final quad = varignonQuad();
      final far = FreePoint(id: newId(), position: const Vec2(100, 100));
      quad.construction.add(far);

      final candidate = fourthCorner(quad.corners[0], far, quad.corners[1]);
      expect(
        coincidentExistingPoint(quad.construction.objects, candidate),
        isNull,
      );
    });
  });
}
