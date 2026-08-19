import 'dart:math' as math;
import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tolerances.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';
import 'package:regula/domain/projective/tracing/trace_step_budget_exception.dart';
import 'package:regula/domain/projective/tracing/traced_branch.dart';

import '../../../projective_stubs.dart';

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
  }) : super.canonical();

  final List<ProjPoint> staticCandidates;
  final List<ProjPoint> tracedCandidates;
  ProjPoint? _tracked;

  @override
  ProjPoint? get projPoint => _tracked;

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
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

    test(
      'persistent miss: conjugate roots continue through the complex '
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
      },
    );

    test(
      'near-tangency approach: the controller is forced to halve and '
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
      },
    );

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
        throwsA(
          isA<TraceStepBudgetException>().having(
            (e) => e.tReached,
            'tReached',
            allOf(greaterThan(0.2), lessThan(0.4)),
          ),
        ),
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
      // Canonical pair order (id ascending) — the scripted double extends
      // the generative constructor, which asserts it. Line ∩ conic
      // candidates are ordered by *type*, not argument order, so naming
      // the circle first changes nothing the rig depends on.
      final a = _ScriptedIntersectionPoint(
        id: 'sa',
        curve1: circle,
        curve2: line,
        branchIndex: branchA,
        staticCandidates: seeds,
        tracedCandidates: tracedCandidates,
      );
      final b = _ScriptedIntersectionPoint(
        id: 'sb',
        curve1: circle,
        curve2: line,
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
        'the step, and with no step size resolving it the budget starves', () {
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
        throwsA(
          isA<TraceStepBudgetException>()
              .having((e) => e.tReached, 'tReached', 0)
              .having((e) => e.trials, 'trials', 25),
        ),
      );
      expect(accepted, isEmpty);
      expect(a.tracedBranch.isActive, isFalse);
      expect(b.tracedBranch.isActive, isFalse);
    });

    test(
      'a shared grab of coincident candidates (a double root) is benign',
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
        expect(
          (result.acceptedSteps, result.rejectedSteps, result.detours),
          (1, 0, 0),
        );
        expect(a.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
        expect(b.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
      },
    );

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
      expect(
        (result.acceptedSteps, result.rejectedSteps, result.detours),
        (1, 0, 0),
      );
      expect(a.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
      expect(b.projPoint!.closeTo(ProjPoint.real(0.1, 0, 1)), isTrue);
    });
  });

  group('recomputeAlongPath: static fallbacks', () {
    test('nothing seedable collapses to a single static solve at the end', () {
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
      expect(
        (result.acceptedSteps, result.rejectedSteps, result.detours),
        (1, 0, 0),
      );
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

  group('recomputeAlongPath: structural double roots (Phase 117b)', () {
    /// The apatitos-topos.rgl freeze rig: a tangent from a free point C
    /// to a circle, and the point where that tangent meets the circle.
    /// The tangent touches by construction, so the intersection's two
    /// candidates coincide at every position of every parent — a double
    /// root that no step size can separate.
    (Construction, IntersectionPoint) tangencyRig() {
      final construction = Construction();
      final centre = fp('o', 0, 0);
      final rim = fp('r', 2, 0);
      final c = fp('c', -4, 0);
      final circle = CircleCenterPoint(id: 'k', center: centre, onCircle: rim);
      final tangent = TangentLine(
        id: 'tan',
        point: c,
        circle: circle,
        branch: 0,
      );
      final touch = IntersectionPoint(
        id: 'g',
        curve1: tangent,
        curve2: circle,
        branchIndex: 0,
      );
      construction
        ..add(centre)
        ..add(rim)
        ..add(c)
        ..add(circle)
        ..add(tangent)
        ..add(touch);
      return (construction, touch);
    }

    test('the candidates really do coincide — the premise of this group', () {
      final (_, touch) = tangencyRig();
      final candidates = intersectionCandidates(touch.curve1, touch.curve2);
      expect(candidates, hasLength(2));
      expect(
        TracedBranch.candidateSeparation(candidates),
        lessThan(doubleRootEpsilon),
      );
    });

    test('a drag past one does not starve: the pass completes instead of '
        'burning its whole budget and bailing', () {
      // Before 117b this slot seeded, the Cinderella bound (motion <
      // separation/2, with separation ~1e-16) refused every trial, the
      // controller halved to nothing and every frame of every drag in
      // the document threw. Each of those ~130 refused trials recomputed
      // the whole downstream graph, which is what froze the app.
      final (construction, touch) = tangencyRig();
      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(-4, 0), Vec2(-5, 3)),
      );
      expect(result.acceptedSteps, lessThan(8));
      expect(result.rejectedSteps, lessThan(8));
      // And the answer is right: the touch point of the tangent from
      // (−5, 3) still sits on the circle and on the tangent.
      expect(touch.position!.norm, closeTo(2, 1e-9));
    });

    test('an unseedable double root does not stop the pass tracing '
        'everything else', () {
      // A second, genuinely transverse intersection downstream of the
      // same drag must keep its continuation.
      final (construction, _) = tangencyRig();
      final far = fp('f', 0, 6);
      final chord = LineThroughTwoPoints(
        id: 'ch',
        point1: construction.objects.whereType<FreePoint>().first,
        point2: far,
      );
      final circle = construction.objects.whereType<CircleCenterPoint>().single;
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: chord,
        curve2: circle,
        branchIndex: 0,
      );
      construction
        ..add(far)
        ..add(chord)
        ..add(crossing);
      final before = crossing.projPoint!;
      final result = construction.recomputeAlongPath(
        'f',
        const DragPath(Vec2(0, 6), Vec2(1, 6)),
      );
      expect(result.acceptedSteps, greaterThan(0));
      // A short drag cannot move the tracked root far — a swap onto the
      // other branch would jump it across the circle.
      expect(crossing.position!.distanceTo(before.toVec2()!), lessThan(1));
    });
  });

  group('recomputeAlongPath: loci are leaves (Phase 117b)', () {
    test('a locus recomputes once per pass, not once per trial', () {
      // Recomputing a locus is a whole traced sweep of its own, and no
      // acceptance decision can read one (nothing may take a locus as a
      // parent). Before 117b every trial paid for one, so a pass that
      // refined hard — the frozen document's every frame — paid its
      // whole step budget in full locus sweeps.
      final construction = Construction();
      final fixed = fp('a', 0, 0);
      final moving = fp('c2', -6, 4);
      final anchor = fp('an', 10, 10);
      final k1 = FixedRadiusCircle(id: 'k1', center: fixed, radius: 2);
      final k2 = FixedRadiusCircle(id: 'k2', center: moving, radius: 2);
      // Two tracked roots on the circle pair — these make the pass work.
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
      // …and an expensive leaf downstream of the same drag.
      final driver = PointOnObject(id: 'drv', curve: k2, parameter: 0);
      final traced = Midpoint(id: 'm', point1: driver, point2: anchor);
      final locus = _CountingLocus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 32,
      );
      construction
        ..add(fixed)
        ..add(moving)
        ..add(anchor)
        ..add(k1)
        ..add(k2)
        ..add(p0)
        ..add(p1)
        ..add(driver)
        ..add(traced)
        ..add(locus);

      locus.recomputes = 0;
      final result = construction.recomputeAlongPath(
        'c2',
        const DragPath(Vec2(-6, 4), Vec2(6, 4)),
      );
      expect(
        result.acceptedSteps + result.rejectedSteps,
        greaterThan(1),
        reason: 'the pass must actually take several trials to be a test',
      );
      expect(locus.recomputes, 1);
      // Settled at the pass's end state, not left stale.
      expect(locus.samples, isNotNull);
      final tracedSamples = locus.samples!;
      locus.recompute();
      expect(locus.samples, tracedSamples);
    });

    test('a bailing pass still settles its loci', () {
      // The budget path throws, and the public API must not leave a
      // stale locus behind for a caller that catches and carries on.
      // The drag ends exactly on the circles' tangency, where no arc can
      // enclose the singular endpoint and the controller creeps until it
      // throws (the Phase 115 case).
      final construction = Construction();
      final fixed = fp('a', 0, 0);
      final moving = fp('c2', 0, 6);
      final anchor = fp('an', 10, 10);
      final k1 = FixedRadiusCircle(id: 'k1', center: fixed, radius: 2);
      final k2 = FixedRadiusCircle(id: 'k2', center: moving, radius: 2);
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
      final driver = PointOnObject(id: 'drv', curve: k2, parameter: 0);
      final traced = Midpoint(id: 'm', point1: driver, point2: anchor);
      final locus = _CountingLocus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 32,
      );
      construction
        ..add(fixed)
        ..add(moving)
        ..add(anchor)
        ..add(k1)
        ..add(k2)
        ..add(p0)
        ..add(p1)
        ..add(driver)
        ..add(traced)
        ..add(locus);

      locus.recomputes = 0;
      expect(
        () => construction.recomputeAlongPath(
          'c2',
          const DragPath(Vec2(0, 6), Vec2(0, 4)),
        ),
        throwsA(isA<TraceStepBudgetException>()),
      );
      expect(locus.recomputes, 1);
      final tracedSamples = locus.samples;
      locus.recompute();
      expect(locus.samples, tracedSamples, reason: 'settled, not stale');
    });
  });

  group('recomputeAlongPath: complex detour (Phase 115)', () {
    test('through a tangency: the pass detours and crosses — points go '
        'complex, come back real, no jump, no swap, deterministic sides', () {
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

    test('there and back across the tangency trades the two branches, and '
        'a second round trip trades them back (Phase 120c: honest '
        'monodromy)', () {
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final seed0 = p0.projPoint!;
      final seed1 = p1.projPoint!;

      void roundTrip() {
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
      }

      // The half-plane is constant, so the outward leg passes over the
      // branch point and the return leg — which parameterizes the reverse
      // path — passes under it. The round trip closes a loop, and a loop
      // around a branch point is not the identity: the conjugate mates
      // trade places. That is the geometry, not an artifact.
      roundTrip();
      expect(p0.projPoint!.closeTo(seed1, 1e-9), isTrue);
      expect(p1.projPoint!.closeTo(seed0, 1e-9), isTrue);
      expect(chartIm(p0.projPoint!).sign, chartIm(seed1).sign);
      expect(chartIm(p1.projPoint!).sign, chartIm(seed0).sign);

      // The split is an involution, so going round again restores both.
      roundTrip();
      expect(p0.projPoint!.closeTo(seed0, 1e-9), isTrue);
      expect(p1.projPoint!.closeTo(seed1, 1e-9), isTrue);
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
          isA<TraceStepBudgetException>().having(
            (e) => e.tReached,
            'tReached',
            greaterThan(0.99),
          ),
        ),
      );
      construction.moveFreePoint('c2', const Vec2(0, 4));
      expect(p0.position!.closeTo(const Vec2(0, 2)), isTrue);
      expect(p1.position!.closeTo(const Vec2(0, 2)), isTrue);
    });
  });

  group('recomputeAlongPath: round trips are honest (Phase 120c)', () {
    /// Two equal-radius circles on free centres, overlapping, with one
    /// crossing materialized — the reported rig, and the shape of
    /// `cinderella-jumping.rgl`. Dragging b left past |ab| = 2r and back
    /// crosses one tangency in each direction.
    (Construction, IntersectionPoint) equalCircles() {
      final construction = Construction();
      final a = fp('a', 0, 0);
      final b = fp('b', -120, 0);
      final k1 = FixedRadiusCircle(id: 'k1', center: a, radius: 100);
      final k2 = FixedRadiusCircle(id: 'k2', center: b, radius: 100);
      final p = IntersectionPoint(
        id: 'p',
        curve1: k1,
        curve2: k2,
        branchIndex: 0,
      );
      construction
        ..add(a)
        ..add(b)
        ..add(k1)
        ..add(k2)
        ..add(p);
      return (construction, p);
    }

    /// Drags b out to x = −300 and back to −120 [trips] times, over
    /// [frames] frames each way, with [jitter] world units of noise in y
    /// — pointer sampling. Returns the sign of the crossing's y.
    double roundTrips(int trips, int frames, double jitter, int seed) {
      final (construction, p) = equalCircles();
      final rng = math.Random(seed);
      final memory = <String, ProjPoint>{};
      var from = const Vec2(-120, 0);
      double y() => (rng.nextDouble() - 0.5) * 2 * jitter;
      final targets = <Vec2>[
        for (var trip = 0; trip < trips; trip++) ...[
          for (var i = 1; i <= frames; i++) Vec2(-120 - 180 * i / frames, y()),
          for (var i = 1; i <= frames; i++) Vec2(-300 + 180 * i / frames, y()),
        ],
      ];
      for (final to in targets) {
        try {
          construction.recomputeAlongPath(
            'b',
            DragPath(from, to),
            seedMemory: memory,
          );
        } on TraceStepBudgetException {
          memory.clear();
          construction.moveFreePoint('b', to);
        }
        from = to;
      }
      return p.position!.y.sign;
    }

    test('one round trip trades the crossings, two restore them', () {
      // The detour half-plane is constant, so a round trip closes a loop
      // around the branch point. A loop around a branch point is not the
      // identity — the two crossings genuinely trade places, which is
      // Cinderella's behaviour and the geometry's own answer. The root
      // split is an involution, so a second trip trades them back.
      final start = roundTrips(0, 20, 0, 0);
      expect(start, -1, reason: 'the rig starts on the lower crossing');
      expect(roundTrips(1, 20, 0, 0), -start);
      expect(roundTrips(2, 20, 0, 0), start);
      expect(roundTrips(3, 20, 0, 0), -start);
    });

    test('the outcome does not depend on pointer noise or frame timing', () {
      // The defect this convention also closes: the old rule read the
      // half-plane off the drag direction, taking its sign from dy and
      // consulting dx only when dy was exactly zero — so its seam lay on
      // the horizontal axis, which is where this gesture lives, and a
      // twentieth of a pixel of jitter flipped the result about a third
      // of the time. A constant reads nothing about the gesture, so
      // there is no seam for noise to land on.
      final expected = roundTrips(1, 20, 0, 0);
      for (final jitter in [0.0, 0.05, 1.0]) {
        for (var seed = 0; seed < 20; seed++) {
          expect(
            roundTrips(1, 20, jitter, 1000 + seed),
            expected,
            reason: 'jitter $jitter, seed $seed disagreed',
          );
        }
      }
      // Coarse frames are a fast pointer: fewer, wider passes.
      for (var seed = 0; seed < 20; seed++) {
        expect(roundTrips(1, 3, 1, 2000 + seed), expected);
      }
    });

    test('a round trip split across two gestures trades them too', () {
      // Gesture boundaries drop the seed memory and clear the slots, with
      // a static solve in between. The half-plane is a constant, so
      // nothing about the outcome depends on where the gestures split.
      final (construction, p) = equalCircles();
      final side = p.position!.y.sign;
      construction.recomputeAlongPath(
        'b',
        const DragPath(Vec2(-120, 0), Vec2(-300, 0)),
      );
      construction.moveFreePoint('b', const Vec2(-300, 0));
      construction.recomputeAlongPath(
        'b',
        const DragPath(Vec2(-300, 0), Vec2(-120, 0)),
      );
      expect(p.position!.y.sign, -side);
    });
  });

  group('recomputeAlongPath: branch adoption (Phase 116)', () {
    /// The relabel rig: a line through free a(−10,0) and free b — the
    /// dragged point — and a fixed circle floating at (0,5) with radius
    /// 3, so the branches are the conjugate pair x = ±4i for as long as
    /// b stays on the axis. Dragging b past a reverses the direction
    /// anchor b−a, which flips the canonical conjugate order while the
    /// roots themselves sit still.
    (Construction, IntersectionPoint, IntersectionPoint) relabelRig() {
      final construction = Construction();
      final a = fp('a', -10, 0);
      final b = fp('b', 10, 0);
      final center = fp('c', 0, 5);
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
      return (construction, p0, p1);
    }

    test('a pass that flips canonical order under still roots adopts the '
        'flipped indices — the next static recompute reproduces the traced '
        'branch', () {
      final (construction, p0, p1) = relabelRig();
      final side0 = chartIm(p0.projPoint!).sign;
      final side1 = chartIm(p1.projPoint!).sign;
      expect(side0, isNot(side1));

      construction.recomputeAlongPath(
        'b',
        const DragPath(Vec2(10, 0), Vec2(-20, 0)),
      );

      // The tracked roots never moved, but their canonical addresses did
      // — and the pass re-derived branchIndex to match.
      expect(p0.branchIndex, 1);
      expect(p1.branchIndex, 0);
      expect(chartIm(p0.projPoint!).sign, side0);
      expect(chartIm(p1.projPoint!).sign, side1);

      // The payoff: a static recompute at the same state — a commit, a
      // bail, a reload — now re-selects the traced branch instead of
      // relabeling by the pre-drag index.
      construction.moveFreePoint('b', const Vec2(-20, 0));
      expect(chartIm(p0.projPoint!).sign, side0);
      expect(chartIm(p1.projPoint!).sign, side1);
    });

    test('a pass that preserves canonical order adopts nothing: the '
        'tangency crossing keeps both indices', () {
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final result = construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
      );
      expect(result.detours, 1);
      expect(p0.branchIndex, 0);
      expect(p1.branchIndex, 1);
    });

    test('a pass whose final step coasts adopts nothing: no candidates at '
        'the end means no canonical address to re-derive', () {
      // b ends exactly on a — the carrier line degenerates, candidates
      // vanish, the branches coast to the end. branchIndex must survive
      // untouched for the static solve to keep addressing sanely.
      final (construction, p0, p1) = relabelRig();
      construction.recomputeAlongPath(
        'b',
        const DragPath(Vec2(10, 0), Vec2(-10, 0)),
      );
      expect(p0.projPoint, isNull);
      expect(p0.branchIndex, 0);
      expect(p1.branchIndex, 1);
    });

    // Phase 120c, from `ellipse-intersection-issue.rgl`: two ellipses
    // crossing four times, dragged until the crossings vanish and come
    // back. The user's saved file had six intersection points on the
    // pair, four of them stored at branchIndex 1.
    //
    // Adoption was capped at matchedIndex <= 1 — right while two
    // candidates was all any carrier pair could produce, and left behind
    // when Phase 120's conics made four reachable. The cap does not
    // merely skip adoption: it makes it *asymmetric*. A root landing at
    // index 0 or 1 writes back while one landing at 2 or 3 does not, so
    // two branches converge onto the same stored index and the next
    // static recompute puts both points on the same root.
    (Construction, List<IntersectionPoint>) fourWayRig() {
      final construction = Construction();
      final foci = [
        fp('a1', 276.28515625, -549.99609375),
        fp('a2', 852.93359375, -511.88671875),
        fp('a3', 527.05859375, -349.2734375),
        fp('b1', 558.8051299943472, -469.1066983991435),
        fp('b2', 550.9898345406327, -561.0437497250491),
        fp('b3', 343.23828125, -549.99609375),
      ];
      for (final p in foci) {
        construction.add(p);
      }
      final e1 = BifocalConic(
        id: 'e1',
        focus1: foci[0],
        focus2: foci[1],
        point: foci[2],
        difference: false,
      );
      final e2 = BifocalConic(
        id: 'e2',
        focus1: foci[3],
        focus2: foci[4],
        point: foci[5],
        difference: false,
      );
      construction
        ..add(e1)
        ..add(e2);
      final points = [
        for (var i = 0; i < 4; i++)
          IntersectionPoint(id: 'i$i', curve1: e1, curve2: e2, branchIndex: i),
      ];
      for (final p in points) {
        construction.add(p);
      }
      return (construction, points);
    }

    test('adoption is atomic per curve pair: many random drags never leave '
        'two branches on one address (Phase 120c)', () {
      // The guards on adoption are *per point*, so a pass could adopt for
      // some points on a pair and not others — and a stale index can
      // collide with a freshly adopted one. Two points on the same
      // ordered pair sharing a branchIndex are the same intersection by
      // construction: they resolve to the same candidate for ever, no
      // later pass separates them, and the user sees two points stacked
      // on one crossing with another empty. Collision refusal makes that
      // unreachable within a pass; adoption now refuses to *write* it
      // too, per pair, all-or-nothing.
      final random = math.Random(20250817);
      for (var trial = 0; trial < 60; trial++) {
        final (construction, points) = fourWayRig();
        var from = const Vec2(527.05859375, -349.2734375);
        for (var move = 0; move < 4; move++) {
          final to = Vec2(
            420 + random.nextDouble() * 220,
            -560 + random.nextDouble() * 420,
          );
          try {
            construction.recomputeAlongPath('a3', DragPath(from, to));
          } on TraceStepBudgetException {
            construction.moveFreePoint('a3', to);
          }
          from = to;
          expect(
            points.map((p) => p.branchIndex).toSet(),
            hasLength(4),
            reason:
                'trial $trial move $move collapsed: '
                '${points.map((p) => p.branchIndex).toList()}',
          );
        }
      }
    });

    test('four conic∩conic branches keep four distinct canonical addresses '
        'across a drag (Phase 120c)', () {
      final (construction, points) = fourWayRig();
      expect(
        intersectionCandidates(points.first.curve1, points.first.curve2).length,
        4,
      );
      expect(points.map((p) => p.branchIndex).toSet(), {0, 1, 2, 3});
      expect(points.every((p) => p.position != null), isTrue);

      // Drag the third free point so the crossings go complex and return.
      var from = const Vec2(527.05859375, -349.2734375);
      for (final to in const [
        Vec2(527, -300),
        Vec2(527, -250),
        Vec2(527, -300),
        Vec2(527.05859375, -349.2734375),
      ]) {
        try {
          construction.recomputeAlongPath('a3', DragPath(from, to));
        } on TraceStepBudgetException {
          // A starving frame bails to the static solve, exactly as the
          // drag session's preview does; identity is what is under test.
          construction.moveFreePoint('a3', to);
        }
        from = to;
        // The invariant: distinct branches address distinct roots. A
        // collision here is the double point the user saw, and the tool
        // then stacks a fresh object on the crossing left unoccupied.
        expect(
          points.map((p) => p.branchIndex).toSet(),
          hasLength(4),
          reason:
              'branches collapsed after dragging to $to: '
              '${points.map((p) => '${p.id}#${p.branchIndex}').join(' ')}',
        );
      }
    });
  });

  group('the parameter drive on a general conic host (Phase 132)', () {
    // `_chartEvaluator` had two arms — a line's `pointAt` and a circle's
    // — and *threw* for anything else, on the argument that an undefined
    // carrier leaves every dependent candidate-free so a detour is
    // unreachable. Phase 132 made a conic host a *defined* carrier with
    // no `CircleEq`, which is exactly the case that argument does not
    // cover, so the throw became reachable and the arm is now real.
    (Construction, PointOnObject, FivePointConic) conicRig() {
      final construction = Construction();
      final pts = [
        fp('c0', 4, 0),
        fp('c1', 0, 3),
        fp('c2', -4, 0),
        fp('c3', 0, -3),
        fp('c4', 2.4, 2.4),
      ];
      final k = FivePointConic(id: 'k', points: pts);
      final glued = PointOnObject(id: 'g', curve: k, parameter: 0.2);
      for (final p in pts) {
        construction.add(p);
      }
      construction
        ..add(k)
        ..add(glued);
      return (construction, glued, k);
    }

    test('a real parameter path drives the point along the conic', () {
      final (construction, glued, k) = conicRig();
      final seen = <double>[];
      construction.recomputeAlongParameterPath('g', 0.2, 2.6, onStep: seen.add);
      expect(glued.isDefined, isTrue);
      expect(glued.parameter, closeTo(2.6, 1e-12));
      expect(
        k.conic!.containsPoint(glued.projPoint!, 1e-9),
        isTrue,
        reason: 'every real step lands on the curve',
      );
      expect(seen, isNotEmpty);
    });

    test('the drive ends bitwise on the static solve at the path end', () {
      // What the evaluator's "real angle reproduces the real evaluation"
      // property buys: the commit's static recompute must not move the
      // point the drive left behind.
      final (construction, glued, _) = conicRig();
      construction.recomputeAlongParameterPath('g', 0.2, 1.9);
      final afterDrive = glued.position!;
      glued.recompute();
      expect(glued.position!.x, afterDrive.x);
      expect(glued.position!.y, afterDrive.y);
    });

    test('an unparameterized conic host still refuses to continue', () {
      // The evaluator's guard is `isParameterized`, not "is a GeoCircle":
      // an imaginary ellipse has a conic and no ink, and there is nothing
      // to walk along.
      final construction = Construction();
      final empty = StubProjectiveConic(
        const ConicMatrix(
          Complex.one,
          Complex.zero,
          Complex.one,
          Complex.zero,
          Complex.zero,
          Complex.one,
        ),
        id: 'e',
      );
      final glued = PointOnObject(id: 'g', curve: empty, parameter: 0.3);
      construction
        ..add(empty)
        ..add(glued);
      expect(glued.isDefined, isFalse);
    });
  });

  group('recomputeAlongParameterPath (Phase 116b): the parameter drive', () {
    /// The Cinderella no-jump demo: C and D constrained to the line
    /// y = 0, an equal circle around each, E0/E1 the circle∩circle pair
    /// (parent order circleD, circleC — like the original file). Sliding
    /// C across D reverses the directed center line, flipping canonical
    /// order under roots that never approach each other (they sit at
    /// ±√(r² − d²/4) on the perpendicular bisector); at exact
    /// coincidence the circles are identical and E is undefined.
    /// Returns (construction, C, D, E0, E1); C sits at x = 5, D at
    /// x = −2, radii 6.
    (
      Construction,
      PointOnObject,
      PointOnObject,
      IntersectionPoint,
      IntersectionPoint,
    )
    cinderellaRig() {
      final construction = Construction();
      final a = fp('a', -10, 0);
      final b = fp('b', 10, 0);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      construction
        ..add(a)
        ..add(b)
        ..add(line);
      final form = line.line!;
      final c = PointOnObject(
        id: 'C',
        curve: line,
        parameter: form.parameterAt(const Vec2(5, 0)),
      );
      final d = PointOnObject(
        id: 'D',
        curve: line,
        parameter: form.parameterAt(const Vec2(-2, 0)),
      );
      final circleC = FixedRadiusCircle(id: 'kC', center: c, radius: 6);
      final circleD = FixedRadiusCircle(id: 'kD', center: d, radius: 6);
      final e0 = IntersectionPoint(
        id: 'E0',
        curve1: circleD,
        curve2: circleC,
        branchIndex: 0,
      );
      final e1 = IntersectionPoint(
        id: 'E1',
        curve1: circleD,
        curve2: circleC,
        branchIndex: 1,
      );
      construction
        ..add(c)
        ..add(d)
        ..add(circleC)
        ..add(circleD)
        ..add(e0)
        ..add(e1);
      return (construction, c, d, e0, e1);
    }

    double ySide(IntersectionPoint p) => p.position!.y.sign;

    test('validation: rejects non-constrained-point ids and non-positive '
        'budgets', () {
      final (construction, c, _, _, _) = cinderellaRig();
      expect(
        () => construction.recomputeAlongParameterPath('l', 0, 1),
        throwsArgumentError,
      );
      expect(
        () => construction.recomputeAlongParameterPath(
          'C',
          c.parameter,
          c.parameter + 1,
          stepBudget: 0,
        ),
        throwsArgumentError,
      );
    });

    test('the Cinderella demo: sliding C across D never swaps E — sides '
        'hold at every observed step, the flip is adopted, and the static '
        'solve then reproduces the traced branch', () {
      final (construction, c, d, e0, e1) = cinderellaRig();
      final side0 = ySide(e0);
      final side1 = ySide(e1);
      expect(side0, isNot(side1));

      // Across D (at parameter for x = −2) to x = −9. The interior
      // parameter where C == D is hit or straddled by dyadic trials;
      // either way the sides must never flip while E is defined.
      final line = construction.byId('l')! as LineThroughTwoPoints;
      final to = line.line!.parameterAt(const Vec2(-9, 0));
      construction.recomputeAlongParameterPath(
        'C',
        c.parameter,
        to,
        onStep: (_) {
          if (e0.position != null) {
            expect(ySide(e0), side0);
            expect(ySide(e1), side1);
          }
        },
      );

      expect(c.position!.closeTo(const Vec2(-9, 0)), isTrue);
      expect(ySide(e0), side0);
      expect(ySide(e1), side1);
      // The directed center line reversed: canonical order flipped and
      // the pass adopted it. The rig names the circles kD, kC — the
      // non-canonical order — so the constructor stored (kC, kD) and
      // renumbered both points onto it (Phase 120c); the *sides* asserted
      // above are what the demo is about, and the indices are their
      // mirror.
      expect(e0.branchIndex, 0);
      expect(e1.branchIndex, 1);
      // A static recompute — commit, bail, reload — re-selects the
      // traced branch.
      construction.setPointOnObjectParameter('C', to);
      expect(ySide(e0), side0);
      expect(ySide(e1), side1);
      expect(d.position!.closeTo(const Vec2(-2, 0)), isTrue);
    });

    test('seed memory bridges a pass boundary that lands exactly on the '
        'degeneracy: identity survives the undefined frame; without it, '
        'the next pass relabels statically', () {
      final (construction, c, _, e0, e1) = cinderellaRig();
      final side0 = ySide(e0);
      final form = (construction.byId('l')! as LineThroughTwoPoints).line!;
      final atD = form.parameterAt(const Vec2(-2, 0));
      final past = form.parameterAt(const Vec2(-9, 0));

      // With memory: frame 1 ends on coincident circles (E undefined,
      // roots remembered), frame 2 re-seeds from memory and E re-emerges
      // on its own side, adoption recorded.
      final memory = <String, ProjPoint>{};
      construction.recomputeAlongParameterPath(
        'C',
        c.parameter,
        atD,
        seedMemory: memory,
      );
      expect(e0.position, isNull);
      expect(memory, contains('E0'));
      construction.recomputeAlongParameterPath(
        'C',
        atD,
        past,
        seedMemory: memory,
      );
      expect(ySide(e0), side0);
      // Mirrored by the canonical pair order, as above.
      expect(e0.branchIndex, 0);

      // The discriminator, on a fresh rig: the same two passes without
      // memory lose the identity at the undefined boundary — the second
      // pass has nothing to seed, collapses to the static solve, and the
      // pre-drag branchIndex lands E0 on the other side. If this ever
      // holds sides, the rig no longer separates memory from statics.
      final (construction2, c2, _, e0b, _) = cinderellaRig();
      construction2.recomputeAlongParameterPath('C', c2.parameter, atD);
      expect(e0b.position, isNull);
      construction2.recomputeAlongParameterPath('C', atD, past);
      expect(ySide(e0b), -side0);
    });

    test('a tangency slide detours and crosses (line carrier): same '
        'canonical shape as the free-point drag, driven by parameter', () {
      // A vertical carrier x = 0, the circle's center constrained to it,
      // sliding down from y = 5 to y = 0 across the tangency with the
      // baseline at y = 3 — the parameter-drive twin of the Phase 115
      // canonical test.
      final construction = Construction();
      final a = fp('a', -10, 0);
      final b = fp('b', 10, 0);
      final v1 = fp('v1', 0, -10);
      final v2 = fp('v2', 0, 10);
      final baseline = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final carrier = LineThroughTwoPoints(id: 'v', point1: v1, point2: v2);
      construction
        ..add(a)
        ..add(b)
        ..add(v1)
        ..add(v2)
        ..add(baseline)
        ..add(carrier);
      final form = carrier.line!;
      final m = PointOnObject(
        id: 'M',
        curve: carrier,
        parameter: form.parameterAt(const Vec2(0, 5)),
      );
      final circle = FixedRadiusCircle(id: 'k', center: m, radius: 3);
      final p0 = IntersectionPoint(
        id: 'p0',
        curve1: baseline,
        curve2: circle,
        branchIndex: 0,
      );
      final p1 = IntersectionPoint(
        id: 'p1',
        curve1: baseline,
        curve2: circle,
        branchIndex: 1,
      );
      construction
        ..add(m)
        ..add(circle)
        ..add(p0)
        ..add(p1);
      final seed0 = p0.projPoint!;
      final seed1 = p1.projPoint!;
      final top = m.parameter;
      final bottom = form.parameterAt(const Vec2(0, 0));

      final down = construction.recomputeAlongParameterPath('M', top, bottom);
      expect(down.detours, 1);
      // Crossed and real, endpoint = static solve, labels included.
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      expect(p0.position, isNotNull);
      expect(p1.position, isNotNull);
      construction.setPointOnObjectParameter('M', bottom);
      expect(p0.projPoint!.closeTo(tracked0, 1e-6), isTrue);
      expect(p1.projPoint!.closeTo(tracked1, 1e-6), isTrue);

      // A round trip trades the branches, like the free-point drag: the
      // parameter drive takes the same constant half-plane, so its
      // reversal closes the same loop around the branch point (Phase
      // 120c). A second trip restores them.
      final up = construction.recomputeAlongParameterPath('M', bottom, top);
      expect(up.detours, 1);
      expect(p0.projPoint!.closeTo(seed1, 1e-9), isTrue);
      expect(p1.projPoint!.closeTo(seed0, 1e-9), isTrue);
      construction.recomputeAlongParameterPath('M', top, bottom);
      construction.recomputeAlongParameterPath('M', bottom, top);
      expect(p0.projPoint!.closeTo(seed0, 1e-9), isTrue);
      expect(p1.projPoint!.closeTo(seed1, 1e-9), isTrue);
    });

    test('a circle-carrier drive detours through tangency: the chart form '
        'continues through complex cos/sin', () {
      // The center rides a circle of radius 5 about the origin; its
      // radius-3 circle crosses tangency with the baseline y = 0 where
      // 5·sin θ = 3 (θ ≈ 0.6435), between the slide's θ = 1.2 and 0.3.
      final construction = Construction();
      final a = fp('a', -10, 0);
      final b = fp('b', 10, 0);
      final hub = fp('h', 0, 0);
      final baseline = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final carrier = FixedRadiusCircle(id: 'c5', center: hub, radius: 5);
      construction
        ..add(a)
        ..add(b)
        ..add(hub)
        ..add(baseline)
        ..add(carrier);
      final m = PointOnObject(id: 'M', curve: carrier, parameter: 1.2);
      final circle = FixedRadiusCircle(id: 'k', center: m, radius: 3);
      final p0 = IntersectionPoint(
        id: 'p0',
        curve1: baseline,
        curve2: circle,
        branchIndex: 0,
      );
      final p1 = IntersectionPoint(
        id: 'p1',
        curve1: baseline,
        curve2: circle,
        branchIndex: 1,
      );
      construction
        ..add(m)
        ..add(circle)
        ..add(p0)
        ..add(p1);
      expect(p0.position, isNull); // still a miss at θ = 1.2

      final result = construction.recomputeAlongParameterPath('M', 1.2, 0.3);
      expect(result.detours, 1);
      expect(p0.position, isNotNull);
      expect(p1.position, isNotNull);
      // Endpoint = static solve, labels included.
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.setPointOnObjectParameter('M', 0.3);
      expect(p0.projPoint!.closeTo(tracked0, 1e-6), isTrue);
      expect(p1.projPoint!.closeTo(tracked1, 1e-6), isTrue);
    });
  });
}

/// A [Locus] that counts its recomputes — the leaf-deferral probe.
class _CountingLocus extends Locus {
  _CountingLocus({
    required super.id,
    required super.driver,
    required super.traced,
    super.sampleCount,
  });

  int recomputes = 0;

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    recomputes++;
    super.recompute();
  }
}
