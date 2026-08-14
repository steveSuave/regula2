import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';
import 'package:regula/domain/projective/tracing/trace_step_budget_exception.dart';

/// A puppet intersection point: real parents wire it into the graph (and
/// their real candidates give the seed its separation), but its own
/// candidates are scripted, so the controller's collision path can be
/// driven deterministically — real geometry only reaches a matching
/// ambiguity through exact ties or coast re-acquisitions, which adaptive
/// steps cannot be made to hit reliably (resolving them for real is
/// Phase 115's detour). Mirrors the real `recompute`'s traced/static
/// split exactly.
class _ScriptedIntersectionPoint extends IntersectionPoint {
  _ScriptedIntersectionPoint({
    required super.id,
    required super.curve1,
    required super.curve2,
    required super.branchIndex,
    required this.staticCandidates,
    required this.tracedCandidates,
  });

  final List<ProjPoint> staticCandidates;
  final List<ProjPoint> tracedCandidates;
  ProjPoint? _tracked;

  @override
  ProjPoint? get projPoint => _tracked;

  @override
  void recompute() {
    if (tracedBranch.isActive) {
      _tracked = tracedBranch.follow(tracedCandidates);
      return;
    }
    _tracked =
        staticCandidates[math.min(branchIndex, staticCandidates.length - 1)];
  }
}

