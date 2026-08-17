// Phase 101 SPIKE 1: complex-arithmetic throughput, boxed vs SoA.
//
// Measures tracing-shaped workloads — quadratic and cubic root solving in a
// tight loop with pseudo-random complex coefficients — in three styles:
//
//   boxed    allocating `Complex` objects (the domain API type)
//   records  helper functions returning `(double, double)` records
//   soa      fully inlined scalar double math (Float64List-compatible shape:
//            every value is a pair of local doubles, no allocation)
//
// Run on VM (`dart run`), AOT (`dart compile exe`), dart2js and dart2wasm via
// `benchmark/run_all.sh`. Checksums must agree across styles (same formulas),
// which doubles as a correctness cross-check of the inlined math.
//
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:regula/domain/projective/complex.dart';

const quadraticIterations = 500000;
const cubicIterations = 200000;

// ---------------------------------------------------------------------------
// Pseudo-random coefficient stream: 32-bit LCG mapped to [-2, 2).
// Identical across variants so checksums are comparable.
// ---------------------------------------------------------------------------

const _lcgA = 1664525;
const _lcgC = 1013904223;
const _lcgMask = 0xFFFFFFFF;

int _nextSeed(int seed) => (seed * _lcgA + _lcgC) & _lcgMask;

double _toCoeff(int seed) => seed * (4.0 / 4294967296.0) - 2.0;

// ---------------------------------------------------------------------------
// Quadratic: roots of a·z² + b·z + c = 0 via (-b ± sqrt(b² − 4ac)) · (2a)⁻¹.
// ---------------------------------------------------------------------------

double quadraticBoxed(int n) {
  var seed = 42;
  var acc = 0.0;
  for (var iter = 0; iter < n; iter++) {
    seed = _nextSeed(seed);
    final ar = _toCoeff(seed);
    seed = _nextSeed(seed);
    final ai = _toCoeff(seed);
    seed = _nextSeed(seed);
    final br = _toCoeff(seed);
    seed = _nextSeed(seed);
    final bi = _toCoeff(seed);
    seed = _nextSeed(seed);
    final cr = _toCoeff(seed);
    seed = _nextSeed(seed);
    final ci = _toCoeff(seed);

    final a = Complex(ar, ai);
    final b = Complex(br, bi);
    final c = Complex(cr, ci);
    final s = (b * b - (a * c).scale(4)).sqrt;
    final invA2 = Complex.one / a.scale(2);
    final r1 = (-b + s) * invA2;
    final r2 = (-b - s) * invA2;
    acc += r1.re + r1.im + r2.re + r2.im;
  }
  return acc;
}

(double, double) _rMul(double ar, double ai, double br, double bi) =>
    (ar * br - ai * bi, ar * bi + ai * br);

(double, double) _rSqrt(double zr, double zi) {
  if (zr == 0 && zi == 0) return (0, 0);
  final mag = math.sqrt(zr * zr + zi * zi);
  final t = math.sqrt((mag + zr.abs()) / 2);
  if (zr >= 0) return (t, zi / (2 * t));
  return (zi.abs() / (2 * t), zi >= 0 ? t : -t);
}

(double, double) _rDiv(double ar, double ai, double br, double bi) {
  if (br.abs() >= bi.abs()) {
    final r = bi / br;
    final d = br + bi * r;
    return ((ar + ai * r) / d, (ai - ar * r) / d);
  } else {
    final r = br / bi;
    final d = br * r + bi;
    return ((ar * r + ai) / d, (ai * r - ar) / d);
  }
}

double quadraticRecords(int n) {
  var seed = 42;
  var acc = 0.0;
  for (var iter = 0; iter < n; iter++) {
    seed = _nextSeed(seed);
    final ar = _toCoeff(seed);
    seed = _nextSeed(seed);
    final ai = _toCoeff(seed);
    seed = _nextSeed(seed);
    final br = _toCoeff(seed);
    seed = _nextSeed(seed);
    final bi = _toCoeff(seed);
    seed = _nextSeed(seed);
    final cr = _toCoeff(seed);
    seed = _nextSeed(seed);
    final ci = _toCoeff(seed);

    final (b2r, b2i) = _rMul(br, bi, br, bi);
    final (acr, aci) = _rMul(ar, ai, cr, ci);
    final (sr, si) = _rSqrt(b2r - 4 * acr, b2i - 4 * aci);
    final (ivr, ivi) = _rDiv(1, 0, 2 * ar, 2 * ai);
    final (r1r, r1i) = _rMul(-br + sr, -bi + si, ivr, ivi);
    final (r2r, r2i) = _rMul(-br - sr, -bi - si, ivr, ivi);
    acc += r1r + r1i + r2r + r2i;
  }
  return acc;
}

