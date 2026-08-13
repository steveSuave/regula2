import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/math/angle_bisector.dart' as v1;
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';

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

    test('nearly parallel lines bisect to the mid-parallel (V1 band gone)',
        () {
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
}