void main() {
  FreePoint fp(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  /// Scale-invariant chordal separation — the measure branch matching
  /// minimizes, usable on complex and infinite points alike.
  double chordal(ProjPoint p, ProjPoint q) =>
      math.sqrt(p.join(q).norm2 / (p.norm2 * q.norm2));

  /// The imaginary part of the tracked root's chart abscissa —
  /// representative-invariant (x/w survives rescaling), the quantity that
  /// distinguishes conjugate mates on a horizontal carrier.
  double chartIm(ProjPoint p) => (p.x / p.w).im;

  /// The toy rig: the fixed line y = 0 and a rigid radius-3 circle whose
  /// free center is the dragged point, with both intersection branches.
  /// Returns (construction, center, branch0, branch1).
  (Construction, FreePoint, IntersectionPoint, IntersectionPoint) lineAndCircle(
    Vec2 centerStart,
  ) {
    final construction = Construction();
    final a = fp('a', -10, 0);
    final b = fp('b', 10, 0);
    final center = fp('c', centerStart.x, centerStart.y);
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final circle = FixedRadiusCircle(id: 'k', center: center, radius: 3);
    final p0 = IntersectionPoint(
      id: 'p0',
      curve1: line,
      curve2: circle,
      branchIndex: 0,
    );
    final p1 = IntersectionPoint(
      id: 'p1',
      curve1: line,
      curve2: circle,
      branchIndex: 1,
    );
    construction
      ..add(a)
      ..add(b)
      ..add(center)
      ..add(line)
      ..add(circle)
      ..add(p0)
      ..add(p1);
    return (construction, center, p0, p1);
  }

  group('recomputeAlongPath: validation', () {
    test('rejects non-free-point ids and non-positive step budgets', () {
      final (construction, _, _, _) = lineAndCircle(const Vec2(0, 1));
      const path = DragPath(Vec2(0, 1), Vec2(0, -1));
      expect(
        () => construction.recomputeAlongPath('l', path),
        throwsArgumentError,
      );
      expect(
        () => construction.recomputeAlongPath('c', path, stepBudget: 0),
        throwsArgumentError,
      );
    });
  });

  group('recomputeAlongPath: adaptive toy harness '
      '(line dragged across a circle)', () {
    test('secant sweep: every accepted step obeys the Cinderella bound, no '
        'branch swap, static endpoint — identity chains across paths and a '
        'smooth path costs few trials', () {
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 1));
      final h0 = <ProjPoint>[p0.projPoint!];
      final h1 = <ProjPoint>[p1.projPoint!];
      var notifications = 0;
      construction.addListener(() => notifications++);
      void record(double t) {
        h0.add(p0.projPoint!);
        h1.add(p1.projPoint!);
      }

      // Two consecutive legs, like two preview frames: the second seeds
      // from the value the first left behind.
      final r1 = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 1), Vec2(0, 0)),
        onStep: record,
      );
      final r2 = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 0), Vec2(0, -1)),
        onStep: record,
      );

      expect(notifications, 2);
      // onStep fires once per accepted step, nothing per rejected trial.
      expect(h0, hasLength(1 + r1.acceptedSteps + r2.acceptedSteps));
      // The roots barely move over each leg, so the controller accepts
      // whole paths after at most a couple of refinements.
      expect(r1.acceptedSteps + r1.rejectedSteps, lessThanOrEqualTo(4));
      expect(r2.acceptedSteps + r2.rejectedSteps, lessThanOrEqualTo(4));
      // The circle stays secant to the line throughout (|cy| ≤ 1 < 3), so
      // both branches are real everywhere and never change sides.
      for (final p in h0) {
        expect(p.toVec2()!.x, lessThan(0));
      }
      for (final p in h1) {
        expect(p.toVec2()!.x, greaterThan(0));
      }
      // The acceptance rule itself: per accepted step, each root moved
      // less than half the branch separation at the previous step
      // (separation stays near chordal 0.6 on this rig).
      for (var i = 1; i < h0.length; i++) {
        expect(chordal(h0[i - 1], h0[i]), lessThan(0.35));
        expect(chordal(h1[i - 1], h1[i]), lessThan(0.35));
      }
      // No degeneracy was crossed, so the endpoint agrees with the static
      // solve including branch labels: x² = 9 − 1 at cy = −1.
      final r = math.sqrt(8);
      expect(p0.position!.closeTo(Vec2(-r, 0)), isTrue);
      expect(p1.position!.closeTo(Vec2(r, 0)), isTrue);
      expect(p0.tracedBranch.isActive, isFalse);
      expect(p1.tracedBranch.isActive, isFalse);
    });

    test('persistent miss: conjugate roots continue through the complex '
        'domain and the endpoint matches the static solve, labels included',
        () {
      // Center rides y = 5 while the line is y = 0: never intersects,
      // both branches complex the whole way (x = cx ± 4i). The long
      // horizontal path forces the controller to subdivide.
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final h0 = <ProjPoint>[p0.projPoint!];
      final h1 = <ProjPoint>[p1.projPoint!];
      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(40, 5)),
        onStep: (_) {
          h0.add(p0.projPoint!);
          h1.add(p1.projPoint!);
        },
      );

      expect(h0, hasLength(1 + result.acceptedSteps));
      final sign0 = chartIm(h0.first).sign;
      final sign1 = chartIm(h1.first).sign;
      expect(sign0, isNot(sign1));
      for (var i = 0; i < h0.length; i++) {
        // Never drawable, never lost: complex the whole way, each branch
        // pinned to its own conjugate side.
        expect(p0.position, isNull);
        expect(chartIm(h0[i]).sign, sign0);
        expect(chartIm(h1[i]).sign, sign1);
      }
      // No realness transition happened, so labels are preserved: a
      // fresh static solve at the endpoint picks the same roots.
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', const Vec2(40, 5));
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    });

    test('near-tangency approach: the controller is forced to halve and '
        'still matches — endpoint equals the static solve, labels included',
        () {
      // Descend from y = 5 toward the tangency at y = 3, stopping just
      // above it: the conjugate pair shrinks toward the touch point, the
      // separation collapses with it, and the whole-path trial (and its
      // first refinements) violate the Cinderella bound.
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final sign0 = chartIm(p0.projPoint!).sign;
      final sign1 = chartIm(p1.projPoint!).sign;
      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 3.05)),
      );

      expect(result.rejectedSteps, greaterThan(0));
      expect(chartIm(p0.projPoint!).sign, sign0);
      expect(chartIm(p1.projPoint!).sign, sign1);
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', const Vec2(0, 3.05));
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    });

    test('through-infinity loophole (glados counterexample): a wide secant '
        'step whose chordal wrap made the far branch look nearer is '
        'refused by the motion cap — no swap', () {
      // r = 2.1, center (−1.8, 0) → (1.7, 0.819): on the whole-path
      // trial the left root (x = −3.9) sits chordally *closer* to the
      // new right root (x = 3.63, quarter-turn away through the point at
      // infinity of RP¹) than to its true continuation (x = −0.23), with
      // both swapped motions just under sep/2 — the separation-relative
      // rule alone accepted a silent branch swap. The absolute motion
      // cap refuses the wide step; refined steps match correctly.
      final construction = Construction();
      final a = fp('a', -10, 0);
      final b = fp('b', 10, 0);
      final center = fp('c', -1.8, 0);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final circle = FixedRadiusCircle(id: 'k', center: center, radius: 2.1);
      final p0 = IntersectionPoint(
        id: 'p0',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
      );
      final p1 = IntersectionPoint(
        id: 'p1',
        curve1: line,
        curve2: circle,
        branchIndex: 1,
      );
      construction
        ..add(a)
        ..add(b)
        ..add(center)
        ..add(line)
        ..add(circle)
        ..add(p0)
        ..add(p1);

      const end = Vec2(1.7, 0.8190000000000001);
      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(-1.8, 0), end),
        onStep: (_) {
          final cx = center.position.x;
          expect(p0.position!.x, lessThan(cx));
          expect(p1.position!.x, greaterThan(cx));
        },
      );
      expect(result.rejectedSteps, greaterThan(0));
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', end);
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    });

    test('through a tangency with an insufficient budget: the creep '
        'exhausts before the detour trigger is reached, and the pass '
        'throws, leaving a cleanly bail-able state', () {
      // Crossing y = 3 collapses the branch separation to zero, so the
      // allowed motion per step collapses with it: accepted steps creep
      // toward t* = 0.4 (each trial that would cross moves a root at
      // least its full distance to the touch point — strictly refused).
      // Reaching the Phase 115 detour trigger takes ~17 halvings plus
      // the interleaved accepts, so a budget of 40 exhausts first — the
      // graceful-bail path survives exactly as in Phase 114 (the
      // default budget crosses instead; see the complex-detour group).
      // The small budget also keeps the creep far from floating-point
      // noise around the strict inequality.
      final (construction, center, p0, p1) = lineAndCircle(const Vec2(0, 5));
      expect(
        () => construction.recomputeAlongPath(
          'c',
          const DragPath(Vec2(0, 5), Vec2(0, 0)),
          stepBudget: 40,
        ),
        throwsA(isA<TraceStepBudgetException>().having(
          (e) => e.tReached,
          'tReached',
          allOf(greaterThan(0.2), lessThan(0.4)),
        )),
      );

      // The pass cleaned up: slots inactive, and the caller's static bail
      // (moveFreePoint to the intended target) fully recovers.
      expect(p0.tracedBranch.isActive, isFalse);
      expect(p1.tracedBranch.isActive, isFalse);
      expect(center.position.y, lessThan(5));
      construction.moveFreePoint('c', const Vec2(0, 0));
      expect(p0.position!.closeTo(Vec2(-3, 0)), isTrue);
      expect(p1.position!.closeTo(Vec2(3, 0)), isTrue);
    });
  });

  group('recomputeAlongPath: collision refusal (scripted candidates)', () {
    // Seeds sit at x = 0 and x = 0.05 on the axis (distinct — a real
    // check pair); the parents' real candidates (x = 2, 8) give the seed
    // a chordal separation of ~0.33, so scripted motions of ~0.1 pass
    // the Cinderella bound and the collision check alone decides.
    final seeds = [ProjPoint.real(0, 0, 1), ProjPoint.real(0.05, 0, 1)];

    (Construction, _ScriptedIntersectionPoint, _ScriptedIntersectionPoint)
        scriptedRig({
      required int branchA,
      required int branchB,
      required List<ProjPoint> tracedCandidates,
    }) {
      final construction = Construction();
      final d = fp('d', 0, 0);
      final g = fp('g', 10, 0);
      final center = fp('o', 5, 0);
      final line = LineThroughTwoPoints(id: 'l', point1: d, point2: g);
      final circle = FixedRadiusCircle(id: 'k', center: center, radius: 3);
      final a = _ScriptedIntersectionPoint(
        id: 'sa',
        curve1: line,
        curve2: circle,
        branchIndex: branchA,
        staticCandidates: seeds,
        tracedCandidates: tracedCandidates,
      );
      final b = _ScriptedIntersectionPoint(
        id: 'sb',
        curve1: line,
        curve2: circle,
        branchIndex: branchB,
        staticCandidates: seeds,
        tracedCandidates: tracedCandidates,
      );
      construction
        ..add(d)
        ..add(g)
        ..add(center)
        ..add(line)
        ..add(circle)
        ..add(a)
        ..add(b);
      return (construction, a, b);
    }

    const path = DragPath(Vec2(0, 0), Vec2(1, 0));

    test('two distinct-seeded branches grabbing the same candidate refuse '
        'the step, and with no step size resolving it the budget starves',
        () {
      // Both seeds are nearest x = 0.1 while a genuinely distinct
      // alternative exists at x = 5 — matching went ambiguous, so every
      // trial must be refused rather than silently merging the branches.
      final (construction, a, b) = scriptedRig(
        branchA: 0,
        branchB: 1,
        tracedCandidates: [ProjPoint.real(0.1, 0, 1), ProjPoint.real(5, 0, 1)],
      );
      final accepted = <double>[];
      expect(
        () => construction.recomputeAlongPath(
          'd',
          path,
          stepBudget: 25,
          onStep: accepted.add,
        ),
        throwsA(isA<TraceStepBudgetException>()
            .having((e) => e.tReached, 'tReached', 0)
            .having((e) => e.trials, 'trials', 25)),
      );
      expect(accepted, isEmpty);
      expect(a.tracedBranch.isActive, isFalse);
      expect(b.tracedBranch.isActive, isFalse);
    });

    test('a shared grab of coincident candidates (a double root) is benign',
        () {
      // The two candidates sit within doubleRootEpsilon of each other:
      // there is no distinct alternative for halving to disambiguate,
      // and riding the touch point together is correct.
      final (construction, a, b) = scriptedRig(
        branchA: 0,
        branchB: 1,
        tracedCandidates: [
          ProjPoint.real(0.1, 0, 1),
          ProjPoint.real(0.1 + 1e-8, 0, 1),
        ],
      );
      final result = construction.recomputeAlongPath('d', path);
      expect(result, (acceptedSteps: 1, rejectedSteps: 0, detours: 0));
      expect(a.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
      expect(b.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
    });

    test('branches seeded coincident are married and ride the same root '
        'without refusal', () {
      // Both objects deliberately track the same branch (both seeded on
      // x = 0): matching them to the same candidate is faithful
      // continuation, and no step size could ever separate them — the
      // pair is exempt from the collision check.
      final (construction, a, b) = scriptedRig(
        branchA: 0,
        branchB: 0,
        tracedCandidates: [ProjPoint.real(0.1, 0, 1), ProjPoint.real(5, 0, 1)],
      );
      final result = construction.recomputeAlongPath('d', path);
      expect(result, (acceptedSteps: 1, rejectedSteps: 0, detours: 0));
      expect(a.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
      expect(b.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
    });
  });

  group('recomputeAlongPath: static fallbacks', () {
    test('nothing seedable collapses to a single static solve at the end',
        () {
      // line1's carrier is undefined (coincident endpoints), so its
      // intersection has no identity to continue.
      final construction = Construction();
      final a = fp('a', 0, 0);
      final b = fp('b', 0, 0);
      final d = fp('d', 0, -5);
      final e = fp('e', 0, 5);
      final line1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
      final line2 = LineThroughTwoPoints(id: 'l2', point1: d, point2: e);
      final ip = IntersectionPoint(
        id: 'x',
        curve1: line1,
        curve2: line2,
        branchIndex: 0,
      );
      construction
        ..add(a)
        ..add(b)
        ..add(d)
        ..add(e)
        ..add(line1)
        ..add(line2)
        ..add(ip);
      expect(ip.projPoint, isNull);

      final observedTs = <double>[];
      final result = construction.recomputeAlongPath(
        'b',
        const DragPath(Vec2(0, 0), Vec2(4, 4)),
        onStep: (t) {
          observedTs.add(t);
          expect(ip.tracedBranch.isActive, isFalse);
        },
      );

      expect(observedTs, [1.0]);
      expect(result, (acceptedSteps: 1, rejectedSteps: 0, detours: 0));
      // Bitwise-exact endpoint, like moveFreePoint.
      expect(b.position, const Vec2(4, 4));
      expect(ip.position!.closeTo(Vec2.zero), isTrue);
    });

    test('locus-chain intersection points are excluded from tracing', () {
      final construction = Construction();
      final f = fp('f', 0, 0);
      final host = FixedRadiusCircle(id: 'host', center: f, radius: 5);
      final driver = PointOnObject(id: 'driver', curve: host, parameter: 0);
      final g = fp('g', 0, 10);
      final chainLine = LineThroughTwoPoints(
        id: 'ld',
        point1: driver,
        point2: g,
      );
      final chainCircleCenter = fp('k2c', 2, 4);
      final chainCircle = FixedRadiusCircle(
        id: 'k2',
        center: chainCircleCenter,
        radius: 3,
      );
      final chained = IntersectionPoint(
        id: 'ipc',
        curve1: chainLine,
        curve2: chainCircle,
        branchIndex: 0,
      );
      final locus = Locus(id: 'locus', driver: driver, traced: chained);
      final m = fp('m', 10, 10);
      final freeLine = LineThroughTwoPoints(id: 'l2', point1: g, point2: m);
      final freeCircleCenter = fp('k3c', 5, 10);
      final freeCircle = FixedRadiusCircle(
        id: 'k3',
        center: freeCircleCenter,
        radius: 3,
      );
      final untracked = IntersectionPoint(
        id: 'ipf',
        curve1: freeLine,
        curve2: freeCircle,
        branchIndex: 0,
      );
      construction
        ..add(f)
        ..add(host)
        ..add(driver)
        ..add(g)
        ..add(chainLine)
        ..add(chainCircleCenter)
        ..add(chainCircle)
        ..add(chained)
        ..add(locus)
        ..add(m)
        ..add(freeLine)
        ..add(freeCircleCenter)
        ..add(freeCircle)
        ..add(untracked);
      expect(chained.projPoint, isNotNull);
      expect(untracked.projPoint, isNotNull);

      var observed = 0;
      final result = construction.recomputeAlongPath(
        'g',
        const DragPath(Vec2(0, 10), Vec2(0, 9)),
        onStep: (_) {
          observed++;
          // Both depend on the dragged point, but the locus-chain member
          // must stay on static branch selection: the sweep-and-restore
          // recompute would drag a tracked root along the sweep.
          expect(chained.tracedBranch.isActive, isFalse);
          expect(untracked.tracedBranch.isActive, isTrue);
        },
      );

      expect(observed, result.acceptedSteps);
      expect(observed, greaterThan(0));
      expect(untracked.tracedBranch.isActive, isFalse);
    });
  });

  group('recomputeAlongPath: complex detour (Phase 115)', () {
    test('through a tangency: the pass detours and crosses — points go '
        'complex, come back real, no jump, no swap, deterministic sides',
        () {
      // Same crossing that starves a 40-trial budget: with the default
      // budget the controller creeps to the trigger, extrapolates
      // t* = 0.4 from the collapsing separation, and walks the upper
      // arc (downward drag). The conjugate pair splits real on the far
      // side with the assignment continuity dictates: for this
      // orientation the −i branch lands on x < 0.
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final minus = chartIm(p0.projPoint!) < 0 ? p0 : p1;
      final plus = identical(minus, p0) ? p1 : p0;
      final histories = <IntersectionPoint, List<ProjPoint>>{
        p0: [p0.projPoint!],
        p1: [p1.projPoint!],
      };
      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
        onStep: (_) {
          histories[p0]!.add(p0.projPoint!);
          histories[p1]!.add(p1.projPoint!);
        },
      );

      expect(result.detours, 1);
      // No jump: every consecutive pair of observed real-step roots is
      // chordally close — including the hop across the detour, whose
      // arc is only as wide as the creep left it.
      for (final history in histories.values) {
        for (var i = 1; i < history.length; i++) {
          expect(chordal(history[i - 1], history[i]), lessThan(0.3));
        }
      }
      // Crossed and real: endpoint at x² = 9 with deterministic sides.
      expect(minus.position!.closeTo(const Vec2(-3, 0)), isTrue);
      expect(plus.position!.closeTo(const Vec2(3, 0)), isTrue);
      // Endpoint = static solve, labels included.
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', const Vec2(0, 0));
      expect(p0.projPoint!.closeTo(tracked0, 1e-6), isTrue);
      expect(p1.projPoint!.closeTo(tracked1, 1e-6), isTrue);
    });

    test('there and back across the tangency is an identity: each branch '
        'returns to its own conjugate side (odd orientation, zero net '
        'winding)', () {
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final seed0 = p0.projPoint!;
      final seed1 = p1.projPoint!;

      final down = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
      );
      final up = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 0), Vec2(0, 5)),
      );

      expect(down.detours, 1);
      expect(up.detours, 1);
      // A fixed absolute half-plane would swap the conjugates here (one
      // net winding around the branch point); the odd orientation rule
      // retraces the same physical side and restores both labels.
      expect(p0.projPoint!.closeTo(seed0, 1e-9), isTrue);
      expect(p1.projPoint!.closeTo(seed1, 1e-9), isTrue);
      expect(chartIm(p0.projPoint!).sign, chartIm(seed0).sign);
      expect(chartIm(p1.projPoint!).sign, chartIm(seed1).sign);
    });

    test('a co-traced regular pair rides the detour unharmed: no enclosed '
        'singularity of its own means its endpoint equals the real-path '
        'endpoint', () {
      // The r = 3 circle's tangency at y = 3 forces the detour; a
      // concentric r = 6 circle's intersections with the same line stay
      // transverse the whole way (x = ±√(36 − y²), y ∈ [0, 5]). The
      // detour drags them through complex parameters too — but encloses
      // no singularity of *theirs*, so continuation is homotopic to the
      // real path: same sides, same endpoint, no swap.
      final (construction, center, _, _) = lineAndCircle(const Vec2(0, 5));
      final line = construction.byId('l')!;
      final outer = FixedRadiusCircle(id: 'k6', center: center, radius: 6);
      final q0 = IntersectionPoint(
        id: 'q0',
        curve1: line,
        curve2: outer,
        branchIndex: 0,
      );
      final q1 = IntersectionPoint(
        id: 'q1',
        curve1: line,
        curve2: outer,
        branchIndex: 1,
      );
      construction
        ..add(outer)
        ..add(q0)
        ..add(q1);

      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
        onStep: (_) {
          // Never swapped at any observed real step.
          expect(q0.position!.x, lessThan(0));
          expect(q1.position!.x, greaterThan(0));
        },
      );

      expect(result.detours, 1);
      expect(q0.position!.closeTo(Vec2(-6, 0)), isTrue);
      expect(q1.position!.closeTo(Vec2(6, 0)), isTrue);
    });

    test('the chord and perpendicular bisector of the traced pair stay '
        'real, defined lines across the degenerate crossing', () {
      // The Cinderella payoff demo in miniature: the join of a
      // conjugate pair is real, and so is its perpendicular bisector —
      // both keep rendering while the points are invisible, with no
      // jump through the tangency. On this symmetric rig the bisector
      // is x = 0 for the entire drag, complex phase included — pinned
      // as a continuity check. (Inside the arc the points are not
      // conjugates and both lines are momentarily complex, but the
      // arc's interior is never observed — onStep fires at real
      // parameters only.)
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final chord = LineThroughTwoPoints(id: 'chord', point1: p0, point2: p1);
      final bisector = PerpendicularBisectorLine(
        id: 'bisector',
        point1: p0,
        point2: p1,
      );
      construction
        ..add(chord)
        ..add(bisector);

      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
        onStep: (_) {
          expect(chord.line, isNotNull);
          final b = bisector.line!;
          // A vertical line through the origin: a·0 + b·0 + c = 0 with
          // no y component.
          expect(b.direction.x.abs(), lessThan(1e-9));
          expect(b.distanceTo(Vec2.zero), lessThan(1e-9));
        },
      );
      expect(result.detours, 1);
      expect(chord.line, isNotNull);
      expect(bisector.line, isNotNull);
    });

    (Construction, IntersectionPoint, IntersectionPoint) circlePair(
      Vec2 start,
    ) {
      final construction = Construction();
      final c1 = fp('c1', 0, 0);
      final c2 = fp('c2', start.x, start.y);
      final k1 = FixedRadiusCircle(id: 'k1', center: c1, radius: 2);
      final k2 = FixedRadiusCircle(id: 'k2', center: c2, radius: 2);
      final p0 = IntersectionPoint(
        id: 'p0',
        curve1: k1,
        curve2: k2,
        branchIndex: 0,
      );
      final p1 = IntersectionPoint(
        id: 'p1',
        curve1: k1,
        curve2: k2,
        branchIndex: 1,
      );
      construction
        ..add(c1)
        ..add(c2)
        ..add(k1)
        ..add(k2)
        ..add(p0)
        ..add(p1);
      return (construction, p0, p1);
    }

    test('a near-miss is traced through on the real axis: no detour, no '
        'swap, endpoint = static solve', () {
      // Two r = 2 circles whose centers pass within 4 + 1e-6 — the
      // conjugate roots nearly collide mid-path but never do. The
      // Cinderella bound alone squeezes through; the detour trigger
      // (both step and separation collapsed) never fires, so no arc is
      // planned near the complex branch points and the labels are the
      // real path's own.
      const y = 4.0 + 1e-6;
      final (construction, p0, p1) = circlePair(const Vec2(-6, y));
      final s0 = chartIm(p0.projPoint!).sign;
      final s1 = chartIm(p1.projPoint!).sign;
      final result = construction.recomputeAlongPath(
        'c2',
        const DragPath(Vec2(-6, y), Vec2(6, y)),
      );

      expect(result.detours, 0);
      expect(chartIm(p0.projPoint!).sign, s0);
      expect(chartIm(p1.projPoint!).sign, s1);
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c2', const Vec2(6, y));
      expect(p0.projPoint!.closeTo(tracked0, 1e-6), isTrue);
      expect(p1.projPoint!.closeTo(tracked1, 1e-6), isTrue);
    });

    test('an ultra-tight near-miss starves cleanly rather than risking a '
        'false detour', () {
      // At 4 + 1e-10 the almost-collision sits below the scales the
      // collapse-law samples can resolve; the undershooting estimate
      // keeps every planned arc short of the closest approach, so the
      // pass never winds around the complex branch points — it burns
      // the budget and bails, and the static solve recovers. (A silent
      // swap here would be wrong by ~1e-10 world units; a bail is
      // honest.)
      const y = 4.0 + 1e-10;
      final (construction, p0, p1) = circlePair(const Vec2(-6, y));
      expect(
        () => construction.recomputeAlongPath(
          'c2',
          const DragPath(Vec2(-6, y), Vec2(6, y)),
        ),
        throwsA(isA<TraceStepBudgetException>()),
      );
      expect(p0.tracedBranch.isActive, isFalse);
      expect(p1.tracedBranch.isActive, isFalse);
      construction.moveFreePoint('c2', const Vec2(6, y));
      expect(p0.projPoint, isNotNull);
      expect(p1.projPoint, isNotNull);
    });

    test('a drag ending exactly on the tangency starves and bails: no '
        'valid arc exists around a singular endpoint', () {
      // t* sits at the path's end, so the pass would have to finish at
      // a complex parameter; DetourArc.plan refuses and the controller
      // creeps until the budget throws. The static bail lands both
      // branches on the double root.
      final (construction, p0, p1) = circlePair(const Vec2(0, 6));
      expect(
        () => construction.recomputeAlongPath(
          'c2',
          const DragPath(Vec2(0, 6), Vec2(0, 4)),
        ),
        throwsA(
          isA<TraceStepBudgetException>()
              .having((e) => e.tReached, 'tReached', greaterThan(0.99)),
        ),
      );
      construction.moveFreePoint('c2', const Vec2(0, 4));
      expect(p0.position!.closeTo(const Vec2(0, 2)), isTrue);
      expect(p1.position!.closeTo(const Vec2(0, 2)), isTrue);
    });
  });
}
