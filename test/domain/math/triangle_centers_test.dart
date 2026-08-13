import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/triangle_centers.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

/// Numeric properties skip triangles with less than this (doubled) area:
/// the centers of needle-thin triangles are ill-conditioned, and asserting
/// tight tolerances on them tests floating point, not the formulas.
bool isWellConditioned(Vec2 a, Vec2 b, Vec2 c) =>
    (b - a).cross(c - a).abs() >= 1.0;

void main() {
  group('triangle centers on canonical triangles', () {
    // 3-4-5 right triangle with the right angle at the origin.
    const a = Vec2.zero;
    const b = Vec2(4, 0);
    const c = Vec2(0, 3);

    test('centroid of the 3-4-5 triangle', () {
      expect(centroid(a, b, c).closeTo(const Vec2(4 / 3, 1), 1e-12), isTrue);
    });

    test('circumcenter of a right triangle is the hypotenuse midpoint', () {
      expect(circumcenter(a, b, c)!.closeTo(const Vec2(2, 1.5), 1e-12), isTrue);
    });

    test('orthocenter of a right triangle is the right-angle vertex', () {
      expect(orthocenter(a, b, c)!.closeTo(a, 1e-12), isTrue);
    });

    test('incenter of the 3-4-5 triangle is (1, 1)', () {
      expect(incenter(a, b, c)!.closeTo(const Vec2(1, 1), 1e-12), isTrue);
    });

    test('all four centers coincide on an equilateral triangle', () {
      const p = Vec2.zero;
      const q = Vec2(1, 0);
      final r = Vec2(0.5, math.sqrt(3) / 2);
      final g = centroid(p, q, r);
      expect(circumcenter(p, q, r)!.closeTo(g, 1e-12), isTrue);
      expect(orthocenter(p, q, r)!.closeTo(g, 1e-12), isTrue);
      expect(incenter(p, q, r)!.closeTo(g, 1e-12), isTrue);
    });

    test('degenerate triangles yield null (centroid stays defined)', () {
      const p = Vec2(1, 1);
      const q = Vec2(2, 2);
      const r = Vec2(3, 3);
      expect(circumcenter(p, q, r), isNull);
      expect(orthocenter(p, q, r), isNull);
      expect(incenter(p, q, r), isNull);
      expect(centroid(p, q, r), const Vec2(2, 2));
      // Coincident points are degenerate too.
      expect(circumcenter(p, p, p), isNull);
      expect(incenter(p, p, q), isNull);
    });

    test('circumradius of a right triangle is half the hypotenuse', () {
      expect(circumradius(a, b, c), closeTo(2.5, 1e-12));
    });

    test('inradius of the 3-4-5 triangle is (3 + 4 − 5) / 2 = 1', () {
      expect(inradius(a, b, c), closeTo(1, 1e-12));
    });

    test('equilateral radii: R = s/√3 and r = R/2', () {
      const p = Vec2.zero;
      const q = Vec2(1, 0);
      final r = Vec2(0.5, math.sqrt(3) / 2);
      expect(circumradius(p, q, r), closeTo(1 / math.sqrt(3), 1e-12));
      expect(inradius(p, q, r), closeTo(1 / (2 * math.sqrt(3)), 1e-12));
    });

    test('radii of degenerate triangles are null', () {
      const p = Vec2(1, 1);
      const q = Vec2(2, 2);
      expect(circumradius(p, q, const Vec2(3, 3)), isNull);
      expect(inradius(p, q, const Vec2(3, 3)), isNull);
      expect(circumradius(p, p, p), isNull);
      expect(inradius(p, p, q), isNull);
    });
  });

  group('triangle center properties', () {
    Glados3(any.vec2, any.vec2, any.vec2).test(
      'centroid is permutation-invariant and averages the vertices',
      (a, b, c) {
        final g = centroid(a, b, c);
        expect(g.closeTo(centroid(c, a, b), 1e-9), isTrue);
        expect((g * 3).closeTo(a + b + c, 1e-9), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'circumcenter is equidistant from all three vertices',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final o = circumcenter(a, b, c)!;
        final r = o.distanceTo(a);
        final tolerance = 1e-9 * (1 + r);
        expect(o.distanceTo(b), closeTo(r, tolerance));
        expect(o.distanceTo(c), closeTo(r, tolerance));
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'vertex-to-orthocenter is perpendicular to the opposite side',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final h = orthocenter(a, b, c)!;
        void checkAltitude(Vec2 vertex, Vec2 s1, Vec2 s2) {
          final toH = h - vertex;
          final side = s2 - s1;
          final tolerance = 1e-9 * math.max(1.0, toH.norm * side.norm);
          expect(toH.dot(side).abs(), lessThanOrEqualTo(tolerance));
        }

        checkAltitude(a, b, c);
        checkAltitude(b, c, a);
        checkAltitude(c, a, b);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'incenter is equidistant from the three sides and inside',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final i = incenter(a, b, c)!;
        final r1 = LineEq.throughPoints(a, b).distanceTo(i);
        final r2 = LineEq.throughPoints(b, c).distanceTo(i);
        final r3 = LineEq.throughPoints(c, a).distanceTo(i);
        expect(r2, closeTo(r1, 1e-9 * (1 + r1)));
        expect(r3, closeTo(r1, 1e-9 * (1 + r1)));
        // Inside: the incenter sits on the same side of every edge as the
        // triangle's interior (same orientation sign as the triangle itself).
        final orientation = (b - a).cross(c - a).sign;
        expect((b - a).cross(i - a).sign, orientation);
        expect((c - b).cross(i - b).sign, orientation);
        expect((a - c).cross(i - c).sign, orientation);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'Euler line: circumcenter, centroid and orthocenter align',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final o = circumcenter(a, b, c)!;
        final g = centroid(a, b, c);
        final h = orthocenter(a, b, c)!;
        expect(isCollinear(o, g, h, 1e-9), isTrue);
        // The centroid divides O→H in ratio 1:2.
        expect(
          g.closeTo(o.lerp(h, 1 / 3), 1e-6 * (1 + o.distanceTo(h))),
          isTrue,
        );
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'inradius is the distance from the incenter to every side',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final i = incenter(a, b, c)!;
        final r = inradius(a, b, c)!;
        final tolerance = 1e-9 * (1 + r);
        expect(LineEq.throughPoints(a, b).distanceTo(i), closeTo(r, tolerance));
        expect(LineEq.throughPoints(b, c).distanceTo(i), closeTo(r, tolerance));
        expect(LineEq.throughPoints(c, a).distanceTo(i), closeTo(r, tolerance));
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'Euler formula: |OI|² = R(R − 2r)',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final o = circumcenter(a, b, c)!;
        final i = incenter(a, b, c)!;
        final bigR = circumradius(a, b, c)!;
        final r = inradius(a, b, c)!;
        final d2 = o.distanceTo(i) * o.distanceTo(i);
        expect(d2, closeTo(bigR * (bigR - 2 * r), 1e-6 * (1 + bigR * bigR)));
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'nine-point circle passes through the three side midpoints',
      (a, b, c) {
        if (!isWellConditioned(a, b, c)) return;
        final center = circumcenter(a, b, c)!.lerp(orthocenter(a, b, c)!, 0.5);
        final radius = circumradius(a, b, c)! / 2;
        final tolerance = 1e-6 * (1 + radius);
        expect(center.distanceTo(a.lerp(b, 0.5)), closeTo(radius, tolerance));
        expect(center.distanceTo(b.lerp(c, 0.5)), closeTo(radius, tolerance));
        expect(center.distanceTo(c.lerp(a, 0.5)), closeTo(radius, tolerance));
      },
    );

    Glados2(any.vec2, any.vec2).test(
      'degenerate input yields null for all non-centroid centers',
      (a, b) {
        // Force collinearity: c on the segment a→b.
        final c = a.lerp(b, 0.5);
        expect(circumcenter(a, b, c), isNull);
        expect(orthocenter(a, b, c), isNull);
        expect(incenter(a, b, c), isNull);
      },
    );
  });
}
