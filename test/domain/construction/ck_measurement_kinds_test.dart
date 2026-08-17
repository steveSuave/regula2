import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/length_measurement.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/slope_measurement.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

/// Phase 124: the measurement kinds under a substituted absolute.
///
/// The only place the wiring is exercised — the codec still refuses to
/// open a non-Euclidean document, so nothing here is reachable from the
/// app yet. What it pins is that the kinds *read* the absolute they are
/// handed, that Euclidean is untouched, and that the kinds which cannot
/// generalize go undefined rather than reporting a Euclidean number.
void main() {
  FreePoint p(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  group('Euclidean is untouched', () {
    test('distance, angle and slope read exactly what they always did', () {
      final a = p('a', 0, 0);
      final b = p('b', 3, 4);
      final c = p('c', 0, 5);
      final xArm = p('x', 5, 0);
      final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
      // The wedge from the +x arm to the +y arm — a right angle. (Using
      // b = (3,4) here would mark acos(4/5), not π/2.)
      final angle = VertexAngle(id: 'v', arm1: xArm, vertex: a, arm2: c);

      distance.recompute(Absolute.euclidean);
      angle.recompute(Absolute.euclidean);

      // Exactly 5 and exactly a right angle — the chart's answers, not
      // approximations of them.
      expect(distance.value, 5);
      expect(angle.measure, math.pi / 2);
    });

    test('a line angle of 90° is exactly 90°', () {
      final o = p('o', 0, 0);
      final x = p('x', 1, 0);
      final y = p('y', 0, 1);
      final l1 = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: o, point2: y);
      final angle = LineAngle(id: 'la', line1: l1, line2: l2);
      angle.recompute(Absolute.euclidean);
      expect(angle.measure, math.pi / 2);
    });
  });

  group('a proper absolute changes the number, not the drawing', () {
    test('distance becomes the hyperbolic one', () {
      // Two points on the x-axis inside the Beltrami–Klein disc. The
      // Euclidean answer is 0.5; the hyperbolic one is artanh(0.5).
      final a = p('a', 0, 0);
      final b = p('b', 0.5, 0);
      final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);

      distance.recompute(Absolute.euclidean);
      expect(distance.value, closeTo(0.5, 1e-15));

      distance.recompute(Absolute.hyperbolic);
      expect(
        distance.value,
        closeTo(0.5 * math.log(1.5 / 0.5), 1e-12),
        reason: 'artanh(0.5)',
      );

      // The anchor is where the label goes — chart, in both geometries.
      expect(distance.anchor, Vec2(0.25, 0));
    });

    test('the angle marker stays chart while the measure goes CK', () {
      final v = p('v', 0.1, 0.1);
      final a = p('a', 0.6, 0.15);
      final b = p('b', 0.15, 0.7);
      final angle = VertexAngle(id: 'ang', arm1: a, vertex: v, arm2: b);

      angle.recompute(Absolute.euclidean);
      final euclidean = angle.measure!;
      final marker = angle.angle!;

      angle.recompute(Absolute.hyperbolic);
      // The marker is unchanged — it is drawn between the same two chords
      // at the same screen vertex.
      expect(angle.angle!.vertex, marker.vertex);
      expect(angle.angle!.sweep, marker.sweep);
      // The measure is not.
      expect(angle.measure, isNot(closeTo(euclidean, 1e-6)));
      expect(angle.measure, inInclusiveRange(0, math.pi / 2));
    });

    test('a right angle is right in every geometry it is right in', () {
      // Perpendicularity is conjugacy w.r.t. the absolute, so two lines
      // that are hyperbolically perpendicular measure exactly π/2 there —
      // and the axes through the disc centre are perpendicular in both.
      final o = p('o', 0, 0);
      final x = p('x', 0.5, 0);
      final y = p('y', 0, 0.5);
      final l1 = LineThroughTwoPoints(id: 'l1', point1: o, point2: x);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: o, point2: y);
      final angle = LineAngle(id: 'la', line1: l1, line2: l2);
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        angle.recompute(absolute);
        expect(angle.measure, math.pi / 2, reason: absolute.metric.name);
      }
    });
  });

  group('the kinds that cannot generalize say so', () {
    test('length, area and slope go undefined, not Euclidean', () {
      final a = p('a', 0, 0);
      final b = p('b', 0.5, 0);
      final c = p('c', 0, 0.5);
      final circle = ThreePointCircle(
        id: 'c1',
        point1: a,
        point2: b,
        point3: c,
      );
      final length = LengthMeasurement(id: 'len', subject: circle);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final slope = SlopeMeasurement(id: 's', subject: line);

      for (final m in [length, slope]) {
        m.recompute(Absolute.euclidean);
        expect(m.value, isNotNull, reason: '${m.id} Euclidean');
        m.recompute(Absolute.hyperbolic);
        expect(m.value, isNull, reason: '${m.id} hyperbolic');
        expect(m.anchor, isNull);
        expect(m.isDefined, isFalse);
      }
    });
  });

  group('the construction hands its own absolute down', () {
    test('every recompute goes through the document kernel', () {
      // Not the default on the signature — the construction's own kernel.
      // With only Euclidean loadable this is what it resolves to, and the
      // point is that the value travelled rather than that it is this one.
      final construction = Construction();
      expect(construction.kernel, const DocumentKernel());
      expect(construction.kernel.absolute, Absolute.euclidean);

      final a = p('a', 0, 0);
      final b = p('b', 3, 4);
      construction.add(a);
      construction.add(b);
      final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
      construction.add(distance);
      expect(distance.value, 5);

      construction.moveFreePoint('b', Vec2(6, 8));
      expect(distance.value, 10);
    });
  });
}
