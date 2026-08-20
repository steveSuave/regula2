// Phase 139: what a traced trial costs, and against what.
//
// `TracingFlags.dragStepBudget` shipped as the constant 128 (Phase 114).
// A constant is the wrong shape because a trial is not a fixed amount of
// work: it recomputes every object downstream of the dragged point. This
// harness is the evidence for the replacement (PLAN §"The step budget is
// an amount of work, not a number of trials"), and it is what recalibrates
// `dragStepBudgetWork` if the kernel ever gets materially faster.
//
// It measures a *starving* frame — one that spends its whole budget and
// throws — because that is the case the budget bounds. The path ends
// exactly on a tangency, where no arc can enclose the singular endpoint,
// so the controller creeps until it gives up (the Phase 115 case). A path
// that merely crosses a degeneracy detours in ~66 trials on every size
// and measures nothing about the budget at all.
//
// Two readings:
//
//   scaling   per-trial cost against graph size, over a 32x range. The
//             per-object figure is the flat one; that flatness is what
//             makes "work / objects-per-trial" a well-founded budget.
//   budget    absolute frame cost at a range of budgets, plain and
//             carrying a locus, against the 8 ms drag-frame gate.
//
// Run on VM (`dart run`), AOT, dart2js and dart2wasm via
// `benchmark/run_drag_budget.sh`. Keep this file Flutter-free (domain
// imports only) or the js/wasm targets break.
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
import 'package:regula/domain/projective/tracing/tracing_flags.dart';

/// The Phase 116 drag-frame gate, for reference in the report. Not
/// enforced here: a starving frame is the pathological case, not the
/// steady state, and `tracing_bench.dart` is where the gate is a gate.
const dragFrameBudgetMs = 8;

/// `tracing_bench.dart`'s stress construction, parameterized by depth:
/// baseline y = 0 through a/b, then [layers] of midpoint → circle → two
/// intersection branches, everything downstream of the dragged point 'd'.
/// 24 layers is the 100-object rig the gate is defined on.
Construction buildStress(int layers) {
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
  for (var k = 0; k < layers; k++) {
    final m = Midpoint(id: 'm$k', point1: prev, point2: k.isEven ? a : b);
    final circle = FixedRadiusCircle(
      id: 'k$k',
      center: m,
      radius: 3.0 + (k % 7),
    );
    construction
      ..add(m)
      ..add(circle)
      ..add(
        IntersectionPoint(
          id: 'p${k}a',
          curve1: baseline,
          curve2: circle,
          branchIndex: 0,
        ),
      )
      ..add(
        IntersectionPoint(
          id: 'p${k}b',
          curve1: baseline,
          curve2: circle,
          branchIndex: 1,
        ),
      );
    prev = m;
  }
  return construction;
}

/// The same, carrying a 128-sample locus downstream of the same drag —
/// `tracing_bench.dart`'s second gate rig. A locus is settled once per
/// pass (Phase 117b), so it lifts the frame's *fixed* cost and not its
/// per-trial cost: the two rows below are what says so.
Construction buildLocusStress(int layers) {
  final c = buildStress(layers);
  final host = c.objects.whereType<FixedRadiusCircle>().first;
  final anchor = c.objects.whereType<FreePoint>().first;
  final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
  final chord = LineThroughTwoPoints(id: 'lc', point1: anchor, point2: driver);
  final other = IntersectionPoint(
    id: 'le',
    curve1: host,
    curve2: chord,
    branchIndex: 0,
  );
  final traced = Midpoint(id: 'lm', point1: driver, point2: other);
  return c
    ..add(driver)
    ..add(chord)
    ..add(other)
    ..add(traced)
    ..add(Locus(id: 'loc', driver: driver, traced: traced));
}

/// A frame whose path *ends* on the layer-0 tangency (the circle about
/// m0 touches the baseline at y_d = 6, since m0 halves toward it and the
/// radius is 3). The singularity sits at the path's end, so no detour
/// arc can enclose it and the controller creeps until the budget runs
/// out — [budget] trials, every time, which is what makes the cost
/// readable.
const _from = Vec2(0, 8);
const _to = Vec2(0, 6);

