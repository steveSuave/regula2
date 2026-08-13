import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/intersections.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../math/generators.dart';

void main() {
  FreePoint fp(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  LineThroughTwoPoints lineThrough(String id, GeoPointPair pair) =>
      LineThroughTwoPoints(id: id, point1: pair.$1, point2: pair.$2);

  group('IntersectionPoint: line ∩ line', () {
    test('finds the crossing, branch 0', () {
      final l1 = lineThrough('l1', (fp('a', -1, 0), fp('b', 1, 0)));
      final l2 = lineThrough('l2', (fp('c', 0, -1), fp('d', 0, 1)));
      final x = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );
      expect(x.position!.closeTo(Vec2.zero), isTrue);
    });

    test('undefined for parallel lines, recovers when they tilt', () {
      final a = fp('a', 0, 0);
      final b = fp('b', 4, 0);
      final l1 = lineThrough('l1', (a, b));
      final l2 = lineThrough('l2', (fp('c', 0, 1), fp('d', 4, 1)));
      final x = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );
      expect(x.isDefined, isFalse);

      b.position = const Vec2(4, 2); // tilt l1 so they cross
      l1.recompute();
      x.recompute();
      expect(x.isDefined, isTrue);
      expect(x.position!.closeTo(const Vec2(2, 1)), isTrue);
    });
  });

  group('IntersectionPoint: line ∩ circle', () {
    test('branches are ordered along the line direction, both orders', () {
      // Horizontal line left→right through a unit circle at the origin.
      final l = lineThrough('l', (fp('a', -2, 0), fp('b', 2, 0)));
      final k = CircleCenterPoint(
        id: 'k',
        center: fp('c', 0, 0),
        onCircle: fp('p', 1, 0),
      );
      final first = IntersectionPoint(
        id: 'x0',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      // Curve order swapped: branch meaning must not change, because the
      // line's role is fixed by type, not argument position.
      final second = IntersectionPoint(
        id: 'x1',
        curve1: k,
        curve2: l,
        branchIndex: 1,
      );
      expect(first.position!.closeTo(const Vec2(-1, 0)), isTrue);
      expect(second.position!.closeTo(const Vec2(1, 0)), isTrue);
    });

    test('both branches clamp to the single point at tangency', () {
      final l = lineThrough('l', (fp('a', -2, 1), fp('b', 2, 1)));
      final k = CircleCenterPoint(
        id: 'k',
        center: fp('c', 0, 0),
        onCircle: fp('p', 1, 0),
      );
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: l,
        curve2: k,
        branchIndex: 1,
      );
      expect(x0.position!.closeTo(const Vec2(0, 1)), isTrue);
      expect(x1.position!.closeTo(const Vec2(0, 1)), isTrue);
    });

    test('survives a drag through no-intersection and back', () {
      final a = fp('a', -2, 0);
      final b = fp('b', 2, 0);
      final l = lineThrough('l', (a, b));
      final k = CircleCenterPoint(
        id: 'k',
        center: fp('c', 0, 0),
        onCircle: fp('p', 1, 0),
      );
      final x = IntersectionPoint(
        id: 'x',
        curve1: l,
        curve2: k,
        branchIndex: 1,
      );
      expect(x.position!.closeTo(const Vec2(1, 0)), isTrue);

      // Drag the line far above the circle: no intersection.
      a.position = const Vec2(-2, 5);
      b.position = const Vec2(2, 5);
      l.recompute();
      x.recompute();
      expect(x.isDefined, isFalse);

      // Drag back: same branch reappears.
      a.position = const Vec2(-2, 0);
      b.position = const Vec2(2, 0);
      l.recompute();
      x.recompute();
      expect(x.position!.closeTo(const Vec2(1, 0)), isTrue);
    });
  });

  group('IntersectionPoint: circle ∩ circle', () {
    test('branch 0 is left of the directed center line', () {
      // Unit circles at (0,0) and (1,0): intersections at (0.5, ±√3/2).
      // Left of the +x directed center line is +y.
      final k1 = CircleCenterPoint(
        id: 'k1',
        center: fp('c1', 0, 0),
        onCircle: fp('p1', 1, 0),
      );
      final k2 = CircleCenterPoint(
        id: 'k2',
        center: fp('c2', 1, 0),
        onCircle: fp('p2', 2, 0),
      );
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: k1,
        curve2: k2,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: k1,
        curve2: k2,
        branchIndex: 1,
      );
      const root3over2 = 0.8660254037844386;
      expect(x0.position!.closeTo(const Vec2(0.5, root3over2), 1e-9), isTrue);
      expect(x1.position!.closeTo(const Vec2(0.5, -root3over2), 1e-9), isTrue);
    });
  });

  group('IntersectionPoint: construction errors', () {
    test('rejects point parents, self-intersection, bad branch index', () {
      final l = lineThrough('l', (fp('a', 0, 0), fp('b', 1, 0)));
      final l2 = lineThrough('l2', (fp('c', 0, 1), fp('d', 1, 2)));
      final p = fp('p', 0, 0);
      expect(
        () => IntersectionPoint(id: 'x', curve1: l, curve2: p, branchIndex: 0),
        throwsArgumentError,
      );
      expect(
        () => IntersectionPoint(id: 'x', curve1: l, curve2: l, branchIndex: 0),
        throwsArgumentError,
      );
      expect(
        () => IntersectionPoint(id: 'x', curve1: l, curve2: l2, branchIndex: 2),
        throwsArgumentError,
      );
    });
  });

  group('projective semantics (Phase 110)', () {
    CircleCenterPoint circleOf(String id, CircleEq c) => CircleCenterPoint(
      id: id,
      center: fp('$id-c', c.center.x, c.center.y),
      onCircle: fp('$id-r', c.center.x + c.radius, c.center.y),
    );

    ProjPoint conjugateOf(ProjPoint p) =>
        ProjPoint(p.x.conj, p.y.conj, p.w.conj);

    Glados2(any.lineEq, any.circleEq).test(
      'line ∩ circle: always two candidates, incident to both parents in ℂ',
      (l, c) {
        final line = StubProjectiveLine(ProjLine.lift(l));
        final circle = StubProjectiveCircle(ConicMatrix.lift(c));
        final candidates = intersectionCandidates(line, circle);
        expect(candidates, hasLength(2));
        for (final p in candidates) {
          expect(
            p.isIncidentTo(line.value!, 1e-6),
            isTrue,
            reason: '$l ∩ $c → $p off the line',
          );
          expect(
            circle.value!.containsPoint(p, 1e-6),
            isTrue,
            reason: '$l ∩ $c → $p off the circle',
          );
        }
      },
    );

    Glados2(any.circleEq, any.circleEq).test(
      'circle ∩ circle: I, J filtered — two candidates, on both conics',
      (c1, c2) {
        final d = c1.center.distanceTo(c2.center);
        final scale = 1 + c1.radius + c2.radius;
        // Stay away from concentricity (I/J-doubled candidates).
        if (d < 1e-3 * scale) {
          return;
        }
        final a = StubProjectiveCircle(ConicMatrix.lift(c1));
        final b = StubProjectiveCircle(ConicMatrix.lift(c2));
        final candidates = intersectionCandidates(a, b);
        expect(candidates, hasLength(2), reason: '$c1 ∩ $c2 → $candidates');
        for (final p in candidates) {
          expect(isCircularPoint(p), isFalse);
          expect(
            a.value!.containsPoint(p, 1e-6),
            isTrue,
            reason: '$c1 ∩ $c2 → $p off the first circle',
          );
          expect(
            b.value!.containsPoint(p, 1e-6),
            isTrue,
            reason: '$c1 ∩ $c2 → $p off the second circle',
          );
        }
      },
    );

    Glados3(any.vec2, any.vec2, any.circleEq).test(
      'line ∩ circle through the object graph agrees with V1 in position '
      'and order',
      (p1, p2, c) {
        if (p1.closeTo(p2, 1e-3)) {
          return;
        }
        final l = lineThrough('l', (fp('a', p1.x, p1.y), fp('b', p2.x, p2.y)));
        final k = circleOf('k', c);
        final scale = 1 + c.radius + c.center.norm;
        // Stay away from V1's tangency classification boundary.
        if ((l.line!.distanceTo(c.center) - c.radius).abs() < 1e-3 * scale) {
          return;
        }
        final x0 = IntersectionPoint(
          id: 'x0',
          curve1: l,
          curve2: k,
          branchIndex: 0,
        );
        final x1 = IntersectionPoint(
          id: 'x1',
          curve1: k,
          curve2: l,
          branchIndex: 1,
        );
        final v1 = intersectLineCircle(l.line!, k.circle!);
        final tol = 1e-6 * scale;
        if (v1.isEmpty) {
          expect(x0.isDefined, isFalse);
          expect(x1.isDefined, isFalse);
          expect(x0.candidateCount, 0);
        } else {
          expect(v1, hasLength(2));
          expect(
            x0.position!.distanceTo(v1[0]),
            lessThan(tol),
            reason: '$l ∩ $c: ${x0.position} vs ${v1[0]}',
          );
          expect(
            x1.position!.distanceTo(v1[1]),
            lessThan(tol),
            reason: '$l ∩ $c: ${x1.position} vs ${v1[1]}',
          );
          expect(x0.candidateCount, 2);
        }
      },
    );

    Glados2(any.circleEq, any.circleEq).test(
      'circle ∩ circle through the object graph agrees with V1 in position '
      'and order',
      (c1, c2) {
        final d = c1.center.distanceTo(c2.center);
        final scale = 1 + c1.radius + c2.radius;
        // Stay away from V1's classification boundaries.
        if (d < 1e-3 * scale ||
            (d - (c1.radius + c2.radius)).abs() < 1e-3 * scale ||
            (d - (c1.radius - c2.radius).abs()).abs() < 1e-3 * scale) {
          return;
        }
        final k1 = circleOf('k1', c1);
        final k2 = circleOf('k2', c2);
        final x0 = IntersectionPoint(
          id: 'x0',
          curve1: k1,
          curve2: k2,
          branchIndex: 0,
        );
        final x1 = IntersectionPoint(
          id: 'x1',
          curve1: k1,
          curve2: k2,
          branchIndex: 1,
        );
        final v1 = intersectCircleCircle(k1.circle!, k2.circle!);
        final tol = 1e-6 * (1 + c1.center.norm + scale);
        if (v1.isEmpty) {
          expect(x0.isDefined, isFalse);
          expect(x1.isDefined, isFalse);
          expect(x0.candidateCount, 0);
        } else {
          expect(v1, hasLength(2));
          expect(
            x0.position!.distanceTo(v1[0]),
            lessThan(tol),
            reason: '$c1 ∩ $c2: ${x0.position} vs ${v1[0]}',
          );
          expect(
            x1.position!.distanceTo(v1[1]),
            lessThan(tol),
            reason: '$c1 ∩ $c2: ${x1.position} vs ${v1[1]}',
          );
          expect(x0.candidateCount, 2);
        }
      },
    );

    test('tangency is a double root: candidateCount 1 on both families', () {
      final l = lineThrough('l', (fp('a', -2, 1), fp('b', 2, 1)));
      final k = circleOf('k', CircleEq(Vec2.zero, 1));
      final x = IntersectionPoint(
        id: 'x',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      expect(x.candidateCount, 1);

      final k2 = circleOf('k2', CircleEq(const Vec2(2, 0), 1));
      final y0 = IntersectionPoint(
        id: 'y0',
        curve1: k,
        curve2: k2,
        branchIndex: 0,
      );
      final y1 = IntersectionPoint(
        id: 'y1',
        curve1: k,
        curve2: k2,
        branchIndex: 1,
      );
      expect(y0.candidateCount, 1);
      expect(y0.position!.closeTo(const Vec2(1, 0)), isTrue);
      expect(y1.position!.closeTo(const Vec2(1, 0)), isTrue);
    });

    test('a real miss keeps the complex pair: conjugate mates, count 0', () {
      final l = lineThrough('l', (fp('a', -2, 2), fp('b', 2, 2)));
      final k = circleOf('k', CircleEq(Vec2.zero, 1));
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: l,
        curve2: k,
        branchIndex: 1,
      );
      expect(x0.isDefined, isFalse);
      expect(x0.candidateCount, 0);
      expect(x0.projPoint, isNotNull);
      expect(x0.projPoint!.isReal(), isFalse);
      expect(x0.projPoint!.closeTo(conjugateOf(x1.projPoint!)), isTrue);
    });

    test('distinct parallel lines meet at a real point at infinity', () {
      final l1 = lineThrough('l1', (fp('a', 0, 0), fp('b', 4, 0)));
      final l2 = lineThrough('l2', (fp('c', 0, 1), fp('d', 4, 1)));
      final x = IntersectionPoint(
        id: 'x',
        curve1: l1,
        curve2: l2,
        branchIndex: 0,
      );
      expect(x.isDefined, isFalse);
      expect(x.candidateCount, 0);
      expect(x.projPoint, isNotNull);
      expect(x.projPoint!.isReal(), isTrue);
      expect(x.projPoint!.isFinite(), isFalse);
      expect(x.projPoint!.closeTo(ProjPoint.real(1, 0, 0)), isTrue);
    });

    test('coincident carriers have no discrete intersection', () {
      final l = StubProjectiveLine(ProjLine.real(1, 2, -3));
      final lScaled = StubProjectiveLine(
        l.value!.scaledBy(const Complex(2, -1)),
      );
      expect(intersectionCandidates(l, lScaled), isEmpty);

      final k = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(const Vec2(1, 2), 3)),
      );
      final kScaled = StubProjectiveCircle(
        k.value!.scaledBy(const Complex(0, 2)),
      );
      expect(intersectionCandidates(k, kScaled), isEmpty);
      final x = IntersectionPoint(
        id: 'x',
        curve1: k,
        curve2: kScaled,
        branchIndex: 0,
      );
      expect(x.isDefined, isFalse);
      expect(x.projPoint, isNull);
      expect(x.candidateCount, 0);
    });

    test('concentric circles: the doubled I, J filter away — no candidates',
        () {
      final k1 = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(const Vec2(1, 2), 1)),
      );
      final k2 = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(const Vec2(1, 2), 2)),
      );
      expect(intersectionCandidates(k1, k2), isEmpty);
      final x = IntersectionPoint(
        id: 'x',
        curve1: k1,
        curve2: k2,
        branchIndex: 0,
      );
      expect(x.isDefined, isFalse);
      expect(x.candidateCount, 0);
    });

    test('constructed-tangency rounding snaps real (double-root band)', () {
      final k = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(Vec2.zero, 1)),
      );
      // A hair on the miss side: the conjugate pair's imaginary part is
      // sqrt-amplified rounding noise, snapped back to the real touch
      // point (V1's world-unit tangency band, reborn relative).
      final above = StubProjectiveLine(ProjLine.real(0, 1, -(1 + 1e-14)));
      final xAbove = IntersectionPoint(
        id: 'xa',
        curve1: above,
        curve2: k,
        branchIndex: 0,
      );
      expect(xAbove.isDefined, isTrue);
      expect(xAbove.position!.closeTo(const Vec2(0, 1), 1e-6), isTrue);
      expect(xAbove.candidateCount, 1);

      // A hair on the crossing side: two real points a root-noise apart
      // still classify as the one touch point.
      final below = StubProjectiveLine(ProjLine.real(0, 1, -(1 - 1e-14)));
      final xBelow = IntersectionPoint(
        id: 'xb',
        curve1: below,
        curve2: k,
        branchIndex: 0,
      );
      expect(xBelow.isDefined, isTrue);
      expect(xBelow.position!.closeTo(const Vec2(0, 1), 1e-6), isTrue);
      expect(xBelow.candidateCount, 1);

      // Well clear of the band: a genuine miss stays complex.
      final clear = StubProjectiveLine(ProjLine.real(0, 1, -1.001));
      final xClear = IntersectionPoint(
        id: 'xc',
        curve1: clear,
        curve2: k,
        branchIndex: 0,
      );
      expect(xClear.isDefined, isFalse);
      expect(xClear.candidateCount, 0);
    });

    test('line ∩ degenerate line-pair conic: real candidates (V2 semantics)',
        () {
      // The line pair x = ±1 (a collinear "circle" carrier's shape).
      final pair = StubProjectiveCircle(
        ConicMatrix.linePair(ProjLine.real(1, 0, -1), ProjLine.real(1, 0, 1)),
      );
      final l = StubProjectiveLine(ProjLine.real(0, 1, 0)); // y = 0
      final candidates = intersectionCandidates(l, pair);
      expect(candidates, hasLength(2));
      final positions = [for (final p in candidates) p.toVec2()!];
      expect(
        positions.any((p) => p.closeTo(const Vec2(1, 0))),
        isTrue,
        reason: '$positions',
      );
      expect(
        positions.any((p) => p.closeTo(const Vec2(-1, 0))),
        isTrue,
        reason: '$positions',
      );
      final x = IntersectionPoint(
        id: 'x',
        curve1: l,
        curve2: pair,
        branchIndex: 0,
      );
      expect(x.isDefined, isTrue);
      expect(x.candidateCount, 2);
    });

    test('branch order is anchored to the affine direction, not the '
        'carrier representative sign', () {
      // Two parents with identical positions (−2, 0) → (2, 0), but the
      // first stored at w = −1, flipping the join's representative. The
      // affine view is orientation-anchored either way, and the branch
      // order must follow it.
      final flipped = StubProjectivePoint(ProjPoint.real(2, 0, -1));
      final plain = StubProjectivePoint(ProjPoint.real(2, 0, 1));
      final l = LineThroughTwoPoints(id: 'l', point1: flipped, point2: plain);
      expect(l.line!.direction.dot(const Vec2(1, 0)), greaterThan(0));
      final k = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(Vec2.zero, 1)),
      );
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: l,
        curve2: k,
        branchIndex: 1,
      );
      expect(x0.position!.closeTo(const Vec2(-1, 0)), isTrue);
      expect(x1.position!.closeTo(const Vec2(1, 0)), isTrue);
    });

    Glados2(any.coordinate, any.coordinate).test(
      'complex rescaling of the parent views leaves the candidate set '
      'and count invariant',
      (re, im) {
        var k = Complex(re, im);
        if (k.abs2 < 1) {
          k = k + const Complex(2, 1);
        }
        final line = StubProjectiveLine(ProjLine.real(0, 1, 0));
        final circle = StubProjectiveCircle(
          ConicMatrix.lift(CircleEq(const Vec2(0.25, 0), 1)),
        );
        final baseline = intersectionCandidates(line, circle);
        final scaledLine = StubProjectiveLine(line.value!.scaledBy(k));
        final scaledCircle = StubProjectiveCircle(circle.value!.scaledBy(k));
        final scaled = intersectionCandidates(scaledLine, scaledCircle);
        expect(scaled, hasLength(baseline.length));
        // Rescaling the line's representative may permute the pair (V1
        // semantics: flipping a line flips its order) — compare sets.
        for (final p in baseline) {
          expect(
            scaled.any((q) => q.closeTo(p, 1e-6)),
            isTrue,
            reason: 'k = $k: $scaled misses $p',
          );
        }
        final x = IntersectionPoint(
          id: 'x',
          curve1: scaledLine,
          curve2: scaledCircle,
          branchIndex: 0,
        );
        expect(x.candidateCount, 2);
      },
    );
  });
}

typedef GeoPointPair = (FreePoint, FreePoint);
