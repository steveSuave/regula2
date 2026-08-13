import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/intersections.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../math/generators.dart';
import 'generators.dart';

ProjPoint conjPoint(ProjPoint p) => ProjPoint(p.x.conj, p.y.conj, p.w.conj);

extension on Any {
  /// Six classical conic coefficients on a 0.01 grid in [-5, 5].
  Generator<List<int>> get conicCoeffInts =>
      listWithLength(6, intInRange(-500, 501));

  Generator<ConicMatrix> get realConic => conicCoeffInts.map(
    (k) => ConicMatrix.coefficients(
      k[0] / 100,
      k[1] / 100,
      k[2] / 100,
      k[3] / 100,
      k[4] / 100,
      k[5] / 100,
    ),
  );

  /// A circle small and near enough to the origin that five-point conic
  /// fitting stays well conditioned: center on a 0.01 grid in [-10, 10],
  /// radius on a 0.01 grid in [0.5, 5].
  Generator<CircleEq> get smallCircle => combine3(
    intInRange(-1000, 1001),
    intInRange(-1000, 1001),
    intInRange(50, 501),
    (int cx, int cy, int r) => CircleEq(Vec2(cx / 100, cy / 100), r / 100),
  );

  /// An affine point on a 0.001 grid (disambiguates the `vec2` generators
  /// that both imported extensions define).
  Generator<Vec2> get gridVec2 => combine2(component, component, Vec2.new);

  /// Five angles on a 0.001 grid in [0, 2π).
  Generator<List<double>> get fiveAngles => listWithLength(
    5,
    intInRange(0, 6283),
  ).map((l) => [for (final i in l) i / 1000]);
}

/// Whether the [angles] (radians, mod 2π) are pairwise at least [gap] apart.
bool anglesSeparated(List<double> angles, double gap) {
  final sorted = [...angles]..sort();
  for (var i = 0; i < sorted.length; i++) {
    final next = sorted[(i + 1) % sorted.length];
    final delta = i + 1 == sorted.length
        ? sorted.first + 2 * math.pi - sorted.last
        : next - sorted[i];
    if (delta < gap) return false;
  }
  return true;
}

