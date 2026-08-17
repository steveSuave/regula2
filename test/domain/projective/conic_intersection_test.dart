import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/circles.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_intersection.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../v1_oracle/intersections.dart';

import '../math/generators.dart';
import 'generators.dart';

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

/// [m] scaled to unit Frobenius norm.
ConicMatrix frob(ConicMatrix m) =>
    m.isZero ? m : m.scaledBy(Complex(1 / math.sqrt(m.norm2)));

/// Whether [p] is (projectively) one of the circular points I, J.
bool isCircular(ProjPoint p) =>
    p.closeTo(circularPointI, 1e-6) || p.closeTo(circularPointJ, 1e-6);

/// Projects [p] to a real affine point, or null if at infinity / non-real.
/// Wider realness tolerance than the production default, so stress-corpus
/// points with measured imaginary contamination still project.
Vec2? projectReal(ProjPoint p, [double realEps = 1e-6]) {
  final n = p.normalized;
  if (n.w.abs < 1e-9) return null;
  final x = n.x / n.w;
  final y = n.y / n.w;
  if (!x.isRealWithin(realEps) || !y.isRealWithin(realEps)) return null;
  return Vec2(x.re, y.re);
}

/// Distance from [expected] to the closest real projection among [points].
double distanceToClosest(List<ProjPoint> points, Vec2 expected) {
  var best = double.infinity;
  for (final p in points) {
    final v = projectReal(p);
    if (v != null) best = math.min(best, v.distanceTo(expected));
  }
  return best;
}

/// [c] moved off the exact circle coefficient shape (`xy = 0`, `xx = yy`)
/// by ~1e-30 relative — far below every tolerance in the kernel, and
/// enough to miss the bitwise dispatch test that sends two circles down
/// the closed-form pencil route. This is how a test asks the *general*
/// route the same geometric question a circle pair asks the short one.
ConicMatrix nudgedOffCircleShape(ConicMatrix c) => ConicMatrix(
  c.xx,
  Complex(1e-30 * math.sqrt(c.norm2)),
  c.yy,
  c.xw,
  c.yw,
  c.ww,
);

/// Scale-free incidence residual of point [p] on conic [m].
double residualOn(ConicMatrix m, ProjPoint p) {
  final n = p.normalized;
  return frob(m).evaluate(n).abs / n.norm2;
}

extension on Any {
  /// A coordinate on a 0.01 grid in [-10, 10] (small enough that five-point
  /// conic fitting stays well conditioned).
  Generator<double> get smallCoord =>
      intInRange(-1000, 1001).map((i) => i / 100);

  Generator<Vec2> get smallVec2 => combine2(smallCoord, smallCoord, Vec2.new);

  /// A random real conic with grid coefficients in [-5, 5].
  Generator<ConicMatrix> get realConic {
    final e = intInRange(-500, 501);
    return combine6(
      e,
      e,
      e,
      e,
      e,
      e,
      (int a, int b, int c, int d, int f, int g) => ConicMatrix.coefficients(
        a / 100,
        b / 100,
        c / 100,
        d / 100,
        f / 100,
        g / 100,
      ),
    );
  }

  Generator<List<Vec2>> get sixPoints => listWithLength(6, smallVec2);
}

