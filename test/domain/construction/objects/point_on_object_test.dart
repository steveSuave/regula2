import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('PointOnObject', () {
    test('near() on a line lands on the tap projection', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);

      final p = PointOnObject.near(
        id: 'p',
        curve: line,
        position: const Vec2(3, 5),
      );

      expect(p.position!.closeTo(const Vec2(3, 0)), isTrue);
      expect(p.parents, [line]);
    });

    test('near() on a circle lands on the radial projection', () {
      final center = FreePoint(id: 'c', position: const Vec2(1, 1));
      final rim = FreePoint(id: 'r', position: const Vec2(3, 1));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);

      final p = PointOnObject.near(
        id: 'p',
        curve: circle,
        position: const Vec2(1, 9),
      );

      expect(p.position!.closeTo(const Vec2(1, 3)), isTrue);
    });

    test('near() on a segment clamps a tap past an endpoint onto it', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final segment = Segment(id: 's', point1: a, point2: b);

      final p = PointOnObject.near(
        id: 'p',
        curve: segment,
        position: const Vec2(6, 1),
      );
      expect(
        p.position!.closeTo(const Vec2(4, 0)),
        isTrue,
        reason: 'the projection lands past b and clamps to it',
      );
    });

    test('near() on a ray clamps a tap behind the origin onto it', () {
      final origin = FreePoint(id: 'o', position: const Vec2(1, 0));
      final through = FreePoint(id: 't', position: const Vec2(4, 0));
      final ray = Ray(id: 'r', origin: origin, through: through);

      final behind = PointOnObject.near(
        id: 'p',
        curve: ray,
        position: const Vec2(-5, 2),
      );
      expect(behind.position!.closeTo(const Vec2(1, 0)), isTrue);

      final ahead = PointOnObject.near(
        id: 'q',
        curve: ray,
        position: const Vec2(90, -3),
      );
      expect(
        ahead.position!.closeTo(const Vec2(90, 0)),
        isTrue,
        reason: 'the through side is unbounded',
      );
    });

    test('a shrinking segment carries the point on its endpoint, then '
        'gives it back', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final segment = Segment(id: 's', point1: a, point2: b);
      final p = PointOnObject(id: 'p', curve: segment, parameter: 3);
      construction
        ..add(a)
        ..add(b)
        ..add(segment)
        ..add(p);
      expect(p.position!.closeTo(const Vec2(3, 0)), isTrue);

      // Shorten the segment past the point: it clamps to the endpoint.
      construction.moveFreePoint('b', const Vec2(2, 0));
      expect(p.position!.closeTo(const Vec2(2, 0)), isTrue);
      expect(p.parameter, 3, reason: 'the stored parameter is untouched');

      // Grow it back: the point returns to where it was.
      construction.moveFreePoint('b', const Vec2(4, 0));
      expect(p.position!.closeTo(const Vec2(3, 0)), isTrue);
    });

    test('near() on a sector clamps the tap into the wedge', () {
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final start = FreePoint(id: 's', position: const Vec2(4, 0));
      final end = FreePoint(id: 'e', position: const Vec2(0, 4));
      final sector = Sector(id: 'w', center: center, start: start, end: end);

      final inside = PointOnObject.near(
        id: 'p',
        curve: sector,
        position: const Vec2(3, 3),
      );
      expect(inside.parameter, closeTo(math.pi / 4, 1e-9));

      final outside = PointOnObject.near(
        id: 'q',
        curve: sector,
        position: const Vec2(-4, 4),
      );
      expect(
        outside.parameter,
        closeTo(math.pi / 2, 1e-9),
        reason: 'a tap past the end rim snaps to the nearer wedge end',
      );
      expect(outside.position!.closeTo(const Vec2(0, 4)), isTrue);
    });

    test('a shrinking wedge carries the point on its rim end, then gives '
        'it back', () {
      final construction = Construction();
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final start = FreePoint(id: 's', position: const Vec2(4, 0));
      final end = FreePoint(id: 'e', position: const Vec2(0, 4));
      final sector = Sector(id: 'w', center: center, start: start, end: end);
      final p = PointOnObject(id: 'p', curve: sector, parameter: math.pi / 2);
      construction
        ..add(center)
        ..add(start)
        ..add(end)
        ..add(sector)
        ..add(p);
      expect(p.position!.closeTo(const Vec2(0, 4)), isTrue);

      // Shrink the wedge to [0, π/4]: the stored parameter falls outside
      // and the rendered position clamps to the end rim.
      construction.moveFreePoint('e', const Vec2(4, 4));
      final rim = Vec2(math.sqrt(8), math.sqrt(8));
      expect(p.position!.closeTo(rim), isTrue);
      expect(
        p.parameter,
        math.pi / 2,
        reason:
            'the stored parameter is untouched — clamping is a '
            'rendering of the extent, not a mutation',
      );

      // Grow the wedge back: the point returns to where it was.
      construction.moveFreePoint('e', const Vec2(0, 4));
      expect(p.position!.closeTo(const Vec2(0, 4)), isTrue);
    });

    test('rides along when the line moves', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = PointOnObject.near(
        id: 'p',
        curve: line,
        position: const Vec2(3, 0),
      );
      construction
        ..add(a)
        ..add(b)
        ..add(line)
        ..add(p);

      // Translate the whole line upward; the point must stay on it.
      construction.moveFreePoint('a', const Vec2(0, 2));
      construction.moveFreePoint('b', const Vec2(4, 2));
      expect(line.line!.contains(p.position!), isTrue);
      expect(p.position!.y, closeTo(2, 1e-9));
    });

    test('rides along when the circle grows', () {
      final construction = Construction();
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final p = PointOnObject.near(
        id: 'p',
        curve: circle,
        position: const Vec2(0, 2),
      );
      construction
        ..add(center)
        ..add(rim)
        ..add(circle)
        ..add(p);

      construction.moveFreePoint('r', const Vec2(5, 0));
      expect(
        p.position!.closeTo(const Vec2(0, 5)),
        isTrue,
        reason: 'the polar angle is fixed, the radius follows the curve',
      );
    });

    test('undefined while the curve is, recovers after', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = PointOnObject.near(
        id: 'p',
        curve: line,
        position: const Vec2(3, 0),
      );
      construction
        ..add(a)
        ..add(b)
        ..add(line)
        ..add(p);

      construction.moveFreePoint('b', Vec2.zero); // line degenerates
      expect(line.isDefined, isFalse);
      expect(p.isDefined, isFalse);

      construction.moveFreePoint('b', const Vec2(4, 0));
      expect(p.isDefined, isTrue);
      expect(line.line!.contains(p.position!), isTrue);
    });

    test('rejects a point parent and projection onto an undefined curve', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      final undefinedLine = LineThroughTwoPoints(id: 'l', point1: a, point2: b);

      expect(
        () => PointOnObject(id: 'p', curve: a, parameter: 0),
        throwsArgumentError,
      );
      expect(
        () => PointOnObject.near(
          id: 'p',
          curve: undefinedLine,
          position: Vec2.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => PointOnObject(id: 'p', curve: undefinedLine, parameter: 1),
        returnsNormally,
        reason: 'a stored parameter survives construction while undefined',
      );
    });
  });

  group('projective semantics (Phase 111)', () {
    test('stores the lifted chart evaluation', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = PointOnObject(id: 'p', curve: line, parameter: 3);

      expect(p.projPoint!.closeTo(ProjPoint.real(3, 0)), isTrue);
      expect(p.projPoint!.isIncidentTo(line.projLine!), isTrue);
    });

    test('a huge parameter stays defined — the chart read-back has no '
        'at-infinity cutoff', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = PointOnObject(id: 'p', curve: line, parameter: 1e12);

      expect(p.isDefined, isTrue);
      expect(p.position, const Vec2(1e12, 0));
    });

    test('a carrier with no chart projection leaves the point undefined, '
        'projPoint null', () {
      // Wholly at infinity: projLine exists, the chart view does not.
      final atInfinity = StubProjectiveLine(ProjLine.infinity);
      final onInfinity = PointOnObject(
        id: 'p',
        curve: atInfinity,
        parameter: 2,
      );
      expect(atInfinity.projLine, isNotNull);
      expect(onInfinity.isDefined, isFalse);
      expect(onInfinity.projPoint, isNull);

      // Complex carrier: same — parameters live in the affine chart.
      final complexLine = StubProjectiveLine(
        ProjLine(Complex.one, const Complex(0, 1), Complex.zero),
      );
      final onComplex = PointOnObject(
        id: 'q',
        curve: complexLine,
        parameter: 2,
      );
      expect(onComplex.isDefined, isFalse);
      expect(onComplex.projPoint, isNull);
    });

    test('a degenerate line-pair carrier (collinear three-point circle) '
        'leaves the point undefined', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      expect(circle.conic, isNotNull);
      expect(circle.circle, isNull);

      final p = PointOnObject(id: 'p', curve: circle, parameter: 1);
      expect(p.isDefined, isFalse);
      expect(p.projPoint, isNull);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'line host: recompute is invariant under complex rescaling of a '
      'carrier parent',
      (p, q, k) {
        if (ProjPoint.lift(p).closeTo(ProjPoint.lift(q))) return;
        final plain = PointOnObject(
          id: 'p1',
          curve: LineThroughTwoPoints(
            id: 'l1',
            point1: StubProjectivePoint(ProjPoint.lift(p)),
            point2: StubProjectivePoint(ProjPoint.lift(q)),
          ),
          parameter: 1.5,
        );
        final scaled = PointOnObject(
          id: 'p2',
          curve: LineThroughTwoPoints(
            id: 'l2',
            point1: StubProjectivePoint(ProjPoint.lift(p).scaledBy(k)),
            point2: StubProjectivePoint(ProjPoint.lift(q)),
          ),
          parameter: 1.5,
        );
        expect(scaled.projPoint!.closeTo(plain.projPoint!, 1e-6), isTrue);
        expect(scaled.position!.closeTo(plain.position!, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'circle host: recompute is invariant under complex rescaling of a '
      'carrier parent',
      (c, r, k) {
        if (ProjPoint.lift(c).closeTo(ProjPoint.lift(r))) return;
        final plain = PointOnObject(
          id: 'p1',
          curve: CircleCenterPoint(
            id: 'k1',
            center: StubProjectivePoint(ProjPoint.lift(c)),
            onCircle: StubProjectivePoint(ProjPoint.lift(r)),
          ),
          parameter: 0.7,
        );
        final scaled = PointOnObject(
          id: 'p2',
          curve: CircleCenterPoint(
            id: 'k2',
            center: StubProjectivePoint(ProjPoint.lift(c).scaledBy(k)),
            onCircle: StubProjectivePoint(ProjPoint.lift(r)),
          ),
          parameter: 0.7,
        );
        expect(scaled.position!.closeTo(plain.position!, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.component).test(
      'line host: pointAt(parameterAt(p)) projections are stable',
      (a, b, t) {
        if (ProjPoint.lift(a).closeTo(ProjPoint.lift(b))) return;
        final line = LineThroughTwoPoints(
          id: 'l',
          point1: FreePoint(id: 'a', position: a),
          point2: FreePoint(id: 'b', position: b),
        );
        final p = PointOnObject(id: 'p', curve: line, parameter: t);
        final carrier = line.line!;
        final recovered = carrier.parameterAt(p.position!);
        expect(recovered, closeTo(t, 1e-6 * (1 + t.abs())));
        expect(carrier.pointAt(recovered).closeTo(p.position!, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.component).test(
      'circle host: pointAt(angleAt(p)) projections are stable',
      (c, r, t) {
        if (ProjPoint.lift(c).closeTo(ProjPoint.lift(r))) return;
        final circle = CircleCenterPoint(
          id: 'k',
          center: FreePoint(id: 'c', position: c),
          onCircle: FreePoint(id: 'r', position: r),
        );
        final p = PointOnObject(id: 'p', curve: circle, parameter: t);
        final carrier = circle.circle!;
        final recovered = carrier.angleAt(p.position!);
        expect(carrier.pointAt(recovered).closeTo(p.position!, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'glued point stays on a line carrier under parent perturbation',
      (a, b, delta) {
        if (ProjPoint.lift(a).closeTo(ProjPoint.lift(b))) return;
        final construction = Construction();
        final pa = FreePoint(id: 'a', position: a);
        final pb = FreePoint(id: 'b', position: b);
        final line = LineThroughTwoPoints(id: 'l', point1: pa, point2: pb);
        final p = PointOnObject(id: 'p', curve: line, parameter: 2.5);
        construction
          ..add(pa)
          ..add(pb)
          ..add(line)
          ..add(p);

        final moved = b + delta;
        if (ProjPoint.lift(a).closeTo(ProjPoint.lift(moved))) return;
        construction.moveFreePoint('b', moved);
        expect(line.isDefined, isTrue);
        expect(p.isDefined, isTrue);
        expect(p.projPoint!.isIncidentTo(line.projLine!, 1e-9), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'glued point stays on a circle carrier under parent perturbation',
      (c, r, delta) {
        if (ProjPoint.lift(c).closeTo(ProjPoint.lift(r))) return;
        final construction = Construction();
        final pc = FreePoint(id: 'c', position: c);
        final pr = FreePoint(id: 'r', position: r);
        final circle = CircleCenterPoint(id: 'k', center: pc, onCircle: pr);
        final p = PointOnObject(id: 'p', curve: circle, parameter: 1.2);
        construction
          ..add(pc)
          ..add(pr)
          ..add(circle)
          ..add(p);

        final moved = r + delta;
        if (ProjPoint.lift(c).closeTo(ProjPoint.lift(moved))) return;
        construction.moveFreePoint('r', moved);
        expect(circle.isDefined, isTrue);
        expect(p.isDefined, isTrue);
        expect(circle.conic!.containsPoint(p.projPoint!, 1e-9), isTrue);
      },
    );
  });

  group('a general conic is a curve a point can be glued to (Phase 132)', () {
    // Before this phase `PointOnObject` knew two parameterizations —
    // signed arc-length on a line, polar angle on a circle — and a conic
    // with no `CircleEq` fell off the end of both: `recompute` left the
    // point undefined and `.near` *threw*. The hit tester has reported
    // general conics since Phase 119 and `resolvePoint` glue-probes every
    // hit curve, so that throw was reachable from the toolbar; the widget
    // test in `geometry_canvas_test.dart` pins the whole path.
    //
    // The parameter is `ConicShape`'s pencil angle, π-periodic and a
    // bijection from [0, π) onto the whole curve. A circle keeps its
    // polar angle, so no stored parameter changes meaning and no
    // document has to be migrated.

    List<FreePoint> ellipsePoints() => [
      FreePoint(id: 'p0', position: const Vec2(4, 0)),
      FreePoint(id: 'p1', position: const Vec2(0, 3)),
      FreePoint(id: 'p2', position: const Vec2(-4, 0)),
      FreePoint(id: 'p3', position: const Vec2(0, -3)),
      FreePoint(id: 'p4', position: const Vec2(2.4, 2.4)),
    ];

    test('a glued point sits exactly on the conic, not merely near it', () {
      final pts = ellipsePoints();
      final k = FivePointConic(id: 'k', points: pts);
      expect(
        k.circle,
        isNull,
        reason:
            'not a circle — the case that had no '
            'parameterization at all',
      );
      for (var i = 0; i < 12; i++) {
        final p = PointOnObject(id: 'g', curve: k, parameter: math.pi * i / 12);
        expect(p.isDefined, isTrue);
        expect(k.conic!.containsPoint(p.projPoint!, 1e-9), isTrue);
      }
    });

    test('the parameter is exactly π-periodic', () {
      final k = FivePointConic(id: 'k', points: ellipsePoints());
      for (final phi in [0.0, 0.4, 1.1, 2.9]) {
        final a = PointOnObject(id: 'a', curve: k, parameter: phi);
        final b = PointOnObject(id: 'b', curve: k, parameter: phi + math.pi);
        expect(a.position!.closeTo(b.position!), isTrue);
      }
    });

    test('.near glues where the tap landed — the nearest point of the ink, '
        'not the arc of the join', () {
      final k = FivePointConic(id: 'k', points: ellipsePoints());
      for (final tap in [
        const Vec2(3.6, 1.3),
        const Vec2(-3.9, 0.2),
        const Vec2(0.1, -2.9),
      ]) {
        final glued = PointOnObject.near(id: 'g', curve: k, position: tap);
        expect(k.conic!.containsPoint(glued.projPoint!, 1e-9), isTrue);
        // No sample of the curve is closer to the tap than the glue is.
        final shape = ConicShape.of(k.conic!);
        final chosen = glued.position!.distanceTo(tap);
        for (var i = 0; i < 720; i++) {
          final v = shape.chartPointAt(math.pi * i / 720);
          if (v == null) continue;
          expect(v.distanceTo(tap), greaterThan(chosen - 1e-6));
        }
      }
    });

    test('the point rides the conic when a defining point moves', () {
      final pts = ellipsePoints();
      final k = FivePointConic(id: 'k', points: pts);
      final construction = Construction();
      for (final p in pts) {
        construction.add(p);
      }
      construction
        ..add(k)
        ..add(PointOnObject(id: 'g', curve: k, parameter: 0.97));
      for (var i = 1; i <= 8; i++) {
        construction.moveFreePoint('p4', Vec2(2.4, 2.4 + i * 0.05));
        final glued = construction.byId('g')! as PointOnObject;
        expect(glued.isDefined, isTrue);
        expect(k.conic!.containsPoint(glued.projPoint!, 1e-9), isTrue);
      }
    });

    test('a conic with no real curve leaves the point undefined', () {
      // An imaginary ellipse: real coefficients, no real points.
      final empty = StubProjectiveConic(
        const ConicMatrix(
          Complex.one,
          Complex.zero,
          Complex.one,
          Complex.zero,
          Complex.zero,
          Complex.one,
        ),
      );
      expect(ConicShape.of(empty.conic!).isParameterized, isFalse);
      final p = PointOnObject(id: 'g', curve: empty, parameter: 0.5);
      expect(p.isDefined, isFalse);
      expect(p.projPoint, isNull);
      expect(
        () => PointOnObject.near(id: 'g', curve: empty, position: Vec2.zero),
        throwsArgumentError,
      );
    });
  });
}