double quadraticSoa(int n) {
  var seed = 42;
  var acc = 0.0;
  for (var iter = 0; iter < n; iter++) {
    seed = _nextSeed(seed);
    final ar = _toCoeff(seed);
    seed = _nextSeed(seed);
    final ai = _toCoeff(seed);
    seed = _nextSeed(seed);
    final br = _toCoeff(seed);
    seed = _nextSeed(seed);
    final bi = _toCoeff(seed);
    seed = _nextSeed(seed);
    final cr = _toCoeff(seed);
    seed = _nextSeed(seed);
    final ci = _toCoeff(seed);

    // disc = b² − 4ac
    final dr = br * br - bi * bi - 4 * (ar * cr - ai * ci);
    final di = 2 * br * bi - 4 * (ar * ci + ai * cr);
    // s = principal sqrt(disc)
    final mag = math.sqrt(dr * dr + di * di);
    final t = math.sqrt((mag + dr.abs()) / 2);
    final double sr;
    final double si;
    if (dr >= 0) {
      sr = t;
      si = di / (2 * t);
    } else {
      sr = di.abs() / (2 * t);
      si = di >= 0 ? t : -t;
    }
    // inv = 1 / (2a), Smith
    final b2r = 2 * ar, b2i = 2 * ai;
    final double ivr;
    final double ivi;
    if (b2r.abs() >= b2i.abs()) {
      final r = b2i / b2r;
      final d = b2r + b2i * r;
      ivr = 1 / d;
      ivi = -r / d;
    } else {
      final r = b2r / b2i;
      final d = b2r * r + b2i;
      ivr = r / d;
      ivi = -1 / d;
    }
    final n1r = -br + sr, n1i = -bi + si;
    final n2r = -br - sr, n2i = -bi - si;
    final r1r = n1r * ivr - n1i * ivi, r1i = n1r * ivi + n1i * ivr;
    final r2r = n2r * ivr - n2i * ivi, r2i = n2r * ivi + n2i * ivr;
    acc += r1r + r1i + r2r + r2i;
  }
  return acc;
}

// ---------------------------------------------------------------------------
// Cubic: all three roots of z³ + a2·z² + a1·z + a0 = 0 by Cardano:
// depress to t³ + pt + q, u³ = −q/2 + sqrt((q/2)² + (p/3)³),
// t_k = ω^k·u − p/(3·ω^k·u), z_k = t_k − a2/3.
// ---------------------------------------------------------------------------

final Complex _omega = Complex(-0.5, math.sqrt(3) / 2);

Complex _cbrt(Complex z) {
  final m = z.abs;
  if (m == 0) return Complex.zero;
  return Complex.polar(math.exp(math.log(m) / 3), z.arg / 3);
}

double cubicBoxed(int n) {
  var seed = 7;
  var acc = 0.0;
  for (var iter = 0; iter < n; iter++) {
    seed = _nextSeed(seed);
    final a2r = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a2i = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a1r = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a1i = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a0r = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a0i = _toCoeff(seed);

    final a2 = Complex(a2r, a2i);
    final a1 = Complex(a1r, a1i);
    final a0 = Complex(a0r, a0i);

    final p = a1 - (a2 * a2).scale(1 / 3);
    final q = (a2 * a2 * a2).scale(2 / 27) - (a2 * a1).scale(1 / 3) + a0;
    final hq = q.scale(0.5);
    final p3 = p.scale(1 / 3);
    final s = (hq * hq + p3 * p3 * p3).sqrt;
    var u = _cbrt(-hq + s);
    if (u.abs2 < 1e-30) u = _cbrt(-hq - s);
    final shift = a2.scale(1 / 3);
    var w = u;
    for (var k = 0; k < 3; k++) {
      final root = w - p3 / w - shift;
      acc += root.re + root.im;
      w = w * _omega;
    }
  }
  return acc;
}

final double _omegaR = -0.5;
final double _omegaI = math.sqrt(3) / 2;

