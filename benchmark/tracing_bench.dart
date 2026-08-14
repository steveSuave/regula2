// Phase 113/114: tracing cost per drag frame.
//
// Builds the 100-object stress construction the Phase 116 performance gate
// is defined on (a dragged free point with everything downstream: a chain
// of 24 midpoints, each carrying a circle and both intersection branches
// with a baseline — 48 IntersectionPoints tracking roots), then measures:
//
//   static frame    one moveFreePoint solve — today's per-frame drag cost
//   traced frame    recomputeAlongPath under the Phase 114 adaptive step
//                   controller (whole-path first trial, halve on refusal)
//
// The gate is ≤ 8 ms kernel time per drag frame (PLAN, Phase 116). This
// harness runs the *boxed* engine — the SoA `Float64List` rewrite of the
// hot loop is Phase 122's tick — so these numbers are the ceiling the SoA
// pass later has to beat. On smooth frames the controller accepts the
// whole path in one trial, so the expected shape is a small multiple of
// the static solve (seeding + one matched recompute), not 16×.
//
// Run on VM (`dart run`), AOT, dart2js and dart2wasm via
// `benchmark/run_tracing.sh`. Keep this file Flutter-free (domain imports
// only) or the js/wasm targets break.
//
// ignore_for_file: avoid_print

import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';

const framesPerRun = 50;

/// 100 objects, everything downstream of the dragged point 'd': baseline
/// y = 0 through a/b, then 24 layers of midpoint → circle → two
/// intersection branches. Midpoints halve toward the axis, radii cycle
/// 3..9, so the branches are a mix of real and conjugate-complex roots —
/// both the solve and the matching run everywhere.
(Construction, IntersectionPoint) buildStress() {
  final construction = Construction();
  final a = FreePoint(id: 'a', position: const Vec2(-50, 0));
  final b = FreePoint(id: 'b', position: const Vec2(50, 0));
  final d = FreePoint(id: 'd', position: const Vec2(0, 30));
  final baseline = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
  construction
    ..add(a)
    ..add(b)
    ..add(d)
    ..add(baseline);
  GeoPoint prev = d;
  late IntersectionPoint deepest;
  for (var k = 0; k < 24; k++) {
    final m = Midpoint(id: 'm$k', point1: prev, point2: k.isEven ? a : b);
    final circle = FixedRadiusCircle(
      id: 'k$k',
      center: m,
      radius: 3.0 + (k % 7),
    );
    final i0 = IntersectionPoint(
      id: 'p${k}a',
      curve1: baseline,
      curve2: circle,
      branchIndex: 0,
    );
    deepest = IntersectionPoint(
      id: 'p${k}b',
      curve1: baseline,
      curve2: circle,
      branchIndex: 1,
    );
    construction
      ..add(m)
      ..add(circle)
      ..add(i0)
      ..add(deepest);
    prev = m;
  }
  assert(construction.length == 100, 'the gate is defined on 100 objects');
  return (construction, deepest);
}

double _probe(IntersectionPoint p) {
  final root = p.projPoint;
  if (root == null) return -1;
  return root.x.re + root.x.im + root.y.re + root.w.re;
}

/// [n] drag frames, each resolved statically (one solve at the frame's
/// end position — today's preview cost). The drag oscillates vertically
/// so every frame moves every object.
double staticFrames(int n) {
  final (construction, deepest) = buildStress();
  var acc = 0.0;
  for (var f = 0; f < n; f++) {
    final y = f.isEven ? 29.5 : 30.5;
    construction.moveFreePoint('d', Vec2(0, y));
    acc += _probe(deepest);
  }
  return acc;
}

/// Trials the traced run spent, for the trials-per-frame report.
var _acceptedTotal = 0;
var _rejectedTotal = 0;

/// [n] drag frames, each resolved through recomputeAlongPath under the
/// adaptive controller, with branch matching on all 48 slots.
double tracedFrames(int n) {
  final (construction, deepest) = buildStress();
  var from = const Vec2(0, 30);
  var acc = 0.0;
  _acceptedTotal = 0;
  _rejectedTotal = 0;
  for (var f = 0; f < n; f++) {
    final to = Vec2(0, f.isEven ? 29.5 : 30.5);
    final trials = construction.recomputeAlongPath('d', DragPath(from, to));
    _acceptedTotal += trials.acceptedSteps;
    _rejectedTotal += trials.rejectedSteps;
    from = to;
    acc += _probe(deepest);
  }
  return acc;
}

// Harness: warmup ×2, best of 5 measured runs, ms per drag frame.
final _checksums = <String, double>{};

double _bench(String name, int n, double Function(int) run) {
  run(n);
  run(n);
  var bestUs = double.infinity;
  final sw = Stopwatch();
  for (var i = 0; i < 5; i++) {
    sw
      ..reset()
      ..start();
    _checksums[name] = run(n);
    sw.stop();
    final us = sw.elapsedMicroseconds.toDouble();
    if (us < bestUs) bestUs = us;
  }
  final msPerFrame = bestUs / 1000 / n;
  print(
    '${name.padRight(18)} ${msPerFrame.toStringAsFixed(3).padLeft(8)} ms/frame'
    '   (checksum ${_checksums[name]!.toStringAsFixed(6)})',
  );
  return msPerFrame;
}

void main(List<String> args) {
  final scale = args.isEmpty ? 1 : int.parse(args.first);
  final n = framesPerRun * scale;

  print('drag frames on the 100-object stress construction ($n frames):');
  final staticMs = _bench('  static x1', n, staticFrames);
  final tracedMs = _bench('  traced adaptive', n, tracedFrames);
  final trialsPerFrame = (_acceptedTotal + _rejectedTotal) / n;
  print(
    'traced/static ${(tracedMs / staticMs).toStringAsFixed(2)}x'
    '   ${trialsPerFrame.toStringAsFixed(2)} trials/frame'
    ' (${(_rejectedTotal / n).toStringAsFixed(2)} rejected)'
    '   8 ms budget: ${tracedMs <= 8 ? 'PASS' : 'FAIL'}'
    ' (${(tracedMs / 8 * 100).toStringAsFixed(0)}% used)',
  );
}