double _starvingFrames(Construction Function() build, int budget, int frames) {
  var trials = 0.0;
  for (var f = 0; f < frames; f++) {
    final construction = build();
    construction.moveFreePoint('d', _from);
    try {
      final r = construction.recomputeAlongPath(
        'd',
        const DragPath(_from, _to),
        stepBudget: budget,
      );
      trials += r.acceptedSteps + r.rejectedSteps;
    } on Object {
      trials += budget;
    }
  }
  return trials;
}

/// Warmup ×2, best of 5, ms per frame — `tracing_bench.dart`'s harness.
(double, double) _bench(Construction Function() build, int budget, int frames) {
  _starvingFrames(build, budget, frames);
  _starvingFrames(build, budget, frames);
  var bestUs = double.infinity;
  var trials = 0.0;
  final sw = Stopwatch();
  for (var i = 0; i < 5; i++) {
    sw
      ..reset()
      ..start();
    trials = _starvingFrames(build, budget, frames);
    sw.stop();
    final us = sw.elapsedMicroseconds.toDouble();
    if (us < bestUs) bestUs = us;
  }
  return (bestUs / 1000 / frames, trials / frames);
}

/// Marginal cost of a trial: the slope between two budgets, so the
/// pass's fixed cost (hoisting the dependents, seeding every slot, the
/// drive and recompute at t = 0) cancels instead of being charged to
/// every trial. Reading a one-trial frame as a trial's cost is what put
/// "one trial is ~0.08 ms" in the Phase 134 notes — it is ~7× the truth.
const _lowTrials = 32;
const _highTrials = 256;

void main(List<String> args) {
  final scale = args.isEmpty ? 1 : int.parse(args.first);
  final frames = 10 * scale;

  print('per-trial cost of a starving frame, against graph size:');
  print('  layers  objects  per-trial |  us/trial   us/object');
  for (final layers in [3, 6, 12, 24, 48, 96]) {
    final probe = buildStress(layers);
    final work = probe.tracedWorkPerTrial('d');
    final (lo, _) = _bench(() => buildStress(layers), _lowTrials, frames);
    final (hi, _) = _bench(() => buildStress(layers), _highTrials, frames);
    final usPerTrial = (hi - lo) / (_highTrials - _lowTrials) * 1000;
    print(
      '  ${layers.toString().padLeft(6)} '
      '${probe.length.toString().padLeft(8)} '
      '${work.toString().padLeft(10)} | '
      '${usPerTrial.toStringAsFixed(2).padLeft(9)} '
      '${(usPerTrial / work).toStringAsFixed(3).padLeft(11)}'
      '${layers == 24 ? '   <- the gate rig' : ''}',
    );
  }
  print(
    '  the us/object column is the flat one — that is what makes a work'
    ' quota well-founded.',
  );

  print('');
  print('cost of a starving frame at a range of budgets:');
  for (final (name, build) in [
    ('  stress, 100 objects', () => buildStress(24)),
    ('  + a 128-sample locus', () => buildLocusStress(24)),
  ]) {
    final work = build().tracedWorkPerTrial('d');
    print(
      '$name ($work objects per trial, derived budget '
      '${TracingFlags.dragStepBudgetFor(work)}):',
    );
    for (final budget in [32, 128, 256, 512, 1024, 2048]) {
      final (ms, trials) = _bench(build, budget, frames);
      print(
        '    budget ${budget.toString().padLeft(5)}  '
        '${ms.toStringAsFixed(3).padLeft(7)} ms  '
        '${trials.toStringAsFixed(0).padLeft(5)} trials  '
        '${(ms / dragFrameBudgetMs * 100).toStringAsFixed(0).padLeft(4)}%'
        ' of the $dragFrameBudgetMs ms gate',
      );
    }
  }
  print(
    '  cost flattens past ~500 trials — the walk stops progressing while'
    ' the counter runs.',
  );
  print(
    '  That is where dragStepBudgetMax'
    ' (${TracingFlags.dragStepBudgetMax}) comes from.',
  );
}
