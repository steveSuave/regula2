import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/intersections.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/pencil.dart';

import '../math/generators.dart';

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

CMat3 circleConic(CircleEq c) {
  final cx = c.center.x, cy = c.center.y, r = c.radius;
  return [
    [const Complex(1), Complex.zero, Complex(-cx)],
    [Complex.zero, const Complex(1), Complex(-cy)],
    [Complex(-cx), Complex(-cy), Complex(cx * cx + cy * cy - r * r)],
  ];
}

CVec3 circleLift(List<double> reals) =>
    [for (final x in reals) Complex(x)];

final CVec3 pointI = [Complex.one, Complex.i, Complex.zero];
final CVec3 pointJ = [Complex.one, -Complex.i, Complex.zero];

/// Whether [p] is (projectively) one of the circular points I, J.
bool isCircular(CVec3 p) {
  final n = normalizeVec(p);
  final toI = vecNorm2(crossVec(n, pointI));
  final toJ = vecNorm2(crossVec(n, pointJ));
  return math.min(toI, toJ) <= 1e-12 * vecNorm2(n);
}

/// Projects [p] to a real affine point, or null if at infinity / non-real.
Vec2? projectReal(CVec3 p) {
  final n = normalizeVec(p);
  if (n[2].abs <= 1e-9) return null;
  final x = n[0] / n[2];
  final y = n[1] / n[2];
  if (!x.isRealWithin(1e-6) || !y.isRealWithin(1e-6)) return null;
  return Vec2(x.re, y.re);
}

/// Distance from [expected] to the closest real projection among [points].
double distanceToClosest(List<CVec3> points, Vec2 expected) {
  var best = double.infinity;
  for (final p in points) {
    final v = projectReal(p);
    if (v != null) best = math.min(best, v.distanceTo(expected));
  }
  return best;
}

/// Whether lines [g] and [h] agree up to (complex) scale.
bool sameLine(CVec3 g, CVec3 h) =>
    vecNorm2(crossVec(g, h)) <= 1e-12 * vecNorm2(g) * vecNorm2(h);

/// Scale-free incidence residual of point [p] on unit-Frobenius-normalized [m].
double residualOn(CMat3 m, CVec3 p) {
  final n = normalizeVec(p);
  return quadForm(normalizeConic(m), n).abs / vecNorm2(n);
}

Complex cval(double re, [double im = 0]) => Complex(re, im);

/// The conic through five points as a real coefficient row
/// [a, b, c, d, e, f] of ax² + bxy + cy² + dx + ey + f = 0, or null when the
/// five points do not determine a unique conic (linear system rank < 5).
List<double>? conicThroughFivePoints(List<Vec2> pts) {
  assert(pts.length == 5, 'a conic is determined by five points');
  final m = [
    for (final p in pts)
      [p.x * p.x, p.x * p.y, p.y * p.y, p.x, p.y, 1.0],
  ];
  final pivotCols = <int>[];
  var row = 0;
  for (var col = 0; col < 6 && row < 5; col++) {
    var bestRow = row;
    for (var r = row + 1; r < 5; r++) {
      if (m[r][col].abs() > m[bestRow][col].abs()) bestRow = r;
    }
    if (m[bestRow][col].abs() < 1e-9) continue;
    final tmp = m[row];
    m[row] = m[bestRow];
    m[bestRow] = tmp;
    for (var r = 0; r < 5; r++) {
      if (r == row) continue;
      final f = m[r][col] / m[row][col];
      for (var cc = col; cc < 6; cc++) {
        m[r][cc] -= f * m[row][cc];
      }
    }
    pivotCols.add(col);
    row++;
  }
  if (row < 5) return null;
  final free =
      ({0, 1, 2, 3, 4, 5}..removeAll(pivotCols)).single;
  final sol = List<double>.filled(6, 0);
  sol[free] = 1;
  for (var r = 0; r < 5; r++) {
    final pc = pivotCols[r];
    sol[pc] = -m[r][free] / m[r][pc];
  }
  return sol;
}

CMat3 conicFromCoeffs(List<double> k) => [
      [cval(k[0]), cval(k[1] / 2), cval(k[3] / 2)],
      [cval(k[1] / 2), cval(k[2]), cval(k[4] / 2)],
      [cval(k[3] / 2), cval(k[4] / 2), cval(k[5])],
    ];

