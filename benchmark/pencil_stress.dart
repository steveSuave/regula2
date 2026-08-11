// Phase 102 SPIKE 2: stress corpus for the conic∩conic pencil prototype.
// Prints measured error bounds; the numbers land in STATUS and inform the
// tolerances pinned in test/domain/projective/pencil_test.dart.
//
// Run: dart run benchmark/pencil_stress.dart
//
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/pencil.dart';

CMat3 circleConic(double cx, double cy, double r) => [
      [const Complex(1), Complex.zero, Complex(-cx)],
      [Complex.zero, const Complex(1), Complex(-cy)],
      [Complex(-cx), Complex(-cy), Complex(cx * cx + cy * cy - r * r)],
    ];

/// Max |xᵀMx| over the returned points against unit-Frobenius [m], with the
/// point normalized — a scale-free incidence residual.
double incidenceResidual(List<CVec3> points, CMat3 m) {
  final n = normalizeConic(m);
  var worst = 0.0;
  for (final p in points) {
    final x = normalizeVec(p);
    worst = math.max(worst, quadForm(n, x).abs / vecNorm2(x));
  }
  return worst;
}

/// Distance in the affine chart from the closest returned point to (x, y).
double closestAffineError(List<CVec3> points, double x, double y) {
  var best = double.infinity;
  for (final p in points) {
    if (p[2].abs < 1e-9) continue;
    final px = p[0] / p[2];
    final py = p[1] / p[2];
    final dx = px - Complex(x);
    final dy = py - Complex(y);
    best = math.min(best, math.sqrt(dx.abs2 + dy.abs2));
  }
  return best;
}

void main() {
  print('--- near-tangent circles: r=1 at d = 2 − ε (real pair ~sqrt(ε) apart) ---');
  print('eps        incidence   point-error   (expected points (d/2, ±sqrt(1−d²/4)))');
  for (var e = 3; e <= 12; e++) {
    final eps = math.pow(10.0, -e).toDouble();
    final d = 2 - eps;
    final a = circleConic(0, 0, 1);
    final b = circleConic(d, 0, 1);
    final pts = intersectConicsPencil(a, b);
    final ex = d / 2;
    final ey = math.sqrt(math.max(0, 1 - ex * ex));
    final err = math.max(
      closestAffineError(pts, ex, ey),
      closestAffineError(pts, ex, -ey),
    );
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    print('1e-$e'.padRight(11) +
        res.toStringAsExponential(1).padRight(12) +
        err.toStringAsExponential(1));
  }

  print('--- just-missing circles: r=1 at d = 2 + ε (conjugate pair) ---');
  print('eps        incidence   |Im| of pair');
  for (var e = 3; e <= 12; e++) {
    final eps = math.pow(10.0, -e).toDouble();
    final d = 2 + eps;
    final a = circleConic(0, 0, 1);
    final b = circleConic(d, 0, 1);
    final pts = intersectConicsPencil(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    var maxIm = 0.0;
    for (final p in pts) {
      if (p[2].abs < 1e-9) continue;
      maxIm = math.max(maxIm, (p[1] / p[2]).im.abs());
    }
    print('1e-$e'.padRight(11) +
        res.toStringAsExponential(1).padRight(12) +
        maxIm.toStringAsExponential(1));
  }

  print('--- nearly identical circles: r=1, centers δ apart ---');
  print('delta      incidence');
  for (var e = 3; e <= 12; e++) {
    final delta = math.pow(10.0, -e).toDouble();
    final a = circleConic(0, 0, 1);
    final b = circleConic(delta, 0, 1);
    final pts = intersectConicsPencil(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    // True finite intersections: x = δ/2, y = ±sqrt(1 − δ²/4) ≈ ±1.
    final err = closestAffineError(pts, delta / 2, math.sqrt(1 - delta * delta / 4));
    print('1e-$e'.padRight(11) +
        res.toStringAsExponential(1).padRight(12) +
        err.toStringAsExponential(1));
  }

  print('--- scale extremes: transverse circle pairs at radius 10^k ---');
  print('scale      incidence   rel-point-error');
  for (var k = -8; k <= 8; k += 2) {
    final s = math.pow(10.0, k).toDouble();
    // Unit-circle picture scaled by s: centers (0,0),(s,0), r=s → meet at
    // s·(1/2, ±sqrt(3)/2).
    final a = circleConic(0, 0, s);
    final b = circleConic(s, 0, s);
    final pts = intersectConicsPencil(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    final err = closestAffineError(pts, s / 2, s * math.sqrt(3) / 2) / s;
    print('1e$k'.padRight(11) +
        res.toStringAsExponential(1).padRight(12) +
        err.toStringAsExponential(1));
  }

  print('--- far-offset unit circles: centers near (10^k, 0), transverse ---');
  print('offset     incidence   point-error   (translation conditioning gap)');
  for (var k = 0; k <= 8; k += 2) {
    final off = math.pow(10.0, k).toDouble();
    final a = circleConic(off, 0, 1);
    final b = circleConic(off + 1, 0, 1);
    final pts = intersectConicsPencil(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    final err = math.max(
      closestAffineError(pts, off + 0.5, math.sqrt(3) / 2),
      closestAffineError(pts, off + 0.5, -math.sqrt(3) / 2),
    );
    print('1e$k'.padRight(11) +
        res.toStringAsExponential(1).padRight(12) +
        err.toStringAsExponential(1));
  }

  print('--- concentric circles (all four points at I, J) ---');
  final pts = intersectConicsPencil(circleConic(0, 0, 1), circleConic(0, 0, 2));
  for (final p in pts) {
    final n = normalizeVec(p);
    final toI = vecNorm2(crossVec(n, [Complex.one, Complex.i, Complex.zero]));
    final toJ = vecNorm2(crossVec(n, [Complex.one, -Complex.i, Complex.zero]));
    print('  point ${n.map((c) => c.toString()).join(', ')}  '
        'dist²(I)=${toI.toStringAsExponential(1)} dist²(J)=${toJ.toStringAsExponential(1)}');
  }
}

