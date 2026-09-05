// Phase 189 probe: what a detour costs in trials, and where.
//
// A pass that starves plans a detour arc; on a graph large enough for
// the Phase 139 floor to bind, the arc plus its exit may not fit the
// trials left. Phase 139 asked for a pass to decline a detour it cannot
// afford; this probe was the measurement before building that, and it
// is the evidence for what was built instead (PLAN §"A pass keeps what
// it carried across").
//
// Two readings:
//
//   parts     each detour split three ways — the approach that
//             classified the starvation, the arc, and the exit's climb
//             back to path scale — on every rig the suite detours on, at
//             a budget nothing bails at. The crossing is made at the
//             arc's end; the exit is where the floor runs out.
//   regimes   the same crossings against the budget: throws (crossed
//             nothing), kept at t (crossed, stopped short), complete.
//
// VM only (`dart run benchmark/detour_cost_probe.dart`); trial counts
// are target-independent. Keep it Flutter-free.
//
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';
import 'package:regula/domain/projective/tracing/trace_diagnostics.dart';
import 'package:regula/domain/projective/tracing/trace_step_budget_exception.dart';

import 'drag_budget_bench.dart' show buildStress;

typedef Sample = ({double t, int trials, int arc, int detours, double sep});

Construction toy(Vec2 centerStart) {
  final c = Construction();
  final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
  final b = FreePoint(id: 'b', position: const Vec2(10, 0));
  final center = FreePoint(id: 'c', position: centerStart);
  final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
  final k = FixedRadiusCircle(id: 'k', center: center, radius: 3);
  return c
    ..add(a)
    ..add(b)
    ..add(center)
    ..add(line)
    ..add(k)
    ..add(IntersectionPoint(id: 'p0', curve1: line, curve2: k, branchIndex: 0))
    ..add(IntersectionPoint(id: 'p1', curve1: line, curve2: k, branchIndex: 1));
}

Construction crossingRig() {
  const b = Vec2(-8, -1);
  final a = FreePoint(id: 'a', position: Vec2.zero);
  final unit = FreePoint(id: 'u', position: const Vec2(1, 0));
  final axis = LineThroughTwoPoints(id: 'axis', point1: a, point2: unit);
  final driver = PointOnObject(id: 'drv', curve: axis, parameter: -6.25);
  final copy = HomotheticPoint(id: 'cp', point: driver, center: a, ratio: 1);
  final circle = CircleCenterPoint(id: 'd', center: a, onCircle: copy);
  final off = FreePoint(id: 'b', position: b);
  final chord = LineThroughTwoPoints(id: 'c', point1: off, point2: driver);
  Vec2 otherCrossing(double t) {
    final s = 2 * t * (8 + t) / ((8 + t) * (8 + t) + 1);
    return Vec2(t + s * (b.x - t), -s);
  }

  var index = 0;
  for (final candidate in [0, 1]) {
    final probe = IntersectionPoint(
      id: 'g',
      curve1: circle,
      curve2: chord,
      branchIndex: candidate,
    );
    if (probe.position!.distanceTo(otherCrossing(-6.25)) < 1e-9) {
      index = candidate;
    }
  }
  final g = IntersectionPoint(
    id: 'g',
    curve1: circle,
    curve2: chord,
    branchIndex: index,
  );
  return Construction()
    ..add(a)
    ..add(unit)
    ..add(axis)
    ..add(driver)
    ..add(copy)
    ..add(circle)
    ..add(off)
    ..add(chord)
    ..add(g);
}

double minSep(Construction c) {
  var m = double.infinity;
  for (final o in c.objects) {
    if (o is IntersectionPoint) {
      m = math.min(m, o.tracedBranch.separation);
    }
  }
  return m;
}