extension on Any {
  /// A coordinate on a 0.01 grid in [-10, 10] (small enough that five-point
  /// conic fitting stays well conditioned).
  Generator<double> get smallCoord =>
      intInRange(-1000, 1001).map((i) => i / 100);

  Generator<Vec2> get smallVec2 => combine2(smallCoord, smallCoord, Vec2.new);

  /// A grid complex number in [-8, 8] per component.
  Generator<Complex> get gridComplex => combine2(
        intInRange(-800, 801).map((i) => i / 100),
        intInRange(-800, 801).map((i) => i / 100),
        Complex.new,
      );

  /// A random real symmetric conic matrix with grid entries in [-5, 5].
  Generator<CMat3> get realConic {
    final e = intInRange(-500, 501);
    return combine6(
      e,
      e,
      e,
      e,
      e,
      e,
      (int a, int b, int c, int d, int f, int g) =>
          conicFromCoeffs([a / 100, b / 100, c / 100, d / 100, f / 100, g / 100]),
    );
  }

  Generator<List<Vec2>> get sixPoints => listWithLength(6, smallVec2);
}

void main() {
  group('solveCubic', () {
    test('distinct real roots', () {
      // (λ−1)(λ−2)(λ−3) = λ³ − 6λ² + 11λ − 6
      final roots =
          solveCubic(cval(1), cval(-6), cval(11), cval(-6));
      expect(roots, hasLength(3));
      for (final expected in const [1.0, 2.0, 3.0]) {
        expect(
          roots.any((r) => r.closeTo(Complex(expected), 1e-10)),
          isTrue,
          reason: 'missing root $expected in $roots',
        );
      }
    });

    test('complex roots', () {
      // (λ² + 1)(λ − 2) = λ³ − 2λ² + λ − 2
      final roots = solveCubic(cval(1), cval(-2), cval(1), cval(-2));
      expect(roots, hasLength(3));
      for (final expected in [Complex.i, -Complex.i, cval(2)]) {
        expect(roots.any((r) => r.closeTo(expected, 1e-10)), isTrue);
      }
    });

    test('degree drop to quadratic and linear', () {
      // 0·λ³ + (λ−1)(λ−2)
      final quad = solveCubic(Complex.zero, cval(1), cval(-3), cval(2));
      expect(quad, hasLength(2));
      expect(quad.any((r) => r.closeTo(cval(1), 1e-10)), isTrue);
      expect(quad.any((r) => r.closeTo(cval(2), 1e-10)), isTrue);
      final lin = solveCubic(Complex.zero, Complex.zero, cval(2), cval(-6));
      expect(lin, hasLength(1));
      expect(lin.single.closeTo(cval(3), 1e-10), isTrue);
      expect(solveCubic(Complex.zero, Complex.zero, Complex.zero, cval(1)),
          isEmpty);
    });

    test('double root at reduced accuracy', () {
      // (λ−1)²(λ−2) = λ³ − 4λ² + 5λ − 2
      final roots = solveCubic(cval(1), cval(-4), cval(5), cval(-2));
      expect(roots, hasLength(3));
      expect(roots.where((r) => r.closeTo(cval(1), 1e-6)), hasLength(2));
      expect(roots.where((r) => r.closeTo(cval(2), 1e-9)), hasLength(1));
    });

    test('triple root', () {
      // (λ−1)³ = λ³ − 3λ² + 3λ − 1
      final roots = solveCubic(cval(1), cval(-3), cval(3), cval(-1));
      expect(roots, hasLength(3));
      for (final r in roots) {
        expect(r.closeTo(cval(1), 1e-4), isTrue, reason: '$r');
      }
    });

    Glados3(any.gridComplex, any.gridComplex, any.gridComplex)
        .test('reconstructs grid roots from Vieta coefficients', (r1, r2, r3) {
      final c2 = -(r1 + r2 + r3);
      final c1 = r1 * r2 + r1 * r3 + r2 * r3;
      final c0 = -(r1 * r2 * r3);
      final roots = solveCubic(Complex.one, c2, c1, c0);
      expect(roots, hasLength(3));
      for (final expected in [r1, r2, r3]) {
        expect(
          roots.any((r) => r.closeTo(expected, 1e-5)),
          isTrue,
          reason: 'missing root $expected in $roots',
        );
      }
    });
  });

  group('splitDegenerateConic', () {
    test('splits a known real line pair', () {
      final g = circleLift([1, 2, 3]);
      final h = circleLift([-1, 0, 1]);
      final c = [
        for (var i = 0; i < 3; i++)
          [for (var j = 0; j < 3; j++) g[i] * h[j] + h[i] * g[j]],
      ];
      final (s1, s2) = splitDegenerateConic(c);
      final direct = sameLine(s1, g) && sameLine(s2, h);
      final swapped = sameLine(s1, h) && sameLine(s2, g);
      expect(direct || swapped, isTrue, reason: 'got $s1, $s2');
    });

    test('rank-1 double line', () {
      final g = circleLift([2, -1, 4]);
      final c = [
        for (var i = 0; i < 3; i++)
          [for (var j = 0; j < 3; j++) g[i] * g[j]],
      ];
      final (s1, s2) = splitDegenerateConic(c);
      expect(sameLine(s1, g), isTrue);
      expect(sameLine(s2, g), isTrue);
    });

    Glados2(any.gridComplex, any.gridComplex)
        .test('recovers random complex line pairs', (za, zb) {
      // Two lines built from the generated numbers, kept independent.
      final g = [za, zb, Complex.one];
      final h = [zb + Complex.one, -za, Complex.i];
      if (vecNorm2(crossVec(g, h)) < 1e-6) return;
      final c = [
        for (var i = 0; i < 3; i++)
          [for (var j = 0; j < 3; j++) g[i] * h[j] + h[i] * g[j]],
      ];
      final (s1, s2) = splitDegenerateConic(c);
      final direct = sameLine(s1, g) && sameLine(s2, h);
      final swapped = sameLine(s1, h) && sameLine(s2, g);
      expect(direct || swapped, isTrue);
    });
  });

  group('intersectLineConic', () {
    final unitCircle = circleConic(CircleEq(Vec2.zero, 1));

    test('transverse chord', () {
      final pts = intersectLineConic(circleLift([0, 1, 0]), unitCircle);
      expect(pts, hasLength(2));
      expect(distanceToClosest(pts, const Vec2(1, 0)), lessThan(1e-12));
      expect(distanceToClosest(pts, const Vec2(-1, 0)), lessThan(1e-12));
    });

    test('tangent line yields a double point', () {
      final pts = intersectLineConic(circleLift([1, 0, -1]), unitCircle);
      for (final p in pts) {
        expect(projectReal(p), isNotNull);
        expect(projectReal(p)!.distanceTo(const Vec2(1, 0)), lessThan(1e-7));
      }
    });

    test('missing line yields a conjugate pair', () {
      final pts = intersectLineConic(circleLift([1, 0, -2]), unitCircle);
      // x = 2, y = ±i√3: non-real, so no real projection.
      for (final p in pts) {
        expect(projectReal(p), isNull);
        expect(residualOn(unitCircle, p), lessThan(1e-12));
      }
    });

    Glados2(any.lineEq, any.circleEq)
        .test('agrees with V1 intersectLineCircle positions', (l, c) {
      final margin = 1e-3 * (1 + c.radius);
      if ((l.distanceTo(c.center) - c.radius).abs() < margin) return;
      final conic = circleConic(c);
      final line = circleLift([l.a, l.b, l.c]);
      final pts = intersectLineConic(line, conic);
      expect(pts, hasLength(2));
      final v1 = intersectLineCircle(l, c);
      final tol = 1e-6 * (1 + c.center.norm + c.radius);
      if (v1.length == 2) {
        for (final expected in v1) {
          expect(distanceToClosest(pts, expected), lessThan(tol),
              reason: 'line $l circle $c: $pts vs $v1');
        }
      } else {
        // Miss: neither point may be a real point near the circle.
        for (final p in pts) {
          final v = projectReal(p);
          if (v != null) {
            expect(c.distanceTo(v), greaterThan(margin / 2));
          }
        }
      }
      for (final p in pts) {
        expect(residualOn(conic, p), lessThan(1e-9));
      }
    });
  });

  group('intersectConicsPencil on circles', () {
    test('transverse circles: two real points plus I and J', () {
      final a = circleConic(CircleEq(Vec2.zero, math.sqrt(2)));
      final b = circleConic(CircleEq(const Vec2(2, 0), math.sqrt(2)));
      final pts = intersectConicsPencil(a, b);
      expect(pts, hasLength(4));
      expect(pts.where(isCircular), hasLength(2));
      expect(distanceToClosest(pts, const Vec2(1, 1)), lessThan(1e-10));
      expect(distanceToClosest(pts, const Vec2(1, -1)), lessThan(1e-10));
    });

    test('externally tangent circles: doubled tangency point', () {
      final a = circleConic(CircleEq(Vec2.zero, 1));
      final b = circleConic(CircleEq(const Vec2(2, 0), 1));
      final pts = intersectConicsPencil(a, b);
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
      final a = circleConic(CircleEq(Vec2.zero, 1));
      final b = circleConic(CircleEq(Vec2.zero, 2));
      final pts = intersectConicsPencil(a, b);
      expect(pts, hasLength(4));
      for (final p in pts) {
        final n = normalizeVec(p);
        final toI = vecNorm2(crossVec(n, pointI));
        final toJ = vecNorm2(crossVec(n, pointJ));
        expect(math.min(toI, toJ), lessThan(1e-14));
      }
    });

    Glados2(any.circleEq, any.circleEq)
        .test('agrees with V1 intersectCircleCircle', (c1, c2) {
      final d = c1.center.distanceTo(c2.center);
      final scale = 1 + c1.radius + c2.radius;
      final margin = 1e-3 * scale;
      // Stay away from V1's classification boundaries.
      if (d < margin ||
          (d - (c1.radius + c2.radius)).abs() < margin ||
          (d - (c1.radius - c2.radius).abs()).abs() < margin) {
        return;
      }
      final a = circleConic(c1);
      final b = circleConic(c2);
      final pts = intersectConicsPencil(a, b);
      expect(pts, hasLength(4));
      expect(pts.where(isCircular), hasLength(2),
          reason: 'circles $c1 $c2 → $pts');
      final v1 = intersectCircleCircle(c1, c2);
      final tol = 1e-6 * (1 + c1.center.norm + scale);
      if (v1.length == 2) {
        for (final expected in v1) {
          expect(distanceToClosest(pts, expected), lessThan(tol),
              reason: 'circles $c1 $c2: $pts vs $v1');
        }
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
    });
  });

  group('conics through shared points', () {
    Glados(any.sixPoints).test(
        'pencil roots contain the four shared points', (raw) {
      final shared = raw.sublist(0, 4);
      // Distinctness of the shared points.
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          if (shared[i].distanceTo(shared[j]) < 0.1) return;
        }
      }
      final coeffsA = conicThroughFivePoints([...shared, raw[4]]);
      final coeffsB = conicThroughFivePoints([...shared, raw[5]]);
      if (coeffsA == null || coeffsB == null) return;
      final a = conicFromCoeffs(coeffsA);
      final b = conicFromCoeffs(coeffsB);
      // Skip degenerate or near-degenerate conics; the glados corpus is for
      // the generic path (degeneracies are unit-tested).
      if (det3(normalizeConic(a)).abs < 1e-4 ||
          det3(normalizeConic(b)).abs < 1e-4) {
        return;
      }
      final pts = intersectConicsPencil(a, b);
      expect(pts, hasLength(4));
      for (final s in shared) {
        expect(distanceToClosest(pts, s), lessThan(1e-5),
            reason: 'shared $s not among $pts');
      }
    });
  });

  group('random real conic incidence', () {
    Glados2(any.realConic, any.realConic)
        .test('all four roots lie on both conics', (a, b) {
      if (det3(normalizeConic(a)).abs < 1e-2 ||
          det3(normalizeConic(b)).abs < 1e-2) {
        return;
      }
      final pts = intersectConicsPencil(a, b);
      expect(pts, hasLength(4));
      for (final p in pts) {
        expect(residualOn(a, p), lessThan(1e-8),
            reason: 'point $p off conic A');
        expect(residualOn(b, p), lessThan(1e-8),
            reason: 'point $p off conic B');
      }
    });
  });

  group('stress corpus regression (bounds from benchmark/pencil_stress.dart)',
      () {
    test('near-tangent circles down to ε = 1e-12', () {
      for (var e = 3; e <= 12; e++) {
        final eps = math.pow(10.0, -e).toDouble();
        final d = 2 - eps;
        final a = circleConic(CircleEq(Vec2.zero, 1));
        final b = circleConic(CircleEq(Vec2(d, 0), 1));
        final pts = intersectConicsPencil(a, b);
        final ex = d / 2;
        final ey = math.sqrt(math.max(0, 1 - ex * ex));
        // Measured: incidence ≤ 2e-16, point error ≤ 1.2e-11; ×100 margin.
        expect(distanceToClosest(pts, Vec2(ex, ey)), lessThan(1e-9),
            reason: 'eps 1e-$e');
        for (final p in pts) {
          expect(residualOn(a, p), lessThan(1e-13), reason: 'eps 1e-$e');
        }
      }
    });

    test('just-missing circles produce the conjugate pair, |Im| ≈ sqrt(ε)',
        () {
      for (var e = 4; e <= 12; e += 2) {
        final eps = math.pow(10.0, -e).toDouble();
        final a = circleConic(CircleEq(Vec2.zero, 1));
        final b = circleConic(CircleEq(Vec2(2 + eps, 0), 1));
        final pts = intersectConicsPencil(a, b);
        final finite = pts.where((p) => !isCircular(p)).toList();
        expect(finite, hasLength(2), reason: 'eps 1e-$e');
        for (final p in finite) {
          final n = normalizeVec(p);
          final im = (n[1] / n[2]).im.abs();
          // |y| = sqrt(ε + ε²/4) ≈ sqrt(ε); allow a factor-2 band.
          expect(im, greaterThan(math.sqrt(eps) / 2), reason: 'eps 1e-$e');
          expect(im, lessThan(2 * math.sqrt(eps)), reason: 'eps 1e-$e');
          expect(residualOn(a, p), lessThan(1e-13), reason: 'eps 1e-$e');
        }
      }
    });

    test('nearly identical circles stay accurate through the near-triple root',
        () {
      for (var e = 3; e <= 12; e++) {
        final delta = math.pow(10.0, -e).toDouble();
        final a = circleConic(CircleEq(Vec2.zero, 1));
        final b = circleConic(CircleEq(Vec2(delta, 0), 1));
        final pts = intersectConicsPencil(a, b);
        // Measured: incidence ≤ 8e-11, point error ≤ 1.7e-7; ×100 margin.
        final expected = Vec2(delta / 2, math.sqrt(1 - delta * delta / 4));
        expect(distanceToClosest(pts, expected), lessThan(1e-4),
            reason: 'delta 1e-$e');
        for (final p in pts) {
          expect(residualOn(a, p), lessThan(1e-8), reason: 'delta 1e-$e');
        }
      }
    });

    test('scale extremes are exact after balancing', () {
      for (var k = -8; k <= 8; k += 2) {
        final s = math.pow(10.0, k).toDouble();
        final a = circleConic(CircleEq(Vec2.zero, s));
        final b = circleConic(CircleEq(Vec2(s, 0), s));
        final pts = intersectConicsPencil(a, b);
        // Measured: relative point error ≤ 2.2e-16; ×~10⁴ margin.
        final expected = Vec2(s / 2, s * math.sqrt(3) / 2);
        expect(distanceToClosest(pts, expected) / s, lessThan(1e-12),
            reason: 'scale 1e$k');
      }
    });

    test('far-offset circles: translation gap bounded as measured', () {
      // Measured errors grow ~quadratically with the offset (digits eaten by
      // the coordinate offset — the documented Phase 105 limitation):
      // 1e2 → 8.5e-13, 1e4 → 8.6e-9, 1e6 → 2.9e-5 (at 1e6 the imaginary
      // contamination already exceeds projectReal's realness tolerance, so
      // only the first two offsets are pinned). Order-of-magnitude bounds so
      // an accidental regression (or a fix) surfaces here.
      final bounds = {2: 1e-10, 4: 1e-6};
      for (final entry in bounds.entries) {
        final off = math.pow(10.0, entry.key).toDouble();
        final a = circleConic(CircleEq(Vec2(off, 0), 1));
        final b = circleConic(CircleEq(Vec2(off + 1, 0), 1));
        final pts = intersectConicsPencil(a, b);
        final expected = Vec2(off + 0.5, math.sqrt(3) / 2);
        expect(distanceToClosest(pts, expected), lessThan(entry.value),
            reason: 'offset 1e${entry.key}');
      }
    });
  });
}
