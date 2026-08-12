import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../math/generators.dart';

void main() {
  group('PerpendicularBisectorLine', () {
    test('passes through the midpoint, perpendicular to the join', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 1));
      final q = FreePoint(id: 'q', position: const Vec2(5, 3));
      final bisector = PerpendicularBisectorLine(
        id: 'b',
        point1: p,
        point2: q,
      );
      final line = bisector.line!;
      expect(line.contains(const Vec2(3, 2)), isTrue);
      expect(line.direction.dot(const Vec2(4, 2)), closeTo(0, 1e-12));
      expect(bisector.parents, [p, q]);
    });

    test('undefined while the points coincide, recovers on drag', () {
      final p = FreePoint(id: 'p', position: const Vec2(2, 2));
      final q = FreePoint(id: 'q', position: const Vec2(2, 2));
      final bisector = PerpendicularBisectorLine(
        id: 'b',
        point1: p,
        point2: q,
      );
      expect(bisector.line, isNull);
      expect(bisector.isDefined, isFalse);

      q.position = const Vec2(6, 2);
      bisector.recompute();
      expect(bisector.line, isNotNull);
      expect(bisector.line!.contains(const Vec2(4, 7)), isTrue,
          reason: 'vertical bisector of a horizontal join at x = 4');

      q.position = const Vec2(2, 2);
      bisector.recompute();
      expect(bisector.line, isNull, reason: 'coincident again — undefined');
    });

    test('undefined while a parent is', () {
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final x = FreePoint(id: 'x', position: const Vec2(4, 0));
      final p = FreePoint(id: 'p', position: const Vec2(0, 1));
      final q = FreePoint(id: 'q', position: const Vec2(4, 1));
      final xAxis = LineThroughTwoPoints(id: 'h', point1: o, point2: x);
      final other = LineThroughTwoPoints(id: 'l', point1: p, point2: q);
      final crossing = IntersectionPoint(
        id: 'int',
        curve1: xAxis,
        curve2: other,
        branchIndex: 0,
      );
      final bisector = PerpendicularBisectorLine(
        id: 'b',
        point1: crossing,
        point2: x,
      );
      expect(crossing.position, isNull, reason: 'parallel lines — no crossing');
      expect(bisector.line, isNull);

      // Tilt the second line: the crossing appears and the bisector with it.
      q.position = const Vec2(4, -1);
      other.recompute();
      crossing.recompute();
      bisector.recompute();
      expect(crossing.position, isNotNull);
      expect(bisector.line, isNotNull);
    });

    Glados2(any.vec2, any.vec2).test(
      'every carrier point is equidistant from the two parents',
      (a, b) {
        // Coincident draws would be undefined — nudge like the lineEq
        // generator does.
        final b2 = a == b ? b + const Vec2(1, 0) : b;
        final bisector = PerpendicularBisectorLine(
          id: 'b',
          point1: FreePoint(id: 'p', position: a),
          point2: FreePoint(id: 'q', position: b2),
        );
        final line = bisector.line!;
        for (final t in const [-100.0, -1.0, 0.0, 2.5, 500.0]) {
          final probe = line.pointAt(t);
          // The tolerance scales with the probe distance: the subtraction
          // of two nearly-equal large distances loses absolute precision.
          final scale = 1 + probe.distanceTo(a);
          expect(
            probe.distanceTo(a),
            closeTo(probe.distanceTo(b2), 1e-9 * scale),
          );
        }
      },
    );

    Glados3(any.vec2, any.vec2, any.coordinate).test(
        'recompute is invariant under complex rescaling of a parent '
        '(Phase 107)', (p, q, kRe) {
      if (p.closeTo(q, 1e-3)) {
        return;
      }
      // A genuinely complex scalar, bounded away from zero.
      final k = Complex(kRe.abs() >= 1 ? kRe : kRe + 2, 1.5);
      final plain = PerpendicularBisectorLine(
        id: 'b1',
        point1: StubProjectivePoint(ProjPoint.lift(p)),
        point2: StubProjectivePoint(ProjPoint.lift(q)),
      );
      final scaled = PerpendicularBisectorLine(
        id: 'b2',
        point1: StubProjectivePoint(ProjPoint.lift(p).scaledBy(k)),
        point2: StubProjectivePoint(ProjPoint.lift(q)),
      );
      expect(scaled.projLine!.closeTo(plain.projLine!), isTrue);
      expect(scaled.line!.closeTo(plain.line!), isTrue);
    });
  });
}
