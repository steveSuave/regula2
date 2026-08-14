import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';

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
    test('rejects non-free-point ids and non-positive step counts', () {
      final (construction, _, _, _) = lineAndCircle(const Vec2(0, 1));
      const path = DragPath(Vec2(0, 1), Vec2(0, -1));
      expect(
        () => construction.recomputeAlongPath('l', path),
        throwsArgumentError,
      );
      expect(
        () => construction.recomputeAlongPath('c', path, steps: 0),
        throwsArgumentError,
      );
    });
  });

  group('recomputeAlongPath: toy harness (line dragged across a circle)', () {
    test('secant sweep: continuous histories, no branch swap, static '
        'endpoint — identity chains across consecutive paths', () {
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 1));
      final h0 = <ProjPoint>[];
      final h1 = <ProjPoint>[];
      var notifications = 0;
      construction.addListener(() => notifications++);
      void record(double t) {
        h0.add(p0.projPoint!);
        h1.add(p1.projPoint!);
      }

      // Two consecutive legs, like two preview frames: the second seeds
      // from the value the first left behind.
      construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 1), Vec2(0, 0)),
        steps: 20,
        onStep: record,
      );
      construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 0), Vec2(0, -1)),
        steps: 20,
        onStep: record,
      );

      expect(notifications, 2);
      expect(h0, hasLength(40));
      // The circle stays secant to the line throughout (|cy| ≤ 1 < 3), so
      // both branches are real everywhere and never change sides.
      for (final p in h0) {
        expect(p.toVec2()!.x, lessThan(0));
      }
      for (final p in h1) {
        expect(p.toVec2()!.x, greaterThan(0));
      }
      // Continuity: root motion per substep is far below the branch
      // separation (~5.7 world units, chordal ~0.6).
      for (var i = 1; i < h0.length; i++) {
        expect(chordal(h0[i - 1], h0[i]), lessThan(0.01));
        expect(chordal(h1[i - 1], h1[i]), lessThan(0.01));
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
      // both branches complex the whole way (x = cx ± 4i).
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final h0 = <ProjPoint>[];
      final h1 = <ProjPoint>[];
      construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(4, 5)),
        steps: 40,
        onStep: (_) {
          h0.add(p0.projPoint!);
          h1.add(p1.projPoint!);
        },
      );

      final sign0 = chartIm(h0.first).sign;
      final sign1 = chartIm(h1.first).sign;
      expect(sign0, isNot(sign1));
      for (var i = 0; i < h0.length; i++) {
        // Never drawable, never lost: complex the whole way, each branch
        // pinned to its own conjugate side.
        expect(p0.position, isNull);
        expect(chartIm(h0[i]).sign, sign0);
        expect(chartIm(h1[i]).sign, sign1);
        if (i > 0) {
          expect(chordal(h0[i - 1], h0[i]), lessThan(0.05));
          expect(chordal(h1[i - 1], h1[i]), lessThan(0.05));
        }
      }
      // No realness transition happened, so labels are preserved: a
      // fresh static solve at the endpoint picks the same roots.
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', const Vec2(4, 5));
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    });

    test('through a tangency: histories stay continuous at fixed-step '
        'resolution and the endpoint lands in the static candidate set', () {
      // Center descends from y = 5 to y = 0: complex pair → tangency at
      // cy = 3 → real secant pair. 799 steps never hit cy = 3 exactly and
      // bound the √-sized crossing step below chordal 0.25 (√(6h)).
      final (construction, _, p0, p1) = lineAndCircle(const Vec2(0, 5));
      final h0 = <ProjPoint>[];
      final h1 = <ProjPoint>[];
      construction.recomputeAlongPath(
        'c',
        const DragPath(Vec2(0, 5), Vec2(0, 0)),
        steps: 799,
        onStep: (_) {
          h0.add(p0.projPoint!);
          h1.add(p1.projPoint!);
        },
      );

      for (var i = 1; i < h0.length; i++) {
        expect(chordal(h0[i - 1], h0[i]), lessThan(0.25));
        expect(chordal(h1[i - 1], h1[i]), lessThan(0.25));
      }
      // Endpoint agrees with the static solve up to branch labels: each
      // tracked root is one of x = ±3. Which label each branch carries —
      // and whether both grabbed the same root — is deliberately not
      // asserted: at the tangency the conjugate-to-real handoff is a
      // nearest-neighbour tie; collision refusal is Phase 114, the
      // deterministic complex detour Phase 115.
      expect(p0.position!.x.abs(), closeTo(3, 1e-9));
      expect(p0.position!.y.abs(), closeTo(0, 1e-9));
      expect(p1.position!.x.abs(), closeTo(3, 1e-9));
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
      construction.recomputeAlongPath(
        'b',
        const DragPath(Vec2(0, 0), Vec2(4, 4)),
        steps: 20,
        onStep: (t) {
          observedTs.add(t);
          expect(ip.tracedBranch.isActive, isFalse);
        },
      );

      expect(observedTs, [1.0]);
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
      construction.recomputeAlongPath(
        'g',
        const DragPath(Vec2(0, 10), Vec2(0, 9)),
        steps: 5,
        onStep: (_) {
          observed++;
          // Both depend on the dragged point, but the locus-chain member
          // must stay on static branch selection: the sweep-and-restore
          // recompute would drag a tracked root along the sweep.
          expect(chained.tracedBranch.isActive, isFalse);
          expect(untracked.tracedBranch.isActive, isTrue);
        },
      );

      expect(observed, 5);
      expect(untracked.tracedBranch.isActive, isFalse);
    });
  });
}