void run(
  String name,
  Construction c,
  ({
    int acceptedSteps,
    int rejectedSteps,
    int detours,
    double closing,
    double reached,
  })
  Function(void Function(double) onStep)
  pass,
) {
  TraceDiagnostics.enabled = true;
  TraceDiagnostics.frameBegin(name);
  final samples = <Sample>[];
  void onStep(double t) {
    final f = TraceDiagnostics.current!;
    samples.add((
      t: t,
      trials: f[TraceCounter.dragAccepted] + f[TraceCounter.dragRejected],
      arc: f[TraceCounter.dragArcTrials],
      detours: f[TraceCounter.dragDetours],
      sep: minSep(c),
    ));
  }

  String outcome;
  int total;
  try {
    final r = pass(onStep);
    total = r.acceptedSteps + r.rejectedSteps;
    outcome =
        'done acc=${r.acceptedSteps} rej=${r.rejectedSteps} '
        'detours=${r.detours}';
  } on TraceStepBudgetException catch (e) {
    total = e.trials;
    outcome = 'BAILED at t=${e.tReached.toStringAsFixed(4)} trials=${e.trials}';
  }
  TraceDiagnostics.frameEnd();
  print('== $name: $outcome');
  // Walk the samples: a detour shows as a jump in `detours`.
  var lastAccept = samples.isEmpty ? null : samples.first;
  var seenDetours = 0;
  var arcSoFar = 0;
  var exitFrom = 0;
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i];
    if (s.detours > seenDetours) {
      final arc = s.arc - arcSoFar;
      final creep = s.trials - arc - (lastAccept?.trials ?? 0);
      // Trials in the approach since the separation first dipped below
      // thresholds, read off the accepted-step samples.
      int since(double th) {
        for (var j = i - 1; j >= 0; j--) {
          if (samples[j].sep >= th) {
            return lastAccept!.trials - samples[j].trials;
          }
        }
        return lastAccept!.trials;
      }

      print(
        '   detour ${s.detours}: planned at trials=${s.trials - arc} '
        '(last accept t=${lastAccept!.t.toStringAsFixed(4)} '
        'sep=${lastAccept.sep.toStringAsExponential(1)}, '
        'terminal refusals=$creep) arc=$arc exit-from=${s.trials} '
        '| approach trials since sep<1e-1: ${since(1e-1)}, '
        '<1e-2: ${since(1e-2)}, <1e-3: ${since(1e-3)}',
      );
      seenDetours = s.detours;
      arcSoFar = s.arc;
      exitFrom = s.trials;
    }
    lastAccept = s;
  }
  if (seenDetours > 0) {
    print(
      '   exit of last detour: ${total - exitFrom} trials; pass total $total',
    );
  }
  // Exit profile: accepted steps after the last detour, with sep.
  final tail = samples
      .where((s) => s.detours == seenDetours && seenDetours > 0)
      .take(12);
  if (tail.isNotEmpty) {
    print(
      '   exit profile (t, trials, sep): ${tail.map((s) => '(${s.t.toStringAsFixed(4)},${s.trials},${s.sep.toStringAsExponential(1)})').join(' ')}',
    );
  }
}

/// Second reading: the budget regimes of three crossings — throw (the
/// pass crossed nothing), keep (it crossed and stopped short, Phase 189),
/// complete — as a function of the budget.
void sweepBudgets() {
  print('');
  print('budget regimes (X = throws, P<t> = kept at t, ok = complete):');
  for (final (from, to) in [
    (const Vec2(0, 5), const Vec2(0, 0)),
    (const Vec2(0, 5), const Vec2(0, 1)),
  ]) {
    final line = StringBuffer('  toy $from→$to: ');
    for (var b = 60; b <= 110; b += 2) {
      final c = toy(from);
      try {
        final r = c.recomputeAlongPath('c', DragPath(from, to), stepBudget: b);
        line.write(
          '$b:${r.reached < 1 ? 'P${r.reached.toStringAsFixed(3)}' : 'ok'} ',
        );
      } on TraceStepBudgetException {
        line.write('$b:X ');
      }
    }
    print(line);
  }
  final line = StringBuffer('  crossing rig −6.25→−9: ');
  for (var b = 100; b <= 160; b += 4) {
    final c = crossingRig();
    try {
      final r = c.recomputeAlongParameterPath('drv', -6.25, -9, stepBudget: b);
      line.write(
        '$b:${r.reached < 1 ? 'P${r.reached.toStringAsFixed(3)}' : 'ok'} ',
      );
    } on TraceStepBudgetException {
      line.write('$b:X ');
    }
  }
  print(line);
}

void main() {
  {
    final c = toy(const Vec2(0, 5));
    run(
      'toy line∩circle (0,5)→(0,0)',
      c,
      (onStep) => c.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
        stepBudget: 2048,
        onStep: onStep,
      ),
    );
  }
  for (final (from, to) in [
    (const Vec2(0, 4), const Vec2(0, -4)),
    (const Vec2(0, 2), const Vec2(0, -4)),
    (const Vec2(0, 0), const Vec2(0, -5)),
    (const Vec2(-5, 2), const Vec2(5, 2)),
  ]) {
    final c = toy(from);
    run(
      'toy $from→$to',
      c,
      (onStep) => c.recomputeAlongPath(
        'c',
        DragPath(from, to),
        stepBudget: 2048,
        onStep: onStep,
      ),
    );
  }
  for (final layers in [1, 3, 6, 12, 24, 48]) {
    final c = buildStress(layers);
    c.moveFreePoint('d', const Vec2(0, 8));
    run(
      'stress $layers layers (${c.tracedWorkPerTrial('d')} objects/trial) '
      '(0,8)→(0,4)',
      c,
      (onStep) => c.recomputeAlongPath(
        'd',
        const DragPath(Vec2(0, 8), Vec2(0, 4)),
        stepBudget: 2048,
        onStep: onStep,
      ),
    );
  }
  {
    final c = crossingRig();
    run(
      'crossing rig transversal −6.25→−9',
      c,
      (onStep) => c.recomputeAlongParameterPath(
        'drv',
        -6.25,
        -9,
        stepBudget: 2048,
        onStep: onStep,
      ),
    );
  }
  {
    final c = crossingRig();
    run(
      'crossing rig carrier collapse −1→1',
      c,
      (onStep) => c.recomputeAlongParameterPath(
        'drv',
        -1,
        1,
        stepBudget: 2048,
        onStep: onStep,
      ),
    );
  }
  sweepBudgets();
}
