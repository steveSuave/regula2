import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';

import '../../kitchen_sink.dart';

void main() {
  group('lift-from-affine bridge defaults (Phase 106)', () {
    // The two corpora together contain every concrete GeoObject kind (the
    // codec encoder throws UnsupportedError for a kind missing from them,
    // and the codec round-trip test would fail) — so looping over them is
    // the exhaustive per-kind check the phase calls for.
    test('projective getters agree with the affine views '
        'for every concrete kind', () {
      final construction = buildKitchenSink();
      for (final object in buildPostV1Kinds().objects) {
        construction.add(object);
      }
      var points = 0;
      var lines = 0;
      var circles = 0;
      for (final object in construction.objects) {
        switch (object) {
          case GeoPoint(:final position?):
            points++;
            final projected = object.projPoint?.toVec2();
            expect(projected, isNotNull, reason: 'projPoint of ${object.id}');
            expect(
              projected!.distanceTo(position),
              lessThan(1e-12),
              reason: 'lift∘project of ${object.id}',
            );
          case GeoLine(:final line?):
            lines++;
            final projected = object.projLine?.toLineEq();
            expect(projected, isNotNull, reason: 'projLine of ${object.id}');
            expect(
              projected!.closeTo(line),
              isTrue,
              reason: 'lift∘project of ${object.id}',
            );
          case GeoCircle(:final circle?):
            circles++;
            final projected = object.conic?.toCircleEq();
            expect(projected, isNotNull, reason: 'conic of ${object.id}');
            expect(
              projected!.closeTo(circle),
              isTrue,
              reason: 'lift∘project of ${object.id}',
            );
          default:
            // Angles, polygons, measurements, loci, texts have no
            // projective view; undefined point/line/circle instances are
            // covered by the null-propagation test below.
            break;
        }
      }
      // Guard against the loop going vacuous: the kitchen sink keeps its
      // point/line/circle population defined.
      expect(points, greaterThan(10));
      expect(lines, greaterThan(8));
      expect(circles, greaterThan(6));
    });

    test('every kind keeps the one degeneracy convention when its whole '
        'figure collapses (Phase 121)', () {
      // The convention is "projective value total, projection nullable":
      // a degeneracy gives a *degenerate but real* homogeneous value —
      // the line at infinity, a line pair, a doubled line — and it is
      // only the projection into the chart that goes null. Nothing may
      // give up early and null its projective value while still handing
      // back an affine one, or the reverse.
      //
      // Checking that per kind would need 44 hand-built degeneracies.
      // Collapsing every free point onto one position produces all of
      // them at once: coincident endpoints, collinear triples, zero
      // radii, undefined intersections, arms without an angle. What is
      // asserted is the *implication* — an affine view means a
      // projective value, and the two agree — which is exactly the half
      // of the convention observable from outside.
      final construction = buildKitchenSink();
      for (final object in buildPostV1Kinds().objects) {
        construction.add(object);
      }
      for (final root in construction.objects.whereType<FreePoint>()) {
        construction.moveFreePoint(root.id, const Vec2(3, -2));
      }

      var checked = 0;
      for (final object in construction.objects) {
        switch (object) {
          case GeoPoint(:final position?):
            checked++;
            final projected = object.projPoint?.toVec2();
            expect(projected, isNotNull, reason: 'projPoint of ${object.id}');
            expect(
              projected!.distanceTo(position),
              lessThan(1e-9),
              reason: 'lift∘project of ${object.id}',
            );
          case GeoLine(:final line?):
            checked++;
            final projected = object.projLine?.toLineEq();
            expect(projected, isNotNull, reason: 'projLine of ${object.id}');
            expect(
              projected!.closeTo(line),
              isTrue,
              reason: 'lift∘project of ${object.id}',
            );
          case GeoCircle(:final circle?):
            checked++;
            final projected = object.conic?.toCircleEq();
            expect(projected, isNotNull, reason: 'conic of ${object.id}');
            expect(
              projected!.closeTo(circle),
              isTrue,
              reason: 'lift∘project of ${object.id}',
            );
          default:
            break;
        }
      }
      // Much of the figure is undefined here, which is the point — but a
      // collapse that left *nothing* defined would make the loop vacuous
      // and the test worthless. 29 views survive today: a degeneracy is
      // mostly a *value*, not an absence (a midpoint of coincident points
      // is that point, a zero-radius circle is a circle).
      expect(
        checked,
        greaterThan(20),
        reason: 'the collapsed figure still has defined views to check',
      );
    });

    test('undefined affine views propagate to null projective views', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(1, 2));
      final c = FreePoint(id: 'c', position: const Vec2(5, 2));
      // Coincident endpoints → undefined line.
      final degenerateLine = LineThroughTwoPoints(
        id: 'line',
        point1: a,
        point2: b,
      );
      // Collinear points → undefined circle.
      final farRight = FreePoint(id: 'd', position: const Vec2(9, 2));
      final degenerateCircle = ThreePointCircle(
        id: 'circle',
        point1: a,
        point2: c,
        point3: farRight,
      );
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(farRight)
        ..add(degenerateLine)
        ..add(degenerateCircle);
      // A point derived from an undefined parent is undefined too.
      final degeneratePoint = IntersectionPoint(
        id: 'point',
        curve1: degenerateLine,
        curve2: degenerateCircle,
        branchIndex: 0,
      );
      construction.add(degeneratePoint);

      expect(degenerateLine.line, isNull);
      expect(degenerateLine.projLine, isNull);
      // Migrated circles (Phase 109) keep a projective value through this
      // degeneracy: collinear points yield the degenerate line pair of
      // their line with the line at infinity — [circle] null (undefined
      // for rendering) while [conic] is not.
      expect(degenerateCircle.circle, isNull);
      expect(degenerateCircle.isDefined, isFalse);
      final lineConic = degenerateCircle.conic;
      expect(lineConic, isNotNull);
      expect(
        lineConic!.closeTo(
          ConicMatrix.linePair(
            ProjLine.lift(
              LineEq.throughPoints(const Vec2(1, 2), const Vec2(9, 2)),
            ),
            ProjLine.infinity,
          ),
        ),
        isTrue,
      );
      expect(degeneratePoint.position, isNull);
      expect(degeneratePoint.projPoint, isNull);
    });
  });
}
