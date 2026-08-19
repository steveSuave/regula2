import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/construction/objects/radical_axis_line.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../../v1_oracle/angle_bisector.dart' as v1;

void main() {
  late FreePoint o;
  late FreePoint x;
  late FreePoint y;
  late LineThroughTwoPoints xAxis;
  late LineThroughTwoPoints yAxis;

  setUp(() {
    o = FreePoint(id: 'o', position: Vec2.zero);
    x = FreePoint(id: 'x', position: const Vec2(4, 0));
    y = FreePoint(id: 'y', position: const Vec2(0, 4));
    xAxis = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
    yAxis = LineThroughTwoPoints(id: 'v', point1: o, point2: y);
  });

  group('TwoLineBisectorLine', () {
    test(
      'branch 0 bisects along the direction sum, branch 1 the difference',
      () {
        final sum = TwoLineBisectorLine(
          id: 'b0',
          line1: xAxis,
          line2: yAxis,
          branch: 0,
        );
        final diff = TwoLineBisectorLine(
          id: 'b1',
          line1: xAxis,
          line2: yAxis,
          branch: 1,
        );
        expect(
          sum.line!.closeTo(LineEq.throughPoints(Vec2.zero, const Vec2(1, 1))),
          isTrue,
        );
        expect(
          diff.line!.closeTo(
            LineEq.throughPoints(Vec2.zero, const Vec2(1, -1)),
          ),
          isTrue,
        );
        expect(sum.parents, [xAxis, yAxis]);
      },
    );

    test('constructor validates the branch and distinct lines', () {
      expect(
        () => TwoLineBisectorLine(
          id: 'bad',
          line1: xAxis,
          line2: yAxis,
          branch: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => TwoLineBisectorLine(
          id: 'self',
          line1: xAxis,
          line2: xAxis,
          branch: 0,
        ),
        throwsArgumentError,
      );
    });

    test(
      '.near picks the bisector of the tapped wedge, all four quadrants',
      () {
        // Wedge quadrant → expected bisector: taps in the first quadrant
        // (+x half, +y half) and the third (−x, −y) bisect along y = x;
        // mixed-sign quadrants bisect along y = −x.
        final yEqualsX = LineEq.throughPoints(Vec2.zero, const Vec2(1, 1));
        final yEqualsMinusX = LineEq.throughPoints(
          Vec2.zero,
          const Vec2(1, -1),
        );
        final cases = [
          (const Vec2(3, 0.1), const Vec2(0.1, 3), yEqualsX),
          (const Vec2(-3, 0.1), const Vec2(0.1, -3), yEqualsX),
          (const Vec2(-3, 0.1), const Vec2(0.1, 3), yEqualsMinusX),
          (const Vec2(3, 0.1), const Vec2(0.1, -3), yEqualsMinusX),
        ];
        for (final (tap1, tap2, expected) in cases) {
          final bisector = TwoLineBisectorLine.near(
            id: 'near-$tap1-$tap2',
            line1: xAxis,
            line2: yAxis,
            tap1: tap1,
            tap2: tap2,
          );
          expect(
            bisector.line!.closeTo(expected),
            isTrue,
            reason: 'taps $tap1 / $tap2 pick the wrong wedge',
          );
        }
      },
    );

    test('undefined while the lines are parallel, recovers on drag', () {
      final p = FreePoint(id: 'p', position: const Vec2(0, 1));
      final q = FreePoint(id: 'q', position: const Vec2(4, 1));
      final parallel = LineThroughTwoPoints(id: 'par', point1: p, point2: q);
      final bisector = TwoLineBisectorLine(
        id: 'b',
        line1: xAxis,
        line2: parallel,
        branch: 0,
      );
      expect(bisector.line, isNull);
      expect(bisector.isDefined, isFalse);

      // Tilt the second line: the bisector appears.
      q.position = const Vec2(4, 3);
      parallel.recompute();
      bisector.recompute();
      expect(bisector.line, isNotNull);

      q.position = const Vec2(4, 1);
      parallel.recompute();
      bisector.recompute();
      expect(bisector.line, isNull, reason: 'parallel again — undefined');
    });

    test('.near falls back to branch 0 while the lines do not cross', () {
      final p = FreePoint(id: 'p', position: const Vec2(0, 1));
      final q = FreePoint(id: 'q', position: const Vec2(4, 1));
      final parallel = LineThroughTwoPoints(id: 'par', point1: p, point2: q);
      final bisector = TwoLineBisectorLine.near(
        id: 'b',
        line1: xAxis,
        line2: parallel,
        tap1: const Vec2(2, 0),
        tap2: const Vec2(2, 1),
      );
      expect(bisector.branch, 0);
      expect(bisector.line, isNull);
    });

    test('tracks parent drags continuously within the wedge', () {
      final bisector = TwoLineBisectorLine.near(
        id: 'b',
        line1: xAxis,
        line2: yAxis,
        tap1: const Vec2(3, 0.1),
        tap2: const Vec2(0.1, 3),
      );
      // Tilt the second line: the bisector must stay inside the deformed
      // first-quadrant wedge (both direction components positive — the
      // other branch has mixed signs) and keep the equidistance property.
      y.position = const Vec2(1, 4);
      yAxis.recompute();
      bisector.recompute();
      final direction = bisector.line!.direction;
      final d = direction.y < 0 ? -direction : direction;
      expect(d.x, greaterThan(0));
      expect(d.y, greaterThan(0));
      final probe = bisector.line!.pointAt(2);
      expect(
        xAxis.line!.distanceTo(probe),
        closeTo(yAxis.line!.distanceTo(probe), 1e-9),
      );
    });
  });

  group('projective semantics (Phase 110)', () {
    test('branch semantics anchor to the affine orientation, not the '
        'carrier representative sign', () {
      // A line whose stored representative is flipped (one parent held at
      // w = −1) while its affine view keeps the V1 orientation. Both
      // branches must match V1 computed on the affine views.
      final flipped = StubProjectivePoint(ProjPoint.real(-4, 0, -1));
      final plain = StubProjectivePoint(ProjPoint.real(0, 0, 1));
      final l1 = LineThroughTwoPoints(id: 'h', point1: plain, point2: flipped);
      expect(l1.line!.direction.dot(const Vec2(1, 0)), greaterThan(0));
      final l2 = LineThroughTwoPoints(
        id: 'v',
        point1: FreePoint(id: 'o', position: Vec2.zero),
        point2: FreePoint(id: 'y', position: const Vec2(0, 4)),
      );
      for (final branch in [0, 1]) {
        final bisector = TwoLineBisectorLine(
          id: 'b$branch',
          line1: l1,
          line2: l2,
          branch: branch,
        );
        final expected = v1.twoLineBisector(l1.line!, l2.line!, branch)!;
        expect(
          bisector.line!.closeTo(expected),
          isTrue,
          reason: 'branch $branch: ${bisector.line} vs $expected',
        );
        expect(
          bisector.line!.direction.dot(expected.direction),
          greaterThan(0),
        );
      }
    });

    test('nearly parallel lines bisect to the mid-parallel (V1 band gone)', () {
      // Sine ≈ 1e-10 between the carriers — inside V1's parallel epsilon,
      // where it returned nothing. The genuine bisector is ≈ y = 0.5.
      final l1 = StubProjectiveLine(ProjLine.real(0, 1, 0));
      final l2 = StubProjectiveLine(ProjLine.real(1e-10, 1, -1));
      final bisector = TwoLineBisectorLine(
        id: 'b',
        line1: l1,
        line2: l2,
        branch: 0,
      );
      expect(bisector.isDefined, isTrue);
      expect(bisector.line!.closeTo(LineEq(0, 1, -0.5), 1e-6), isTrue);
    });

    test('exactly parallel or coincident carriers stay undefined', () {
      final l1 = StubProjectiveLine(ProjLine.real(0, 1, 0));
      final l2 = StubProjectiveLine(ProjLine.real(0, 1, -1));
      for (final branch in [0, 1]) {
        final bisector = TwoLineBisectorLine(
          id: 'b$branch',
          line1: l1,
          line2: l2,
          branch: branch,
        );
        expect(bisector.isDefined, isFalse);
        expect(bisector.projLine, isNull);
      }
    });
  });

  group('the branch rests on a chart reading (Phase 136c)', () {
    // Found by the audit, not by a failure, and it is not a nullability
    // defect: `_carrier` is nulled only by a parent's null `projLine` or
    // the zero triple, so the one degeneracy convention holds here. What
    // does *not* hold is continuity. `_anchored` fixes each parent's
    // representative **sign** off the parent's affine
    // `LineEq.direction`, and leaves the sign alone when there is no
    // chart — so which of the two bisectors `branch` names can change at
    // the instant a parent loses its projection.
    //
    // These tests pin the measurements rather than assert the behaviour
    // is right. Making the branch chart-free means re-founding line
    // orientation projectively, which is a branch-ordering change, and
    // CLAUDE.md calls those load-bearing: its own phase, not this one.

    test('the representative sign is load-bearing: negating a parent names '
        'the other bisector', () {
      final flipped = TwoLineBisectorLine(
        id: 'f',
        line1: ChartlessLine(xAxis.projLine!.scaledBy(const Complex(-1))),
        line2: ChartlessLine(yAxis.projLine),
        branch: 0,
      );
      final plain = TwoLineBisectorLine(
        id: 'p',
        line1: ChartlessLine(xAxis.projLine),
        line2: ChartlessLine(yAxis.projLine),
        branch: 0,
      );
      expect(
        flipped.projLine!.closeTo(plain.projLine!),
        isFalse,
        reason: 'so the sign `_anchored` sets is the whole branch',
      );
    });

    test('seven line kinds orient their chart along their own '
        'representative; four can orient against it', () {
      // `_anchored`'s own test, asked of each kind over a sweep of
      // configurations: does `line.direction` agree with the raw
      // representative's (b, -a)? Where it always does, withdrawing the
      // chart is a no-op and no bisector below it can move — which is
      // why Phase 136b's `Segment`/`Ray` change could not affect one.
      // Where it can disagree, the unanchored fallback names the *other*
      // bisector; measured at roughly half of configurations for each of
      // the four.
      bool agrees(GeoLine kind) {
        final proj = kind.projLine!;
        final chart = kind.line!;
        return chart.direction.x * proj.b.re - chart.direction.y * proj.a.re >=
            0;
      }

      final rnd = math.Random(3);
      final disagreements = <String, int>{};
      final samples = <String, int>{};
      void measure(GeoLine kind) {
        if (kind.projLine == null || kind.line == null) return;
        final name = kind.runtimeType.toString();
        samples[name] = (samples[name] ?? 0) + 1;
        if (!agrees(kind)) {
          disagreements[name] = (disagreements[name] ?? 0) + 1;
        }
      }

      for (var i = 0; i < 200; i++) {
        Vec2 v() => Vec2(rnd.nextDouble() * 8 - 4, rnd.nextDouble() * 8 - 4);
        final a = FreePoint(id: 'a', position: v());
        final b = FreePoint(id: 'b', position: v());
        final c = FreePoint(id: 'c', position: v());
        final d = FreePoint(id: 'd', position: v());
        final e = FreePoint(id: 'e', position: v());
        final l1 = LineThroughTwoPoints(id: 'l1', point1: a, point2: b);
        final l2 = LineThroughTwoPoints(id: 'l2', point1: c, point2: d);
        final k1 = ThreePointCircle(id: 'k1', point1: a, point2: b, point3: c);
        final k2 = ThreePointCircle(id: 'k2', point1: c, point2: d, point3: e);
        [
          l1,
          Segment(id: 's', point1: a, point2: b),
          Ray(id: 'r', origin: a, through: b),
          ParallelLine(id: 'pa', through: c, reference: l1),
          PerpendicularLine(id: 'pe', through: c, reference: l1),
          PerpendicularBisectorLine(id: 'pb', point1: a, point2: b),
          AngleBisectorLine(id: 'ab', arm1: a, vertex: b, arm2: c),
          TwoLineBisectorLine(id: 'tb', line1: l1, line2: l2, branch: 0),
          PolarLine(id: 'po', point: d, circle: k1),
          RadicalAxisLine(id: 'ra', circle1: k1, circle2: k2),
          TangentLine(id: 'tg', point: d, circle: k1, branch: 0),
        ].forEach(measure);
      }

      for (final name in [
        'LineThroughTwoPoints',
        'Segment',
        'Ray',
        'ParallelLine',
        'PerpendicularLine',
        'PerpendicularBisectorLine',
        'AngleBisectorLine',
      ]) {
        expect(samples[name], greaterThan(0), reason: '$name was measured');
        expect(
          disagreements[name] ?? 0,
          0,
          reason:
              '$name orients along its own representative, always — so '
              'a chartless one changes no bisector',
        );
      }

      for (final name in [
        'TwoLineBisectorLine',
        'PolarLine',
        'RadicalAxisLine',
        'TangentLine',
      ]) {
        expect(samples[name], greaterThan(0), reason: '$name was measured');
        expect(
          disagreements[name] ?? 0,
          greaterThan(0),
          reason:
              '$name orients by a V1-compat direction unrelated to its '
              'representative, so withdrawing its chart swaps the bisector '
              'below it',
        );
      }
    });

    test('a PolarLine really does lose its chart, so the fallback is '
        'reachable', () {
      // Pole exactly on the centre: the polar is the line at infinity,
      // which has a perfectly good carrier and no `LineEq`. Phase 134
      // established that grid snapping lands the pointer exactly on such
      // parameters, so this is not a measure-zero curiosity.
      final k = ThreePointCircle(
        id: 'k',
        point1: FreePoint(id: 'a', position: const Vec2(3, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(-3, 0)),
        point3: FreePoint(id: 'c', position: const Vec2(0, 3)),
      );
      final polar = PolarLine(
        id: 'pl',
        point: FreePoint(id: 'p', position: Vec2.zero),
        circle: k,
      );
      expect(polar.projLine, isNotNull);
      expect(polar.line, isNull);
      expect(polar.isDefined, isFalse);
    });

    test('and then the bisector below it names the other branch', () {
      // The two halves put together, on a real kind: the same carrier,
      // the same branch index, anchored and unanchored — two different
      // bisectors. This is the discontinuity, demonstrated rather than
      // argued.
      final k = ThreePointCircle(
        id: 'k',
        point1: FreePoint(id: 'a', position: const Vec2(3, 0)),
        point2: FreePoint(id: 'b', position: const Vec2(-3, 0)),
        point3: FreePoint(id: 'c', position: const Vec2(0, 3)),
      );
      final polar = PolarLine(
        id: 'pl',
        point: FreePoint(id: 'p', position: const Vec2(1, 2)),
        circle: k,
      );
      final anchored = TwoLineBisectorLine(
        id: 'b1',
        line1: polar,
        line2: xAxis,
        branch: 0,
      );
      final unanchored = TwoLineBisectorLine(
        id: 'b2',
        line1: ChartlessLine(polar.projLine),
        line2: xAxis,
        branch: 0,
      );
      expect(
        unanchored.projLine!.closeTo(anchored.projLine!),
        isFalse,
        reason: 'losing the chart swapped the branch',
      );
    });
  });
}
