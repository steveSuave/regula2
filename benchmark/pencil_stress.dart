// Stress corpus for conic∩conic (Phase 102 prototype, re-pointed at the
// Phase 105 production `intersectConicConic`). Prints measured error bounds;
// the numbers land in STATUS and inform the tolerances pinned in
// test/domain/projective/conic_intersection_test.dart.
//
// Run: dart run benchmark/pencil_stress.dart
//
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_intersection.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_point.dart';

ConicMatrix circleConic(double cx, double cy, double r) =>
    ConicMatrix.lift(CircleEq(Vec2(cx, cy), r));

/// Max |xᵀMx| over the returned points against unit-Frobenius [m], with the
/// point normalized — a scale-free incidence residual.
double incidenceResidual(List<ProjPoint> points, ConicMatrix m) {
  final n = m.scaledBy(Complex(1 / math.sqrt(m.norm2)));
  var worst = 0.0;
  for (final p in points) {
    final x = p.normalized;
    worst = math.max(worst, n.evaluate(x).abs / x.norm2);
  }
  return worst;
}

/// Distance in the affine chart from the closest returned point to (x, y).
double closestAffineError(List<ProjPoint> points, double x, double y) {
  var best = double.infinity;
  for (final p in points) {
    final n = p.normalized;
    if (n.w.abs < 1e-9) continue;
    final dx = n.x / n.w - Complex(x);
    final dy = n.y / n.w - Complex(y);
    best = math.min(best, math.sqrt(dx.abs2 + dy.abs2));
  }
  return best;
}

void main() {
  print(
    '--- near-tangent circles: r=1 at d = 2 − ε (real pair ~sqrt(ε) apart) ---',
  );
  print(
    'eps        incidence   point-error   (expected points (d/2, ±sqrt(1−d²/4)))',
  );
  for (var e = 3; e <= 12; e++) {
    final eps = math.pow(10.0, -e).toDouble();
    final d = 2 - eps;
    final a = circleConic(0, 0, 1);
    final b = circleConic(d, 0, 1);
    final pts = intersectConicConic(a, b);
    final ex = d / 2;
    final ey = math.sqrt(math.max(0, 1 - ex * ex));
    final err = math.max(
      closestAffineError(pts, ex, ey),
      closestAffineError(pts, ex, -ey),
    );
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    print(
      '1e-$e'.padRight(11) +
          res.toStringAsExponential(1).padRight(12) +
          err.toStringAsExponential(1),
    );
  }

  print('--- just-missing circles: r=1 at d = 2 + ε (conjugate pair) ---');
  print('eps        incidence   |Im| of pair');
  for (var e = 3; e <= 12; e++) {
    final eps = math.pow(10.0, -e).toDouble();
    final d = 2 + eps;
    final a = circleConic(0, 0, 1);
    final b = circleConic(d, 0, 1);
    final pts = intersectConicConic(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    var maxIm = 0.0;
    for (final p in pts) {
      final n = p.normalized;
      if (n.w.abs < 1e-9) continue;
      maxIm = math.max(maxIm, (n.y / n.w).im.abs());
    }
    print(
      '1e-$e'.padRight(11) +
          res.toStringAsExponential(1).padRight(12) +
          maxIm.toStringAsExponential(1),
    );
  }

  print('--- nearly identical circles: r=1, centers δ apart ---');
  print('delta      incidence   point-error');
  for (var e = 3; e <= 12; e++) {
    final delta = math.pow(10.0, -e).toDouble();
    final a = circleConic(0, 0, 1);
    final b = circleConic(delta, 0, 1);
    final pts = intersectConicConic(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    // True finite intersections: x = δ/2, y = ±sqrt(1 − δ²/4) ≈ ±1.
    final err = closestAffineError(
      pts,
      delta / 2,
      math.sqrt(1 - delta * delta / 4),
    );
    print(
      '1e-$e'.padRight(11) +
          res.toStringAsExponential(1).padRight(12) +
          err.toStringAsExponential(1),
    );
  }

  print('--- scale extremes: transverse circle pairs at radius 10^k ---');
  print('scale      incidence   rel-point-error');
  for (var k = -8; k <= 8; k += 2) {
    final s = math.pow(10.0, k).toDouble();
    // Unit-circle picture scaled by s: centers (0,0),(s,0), r=s → meet at
    // s·(1/2, ±sqrt(3)/2).
    final a = circleConic(0, 0, s);
    final b = circleConic(s, 0, s);
    final pts = intersectConicConic(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    final err = closestAffineError(pts, s / 2, s * math.sqrt(3) / 2) / s;
    print(
      '1e$k'.padRight(11) +
          res.toStringAsExponential(1).padRight(12) +
          err.toStringAsExponential(1),
    );
  }

  print('--- far-offset unit circles: centers near (10^k, 0), transverse ---');
  print('offset     incidence   point-error   (translation balancing)');
  for (var k = 0; k <= 8; k += 2) {
    final off = math.pow(10.0, k).toDouble();
    final a = circleConic(off, 0, 1);
    final b = circleConic(off + 1, 0, 1);
    final pts = intersectConicConic(a, b);
    final res = math.max(incidenceResidual(pts, a), incidenceResidual(pts, b));
    final err = math.max(
      closestAffineError(pts, off + 0.5, math.sqrt(3) / 2),
      closestAffineError(pts, off + 0.5, -math.sqrt(3) / 2),
    );
    print(
      '1e$k'.padRight(11) +
          res.toStringAsExponential(1).padRight(12) +
          err.toStringAsExponential(1),
    );
  }

  print('--- concentric circles (all four points at I, J) ---');
  final pts = intersectConicConic(circleConic(0, 0, 1), circleConic(0, 0, 2));
  for (final p in pts) {
    final n = p.normalized;
    final toI = n.join(circularPointI).norm2;
    final toJ = n.join(circularPointJ).norm2;
    print(
      '  point $n  '
      'dist²(I)=${toI.toStringAsExponential(1)} dist²(J)=${toJ.toStringAsExponential(1)}',
    );
  }
}
