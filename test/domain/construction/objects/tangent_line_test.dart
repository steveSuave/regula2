import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/tangents.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../math/generators.dart';

void main() {
  late FreePoint center;
  late FreePoint rim;
  late FreePoint external;
  late CircleCenterPoint circle;

  setUp(() {
    center = FreePoint(id: 'c', position: Vec2.zero);
    rim = FreePoint(id: 'r', position: const Vec2(1, 0));
    external = FreePoint(id: 'e', position: const Vec2(5, 0));
    circle = CircleCenterPoint(id: 'circ', center: center, onCircle: rim);
  });

  group('TangentLine', () {
    test('both branches pass through the point, tangent to the circle', () {
      for (final branch in [0, 1]) {
        final tangent = TangentLine(
          id: 't$branch',
          point: external,
          circle: circle,
          branch: branch,
        );
        final line = tangent.line!;
        expect(
          line.contains(const Vec2(5, 0)),
          isTrue,
          reason: 'branch $branch passes through the external point',
        );
        expect(
          line.distanceTo(Vec2.zero),
          closeTo(1, 1e-12),
          reason: 'branch $branch touches the unit circle',
        );
        expect(tangent.parents, [external, circle]);
      }
      // The two branches are distinct lines, mirror images across the
      // center → point axis (here the x-axis).
      final left = TangentLine(
        id: 'l',
        point: external,
        circle: circle,
        branch: 0,
      );
      final right = TangentLine(
        id: 'r2',
        point: external,
        circle: circle,
        branch: 1,
      );
      expect(left.line!.closeTo(right.line!), isFalse);
      final touchLeft = left.line!.project(Vec2.zero);
      final touchRight = right.line!.project(Vec2.zero);
      expect(touchLeft.y, isPositive, reason: 'branch 0 is the left branch');
      expect(touchRight.y, isNegative);
    });

    test('constructor validates the branch', () {
      expect(
        () =>
            TangentLine(id: 'bad', point: external, circle: circle, branch: 2),
        throwsArgumentError,
      );
    });

    test('undefined while the point is strictly inside, recovers with '
        'sides preserved', () {
      final left = TangentLine(
        id: 'l',
        point: external,
        circle: circle,
        branch: 0,
      );
      expect(left.line, isNotNull);

      external.position = const Vec2(0.5, 0);
      left.recompute();
      expect(left.line, isNull);
      expect(left.isDefined, isFalse);

      // Re-emerge on the other side of the circle: branch 0 is still the
      // touch point to the *left* of the (new) center → point direction.
      external.position = const Vec2(-5, 0);
      left.recompute();
      final touch = left.line!.project(Vec2.zero);
      // Left of the −x direction is −y.
      expect(touch.y, isNegative);
    });

    test('undefined while the circle radius is degenerate', () {
      final tangent = TangentLine(
        id: 't',
        point: external,
        circle: circle,
        branch: 0,
      );
      rim.position = Vec2.zero;
      circle.recompute();
      tangent.recompute();
      expect(tangent.line, isNull);

      rim.position = const Vec2(1, 0);
      circle.recompute();
      tangent.recompute();
      expect(tangent.line, isNotNull);
    });

    test(
      'on the circle both branches collapse to the tangent at the point',
      () {
        external.position = const Vec2(0, 1);
        final left = TangentLine(
          id: 'l',
          point: external,
          circle: circle,
          branch: 0,
        );
        final right = TangentLine(
          id: 'r2',
          point: external,
          circle: circle,
          branch: 1,
        );
        expect(left.line!.closeTo(right.line!), isTrue);
        expect(left.line!.contains(const Vec2(0, 1)), isTrue);
        expect(
          left.line!.contains(const Vec2(7, 1)),
          isTrue,
          reason: 'horizontal tangent at the circle top',
        );
      },
    );

    test('branch stays on its side while the external point orbits', () {
      final left = TangentLine(
        id: 'l',
        point: external,
        circle: circle,
        branch: 0,
      );
      for (var i = 0; i <= 24; i++) {
        final angle = 2 * math.pi * i / 24;
        external.position = Vec2(math.cos(angle), math.sin(angle)) * 3;
        left.recompute();
        final touch = left.line!.project(Vec2.zero);
        expect(
          external.position.cross(touch),
          isPositive,
          reason: 'orbit step $i: branch 0 touch point left of center→point',
        );
      }
    });
  });

  group('projective semantics (Phase 110)', () {
    Glados2(any.vec2, any.circleEq).test(
      'both branches agree with V1 tangent lines and order outside',
      (e, c) {
        final scale = 1 + c.radius + c.center.norm + e.norm;
        // Strictly outside, away from the on-circle collapse.
        if (e.distanceTo(c.center) < c.radius + 1e-3 * scale) {
          return;
        }
        final point = FreePoint(id: 'e', position: e);
        final circ = CircleCenterPoint(
          id: 'circ',
          center: FreePoint(id: 'o', position: c.center),
          onCircle: FreePoint(id: 'r', position: c.center + Vec2(c.radius, 0)),
        );
        final touches = tangentPointsToCircle(e, circ.circle!);
        expect(touches, hasLength(2));
        for (final branch in [0, 1]) {
          final tangent = TangentLine(
            id: 't$branch',
            point: point,
            circle: circ,
            branch: branch,
          );
          final expected = LineEq.pointDirection(
            touches[branch],
            (touches[branch] - c.center).perpendicular,
          );
          expect(tangent.line, isNotNull);
          expect(
            tangent.line!.closeTo(expected, 1e-6),
            isTrue,
            reason:
                'branch $branch of $e / $c: '
                '${tangent.line} vs $expected',
          );
          expect(
            tangent.line!.direction.dot(expected.direction),
            greaterThan(0),
          );
        }
      },
    );

    test('strictly inside: complex conjugate carriers, no affine view', () {
      final point = FreePoint(id: 'e', position: const Vec2(0.3, 0.2));
      final circ = CircleCenterPoint(
        id: 'circ',
        center: FreePoint(id: 'o', position: Vec2.zero),
        onCircle: FreePoint(id: 'r', position: const Vec2(1, 0)),
      );
      final t0 = TangentLine(id: 't0', point: point, circle: circ, branch: 0);
      final t1 = TangentLine(id: 't1', point: point, circle: circ, branch: 1);
      expect(t0.isDefined, isFalse);
      expect(t0.line, isNull);
      expect(t0.projLine, isNotNull);
      expect(t0.projLine!.isReal(), isFalse);
      final conjugate = ProjLine(
        t1.projLine!.a.conj,
        t1.projLine!.b.conj,
        t1.projLine!.c.conj,
      );
      expect(t0.projLine!.closeTo(conjugate), isTrue);
    });

    test('from the center: both tangents are isotropic, undefined', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final circ = CircleCenterPoint(
        id: 'circ',
        center: o,
        onCircle: FreePoint(id: 'r', position: const Vec2(1, 0)),
      );
      final t = TangentLine(id: 't', point: o, circle: circ, branch: 0);
      expect(t.isDefined, isFalse);
      expect(t.line, isNull);
      expect(t.projLine, isNotNull);
      expect(t.projLine!.isReal(), isFalse);
    });

    Glados2(any.coordinate, any.coordinate).test(
      'complex rescaling of the parent views leaves each branch invariant',
      (re, im) {
        var k = Complex(re, im);
        if (k.abs2 < 1) {
          k = k + const Complex(2, 1);
        }
        final pole = ProjPoint.real(5, 1);
        final conic = ConicMatrix.lift(CircleEq(const Vec2(1, 0), 2));
        for (final branch in [0, 1]) {
          final baseline = TangentLine(
            id: 'b$branch',
            point: StubProjectivePoint(pole),
            circle: StubProjectiveCircle(conic),
            branch: branch,
          );
          final scaled = TangentLine(
            id: 's$branch',
            point: StubProjectivePoint(pole.scaledBy(k)),
            circle: StubProjectiveCircle(conic.scaledBy(k)),
            branch: branch,
          );
          expect(
            scaled.projLine!.closeTo(baseline.projLine!, 1e-6),
            isTrue,
            reason: 'branch $branch under k = $k',
          );
        }
      },
    );
  });
}