void main() {
  final unitCircle = ConicMatrix.lift(CircleEq(Vec2.zero, 1));

  group('circular points I and J', () {
    test('lie on the line at infinity, are conjugate, and are not real', () {
      expect(ProjLine.infinity.contains(circularPointI), isTrue);
      expect(ProjLine.infinity.contains(circularPointJ), isTrue);
      expect(conjPoint(circularPointI).closeTo(circularPointJ), isTrue);
      expect(circularPointI.isReal(), isFalse);
      expect(circularPointJ.isReal(), isFalse);
      expect(circularPointI.closeTo(circularPointJ), isFalse);
    });

    Glados(any.circleEq).test('every lifted circle passes through I and J', (
      c,
    ) {
      final conic = ConicMatrix.lift(c);
      expect(conic.containsPoint(circularPointI), isTrue);
      expect(conic.containsPoint(circularPointJ), isTrue);
    });

    test('isCircularPoint recognizes I and J at solver-noise tilt', () {
      expect(isCircularPoint(circularPointI), isTrue);
      expect(isCircularPoint(circularPointJ), isTrue);
      expect(isCircularPoint(circularPointI.scaledBy(const Complex(3, -2))),
          isTrue);
      // The doubled I/J of near-concentric circles arrive with ~1e-8 tilt.
      expect(
        isCircularPoint(
          const ProjPoint(Complex.one, Complex(1e-8, 1), Complex(1e-8, 1e-8)),
        ),
        isTrue,
      );
    });

    test('isCircularPoint rejects everything else', () {
      expect(isCircularPoint(ProjPoint.real(1, 1, 1)), isFalse);
      expect(isCircularPoint(ProjPoint.real(1, 1, 0)), isFalse);
      expect(
        isCircularPoint(const ProjPoint(Complex.one, Complex.i, Complex.one)),
        isFalse,
      );
      expect(
        isCircularPoint(
          const ProjPoint(Complex.zero, Complex.zero, Complex.zero),
        ),
        isFalse,
      );
    });

    Glados(any.conicCoeffInts).test(
      'a real conic passes through I and J iff it has circle shape',
      (k) {
        final conic = ConicMatrix.coefficients(
          k[0] / 100,
          k[1] / 100,
          k[2] / 100,
          k[3] / 100,
          k[4] / 100,
          k[5] / 100,
        );
        if (conic.isZero) return;
        // evaluate(I) = (xx − yy) + 2i·xy, so on the coefficient grid the
        // predicate separates cleanly: through I ⇔ a == c and b == 0.
        final isCircleShape = k[0] == k[2] && k[1] == 0;
        expect(conic.containsPoint(circularPointI), isCircleShape);
        expect(conic.containsPoint(circularPointJ), isCircleShape);
      },
    );
  });

  group('lift and toCircleEq', () {
    Glados2(any.circleEq, any.angle).test('lifted circle contains its points', (
      c,
      theta,
    ) {
      final conic = ConicMatrix.lift(c);
      expect(conic.containsPoint(ProjPoint.lift(c.pointAt(theta))), isTrue);
    });

    Glados2(any.circleEq, any.nonZeroComplex).test(
      'toCircleEq round-trips the lift, up to complex scale',
      (c, s) {
        final projected = ConicMatrix.lift(c).scaledBy(s).toCircleEq();
        expect(projected, isNotNull);
        final tol = 1e-6 * (1 + c.center.norm + c.radius);
        expect(projected!.center.closeTo(c.center, tol), isTrue);
        expect((projected.radius - c.radius).abs(), lessThan(tol));
      },
    );

    test('non-circles project to null', () {
      // Tilted conic (xy term), ellipse, imaginary circle, line pair.
      expect(ConicMatrix.coefficients(1, 1, 1, 0, 0, -1).toCircleEq(), isNull);
      expect(ConicMatrix.coefficients(1, 0, 2, 0, 0, -1).toCircleEq(), isNull);
      expect(ConicMatrix.coefficients(1, 0, 1, 0, 0, 1).toCircleEq(), isNull);
      expect(
        ConicMatrix.linePair(
          ProjLine.real(1, 0, 0),
          ProjLine.real(0, 1, 0),
        ).toCircleEq(),
        isNull,
      );
    });

    test('a point circle projects to radius zero', () {
      final projected = ConicMatrix.coefficients(
        1,
        0,
        1,
        -2,
        -4,
        5,
      ).toCircleEq();
      expect(projected, isNotNull);
      expect(projected!.center.closeTo(const Vec2(1, 2), 1e-12), isTrue);
      expect(projected.radius, lessThan(1e-9));
    });
  });

  group('evaluate, polarLine, containsPoint', () {
    Glados(any.circleEq).test('polar of the center is the line at infinity', (
      c,
    ) {
      final polar = ConicMatrix.lift(c).polarLine(ProjPoint.lift(c.center));
      expect(polar.closeTo(ProjLine.infinity), isTrue);
    });

    Glados2(any.circleEq, any.angle).test(
      'polar at an on-circle point is the tangent there',
      (c, theta) {
        final conic = ConicMatrix.lift(c);
        final p = ProjPoint.lift(c.pointAt(theta));
        final tangent = conic.polarLine(p);
        expect(tangent.contains(p, 1e-7), isTrue);
        // Tangency: both intersection points collapse onto p.
        for (final root in intersectLineConic(tangent, conic)) {
          expect(root.closeTo(p, 1e-5), isTrue);
        }
      },
    );

    Glados3(any.circleEq, any.angle, any.nonZeroComplex).test(
      'containsPoint is invariant under complex rescaling of both sides',
      (c, theta, s) {
        final conic = ConicMatrix.lift(c);
        final p = ProjPoint.lift(c.pointAt(theta));
        expect(conic.scaledBy(s).containsPoint(p.scaledBy(s)), isTrue);
        final off = ProjPoint.lift(c.pointAt(theta) + Vec2(c.radius, 0));
        expect(
          conic.scaledBy(s).containsPoint(off.scaledBy(s)),
          conic.containsPoint(off),
        );
      },
    );

    Glados2(
      any.realConic,
      any.nonZeroComplex,
    ).test('polarLine commutes with rescaling', (conic, s) {
      if (conic.isZero) return;
      final p = ProjPoint.real(3, -2);
      final base = conic.polarLine(p);
      if (base.isZero) return;
      expect(conic.scaledBy(s).polarLine(p.scaledBy(s)).closeTo(base), isTrue);
    });
  });

  group('closeTo, normalized, isReal', () {
    Glados2(any.realConic, any.nonZeroComplex).test(
      'rescaling preserves closeTo, isReal, rank',
      (conic, s) {
        if (conic.isZero) return;
        final scaled = conic.scaledBy(s);
        expect(scaled.closeTo(conic), isTrue);
        expect(scaled.isReal(), conic.isReal());
        expect(scaled.isReal(), isTrue);
        expect(scaled.rank(), conic.rank());
        expect(scaled.normalized.closeTo(conic.normalized), isTrue);
      },
    );

    test('distinct conics are not close', () {
      final shifted = ConicMatrix.lift(CircleEq(const Vec2(1, 0), 1));
      final bigger = ConicMatrix.lift(CircleEq(Vec2.zero, 2));
      final ellipse = ConicMatrix.coefficients(1, 0, 2, 0, 0, -1);
      expect(unitCircle.closeTo(shifted), isFalse);
      expect(unitCircle.closeTo(bigger), isFalse);
      expect(unitCircle.closeTo(ellipse), isFalse);
    });

    test('the zero matrix fails every predicate', () {
      const zero = ConicMatrix(
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
      );
      expect(zero.isZero, isTrue);
      expect(zero.closeTo(zero), isFalse);
      expect(zero.closeTo(unitCircle), isFalse);
      expect(unitCircle.closeTo(zero), isFalse);
      expect(zero.isReal(), isFalse);
      expect(zero.containsPoint(ProjPoint.real(0, 0)), isFalse);
      expect(zero.rank(), 0);
      expect(zero.toCircleEq(), isNull);
    });

    test('genuinely complex conics are not real', () {
      const conic = ConicMatrix(
        Complex.one,
        Complex.zero,
        Complex.one,
        Complex.zero,
        Complex.zero,
        Complex.i,
      );
      expect(conic.isReal(), isFalse);
      // But a real conic scaled by i is still (projectively) real.
      expect(unitCircle.scaledBy(Complex.i).isReal(), isTrue);
    });
  });

  group('rank', () {
    // Restricted to well-conditioned scales: a tiny circle far from the
    // origin is numerically a point circle relative to its matrix norm
    // (|det| = r² drowns against ‖A‖³ ~ |center|⁶) — the translation part
    // of the balancing recipe that Phase 105 adds. At radius ≥ 0.5 and
    // center within 10 of the origin, rank 3 holds with orders of margin.
    Glados(any.smallCircle).test('circles have rank 3', (c) {
      expect(ConicMatrix.lift(c).rank(), 3);
    });

    Glados2(any.projLine, any.projLine).test(
      'a pair of distinct lines has rank 2',
      (g, h) {
        if (g.closeTo(h, 1e-3)) return;
        expect(ConicMatrix.linePair(g, h).rank(), 2);
      },
    );

    Glados(any.projLine).test('a double line has rank 1', (g) {
      expect(ConicMatrix.linePair(g, g).rank(), 1);
    });

    Glados3(any.projLine, any.projLine, any.gridVec2).test(
      'a line pair contains the points of both lines',
      (g, h, v) {
        final conic = ConicMatrix.linePair(g, h);
        if (conic.isZero) return;
        // A point on g: meet with a generic second line through v.
        final other = ProjPoint.lift(
          v,
        ).join(ProjPoint.lift(v + const Vec2(1, 1)));
        for (final line in [g, h]) {
          final p = line.meet(other);
          if (p.isZero) continue;
          expect(conic.containsPoint(p, 1e-9), isTrue);
        }
      },
    );
  });

  group('throughFivePoints', () {
    Glados2(any.smallCircle, any.fiveAngles).test(
      'five points on a circle recover the circle',
      (c, angles) {
        if (!anglesSeparated(angles, 0.05)) return;
        final conic = ConicMatrix.throughFivePoints([
          for (final theta in angles) ProjPoint.lift(c.pointAt(theta)),
        ]);
        expect(conic, isNotNull);
        expect(conic!.closeTo(ConicMatrix.lift(c), 1e-6), isTrue);
        expect(conic.rank(), 3);
      },
    );

    Glados(any.smallCircle).test(
      'the fitted conic contains its five defining points',
      (c) {
        final angles = [0.3, 1.4, 2.8, 4.1, 5.5];
        final points = [
          for (final theta in angles) ProjPoint.lift(c.pointAt(theta)),
        ];
        final conic = ConicMatrix.throughFivePoints(points);
        expect(conic, isNotNull);
        for (final p in points) {
          expect(conic!.containsPoint(p, 1e-7), isTrue);
        }
      },
    );

    test('a repeated point yields null', () {
      final p = ProjPoint.real(1, 2);
      expect(
        ConicMatrix.throughFivePoints([
          p,
          p,
          ProjPoint.real(0, 0),
          ProjPoint.real(3, 1),
          ProjPoint.real(-2, 5),
        ]),
        isNull,
      );
    });

    test('four collinear points yield null', () {
      expect(
        ConicMatrix.throughFivePoints([
          ProjPoint.real(0, 0),
          ProjPoint.real(1, 0),
          ProjPoint.real(2, 0),
          ProjPoint.real(3, 0),
          ProjPoint.real(0, 1),
        ]),
        isNull,
      );
    });

    test('three collinear points force the degenerate line-pair conic', () {
      final points = [
        ProjPoint.real(0, 0),
        ProjPoint.real(1, 0),
        ProjPoint.real(2, 0),
        ProjPoint.real(0, 1),
        ProjPoint.real(0, 2),
      ];
      final conic = ConicMatrix.throughFivePoints(points);
      expect(conic, isNotNull);
      expect(conic!.rank(), 2);
      for (final p in points) {
        expect(conic.containsPoint(p, 1e-9), isTrue);
      }
    });
  });

  group('intersectLineConic', () {
    test('transverse line, canonical order along the representative', () {
      // y = 0 as [0, 1, 0]: direction (b, −a) = (1, 0) → (−1,0) then (1,0).
      final pts = intersectLineConic(ProjLine.real(0, 1, 0), unitCircle);
      expect(pts, hasLength(2));
      expect(pts[0].toVec2()!.closeTo(const Vec2(-1, 0), 1e-12), isTrue);
      expect(pts[1].toVec2()!.closeTo(const Vec2(1, 0), 1e-12), isTrue);
      // Flipping the representative's sign flips the order (V1 semantics).
      final flipped = intersectLineConic(ProjLine.real(0, -1, 0), unitCircle);
      expect(flipped[0].toVec2()!.closeTo(const Vec2(1, 0), 1e-12), isTrue);
      expect(flipped[1].toVec2()!.closeTo(const Vec2(-1, 0), 1e-12), isTrue);
    });

    test('tangent line yields a double point', () {
      final pts = intersectLineConic(ProjLine.real(1, 0, -1), unitCircle);
      expect(pts, hasLength(2));
      for (final p in pts) {
        expect(p.closeTo(ProjPoint.real(1, 0), 1e-6), isTrue);
      }
    });

    test('missing line yields a pinned conjugate pair', () {
      // x = 2 misses the unit circle: points (2, ±i√3).
      final pts = intersectLineConic(ProjLine.real(1, 0, -2), unitCircle);
      expect(pts, hasLength(2));
      for (final p in pts) {
        expect(p.toVec2(), isNull);
        expect(unitCircle.containsPoint(p, 1e-12), isTrue);
      }
      expect(pts[0].closeTo(conjPoint(pts[1]), 1e-12), isTrue);
      // Canonical conjugate order: for [1, 0, −2] the direction is (0, −1),
      // the chart parameter is −y/w, and ascending Im puts y/w = +i√3 first.
      expect((pts[0].y / pts[0].w).im, greaterThan(0));
      expect((pts[1].y / pts[1].w).im, lessThan(0));
    });

    test('the line at infinity meets every circle at I and J', () {
      final pts = intersectLineConic(
        ProjLine.infinity,
        ConicMatrix.lift(CircleEq(const Vec2(3, -2), 5)),
      );
      expect(pts, hasLength(2));
      expect(pts.where((p) => p.closeTo(circularPointI, 1e-12)), hasLength(1));
      expect(pts.where((p) => p.closeTo(circularPointJ, 1e-12)), hasLength(1));
    });

    test('a line lying on a degenerate conic returns points of the line', () {
      final g = ProjLine.real(1, 0, 0);
      final conic = ConicMatrix.linePair(g, ProjLine.real(0, 1, 0));
      final pts = intersectLineConic(g, conic);
      expect(pts, hasLength(2));
      for (final p in pts) {
        expect(p.isZero, isFalse);
        expect(g.contains(p), isTrue);
        expect(conic.containsPoint(p), isTrue);
      }
    });

    Glados2(any.lineEq, any.circleEq).test(
      'agrees with V1 intersectLineCircle, positions and order',
      (l, c) {
        final margin = 1e-3 * (1 + c.radius);
        if ((l.distanceTo(c.center) - c.radius).abs() < margin) return;
        final line = ProjLine.lift(l);
        final conic = ConicMatrix.lift(c);
        final pts = intersectLineConic(line, conic);
        expect(pts, hasLength(2));
        for (final p in pts) {
          expect(p.isIncidentTo(line, 1e-7), isTrue);
          expect(conic.containsPoint(p, 1e-7), isTrue);
        }
        final v1 = intersectLineCircle(l, c);
        final tol = 1e-6 * (1 + c.center.norm + c.radius);
        if (v1.length == 2) {
          for (var i = 0; i < 2; i++) {
            final v = pts[i].toVec2();
            expect(
              v,
              isNotNull,
              reason: 'line $l circle $c: expected real point $i in $pts',
            );
            expect(
              v!.distanceTo(v1[i]),
              lessThan(tol),
              reason: 'line $l circle $c: $pts vs $v1',
            );
          }
        } else {
          // Miss: a conjugate pair with no real projection.
          expect(v1, isEmpty);
          for (final p in pts) {
            expect(p.toVec2(), isNull);
          }
          expect(pts[0].closeTo(conjPoint(pts[1]), 1e-6), isTrue);
        }
      },
    );

    Glados2(
      any.circleEq,
      any.angle,
    ).test('agrees with V1 on constructed tangent lines', (c, theta) {
      final touch = c.pointAt(theta);
      final l = LineEq.pointDirection(touch, (touch - c.center).perpendicular);
      final v1 = intersectLineCircle(l, c);
      expect(v1, hasLength(1));
      final pts = intersectLineConic(ProjLine.lift(l), ConicMatrix.lift(c));
      expect(pts, hasLength(2));
      // Double point: both roots at V1's single tangency point, at the
      // reduced (√eps) accuracy a double root supports.
      final tol = 1e-5 * (1 + c.center.norm + c.radius);
      for (final p in pts) {
        final v = p.toVec2(1e-5);
        expect(v, isNotNull, reason: 'line $l circle $c: $pts');
        expect(
          v!.distanceTo(v1.single),
          lessThan(tol),
          reason: 'line $l circle $c: $pts vs $v1',
        );
      }
    });

    Glados2(any.realConic, any.lineEq).test(
      'both roots are incident to both carriers',
      (conic, l) {
        if (conic.isZero) return;
        final line = ProjLine.lift(l);
        final pts = intersectLineConic(line, conic);
        expect(pts, hasLength(2));
        for (final p in pts) {
          if (p.isZero) continue;
          expect(p.isIncidentTo(line, 1e-7), isTrue);
          expect(conic.containsPoint(p, 1e-7), isTrue);
        }
      },
    );

    Glados3(any.lineEq, any.circleEq, any.nonZeroComplex).test(
      'the point set is invariant under rescaling line and conic',
      (l, c, s) {
        final margin = 1e-3 * (1 + c.radius);
        if ((l.distanceTo(c.center) - c.radius).abs() < margin) return;
        final base = intersectLineConic(ProjLine.lift(l), ConicMatrix.lift(c));
        final scaled = intersectLineConic(
          ProjLine.lift(l).scaledBy(s),
          ConicMatrix.lift(c).scaledBy(s),
        );
        for (final p in scaled) {
          expect(
            base.any((q) => q.closeTo(p, 1e-6)),
            isTrue,
            reason: 'line $l circle $c scale $s: $scaled vs $base',
          );
        }
      },
    );
  });
}
