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
// The gate is ≤ 8 ms kernel time per drag frame (PLAN, Phase 116), and
// since Phase 122 it is mechanical: exceeding it throws, so a CI job can
// enforce it without reading the text. On smooth frames the controller
// accepts the whole path in one trial, so the expected shape is a small
// multiple of the static solve (seeding + one matched recompute), not 16×.
//
// Note what this harness does *not* measure: it accepts every trial, so
// the walk's inner loop barely runs (1.00 trials/frame, 0.00 rejected).
// For where a solve's time actually goes, see `chain_solve_bench.dart`;
// for a walk that starves, measures collisions and detours, see
// `locus_docs_bench.dart`.
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
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';

const framesPerRun = 50;

/// The Phase 116 performance gate: kernel time per drag frame on the
/// stress construction below. Named here because the exit code at the
/// bottom is what makes it a gate rather than a printed opinion.
const dragFrameBudgetMs = 8;

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

/// The Phase 117b gate: the same stress construction carrying a `Locus`
/// downstream of the dragged point — the shape both frozen user
/// documents had. A locus recompute is a whole traced sweep of its own,
/// so before 117b held them back this cost `trials × sweep` per frame
/// (and a starving frame burned the entire step budget in sweeps).
(Construction, IntersectionPoint) buildLocusStress() {
  final (construction, deepest) = buildStress();
  final host = construction.objects.whereType<FixedRadiusCircle>().first;
  final anchor = construction.objects.whereType<FreePoint>().first;
  final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
  // The documents' own shape: a chord drawn from a fixed point *through*
  // the driver, and the circle's other intersection with it. The driver
  // is itself one of that pair's roots, so the sweep meets a transversal
  // crossing twice a turn — the walk, the measured collision and the
  // detour all run, every frame.
  final chord = LineThroughTwoPoints(id: 'lc', point1: anchor, point2: driver);
  final other = IntersectionPoint(
    id: 'le',
    curve1: host,
    curve2: chord,
    branchIndex: 0,
  );
  final traced = Midpoint(id: 'lm', point1: driver, point2: other);
  construction
    ..add(driver)
    ..add(chord)
    ..add(other)
    ..add(traced)
    ..add(Locus(id: 'loc', driver: driver, traced: traced));
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

/// [n] drag frames on [buildLocusStress], resolved statically.
double staticLocusFrames(int n) {
  final (construction, deepest) = buildLocusStress();
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

/// [n] traced drag frames on [buildLocusStress].
double tracedLocusFrames(int n) {
  final (construction, deepest) = buildLocusStress();
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
    '   $dragFrameBudgetMs ms budget: '
    '${tracedMs <= dragFrameBudgetMs ? 'PASS' : 'FAIL'}'
    ' (${(tracedMs / dragFrameBudgetMs * 100).toStringAsFixed(0)}% used)',
  );

  print('');
  print('the same construction carrying a 128-sample Locus (Phase 117b):');
  final staticLocusMs = _bench('  static x1', n, staticLocusFrames);
  final tracedLocusMs = _bench('  traced adaptive', n, tracedLocusFrames);
  final locusTrialsPerFrame = (_acceptedTotal + _rejectedTotal) / n;
  print(
    'traced/static ${(tracedLocusMs / staticLocusMs).toStringAsFixed(2)}x'
    '   ${locusTrialsPerFrame.toStringAsFixed(2)} trials/frame'
    ' (${(_rejectedTotal / n).toStringAsFixed(2)} rejected)'
    '   $dragFrameBudgetMs ms budget: '
    '${tracedLocusMs <= dragFrameBudgetMs ? 'PASS' : 'FAIL'}'
    ' (${(tracedLocusMs / dragFrameBudgetMs * 100).toStringAsFixed(0)}% used)',
  );

  // The gate is mechanical, so that a CI job *can* enforce it (Phase 122)
  // without parsing the text above. Whether it does is the job's choice —
  // `benchmark/run_ci.sh` runs informationally, because a shared runner's
  // timings are not the number this budget is about. Thrown rather than
  // `exit`ed: `dart:io` would cost this file its js and wasm targets, and
  // an uncaught error is a non-zero exit on all four.
  if (tracedMs > dragFrameBudgetMs || tracedLocusMs > dragFrameBudgetMs) {
    throw StateError(
      'FAIL: ${dragFrameBudgetMs}ms drag-frame budget exceeded '
      '(${tracedMs.toStringAsFixed(3)} plain, '
      '${tracedLocusMs.toStringAsFixed(3)} with a locus)',
    );
  }
}
