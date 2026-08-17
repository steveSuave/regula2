import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/trace_acceptance.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tracing/traced_branch.dart';

/// The two-circle rig: unit-ish circles around A(0,0) and B(2,0), radius
/// 2 each — real transverse intersections at (1, ±√3). Returns the
/// pieces the acceptance helpers operate on.
(FreePoint, FreePoint, FixedRadiusCircle, FixedRadiusCircle) _rig() {
  final a = FreePoint(id: 'a', position: Vec2.zero);
  final b = FreePoint(id: 'b', position: const Vec2(2, 0));
  final c1 = FixedRadiusCircle(id: 'c1', center: a, radius: 2);
  final c2 = FixedRadiusCircle(id: 'c2', center: b, radius: 2);
  return (a, b, c1, c2);
}

void main() {
  group('minSeparation', () {
    test('is the tightest slot separation, infinity when unconstrained', () {
      final (_, _, c1, c2) = _rig();
      final ip = IntersectionPoint(
        id: 'i',
        curve1: c1,
        curve2: c2,
        branchIndex: 0,
      );
      expect(
        minSeparation([ip]),
        double.infinity,
        reason: 'inactive/unseeded slot imposes nothing',
      );
      final candidates = intersectionCandidates(c1, c2);
      ip.tracedBranch.seed(ip.projPoint!, candidates: candidates);
      expect(
        minSeparation([ip]),
        TracedBranch.chordalDistance(candidates[0], candidates[1]),
      );
      ip.tracedBranch.clear();
    });
  });

  group('trialAccepted', () {
    test('accepts small motion, refuses motion over half the separation', () {
      final (_, b, c1, c2) = _rig();
      final ip = IntersectionPoint(
        id: 'i',
        curve1: c1,
        curve2: c2,
        branchIndex: 0,
      );
      final branch = ip.tracedBranch;
      branch.seed(ip.projPoint!, candidates: intersectionCandidates(c1, c2));
      final checkpoints = [branch.checkpoint()];

      // Tiny move of B: the tracked root barely moves — accepted.
      b.position = const Vec2(2.001, 0);
      c2.recompute();
      ip.recompute();
      expect(branch.motion, lessThan(checkpoints[0].separation / 2));
      expect(trialAccepted([ip], checkpoints, 1), isTrue);

      // A follow whose nearest candidate is far away: the motion
      // exceeds min(sep/2, maxAcceptedMotion) — refused.
      branch.follow([
        ProjPoint.lift(const Vec2(100, 0)),
        ProjPoint.lift(const Vec2(0, 100)),
      ]);
      expect(branch.motion, greaterThan(maxAcceptedMotion));
      expect(trialAccepted([ip], checkpoints, 1), isFalse);
      branch.clear();
    });

    test('coast entry is refused on a wide trial, allowed on a tiny one', () {
      final (_, b, c1, c2) = _rig();
      final ip = IntersectionPoint(
        id: 'i',
        curve1: c1,
        curve2: c2,
        branchIndex: 0,
      );
      final branch = ip.tracedBranch;
      branch.seed(ip.projPoint!, candidates: intersectionCandidates(c1, c2));
      final checkpoints = [branch.checkpoint()];

      // Collapse the circles onto each other: coincident carriers have
      // no candidates (merely *complex* roots would still be followed —
      // the kernel is total), so the branch coasts.
      b.position = Vec2.zero;
      c2.recompute();
      ip.recompute();
      expect(branch.hasCandidates, isFalse);
      expect(
        trialAccepted([ip], checkpoints, 0.5),
        isFalse,
        reason: 'match→coast on a wide trial hides a degeneracy',
      );
      expect(
        trialAccepted([ip], checkpoints, maxCoastEntrySpan),
        isTrue,
        reason: 'a localized degeneracy may be coasted into',
      );

      // Coast→coast stays permissive at any span.
      final coasting = [branch.checkpoint()];
      ip.recompute();
      expect(trialAccepted([ip], coasting, 1), isTrue);
      branch.clear();
    });
  });

  group('collision refusal', () {
    test('two branches grabbing the same candidate refuse the trial', () {
      final (_, _, c1, c2) = _rig();
      final ip1 = IntersectionPoint(
        id: 'i1',
        curve1: c1,
        curve2: c2,
        branchIndex: 0,
      );
      final ip2 = IntersectionPoint(
        id: 'i2',
        curve1: c1,
        curve2: c2,
        branchIndex: 1,
      );
      final candidates = intersectionCandidates(c1, c2);
      ip1.tracedBranch.seed(candidates[0], candidates: candidates);
      // Seed ip2 *near* candidate 0 (distinct beyond doubleRootEpsilon):
      // both branches will match candidate 0 — the ambiguous grab.
      final near0 = candidates[0].toVec2()! + const Vec2(1e-4, 0);
      ip2.tracedBranch.seed(ProjPoint.lift(near0), candidates: candidates);
      final pairs = collisionCheckPairs([ip1, ip2]);
      expect(pairs, hasLength(1), reason: 'distinct seeds are checked');
      ip1.recompute();
      ip2.recompute();
      expect(ip1.tracedBranch.matchedIndex, ip2.tracedBranch.matchedIndex);
      expect(collisionFree(pairs), isFalse);
      ip1.tracedBranch.clear();
      ip2.tracedBranch.clear();
    });

    test('married seeds (coincident) are exempt from checking', () {
      final (_, _, c1, c2) = _rig();
      final ip1 = IntersectionPoint(
        id: 'i1',
        curve1: c1,
        curve2: c2,
        branchIndex: 0,
      );
      final ip2 = IntersectionPoint(
        id: 'i2',
        curve1: c1,
        curve2: c2,
        branchIndex: 0,
      );
      final candidates = intersectionCandidates(c1, c2);
      ip1.tracedBranch.seed(candidates[0], candidates: candidates);
      ip2.tracedBranch.seed(candidates[0], candidates: candidates);
      expect(collisionCheckPairs([ip1, ip2]), isEmpty);
      ip1.tracedBranch.clear();
      ip2.tracedBranch.clear();
    });
  });
}
