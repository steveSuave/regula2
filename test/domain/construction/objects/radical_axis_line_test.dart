import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/radical_axis_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';

import '../../../projective_stubs.dart';
import '../../../v1_oracle/circle_relations.dart' as v1;
import '../../math/generators.dart';

void main() {
  group('RadicalAxisLine', () {
    (Construction, RadicalAxisLine) build({
      Vec2 center1 = const Vec2(0, 0),
      Vec2 rim1 = const Vec2(2, 0),
      Vec2 center2 = const Vec2(4, 0),
      Vec2 rim2 = const Vec2(6, 0),
    }) {
      final construction = Construction();
      final o1 = FreePoint(id: 'o1', position: center1);
      final r1 = FreePoint(id: 'r1', position: rim1);
      final o2 = FreePoint(id: 'o2', position: center2);
      final r2 = FreePoint(id: 'r2', position: rim2);
      final c1 = CircleCenterPoint(id: 'c1', center: o1, onCircle: r1);
      final c2 = CircleCenterPoint(id: 'c2', center: o2, onCircle: r2);
      final axis = RadicalAxisLine(id: 'x', circle1: c1, circle2: c2);
      construction
        ..add(o1)
        ..add(r1)
        ..add(o2)
        ..add(r2)
        ..add(c1)
        ..add(c2)
        ..add(axis);
      return (construction, axis);
    }

    test('equal circles: the perpendicular bisector of the centers', () {
      final (_, axis) = build();
      expect(axis.line!.closeTo(LineEq(1, 0, -2)), isTrue);
      expect(axis.parents.map((p) => p.id), ['c1', 'c2']);
    });

    test('unequal radii shift the axis toward the larger circle', () {
      // r1 = 1, r2 = 3: powers of (1, y) are equal — the axis is x = 1.
      final (_, axis) = build(rim1: const Vec2(1, 0), rim2: const Vec2(7, 0));
      expect(axis.line!.closeTo(LineEq(1, 0, -1)), isTrue);
    });

    test('drag to concentric: undefined, then recovers', () {
      final (construction, axis) = build();

      construction.moveFreePoint('o2', const Vec2(0, 0));
      expect(axis.isDefined, isFalse);
      expect(axis.line, isNull);

      construction.moveFreePoint('o2', const Vec2(4, 0));
      expect(axis.isDefined, isTrue);
      expect(axis.line!.closeTo(LineEq(1, 0, -2)), isTrue);
    });

    test('undefined while a parent circle is', () {
      // A zero-separation center/rim pair is still a (point) circle, so
      // undefine a parent by collapsing the *other* circle onto it is not
      // possible here; instead drag the first circle's rim onto its
      // center — radius 0 keeps the circle defined — then make the two
      // circles concentric point-circles, which is the undefined case.
      final (construction, axis) = build();
      construction.moveFreePoint('r1', const Vec2(0, 0));
      expect(axis.isDefined, isTrue);

      construction.moveFreePoint('o2', const Vec2(0, 0));
      expect(axis.isDefined, isFalse);
    });

    test('identical circle instances are rejected', () {
      final o = FreePoint(id: 'o', position: const Vec2(0, 0));
      final r = FreePoint(id: 'r', position: const Vec2(2, 0));
      final c = CircleCenterPoint(id: 'c', center: o, onCircle: r);
      expect(
        () => RadicalAxisLine(id: 'x', circle1: c, circle2: c),
        throwsArgumentError,
      );
    });
  });

  group('projective semantics (Phase 110)', () {
    CircleCenterPoint circleOf(String id, CircleEq c) => CircleCenterPoint(
      id: id,
      center: FreePoint(id: '$id-o', position: c.center),
      onCircle: FreePoint(id: '$id-r', position: c.center + Vec2(c.radius, 0)),
    );

    Glados2(any.circleEq, any.circleEq).test(
      'agrees with V1 radicalAxis in line and orientation',
      (c1, c2) {
        final d = c1.center.distanceTo(c2.center);
        if (d < 1e-3 * (1 + c1.radius + c2.radius)) {
          return;
        }
        final k1 = circleOf('k1', c1);
        final k2 = circleOf('k2', c2);
        final axis = RadicalAxisLine(id: 'x', circle1: k1, circle2: k2);
        final expected = v1.radicalAxis(k1.circle!, k2.circle!)!;
        expect(axis.line, isNotNull);
        expect(
          axis.line!.closeTo(expected),
          isTrue,
          reason: '${axis.line} vs $expected',
        );
        expect(axis.line!.direction.dot(expected.direction), greaterThan(0));
      },
    );

    test('concentric circles carry ℓ∞: projective value, no affine view', () {
      final o = FreePoint(id: 'o', position: const Vec2(1, 2));
      final c1 = CircleCenterPoint(
        id: 'c1',
        center: o,
        onCircle: FreePoint(id: 'r1', position: const Vec2(2, 2)),
      );
      final c2 = CircleCenterPoint(
        id: 'c2',
        center: o,
        onCircle: FreePoint(id: 'r2', position: const Vec2(4, 2)),
      );
      final axis = RadicalAxisLine(id: 'x', circle1: c1, circle2: c2);
      expect(axis.isDefined, isFalse);
      expect(axis.line, isNull);
      expect(axis.projLine, isNotNull);
      expect(axis.projLine!.closeTo(ProjLine.infinity), isTrue);
    });

    test('exactly coincident carriers cancel to undefined', () {
      final conic = ConicMatrix.lift(CircleEq(const Vec2(1, 2), 3));
      final axis = RadicalAxisLine(
        id: 'x',
        circle1: StubProjectiveCircle(conic),
        circle2: StubProjectiveCircle(conic.scaledBy(const Complex(2, -1))),
      );
      expect(axis.isDefined, isFalse);
      expect(axis.projLine, isNull);
    });

    Glados2(any.coordinate, any.coordinate).test(
      'complex rescaling of the parent conics leaves the axis invariant',
      (re, im) {
        var k = Complex(re, im);
        if (k.abs2 < 1) {
          k = k + const Complex(2, 1);
        }
        final a = ConicMatrix.lift(CircleEq(const Vec2(1, 2), 2));
        final b = ConicMatrix.lift(CircleEq(const Vec2(4, -1), 1));
        final baseline = RadicalAxisLine(
          id: 'x',
          circle1: StubProjectiveCircle(a),
          circle2: StubProjectiveCircle(b),
        );
        final scaled = RadicalAxisLine(
          id: 'y',
          circle1: StubProjectiveCircle(a.scaledBy(k)),
          circle2: StubProjectiveCircle(b.scaledBy(k)),
        );
        expect(scaled.projLine!.closeTo(baseline.projLine!), isTrue);
        expect(scaled.line!.closeTo(baseline.line!), isTrue);
        // The *geometric* axis is scale-invariant. The orientation is the
        // representative's sign (Phase 137), pinned under sign-preserving
        // rescales; a complex phase legitimately carries into the
        // representative (see the polar's twin test).
        final positively = RadicalAxisLine(
          id: 'z',
          circle1: StubProjectiveCircle(a.scaledBy(Complex(k.abs))),
          circle2: StubProjectiveCircle(b.scaledBy(Complex(k.abs))),
        );
        expect(
          positively.line!.direction.dot(baseline.line!.direction),
          greaterThan(0),
        );
      },
    );
  });

  group('representative-founded orientation (Phase 137)', () {
    test('a negatively-oriented circumcircle parent keeps the V1 axis '
        'orientation — the σ fix has real work', () {
      // ThreePointCircle emits a negative quadratic trace for clockwise
      // winding, and `radicalAxisOf`'s linear part carries the product of
      // both parents' traces — the `sign(tr Q₁ · tr Q₂)` fix keeps the
      // chart on V1's centre₁→centre₂ convention for every winding pair.
      final a = FreePoint(id: 'a', position: const Vec2(3, 0));
      final b = FreePoint(id: 'b', position: const Vec2(-3, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final d = FreePoint(id: 'd', position: const Vec2(7, 1));
      final e = FreePoint(id: 'e', position: const Vec2(9, -1));
      final f = FreePoint(id: 'f', position: const Vec2(8, 3));
      for (final (p1, p2) in [(a, b), (b, a)]) {
        for (final (q1, q2) in [(d, e), (e, d)]) {
          final k1 = ThreePointCircle(
            id: 'k1',
            point1: p1,
            point2: p2,
            point3: c,
          );
          final k2 = ThreePointCircle(
            id: 'k2',
            point1: q1,
            point2: q2,
            point3: f,
          );
          final axis = RadicalAxisLine(id: 'ra', circle1: k1, circle2: k2);
          final offset = k2.circle!.center - k1.circle!.center;
          expect(
            axis.line!.direction.dot(Vec2(offset.y, -offset.x)),
            greaterThan(0),
            reason: 'windings ${p1.id}${p2.id}/${q1.id}${q2.id}',
          );
        }
      }
    });
  });
}