double cubicSoa(int n) {
  var seed = 7;
  var acc = 0.0;
  final omr = _omegaR, omi = _omegaI;
  for (var iter = 0; iter < n; iter++) {
    seed = _nextSeed(seed);
    final a2r = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a2i = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a1r = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a1i = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a0r = _toCoeff(seed);
    seed = _nextSeed(seed);
    final a0i = _toCoeff(seed);

    // p = a1 − a2²/3
    final a2sr = a2r * a2r - a2i * a2i, a2si = 2 * a2r * a2i;
    final pr = a1r - a2sr / 3, pi = a1i - a2si / 3;
    // q = (2/27)·a2³ − a2·a1/3 + a0
    final a2cr = a2sr * a2r - a2si * a2i, a2ci = a2sr * a2i + a2si * a2r;
    final qr = a2cr * (2 / 27) - (a2r * a1r - a2i * a1i) / 3 + a0r;
    final qi = a2ci * (2 / 27) - (a2r * a1i + a2i * a1r) / 3 + a0i;
    final hqr = qr / 2, hqi = qi / 2;
    final p3r = pr / 3, p3i = pi / 3;
    // rad = (q/2)² + (p/3)³
    final p3sr = p3r * p3r - p3i * p3i, p3si = 2 * p3r * p3i;
    final radR = hqr * hqr - hqi * hqi + p3sr * p3r - p3si * p3i;
    final radI = 2 * hqr * hqi + p3sr * p3i + p3si * p3r;
    // s = principal sqrt(rad)
    final mag = math.sqrt(radR * radR + radI * radI);
    final t = math.sqrt((mag + radR.abs()) / 2);
    final double sr;
    final double si;
    if (radR >= 0) {
      sr = t;
      si = radI / (2 * t);
    } else {
      sr = radI.abs() / (2 * t);
      si = radI >= 0 ? t : -t;
    }
    // u = cbrt(−q/2 + s), fall back to the other root of the resolvent
    var unr = -hqr + sr, uni = -hqi + si;
    if (unr * unr + uni * uni < 1e-30) {
      unr = -hqr - sr;
      uni = -hqi - si;
    }
    final um = math.sqrt(unr * unr + uni * uni);
    final ucb = math.exp(math.log(um) / 3);
    final uth = math.atan2(uni, unr) / 3;
    var wr = ucb * math.cos(uth), wi = ucb * math.sin(uth);
    final shr = a2r / 3, shi = a2i / 3;
    for (var k = 0; k < 3; k++) {
      // t_k = w − (p/3)/w, via Smith division
      final double dvr;
      final double dvi;
      if (wr.abs() >= wi.abs()) {
        final r = wi / wr;
        final d = wr + wi * r;
        dvr = (p3r + p3i * r) / d;
        dvi = (p3i - p3r * r) / d;
      } else {
        final r = wr / wi;
        final d = wr * r + wi;
        dvr = (p3r * r + p3i) / d;
        dvi = (p3i * r - p3r) / d;
      }
      acc += (wr - dvr - shr) + (wi - dvi - shi);
      final nwr = wr * omr - wi * omi;
      wi = wr * omi + wi * omr;
      wr = nwr;
    }
  }
  return acc;
}

// ---------------------------------------------------------------------------
// Harness: warmup ×2, best of 5 measured runs, ns per solve.
// ---------------------------------------------------------------------------

final _results = <String, double>{};

double _bench(String name, int n, double Function(int) body) {
  var checksum = 0.0;
  for (var w = 0; w < 2; w++) {
    checksum = body(n);
  }
  var bestUs = double.infinity;
  final sw = Stopwatch();
  for (var run = 0; run < 5; run++) {
    sw
      ..reset()
      ..start();
    checksum = body(n);
    sw.stop();
    final us = sw.elapsedMicroseconds.toDouble();
    if (us < bestUs) bestUs = us;
  }
  final nsPerOp = bestUs * 1000 / n;
  print(
    '${name.padRight(18)} ${nsPerOp.toStringAsFixed(1).padLeft(8)} ns/solve'
    '   (checksum ${checksum.toStringAsFixed(6)})',
  );
  _results[name] = checksum;
  return nsPerOp;
}

void _crossCheck(String a, String b) {
  final da = _results[a]!, db = _results[b]!;
  if ((da - db).abs() > 1e-5 * math.max(1, da.abs())) {
    print('WARN: checksum mismatch $a vs $b: $da vs $db');
  }
}

void main(List<String> args) {
  final scale = args.isEmpty ? 1 : int.parse(args.first);
  final qn = quadraticIterations * scale;
  final cn = cubicIterations * scale;

  print('quadratic ($qn iterations):');
  final qBoxed = _bench('  boxed', qn, quadraticBoxed);
  final qRecords = _bench('  records', qn, quadraticRecords);
  final qSoa = _bench('  soa', qn, quadraticSoa);
  _crossCheck('  boxed', '  records');
  _crossCheck('  boxed', '  soa');

  print('cubic ($cn iterations):');
  final cBoxed = _bench('  boxed', cn, cubicBoxed);
  final cSoa = _bench('  soa', cn, cubicSoa);
  _crossCheck('  boxed', '  soa');

  print(
    'speedups vs boxed: quad records ${(qBoxed / qRecords).toStringAsFixed(2)}x,'
    ' quad soa ${(qBoxed / qSoa).toStringAsFixed(2)}x,'
    ' cubic soa ${(cBoxed / cSoa).toStringAsFixed(2)}x',
  );
}
