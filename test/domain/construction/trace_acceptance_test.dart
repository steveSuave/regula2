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

  group('relabelIsBenign (Phase 121: any candidate count)', () {
    // Real finite points, spaced so the chordal metric is well behaved.
    ProjPoint p(double x, double y) => ProjPoint.real(x, y);

    test('two candidates: a pure renumbering passes, a swap does not', () {
      // The pair barely moves and the canonical order flips. This is the
      // shape the guard was written for, and the general form must agree
      // with the old `1 - index` arithmetic on it exactly.
      final before = [p(1, 3), p(1, -3)];
      final after = [p(1.001, -3), p(1.001, 3)];
      expect(
        relabelIsBenign(
          before: before,
          after: after,
          matchedBefore: 0,
          matchedAfter: 1,
          cap: 0.1,
        ),
        isTrue,
      );
      // Same flip, and the tracked root still barely moves — but the
      // branch it abandoned is nowhere near where it was. The set did
      // not merely renumber, so the flip is not a relabel.
      expect(
        relabelIsBenign(
          before: before,
          after: [p(9, 9), p(1.001, 3)],
          matchedBefore: 0,
          matchedAfter: 1,
          cap: 0.1,
        ),
        isFalse,
      );
    });

    test('four candidates: the case that used to skip the check', () {
      // Before Phase 121 anything but a two-candidate pair returned
      // early, so a conic∩conic member of a locus chain kept no guard at
      // all. Here the set is stationary and the labels rotate by one —
      // benign — and then one root is moved away, which is not.
      final before = [p(4, 0), p(0, 4), p(-4, 0), p(0, -4)];
      final rotated = [p(0, 4.001), p(-4, 0.001), p(0.001, -4), p(4.001, 0)];
      expect(
        relabelIsBenign(
          before: before,
          after: rotated,
          matchedBefore: 0,
          matchedAfter: 3,
          cap: 0.1,
        ),
        isTrue,
      );
      final broken = [...rotated]..[1] = p(-40, 7);
      expect(
        relabelIsBenign(
          before: before,
          after: broken,
          matchedBefore: 0,
          matchedAfter: 3,
          cap: 0.1,
        ),
        isFalse,
        reason: 'the root that was at (0, 4) has no partner within the cap',
      );
    });

    test('the pairing must be a bijection — two roots may not share one', () {
      // Two candidates collapsing onto a third is not a relabel, however
      // close each of them lands to it.
      final before = [p(4, 0), p(0, 4), p(-4, 0), p(0, -4)];
      final collapsed = [p(4, 0), p(-4, 0.001), p(-4, 0.002), p(0, -4)];
      expect(
        relabelIsBenign(
          before: before,
          after: collapsed,
          matchedBefore: 0,
          matchedAfter: 0,
          cap: 0.1,
        ),
        isFalse,
      );
    });

    test('unequal candidate counts impose nothing', () {
      // A root has entered or left the real set, so there is no
      // correspondence to check and the walk's other rules own the case.
      expect(
        relabelIsBenign(
          before: [p(1, 3), p(1, -3)],
          after: [p(1, 3), p(1, -3), p(5, 0), p(-5, 0)],
          matchedBefore: 0,
          matchedAfter: 1,
          cap: 1e-9,
        ),
        isTrue,
      );
    });

    test('a NaN distance refuses, like trialAccepted', () {
      expect(
        relabelIsBenign(
          before: [p(1, 3), p(1, -3)],
          after: [p(1, 3), ProjPoint.real(0, 0, 0)],
          matchedBefore: 0,
          matchedAfter: 0,
          cap: 0.1,
        ),
        isFalse,
      );
    });
  });
}
