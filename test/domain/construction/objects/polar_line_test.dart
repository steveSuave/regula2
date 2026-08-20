import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
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

  group('representative-founded orientation (Phase 137)', () {
    test('the oriented representative is continuous through the '
        'pole-at-centre chart event', () {
      // Grid snapping lands poles exactly on the centre (Phase 134), so
      // this is a state drags actually visit. The carrier there is ℓ∞ —
      // no chart — and the representative-founded orientation must not
      // jump crossing it: successive representatives along a path
      // through the centre never oppose each other.
      final k = StubProjectiveCircle(
        ConicMatrix.lift(CircleEq(const Vec2(1, 2), 2)),
      );
      ProjLine repAt(double t) => PolarLine(
        id: 'p',
        point: FreePoint(id: 'f', position: Vec2(1 + t, 2)),
        circle: k,
      ).projLine!;
      var prev = repAt(-0.01);
      for (var t = -0.008; t <= 0.0101; t += 0.002) {
        final cur = repAt(t);
        final dot =
            prev.a.re * cur.a.re + prev.b.re * cur.b.re + prev.c.re * cur.c.re;
        expect(dot, greaterThan(0), reason: 'sign jump at t = $t');
        prev = cur;
      }
    });

    test('a negatively-oriented circumcircle polarizes with the V1 '
        'orientation — the σ fix has real work', () {
      // ThreePointCircle's determinant emits a *negative* quadratic trace
      // when its points wind clockwise — the same circle, the opposite
      // representative — and the raw polar `A·p` flips with it. The
      // `sign(tr Q · w_p)` fix keeps the chart on V1's centre→pole
      // convention for both windings.
      final a = FreePoint(id: 'a', position: const Vec2(3, 0));
      final b = FreePoint(id: 'b', position: const Vec2(-3, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final pole = FreePoint(id: 'p', position: const Vec2(1, 2));
      for (final (p1, p2) in [(a, b), (b, a)]) {
        final k = ThreePointCircle(id: 'k', point1: p1, point2: p2, point3: c);
        final polar = PolarLine(id: 'pl', point: pole, circle: k);
        final n = pole.position - k.circle!.center;
        expect(
          polar.line!.direction.dot(Vec2(n.y, -n.x)),
          greaterThan(0),
          reason:
              'winding ${p1.id}${p2.id}: V1 runs the polar along the '
              'clockwise-rotated centre→pole offset',
        );
      }
      // The two windings really do produce opposite representatives —
      // otherwise this test stops covering the fix without failing.
      final ccw = ThreePointCircle(id: 'w1', point1: a, point2: b, point3: c);
      final cw = ThreePointCircle(id: 'w2', point1: b, point2: a, point3: c);
      expect(
        (ccw.conic!.xx.re + ccw.conic!.yy.re).sign,
        -(cw.conic!.xx.re + cw.conic!.yy.re).sign,
      );
    });

    test('a chartless carrier polarizes with a specified orientation', () {
      // An ellipse has no CircleEq, so V1's centre→pole chart rule never
      // spoke here and the chart orientation used to be the
      // largest-coefficient artifact of `normalized`. Now it is the
      // representative's, which for x²/4 + y² = 1 and the pole (4, 0)
      // is `tr Q · w_p` times `A·p = (1, 0, −1)` — normal +x, direction
      // −y (downward).
      final ellipse = StubProjectiveCircle(
        ConicMatrix(
          const Complex(0.25),
          Complex.zero,
          Complex.one,
          Complex.zero,
          Complex.zero,
          const Complex(-1),
        ),
      );
      expect(ellipse.circle, isNull);
      final polar = PolarLine(
        id: 'p',
        point: FreePoint(id: 'f', position: const Vec2(4, 0)),
        circle: ellipse,
      );
      expect(polar.line, isNotNull);
      expect(polar.line!.normal.dot(const Vec2(1, 0)), greaterThan(0));
      expect(polar.line!.direction.dot(const Vec2(0, -1)), greaterThan(0));
    });
  });
}
