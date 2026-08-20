import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/mutable_roots.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

void main() {
  group('MutableRoots.reachedFrom', () {
    test('finds free points through a derived chain', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final m = Midpoint(id: 'm', point1: a, point2: b);

      final roots = MutableRoots.reachedFrom([m]);

      expect(roots.freePoints, {a, b});
      expect(roots.gluedPoints, isEmpty);
    });

    test('a glued point is a root and is traversed through', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final glued = PointOnObject(id: 'p', curve: line, parameter: 1.5);
      final m = Midpoint(id: 'm', point1: a, point2: glued);

      final roots = MutableRoots.reachedFrom([m]);

      expect(roots.gluedPoints, {glued});
      // The traversal continued through the glued point to the line's
      // own free endpoints.
      expect(roots.freePoints, {a, b});
    });
  });

  group('perturb and restore', () {
    test('perturb moves every root; restore is bit-exact', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final b = FreePoint(id: 'b', position: const Vec2(-3, 5));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final glued = PointOnObject(id: 'p', curve: line, parameter: 0.75);
      final objects = <GeoObject>[a, b, line, glued];
      for (final object in objects) {
        object.recompute();
      }
      final basePositions = [a.position, b.position, glued.position];
      final baseParameter = glued.parameter;

      final roots = MutableRoots.reachedFrom([glued]);
      roots.perturb(math.Random(7));
      recomputeCarriers(objects, Absolute.euclidean);

      expect(a.position, isNot(basePositions[0]));
      expect(b.position, isNot(basePositions[1]));
      expect(glued.parameter, isNot(baseParameter));

      roots.restore();
      recomputeCarriers(objects, Absolute.euclidean);

      // Bit-exact: Vec2 == is exact component equality, and the derived
      // glued position recomputes identically from restored roots.
      expect(a.position, basePositions[0]);
      expect(b.position, basePositions[1]);
      expect(glued.parameter, baseParameter);
      expect(glued.position, basePositions[2]);
    });

    test('consecutive perturbs displace from the base, not cumulatively', () {
      final a = FreePoint(id: 'a', position: const Vec2(100, 0));
      final roots = MutableRoots.reachedFrom([a]);
      final rng = math.Random(3);

      final displacements = <double>[];
      for (var i = 0; i < 20; i++) {
        roots.perturb(rng);
        displacements.add(a.position.distanceTo(const Vec2(100, 0)));
      }
      // Every displacement is exactly one probe radius off the base —
      // probeScale relative to the magnitude — never a random walk.
      for (final d in displacements) {
        expect(d, closeTo(probeScale * 100, 1e-9));
      }
    });
  });
}
