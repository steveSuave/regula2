import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/triangle_centers.dart' as tc;
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/euclidean.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import 'generators.dart';

void main() {
  group('directionOf', () {
    test('is the affine direction, at infinity, on the line', () {
      final l = ProjLine.lift(
        LineEq.throughPoints(const Vec2(1, 2), const Vec2(4, 6)),
      );
      final d = directionOf(l);
      expect(d.isReal(), isTrue);
      expect(d.isFinite(), isFalse);
      expect(d.isIncidentTo(l), isTrue);
      expect(d.isIncidentTo(ProjLine.infinity), isTrue);
      // Direction (3, 4) up to scale.
      expect(d.closeTo(ProjPoint.real(3, 4, 0)), isTrue);
    });

    test('of the line at infinity is the zero triple', () {
      expect(directionOf(ProjLine.infinity).isZero, isTrue);
      expect(normalDirectionOf(ProjLine.infinity).isZero, isTrue);
    });
  });

  group('normalDirectionOf', () {
    Glados(any.projLine).test('is conjugate to directionOf w.r.t. any circle '
        '(the I,J involution)', (l) {
      final d = directionOf(l);
      final n = normalDirectionOf(l);
      if (d.isZero) {
        return; // l is (projectively) the line at infinity.
      }
      // Conjugacy w.r.t. a conic: n lies on the polar of d. Any circle
      // induces the same involution on the line at infinity — that is
      // what "perpendicularity comes from I, J" means concretely.
      final circle = ConicMatrix.lift(CircleEq(const Vec2(3, -2), 1.5));
      expect(circle.polarLine(d).contains(n), isTrue);
    });

    test('chart directions are orthogonal', () {
      final l = ProjLine.lift(
        LineEq.throughPoints(const Vec2(0, 0), const Vec2(5, 1)),
      );
      final d = directionOf(l);
      final n = normalDirectionOf(l);
      final dot = d.x * n.x + d.y * n.y;
      expect(dot.abs, lessThan(1e-12));
    });
  });

  group('parallelThrough / perpendicularThrough', () {
    Glados2(any.vec2, any.vec2).test('contain the through-point', (p, q) {
      if (p.closeTo(q)) {
        return;
      }
      final l = ProjLine.lift(LineEq.throughPoints(p, q));
      final through = ProjPoint.real(-3, 7);
      expect(parallelThrough(through, l).contains(through), isTrue);
      expect(perpendicularThrough(through, l).contains(through), isTrue);
    });

    test('parallel keeps the direction, perpendicular conjugates it', () {
      final l = ProjLine.lift(
        LineEq.throughPoints(const Vec2(0, 0), const Vec2(2, 1)),
      );
      final through = ProjPoint.real(5, 5);
      final par = parallelThrough(through, l);
      final perp = perpendicularThrough(through, l);
      expect(directionOf(par).closeTo(directionOf(l)), isTrue);
      expect(directionOf(perp).closeTo(normalDirectionOf(l)), isTrue);
    });

    test('through the derived direction itself: the zero triple', () {
      final l = ProjLine.real(0, 1, -2); // y = 2, direction [1 : 0 : 0].
      expect(parallelThrough(ProjPoint.real(1, 0, 0), l).isZero, isTrue);
      expect(perpendicularThrough(ProjPoint.real(0, 1, 0), l).isZero, isTrue);
    });
  });

  group('midpointOf', () {
    Glados2(any.vec2, any.vec2).test('agrees with the affine midpoint', (p, q) {
      final m = midpointOf(ProjPoint.lift(p), ProjPoint.lift(q));
      expect(m.toVec2()!.closeTo(p.lerp(q, 0.5)), isTrue);
    });

    Glados2(any.projPoint, any.nonZeroComplex).test(
      'a point with a rescaling of itself is the point itself',
      (p, k) {
        expect(midpointOf(p, p.scaledBy(k)).closeTo(p), isTrue);
      },
    );

    test('with a point at infinity is that point at infinity', () {
      final m = midpointOf(ProjPoint.real(1, 2), ProjPoint.real(3, 4, 0));
      expect(m.closeTo(ProjPoint.real(3, 4, 0)), isTrue);
    });

    test('of two points at infinity is the zero triple', () {
      expect(
        midpointOf(ProjPoint.real(1, 0, 0), ProjPoint.real(0, 1, 0)).isZero,
        isTrue,
      );
    });
  });

  group('centroidOf', () {
    Glados3(any.vec2, any.vec2, any.vec2).test(
      'agrees with the affine centroid',
      (a, b, c) {
        final g = centroidOf(
          ProjPoint.lift(a),
          ProjPoint.lift(b),
          ProjPoint.lift(c),
        );
        expect(g.toVec2()!.closeTo(tc.centroid(a, b, c), 1e-6), isTrue);
      },
    );

    test('with one vertex at infinity is that point at infinity', () {
      final g = centroidOf(
        ProjPoint.real(1, 2),
        ProjPoint.real(3, 4),
        ProjPoint.real(1, 1, 0),
      );
      expect(g.closeTo(ProjPoint.real(1, 1, 0)), isTrue);
    });
  });

  group('lerpOf', () {
    Glados3(any.vec2, any.vec2, any.component).test(
      'agrees with the affine lerp (extrapolation included)',
      (p, q, t0) {
        final t = t0 / 1000; // [-1, 1] grid
        final r = lerpOf(ProjPoint.lift(p), ProjPoint.lift(q), t);
        expect(r.toVec2()!.closeTo(p.lerp(q, t), 1e-6), isTrue);
      },
    );

    test('t = 0 and t = 1 are the endpoints; t = 0.5 the midpoint', () {
      final p = ProjPoint.real(1, 2);
      final q = ProjPoint.real(-3, 4);
      expect(lerpOf(p, q, 0).closeTo(p), isTrue);
      expect(lerpOf(p, q, 1).closeTo(q), isTrue);
      expect(lerpOf(p, q, 0.5).closeTo(midpointOf(p, q)), isTrue);
    });

    test('with the far endpoint at infinity: that point at infinity for '
        't ≠ 0, the zero triple at t = 0', () {
      final p = ProjPoint.real(1, 2);
      final inf = ProjPoint.real(3, 4, 0);
      expect(lerpOf(p, inf, 0.25).closeTo(inf), isTrue);
      expect(lerpOf(p, inf, 0).isZero, isTrue);
    });

    Glados3(any.projPoint, any.projPoint, any.nonZeroComplex).test(
      'is projectively invariant under rescaling an argument',
      (p, q, k) {
        const t = 0.375;
        final r = lerpOf(p, q, t);
        if (r.isZero) {
          return;
        }
        expect(lerpOf(p.scaledBy(k), q, t).closeTo(r), isTrue);
        expect(lerpOf(p, q.scaledBy(k), t).closeTo(r), isTrue);
      },
    );
  });

  group('perpendicularBisectorOf', () {
    Glados2(any.vec2, any.vec2).test(
      'contains the midpoint, perpendicular to the join, equidistant',
      (p, q) {
        if (p.closeTo(q, 1e-3)) {
          return;
        }
        final bis = perpendicularBisectorOf(
          ProjPoint.lift(p),
          ProjPoint.lift(q),
        );
        expect(
          bis.contains(midpointOf(ProjPoint.lift(p), ProjPoint.lift(q))),
          isTrue,
        );
        expect(
          directionOf(bis).closeTo(
            normalDirectionOf(ProjPoint.lift(p).join(ProjPoint.lift(q))),
          ),
          isTrue,
          reason: 'perpendicular to the join',
        );
        final line = bis.toLineEq()!;
        expect(line.distanceTo(p), closeTo(line.distanceTo(q), 1e-6));
      },
    );

    Glados(any.projPoint).test('of a point and itself is the zero triple', (p) {
      // Exact duplicates cancel bitwise. A *rescaled* duplicate leaves
      // rounding residue instead of an exact zero — which is why the
      // object layer (`carrierThrough`, `PerpendicularBisectorLine`)
      // guards with `closeTo` before calling the kernel.
      expect(perpendicularBisectorOf(p, p).isZero, isTrue);
    });
  });

  group('multilinearity (rescaling covariance)', () {
    Glados3(
      any.projPoint,
      any.projPoint,
      any.nonZeroComplex,
    ).test('midpointOf and perpendicularBisectorOf are projectively '
        'invariant under rescaling an argument', (p, q, k) {
      final m = midpointOf(p, q);
      if (!m.isZero) {
        expect(midpointOf(p.scaledBy(k), q).closeTo(m), isTrue);
        expect(midpointOf(p, q.scaledBy(k)).closeTo(m), isTrue);
      }
      final bis = perpendicularBisectorOf(p, q);
      if (!bis.isZero && !p.closeTo(q)) {
        expect(perpendicularBisectorOf(p.scaledBy(k), q).closeTo(bis), isTrue);
      }
    });

    Glados2(any.projLine, any.nonZeroComplex).test(
      'directions are projectively invariant under rescaling',
      (l, k) {
        final d = directionOf(l);
        if (d.isZero) {
          return;
        }
        expect(directionOf(l.scaledBy(k)).closeTo(d), isTrue);
        expect(
          normalDirectionOf(l.scaledBy(k)).closeTo(normalDirectionOf(l)),
          isTrue,
        );
      },
    );

    Glados3(any.projPoint, any.projLine, any.nonZeroComplex).test(
      'parallelThrough / perpendicularThrough are projectively '
      'invariant under rescaling either argument',
      (p, l, k) {
        final par = parallelThrough(p, l);
        if (par.isZero) {
          return;
        }
        expect(parallelThrough(p.scaledBy(k), l).closeTo(par), isTrue);
        expect(parallelThrough(p, l.scaledBy(k)).closeTo(par), isTrue);
        final perp = perpendicularThrough(p, l);
        if (perp.isZero) {
          return;
        }
        expect(perpendicularThrough(p.scaledBy(k), l).closeTo(perp), isTrue);
        expect(perpendicularThrough(p, l.scaledBy(k)).closeTo(perp), isTrue);
      },
    );

    Glados2(any.vec2, any.nonZeroComplex).test(
      'centroidOf is projectively invariant under rescaling an argument',
      (v, k) {
        final a = ProjPoint.lift(v);
        final b = ProjPoint.real(4, -1);
        final c = ProjPoint.real(-2, 3);
        final g = centroidOf(a, b, c);
        expect(centroidOf(a.scaledBy(k), b, c).closeTo(g), isTrue);
        expect(centroidOf(a, b.scaledBy(k), c).closeTo(g), isTrue);
        expect(centroidOf(a, b, c.scaledBy(k)).closeTo(g), isTrue);
      },
    );
  });
}
