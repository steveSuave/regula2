import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../../v1_oracle/circle_relations.dart' as v1;
import '../../math/generators.dart';

void main() {
  group('PolarLine', () {
    (Construction, PolarLine) build({Vec2 pole = const Vec2(2, 0)}) {
      final construction = Construction();
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final r = FreePoint(id: 'r', position: const Vec2(1, 0));
      final p = FreePoint(id: 'p', position: pole);
      final circle = CircleCenterPoint(id: 'circ', center: o, onCircle: r);
      final polar = PolarLine(id: 'x', point: p, circle: circle);
      construction
        ..add(o)
        ..add(r)
        ..add(p)
        ..add(circle)
        ..add(polar);
      return (construction, polar);
    }

    test('external pole: the chord of contact through the inverse point', () {
      final (_, polar) = build();
      expect(polar.line!.closeTo(LineEq(1, 0, -0.5)), isTrue);
      expect(polar.parents.map((p) => p.id), ['p', 'circ']);
    });

    test('pole on the circle: the tangent at the pole', () {
      final (_, polar) = build(pole: const Vec2(1, 0));
      expect(polar.line!.closeTo(LineEq(1, 0, -1)), isTrue);
    });

    test('drag the pole onto the center: undefined, then recovers', () {
      final (construction, polar) = build();

      construction.moveFreePoint('p', Vec2.zero);
      expect(polar.isDefined, isFalse);
      expect(polar.line, isNull);

      construction.moveFreePoint('p', const Vec2(2, 0));
      expect(polar.isDefined, isTrue);
      expect(polar.line!.closeTo(LineEq(1, 0, -0.5)), isTrue);
    });

    test('undefined while the pole is', () {
      // The pole is a line∩circle intersection; dragging the line clear
      // of the circle undefines it — and the polar with it.
      final construction = Construction();
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final r = FreePoint(id: 'r', position: const Vec2(1, 0));
      final l1 = FreePoint(id: 'l1', position: const Vec2(0.5, -1));
      final l2 = FreePoint(id: 'l2', position: const Vec2(0.5, 1));
      final circle = CircleCenterPoint(id: 'circ', center: o, onCircle: r);
      final line = LineThroughTwoPoints(id: 'l', point1: l1, point2: l2);
      final pole = IntersectionPoint(
        id: 'p',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
      );
      final polar = PolarLine(id: 'x', point: pole, circle: circle);
      construction
        ..add(o)
        ..add(r)
        ..add(l1)
        ..add(l2)
        ..add(circle)
        ..add(line)
        ..add(pole)
        ..add(polar);
      expect(polar.isDefined, isTrue);

      construction.moveFreePoint('l1', const Vec2(5, -1));
      construction.moveFreePoint('l2', const Vec2(5, 1));
      expect(pole.isDefined, isFalse);
      expect(polar.isDefined, isFalse);

      construction.moveFreePoint('l1', const Vec2(0.5, -1));
      construction.moveFreePoint('l2', const Vec2(0.5, 1));
      expect(polar.isDefined, isTrue);
    });
  });

  group('projective semantics (Phase 110)', () {
    Glados2(any.vec2, any.circleEq).test(
      'agrees with V1 polarLine in line and orientation',
      (pole, c) {
        if (pole.distanceTo(c.center) < 1e-3 * (1 + c.center.norm)) {
          return;
        }
        final p = FreePoint(id: 'p', position: pole);
        final circle = CircleCenterPoint(
          id: 'circ',
          center: FreePoint(id: 'o', position: c.center),
          onCircle: FreePoint(id: 'r', position: c.center + Vec2(c.radius, 0)),
        );
        final polar = PolarLine(id: 'x', point: p, circle: circle);
        final expected = v1.polarLine(pole, circle.circle!)!;
        expect(polar.line, isNotNull);
        expect(
          polar.line!.closeTo(expected),
          isTrue,
          reason: '${polar.line} vs $expected',
        );
        expect(polar.line!.direction.dot(expected.direction), greaterThan(0));
      },
    );

    test('the pole at the center carries ℓ∞: projective value, no affine '
        'view', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final circle = CircleCenterPoint(
        id: 'circ',
        center: o,
        onCircle: FreePoint(id: 'r', position: const Vec2(1, 0)),
      );
      final polar = PolarLine(id: 'x', point: o, circle: circle);
      expect(polar.isDefined, isFalse);
      expect(polar.line, isNull);
      expect(polar.projLine, isNotNull);
      expect(polar.projLine!.closeTo(ProjLine.infinity), isTrue);
    });

    Glados2(any.coordinate, any.coordinate).test(
      'complex rescaling of the parent views leaves the polar invariant',
      (re, im) {
        var k = Complex(re, im);
        if (k.abs2 < 1) {
          k = k + const Complex(2, 1);
        }
        final pole = ProjPoint.real(3, 1);
        final conic = ConicMatrix.lift(CircleEq(const Vec2(1, -1), 2));
        final baseline = PolarLine(
          id: 'x',
          point: StubProjectivePoint(pole),
          circle: StubProjectiveCircle(conic),
        );
        final scaled = PolarLine(
          id: 'y',
          point: StubProjectivePoint(pole.scaledBy(k)),
          circle: StubProjectiveCircle(conic.scaledBy(k)),
        );
        expect(scaled.projLine!.closeTo(baseline.projLine!), isTrue);
        expect(scaled.line!.closeTo(baseline.line!), isTrue);
        // The *geometric* line is scale-invariant. The orientation is the
        // representative's sign (Phase 137), so it is pinned only under a
        // sign-preserving rescale — a complex phase legitimately carries
        // into the representative. Real kinds never hand a polar a
        // phase-scaled parent statically (the w-positive contract), and
        // tracing's chart evaluator builds w = 1 by hand (Phase 132c).
        final positively = PolarLine(
          id: 'z',
          point: StubProjectivePoint(pole.scaledBy(Complex(k.abs))),
          circle: StubProjectiveCircle(conic.scaledBy(Complex(k.abs))),
        );
        expect(
          positively.line!.direction.dot(baseline.line!.direction),
          greaterThan(0),
        );
      },
    );
  });
}