void main() {
  group('intersectConicConic on circles', () {
    test('transverse circles: two real points in V1 order, then J, then I', () {
      final a = ConicMatrix.lift(CircleEq(Vec2.zero, math.sqrt(2)));
      final b = ConicMatrix.lift(CircleEq(const Vec2(2, 0), math.sqrt(2)));
      final pts = intersectConicConic(a, b);
      expect(pts, hasLength(4));
      // V1: first point to the left of the directed center line a→b.
      expect(projectReal(pts[0]), isNotNull);
      expect(
        projectReal(pts[0])!.distanceTo(const Vec2(1, 1)),
        lessThan(1e-10),
      );
      expect(projectReal(pts[1]), isNotNull);
      expect(
        projectReal(pts[1])!.distanceTo(const Vec2(1, -1)),
        lessThan(1e-10),
      );
      expect(pts[2].closeTo(circularPointJ, 1e-6), isTrue);
      expect(pts[3].closeTo(circularPointI, 1e-6), isTrue);
    });

    test('swapping the arguments reverses the real pair', () {
      final a = ConicMatrix.lift(CircleEq(Vec2.zero, math.sqrt(2)));
      final b = ConicMatrix.lift(CircleEq(const Vec2(2, 0), math.sqrt(2)));
      final pts = intersectConicConic(b, a);
      expect(
        projectReal(pts[0])!.distanceTo(const Vec2(1, -1)),
        lessThan(1e-10),
      );
      expect(
        projectReal(pts[1])!.distanceTo(const Vec2(1, 1)),
        lessThan(1e-10),
      );
    });

    test('externally tangent circles: doubled tangency point', () {
      final a = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
      final b = ConicMatrix.lift(CircleEq(const Vec2(2, 0), 1));
      final pts = intersectConicConic(a, b);
      expect(pts, hasLength(4));
      final finite = pts.where((p) => !isCircular(p)).toList();
      expect(finite, hasLength(2));
      for (final p in finite) {
        final v = projectReal(p);
        expect(v, isNotNull);
        expect(v!.distanceTo(const Vec2(1, 0)), lessThan(1e-6));
      }
    });

    test('concentric circles: all four points are I and J', () {
      final a = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
      final b = ConicMatrix.lift(CircleEq(Vec2.zero, 2));
      final pts = intersectConicConic(a, b);
      expect(pts, hasLength(4));
      for (final p in pts) {
        expect(
          p.closeTo(circularPointI, 1e-7) || p.closeTo(circularPointJ, 1e-7),
          isTrue,
          reason: '$p',
        );
      }
    });

    test('coincident conics have no discrete intersection', () {
      final a = ConicMatrix.lift(CircleEq(const Vec2(3, -2), 1.5));
      expect(intersectConicConic(a, a), isEmpty);
      expect(intersectConicConic(a, a.scaledBy(const Complex(2, 1))), isEmpty);
    });

    test('zero input propagates to the empty list', () {
      const zero = ConicMatrix(
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
      );
      final a = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
      expect(intersectConicConic(zero, a), isEmpty);
      expect(intersectConicConic(a, zero), isEmpty);
    });

    Glados2(any.circleEq, any.circleEq).test(
      'agrees with V1 intersectCircleCircle in positions and order',
      (c1, c2) {
        final d = c1.center.distanceTo(c2.center);
        final scale = 1 + c1.radius + c2.radius;
        final margin = 1e-3 * scale;
        // Stay away from V1's classification boundaries.
        if (d < margin ||
            (d - (c1.radius + c2.radius)).abs() < margin ||
            (d - (c1.radius - c2.radius).abs()).abs() < margin) {
          return;
        }
        final a = ConicMatrix.lift(c1);
        final b = ConicMatrix.lift(c2);
        final pts = intersectConicConic(a, b);
        expect(pts, hasLength(4));
        expect(
          pts.where(isCircular),
          hasLength(2),
          reason: 'circles $c1 $c2 → $pts',
        );
        final v1 = intersectCircleCircle(c1, c2);
        final tol = 1e-6 * (1 + c1.center.norm + scale);
        if (v1.length == 2) {
          // Canonical order: the real pair first, in V1's order, then J, I.
          final first = projectReal(pts[0]);
          final second = projectReal(pts[1]);
          expect(first, isNotNull, reason: 'circles $c1 $c2 → $pts');
          expect(second, isNotNull, reason: 'circles $c1 $c2 → $pts');
          expect(
            first!.distanceTo(v1[0]),
            lessThan(tol),
            reason: 'circles $c1 $c2: $pts vs $v1',
          );
          expect(
            second!.distanceTo(v1[1]),
            lessThan(tol),
            reason: 'circles $c1 $c2: $pts vs $v1',
          );
          expect(pts[2].closeTo(circularPointJ, 1e-6), isTrue);
          expect(pts[3].closeTo(circularPointI, 1e-6), isTrue);
        } else {
          // Disjoint (separate or nested): no real finite point on both.
          for (final p in pts.where((p) => !isCircular(p))) {
            final v = projectReal(p);
            if (v != null) {
              expect(
                math.max(c1.distanceTo(v), c2.distanceTo(v)),
                greaterThan(margin / 2),
                reason: 'circles $c1 $c2 phantom real point $v',
              );
            }
          }
        }
        for (final p in pts) {
          expect(residualOn(a, p), lessThan(1e-8));
          expect(residualOn(b, p), lessThan(1e-8));
        }
      },
    );

    Glados3(any.circleEq, any.circleEq, any.nonZeroComplex).test(
      'point positions and order are invariant under complex rescaling',
      (c1, c2, k) {
        final d = c1.center.distanceTo(c2.center);
        final scale = 1 + c1.radius + c2.radius;
        final margin = 1e-3 * scale;
        if (d < margin ||
            (d - (c1.radius + c2.radius)).abs() < margin ||
            (d - (c1.radius - c2.radius).abs()).abs() < margin) {
          return;
        }
        final a = ConicMatrix.lift(c1);
        final b = ConicMatrix.lift(c2);
        final baseline = intersectConicConic(a, b);
        final rescaled = intersectConicConic(a.scaledBy(k), b.scaledBy(-k));
        expect(rescaled, hasLength(baseline.length));
        for (var i = 0; i < baseline.length; i++) {
          expect(
            rescaled[i].closeTo(baseline[i], 1e-6),
            isTrue,
            reason: 'index $i: ${rescaled[i]} vs ${baseline[i]} (k = $k)',
          );
        }
      },
    );
  });

  // The pencil of two circles has a degenerate member in closed form — no
  // cubic, no member scoring, no adjugate split. These pin that the shorter
  // route is *taken*, and that taking it changes no answer: the V1-agreement
  // and rescaling-invariance properties above run over it too.
  group('the circle pencil is closed form (Phase 122)', () {
    final a = ConicMatrix.lift(CircleEq(Vec2.zero, math.sqrt(2)));
    final b = ConicMatrix.lift(CircleEq(const Vec2(2, 0), math.sqrt(2)));

    test('the circular points come back exactly on the line at infinity', () {
      // The discriminator: `ℓ∞ ∩ circle` is solved directly, so I and J are
      // exact rather than recovered from a computed cubic root. The general
      // route leaves them at |w| ~ 1e-33 on this same pair — near enough for
      // every consumer, and not zero. If this ever reads "near", the closed
      // form has stopped being reached.
      final pts = intersectConicConic(a, b);
      expect(pts[2].w, Complex.zero);
      expect(pts[3].w, Complex.zero);
      expect(pts[2].y, const Complex(0, -1));
      expect(pts[3].y, Complex.i);
      expect(pts[2].x, Complex.one);
      expect(pts[3].x, Complex.one);
    });

    test('both routes answer the same, points and order', () {
      // A conic 1e-30 off the circle shape is the same geometry and misses
      // the bitwise dispatch test, so it is the general route asked the same
      // question. Both real crossings and the conjugate pair must line up
      // index for index — the order is what `branchIndex` addresses.
      final rng = math.Random(7);
      var real = 0;
      var complex = 0;
      for (var i = 0; i < 400; i++) {
        final c1 = CircleEq(
          Vec2(rng.nextDouble() * 20 - 10, rng.nextDouble() * 20 - 10),
          rng.nextDouble() * 8 + 0.1,
        );
        final c2 = CircleEq(
          Vec2(rng.nextDouble() * 20 - 10, rng.nextDouble() * 20 - 10),
          rng.nextDouble() * 8 + 0.1,
        );
        final closed = intersectConicConic(
          ConicMatrix.lift(c1),
          ConicMatrix.lift(c2),
        );
        final general = intersectConicConic(
          nudgedOffCircleShape(ConicMatrix.lift(c1)),
          ConicMatrix.lift(c2),
        );
        expect(closed, hasLength(4));
        expect(general, hasLength(4));
        if (projectReal(closed[0]) != null) {
          real++;
        } else {
          complex++;
        }
        for (var k = 0; k < 4; k++) {
          expect(
            closed[k].closeTo(general[k], 1e-7),
            isTrue,
            reason: 'circles $c1 $c2 index $k: ${closed[k]} vs ${general[k]}',
          );
        }
      }
      // Both regimes were actually reached — a conjugate pair orders by the
      // imaginary-measure tier, not the centre line, so it is a different
      // rule being checked.
      expect(real, greaterThan(50));
      expect(complex, greaterThan(50));
    });

    test('the centroid balance is load-bearing far from the origin', () {
      // The general recipe's step 1 warns that an unbalanced configuration
      // loses digits quadratically in its offset; the closed form is not
      // exempt, and gets the balance for free because a circle's centre is
      // (−xw/xx, −yw/xx) with no adjugate to form. Unbalanced, the crossings
      // below come out ~2e-5 off.
      const offset = 1e6;
      final far1 = CircleEq(const Vec2(offset, offset), 2.5);
      final far2 = CircleEq(const Vec2(offset + 3, offset + 1), 2);
      final pts = intersectConicConic(
        ConicMatrix.lift(far1),
        ConicMatrix.lift(far2),
      );
      final near = intersectCircleCircle(
        CircleEq(Vec2.zero, 2.5),
        CircleEq(const Vec2(3, 1), 2),
      );
      expect(near, hasLength(2));
      for (var k = 0; k < 2; k++) {
        final v = projectReal(pts[k]);
        expect(v, isNotNull);
        expect(
          Vec2(v!.x - offset, v.y - offset).distanceTo(near[k]),
          lessThan(1e-8),
          reason: 'far crossing $k: $v',
        );
      }
    });

    test('complex carriers stay on both conics', () {
      // What a tracing detour hands it: circles whose centres have left the
      // real axis. The route is holomorphic throughout — a complex centroid
      // is still a translation — so the answer is judged the only way it can
      // be, by incidence on both inputs.
      final ca = circleWithRadius(
        ProjPoint(const Complex(0, 0.3), const Complex(1, -0.2), Complex.one),
        2.5,
      );
      final cb = circleWithRadius(
        ProjPoint(const Complex(3, -0.1), const Complex(1, 0.4), Complex.one),
        2,
      );
      final pts = intersectConicConic(ca, cb);
      expect(pts, hasLength(4));
      for (final p in pts) {
        expect(residualOn(ca, p), lessThan(1e-10), reason: '$p');
        expect(residualOn(cb, p), lessThan(1e-10), reason: '$p');
      }
    });

    test('concentric circles meet only at I and J, each doubled', () {
      // The radical axis degenerates to ℓ∞ itself, so all four points are
      // circular — the honest answer, and the one consumers already filter.
      final pts = intersectConicConic(
        ConicMatrix.lift(CircleEq(const Vec2(4, -3), 1)),
        ConicMatrix.lift(CircleEq(const Vec2(4, -3), 2.5)),
      );
      expect(pts, hasLength(4));
      expect(pts.where(isCircular), hasLength(4));
    });
  });

  group('degenerate inputs', () {
    test('line pair ∩ circle: the four line∩circle points', () {
      final pair = ConicMatrix.linePair(
        ProjLine.real(1, 0, 0), // x = 0
        ProjLine.real(0, 1, 0.5), // y = −1/2
      );
      final circle = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
      final pts = intersectConicConic(pair, circle);
      expect(pts, hasLength(4));
      final h = math.sqrt(0.75);
      for (final expected in [
        const Vec2(0, 1),
        const Vec2(0, -1),
        Vec2(h, -0.5),
        Vec2(-h, -0.5),
      ]) {
        expect(
          distanceToClosest(pts, expected),
          lessThan(1e-9),
          reason: 'missing $expected in $pts',
        );
      }
      for (final p in pts) {
        expect(residualOn(pair, p), lessThan(1e-12));
        expect(residualOn(circle, p), lessThan(1e-12));
      }
    });

    test('double line ∩ circle: both tangency-style pairs on the line', () {
      final pair = ConicMatrix.linePair(
        ProjLine.real(0, 1, 0), // y = 0, twice
        ProjLine.real(0, 1, 0),
      );
      final circle = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
      final pts = intersectConicConic(pair, circle);
      expect(pts, hasLength(4));
      for (final expected in [const Vec2(1, 0), const Vec2(-1, 0)]) {
        // Double roots carry the inherent ~sqrt(machine eps) accuracy of a
        // tangency (the polish is rightly skipped there).
        expect(distanceToClosest(pts, expected), lessThan(1e-6));
      }
    });
  });

  group('conics through shared points', () {
    Glados(any.sixPoints).test('roots contain the four shared points', (raw) {
      final shared = raw.sublist(0, 4);
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          if (shared[i].distanceTo(shared[j]) < 0.1) return;
        }
      }
      final a = ConicMatrix.throughFivePoints([
        for (final p in [...shared, raw[4]]) ProjPoint.lift(p),
      ]);
      final b = ConicMatrix.throughFivePoints([
        for (final p in [...shared, raw[5]]) ProjPoint.lift(p),
      ]);
      if (a == null || b == null) return;
      // Skip degenerate or near-degenerate conics; the glados corpus is for
      // the generic path (degeneracies are unit-tested).
      if (frob(a).det.abs < 1e-4 || frob(b).det.abs < 1e-4) return;
      final pts = intersectConicConic(a, b);
      expect(pts, hasLength(4));
      for (final s in shared) {
        expect(
          distanceToClosest(pts, s),
          lessThan(1e-5),
          reason: 'shared $s not among $pts',
        );
      }
    });
  });

  group('random real conic incidence', () {
    Glados2(any.realConic, any.realConic).test(
      'all four roots lie on both conics',
      (a, b) {
        if (frob(a).det.abs < 1e-2 || frob(b).det.abs < 1e-2) return;
        final pts = intersectConicConic(a, b);
        expect(pts, hasLength(4));
        for (final p in pts) {
          expect(
            residualOn(a, p),
            lessThan(1e-8),
            reason: 'point $p off conic A',
          );
          expect(
            residualOn(b, p),
            lessThan(1e-8),
            reason: 'point $p off conic B',
          );
        }
      },
    );
  });

  group(
    'stress corpus regression (bounds from benchmark/pencil_stress.dart)',
    () {
      test('near-tangent circles down to ε = 1e-12', () {
        for (var e = 3; e <= 12; e++) {
          final eps = math.pow(10.0, -e).toDouble();
          final d = 2 - eps;
          final a = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
          final b = ConicMatrix.lift(CircleEq(Vec2(d, 0), 1));
          final pts = intersectConicConic(a, b);
          final ex = d / 2;
          final ey = math.sqrt(math.max(0, 1 - ex * ex));
          // Measured: incidence ≤ 2e-16, point error ≤ 1.2e-11; ×100 margin.
          expect(
            distanceToClosest(pts, Vec2(ex, ey)),
            lessThan(1e-9),
            reason: 'eps 1e-$e',
          );
          for (final p in pts) {
            expect(residualOn(a, p), lessThan(1e-13), reason: 'eps 1e-$e');
          }
        }
      });

      test('just-missing circles: conjugate pair, |Im| ≈ sqrt(ε), J first', () {
        for (var e = 4; e <= 12; e += 2) {
          final eps = math.pow(10.0, -e).toDouble();
          final a = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
          final b = ConicMatrix.lift(CircleEq(Vec2(2 + eps, 0), 1));
          final pts = intersectConicConic(a, b);
          expect(pts, hasLength(4));
          // All four are complex; canonical order pins J first and I last.
          expect(
            pts.first.closeTo(circularPointJ, 1e-6),
            isTrue,
            reason: 'eps 1e-$e',
          );
          expect(
            pts.last.closeTo(circularPointI, 1e-6),
            isTrue,
            reason: 'eps 1e-$e',
          );
          final finite = pts.where((p) => !isCircular(p)).toList();
          expect(finite, hasLength(2), reason: 'eps 1e-$e');
          for (final p in finite) {
            final n = p.normalized;
            final im = (n.y / n.w).im.abs();
            // |y| = sqrt(ε + ε²/4) ≈ sqrt(ε); allow a factor-2 band.
            expect(im, greaterThan(math.sqrt(eps) / 2), reason: 'eps 1e-$e');
            expect(im, lessThan(2 * math.sqrt(eps)), reason: 'eps 1e-$e');
            expect(residualOn(a, p), lessThan(1e-13), reason: 'eps 1e-$e');
          }
        }
      });

      test(
        'nearly identical circles stay accurate through the near-triple root',
        () {
          for (var e = 3; e <= 12; e++) {
            final delta = math.pow(10.0, -e).toDouble();
            final a = ConicMatrix.lift(CircleEq(Vec2.zero, 1));
            final b = ConicMatrix.lift(CircleEq(Vec2(delta, 0), 1));
            final pts = intersectConicConic(a, b);
            // Measured: incidence ≤ 8e-11, point error ≤ 1.7e-7; ×100 margin.
            final expected = Vec2(delta / 2, math.sqrt(1 - delta * delta / 4));
            expect(
              distanceToClosest(pts, expected),
              lessThan(1e-4),
              reason: 'delta 1e-$e',
            );
            for (final p in pts) {
              expect(residualOn(a, p), lessThan(1e-8), reason: 'delta 1e-$e');
            }
          }
        },
      );

      test('scale extremes are exact after balancing', () {
        for (var k = -8; k <= 8; k += 2) {
          final s = math.pow(10.0, k).toDouble();
          final a = ConicMatrix.lift(CircleEq(Vec2.zero, s));
          final b = ConicMatrix.lift(CircleEq(Vec2(s, 0), s));
          final pts = intersectConicConic(a, b);
          // Measured: relative point error ≤ 2.2e-16; ×~10⁴ margin.
          final expected = Vec2(s / 2, s * math.sqrt(3) / 2);
          expect(
            distanceToClosest(pts, expected) / s,
            lessThan(1e-12),
            reason: 'scale 1e$k',
          );
        }
      });

      test(
        'far-offset circles: translation balancing closes the Spike-2 gap',
        () {
          // The Phase 102 prototype lost digits quadratically in the offset
          // (1e2 → 8.5e-13, 1e4 → 8.6e-9, 1e6 → 2.9e-5, worse beyond). With the
          // centroid translated to the origin the error stays at machine
          // precision relative to the coordinate magnitude: measured ≤ 5e-48 up
          // to 1e4 and 1.2e-10 at 1e6 (≈ one ulp of the answer's coordinates);
          // ×~10⁴ margin. The family necessarily stops at 1e6: at offset 1e8 a
          // unit circle's r² = 1 falls below the ulp (= 2) of the lifted entry
          // ww = cx² − r², so `ConicMatrix.lift` itself degrades the input to a
          // point circle — a representation limit, not a solver one.
          for (var k = 0; k <= 6; k += 2) {
            final off = math.pow(10.0, k).toDouble();
            final a = ConicMatrix.lift(CircleEq(Vec2(off, 0), 1));
            final b = ConicMatrix.lift(CircleEq(Vec2(off + 1, 0), 1));
            final pts = intersectConicConic(a, b);
            final expected = Vec2(off + 0.5, math.sqrt(3) / 2);
            expect(
              distanceToClosest(pts, expected),
              lessThan(1e-12 * (1 + off)),
              reason: 'offset 1e$k',
            );
            for (final p in pts) {
              expect(residualOn(a, p), lessThan(1e-12), reason: 'offset 1e$k');
            }
          }
        },
      );
    },
  );

  group('splitDegenerateConic', () {
    final crossingLines = ConicMatrix.coefficients(1, 0, -1, 0, 0, 0); // y = ±x
    final parallelLines = ConicMatrix.coefficients(1, 0, 0, 0, 0, -1); // x = ±1
    final originPoint = ConicMatrix.coefficients(
      1,
      0,
      1,
      0,
      0,
      0,
    ); // x² + y² = 0
    final doubleLine = ConicMatrix.coefficients(
      1,
      0,
      0,
      0,
      0,
      0,
    ); // x = 0, twice

    test('recovers two real crossing lines', () {
      final (g, h) = splitDegenerateConic(crossingLines);
      expect(g.isReal(), isTrue);
      expect(h.isReal(), isTrue);
      expect(ConicMatrix.linePair(g, h).closeTo(crossingLines), isTrue);
      expect(g.meet(h).toVec2()!.closeTo(Vec2.zero, 1e-9), isTrue);
    });

    test('recovers parallel lines meeting at infinity', () {
      final (g, h) = splitDegenerateConic(parallelLines);
      expect(ConicMatrix.linePair(g, h).closeTo(parallelLines), isTrue);
      expect(g.meet(h).isFinite(), isFalse);
    });

    test('a rank-1 conic comes back as one line, doubled', () {
      final (g, h) = splitDegenerateConic(doubleLine);
      expect(g.closeTo(h), isTrue);
      expect(ConicMatrix.linePair(g, h).closeTo(doubleLine), isTrue);
    });

    test('conjugate components multiply back to the real conic', () {
      final (g, h) = splitDegenerateConic(originPoint);
      expect(g.isReal(), isFalse);
      expect(h.isReal(), isFalse);
      expect(ConicMatrix.linePair(g, h).closeTo(originPoint), isTrue);
    });
  });
}
