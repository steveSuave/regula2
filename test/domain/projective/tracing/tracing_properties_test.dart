import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';

/// Phase 114 glados: random constructions × random smooth drags under the
/// adaptive step controller. The rig is the toy family (fixed line y = 0,
/// dragged circle center), with the generators partitioned by regime —
/// secant throughout, miss throughout, near-tangency approach — so each
/// property can pin the exact continuation behaviour its regime
/// guarantees. Paths *through* a tangency are deliberately absent: they
/// starve the controller by design until Phase 115's detour (pinned
/// deterministically in recompute_along_path_test.dart).
void main() {
  (Construction, FreePoint, IntersectionPoint, IntersectionPoint) rig(
    Vec2 centerStart,
    double radius,
  ) {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
    final b = FreePoint(id: 'b', position: const Vec2(10, 0));
    final center = FreePoint(
      id: 'c',
      position: Vec2(centerStart.x, centerStart.y),
    );
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final circle = FixedRadiusCircle(id: 'k', center: center, radius: radius);
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

  double chartIm(ProjPoint p) => (p.x / p.w).im;

  // Radius in [2, 6] on a 0.1 grid.
  final anyRadius = any.intInRange(20, 61).map((i) => i / 10);
  // Chart abscissa in [-8, 8] on a 0.1 grid.
  final anyX = any.intInRange(-80, 81).map((i) => i / 10);
  // Secant band: |cy| ≤ 0.8·r, as a fraction of the radius, so the roots
  // stay real and at least 0.6·r either side of the center everywhere.
  final anySecantFraction = any.intInRange(-80, 81).map((i) => i / 100);
  // Miss band: cy ≥ r + 0.5 (single sign — crossing the band would pass
  // through two tangencies).
  final anyMissOffset = any.intInRange(5, 41).map((i) => i / 10);
  // Near-tangency gap in [0.001, 0.01].
  final anyGap = any.intInRange(10, 101).map((i) => i / 10000);

  final anySecantDrag = any.combine5(
    anyRadius,
    anyX,
    anySecantFraction,
    anyX,
    anySecantFraction,
    (double r, double x0, double f0, double x1, double f1) =>
        (r, Vec2(x0, f0 * r), Vec2(x1, f1 * r)),
  );

  final anyMissDrag = any.combine5(
    anyRadius,
    anyX,
    anyMissOffset,
    anyX,
    anyMissOffset,
    (double r, double x0, double u0, double x1, double u1) =>
        (r, Vec2(x0, r + u0), Vec2(x1, r + u1)),
  );

  final anyNearTangencyDrag = any.combine3(
    any.intInRange(-20, 21).map((i) => i / 10),
    any.intInRange(-20, 21).map((i) => i / 10),
    anyGap,
    (double x0, double x1, double gap) => (Vec2(x0, 5), Vec2(x1, 3 + gap)),
  );

  Glados(anySecantDrag, ExploreConfig(numRuns: 60)).test(
    'secant drags: real throughout, no branch swap at any accepted step, '
    'endpoint = static solve labels included, trials bounded by the budget',
    ((double, Vec2, Vec2) config) {
      final (r, start, end) = config;
      final (construction, center, p0, p1) = rig(start, r);
      var steps = 0;
      final result = construction.recomputeAlongPath(
        'c',
        DragPath(start, end),
        onStep: (_) {
          steps++;
          // The roots sit at cx ± √(r² − cy²) with |cy| ≤ 0.8r: real,
          // strictly either side of the center — a swap would put a
          // branch on the wrong side.
          final cx = center.position.x;
          expect(p0.position!.x, lessThan(cx));
          expect(p1.position!.x, greaterThan(cx));
        },
      );
      expect(steps, result.acceptedSteps);
      expect(
        result.acceptedSteps + result.rejectedSteps,
        lessThanOrEqualTo(128),
      );
      // No degeneracy on the path, so the endpoint agrees with the
      // static solve including labels.
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', end);
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    },
  );

  Glados(anyMissDrag, ExploreConfig(numRuns: 60)).test(
    'miss drags: complex throughout, each branch pinned to its conjugate '
    'side, endpoint = static solve labels included',
    ((double, Vec2, Vec2) config) {
      final (r, start, end) = config;
      final (construction, _, p0, p1) = rig(start, r);
      final sign0 = chartIm(p0.projPoint!).sign;
      final sign1 = chartIm(p1.projPoint!).sign;
      expect(sign0, isNot(sign1));
      final result = construction.recomputeAlongPath(
        'c',
        DragPath(start, end),
        onStep: (_) {
          expect(p0.position, isNull);
          expect(p1.position, isNull);
          expect(chartIm(p0.projPoint!).sign, sign0);
          expect(chartIm(p1.projPoint!).sign, sign1);
        },
      );
      expect(result.acceptedSteps, greaterThan(0));
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', end);
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    },
  );

  Glados(anyNearTangencyDrag, ExploreConfig(numRuns: 60)).test(
    'adversarial near-tangency approach: the collapsing separation forces '
    'halving, and matching still holds — sides preserved, endpoint = '
    'static solve labels included',
    ((Vec2, Vec2) config) {
      final (start, end) = config;
      final (construction, _, p0, p1) = rig(start, 3);
      final sign0 = chartIm(p0.projPoint!).sign;
      final sign1 = chartIm(p1.projPoint!).sign;
      final result = construction.recomputeAlongPath('c', DragPath(start, end));
      // The whole-path trial moves each root nearly to the touch point —
      // far beyond the Cinderella bound — so the controller must halve.
      expect(result.rejectedSteps, greaterThan(0));
      expect(chartIm(p0.projPoint!).sign, sign0);
      expect(chartIm(p1.projPoint!).sign, sign1);
      final tracked0 = p0.projPoint!;
      final tracked1 = p1.projPoint!;
      construction.moveFreePoint('c', end);
      expect(p0.projPoint!.closeTo(tracked0), isTrue);
      expect(p1.projPoint!.closeTo(tracked1), isTrue);
    },
  );
}
