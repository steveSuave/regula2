import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('ParallelLine', () {
    test('contains the through-point and is parallel to the reference', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final par = ParallelLine(id: 'k', through: p, reference: ref);

      expect(par.parents, [p, ref]);
      expect(par.line!.contains(p.position), isTrue);
      expect(par.line!.isParallelTo(ref.line!), isTrue);
      expect(
        par.line!.contains(a.position),
        isFalse,
        reason: 'a distinct parallel, not the reference itself',
      );
    });

    test('a through-point on the reference yields the same (defined) line', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final par = ParallelLine(id: 'k', through: a, reference: ref);

      expect(par.isDefined, isTrue);
      expect(par.line!.closeTo(ref.line!), isTrue);
    });

    test(
      'reference degenerates (coincident points): undefined, then recovers',
      () {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(4, 0));
        final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
        final p = FreePoint(id: 'p', position: const Vec2(1, 5));
        final par = ParallelLine(id: 'k', through: p, reference: ref);
        construction
          ..add(a)
          ..add(b)
          ..add(ref)
          ..add(p)
          ..add(par);

        construction.moveFreePoint('b', const Vec2(0, 0));
        expect(par.isDefined, isFalse);
        expect(par.line, isNull);

        construction.moveFreePoint('b', const Vec2(0, 4));
        expect(par.isDefined, isTrue);
        expect(par.line!.contains(p.position), isTrue);
        expect(par.line!.isParallelTo(ref.line!), isTrue);
      },
    );

    test('tracks a rotating reference', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final par = ParallelLine(id: 'k', through: p, reference: ref);
      construction
        ..add(a)
        ..add(b)
        ..add(ref)
        ..add(p)
        ..add(par);

      construction.moveFreePoint('b', const Vec2(4, 4));
      expect(par.line!.contains(p.position), isTrue);
      expect(par.line!.isParallelTo(ref.line!), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('reference at the line at infinity: undefined (zero carrier)', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final ref = StubProjectiveLine(ProjLine.infinity);
      final par = ParallelLine(id: 'k', through: p, reference: ref);
      expect(par.isDefined, isFalse);
      expect(par.projLine, isNull);
    });

    test('through-point at the reference direction\'s own point at '
        'infinity: undefined (any parallel would do)', () {
      final through = StubProjectivePoint(ProjPoint.real(1, 0, 0));
      final ref = StubProjectiveLine(
        ProjLine.lift(LineEq(0, 1, -2)), // y = 2, direction [1 : 0 : 0].
      );
      final par = ParallelLine(id: 'k', through: through, reference: ref);
      expect(par.isDefined, isFalse);
      expect(par.projLine, isNull);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of either parent',
      (a, b, k) {
        if (a.closeTo(b, 1e-3)) {
          return;
        }
        final refLine = LineEq.throughPoints(a, b);
        final plain = ParallelLine(
          id: 'k1',
          through: StubProjectivePoint(ProjPoint.real(-3, 7)),
          reference: StubProjectiveLine(ProjLine.lift(refLine)),
        );
        final scaled = ParallelLine(
          id: 'k2',
          through: StubProjectivePoint(ProjPoint.real(-3, 7).scaledBy(k)),
          reference: StubProjectiveLine(ProjLine.lift(refLine).scaledBy(k)),
        );
        expect(scaled.projLine!.closeTo(plain.projLine!), isTrue);
        expect(scaled.line!.closeTo(plain.line!), isTrue);
      },
    );
  });
}
