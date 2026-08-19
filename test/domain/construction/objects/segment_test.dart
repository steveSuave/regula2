import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('Segment', () {
    test('exposes endpoints and a carrier line through both', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 4));
      final s = Segment(id: 's', point1: a, point2: b);
      expect(s.start, const Vec2(0, 0));
      expect(s.end, const Vec2(4, 4));
      expect(s.line!.contains(const Vec2(2, 2)), isTrue);
    });

    test('undefined while endpoints coincide, endpoints still readable', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final b = FreePoint(id: 'b', position: const Vec2(1, 1));
      final s = Segment(id: 's', point1: a, point2: b);
      expect(s.isDefined, isFalse);
      expect(s.line, isNull);
      expect(s.start, const Vec2(1, 1));
      expect(s.end, const Vec2(1, 1));
      expect(s.parameterExtent, isNull);
    });

    test('parameterExtent spans the endpoints; clampParameter confines '
        'carrier parameters to it', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 0));
      final b = FreePoint(id: 'b', position: const Vec2(5, 0));
      final s = Segment(id: 's', point1: a, point2: b);

      final (min, max) = s.parameterExtent!;
      final line = s.line!;
      expect(min, line.parameterAt(const Vec2(1, 0)));
      expect(max, line.parameterAt(const Vec2(5, 0)));
      expect(min!, lessThan(max!), reason: 'bounds come out ordered');

      final inside = (min + max) / 2;
      expect(
        s.clampParameter(inside),
        inside,
        reason: 'inside parameters pass through untouched',
      );
      expect(s.clampParameter(min - 3), min);
      expect(s.clampParameter(max + 3), max);

      // Swapped parents: bounds still ordered, spanning the same world
      // endpoints regardless of the carrier's orientation.
      final reversed = Segment(id: 'r', point1: b, point2: a);
      final (rMin, rMax) = reversed.parameterExtent!;
      expect(rMin!, lessThan(rMax!));
      final ends = [reversed.line!.pointAt(rMin), reversed.line!.pointAt(rMax)];
      expect(ends.any((p) => p.closeTo(const Vec2(1, 0))), isTrue);
      expect(ends.any((p) => p.closeTo(const Vec2(5, 0))), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('an endpoint at infinity leaves the segment undefined but keeps '
        'its carrier (Phase 136b)', () {
      // Phase 107 nulled the carrier too, on the argument that a segment
      // IS its drawn extent. The extent half of that is right and is
      // still pinned below; the carrier half was a fourth, undocumented
      // exception to the one degeneracy convention, and it made the
      // object untraceable — see the class doc.
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final inf = StubProjectivePoint(ProjPoint.real(3, 4, 0));
      final s = Segment(id: 's', point1: a, point2: inf);
      expect(s.isDefined, isFalse);
      expect(s.line, isNull, reason: 'a segment IS its drawn extent');
      expect(s.start, const Vec2(1, 2));
      expect(s.end, isNull);
      expect(s.parameterExtent, isNull);
      final carrier = s.projLine;
      expect(
        carrier,
        isNotNull,
        reason: 'the join of two projective points is a projective line',
      );
      // The real line through the finite endpoint in the direction the
      // infinite one names — what `LineThroughTwoPoints` has answered
      // since Phase 107.
      expect(carrier!.isReal(), isTrue);
      expect(
        carrier.contains(ProjPoint.real(1, 2, 1)),
        isTrue,
        reason: 'through the finite endpoint',
      );
      expect(
        carrier.contains(ProjPoint.real(3, 4, 0)),
        isTrue,
        reason: 'and in the direction the point at infinity names',
      );
    });

    test('a complex endpoint keeps the carrier and hides it from static '
        'intersection (Phase 136b)', () {
      // What the split is *for*: a pass that complexifies a parent still
      // has a carrier to continue along, while nothing static can see
      // it — `intersectionCandidates` refuses complex carriers on its
      // own (the Phase 110 realness gate), so this changes no static
      // answer anywhere.
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final complex = StubProjectivePoint(
        ProjPoint(Complex(3, 0.5), const Complex(4, 0), const Complex(1, 0)),
      );
      final s = Segment(id: 's', point1: a, point2: complex);
      expect(s.isDefined, isFalse);
      expect(s.line, isNull);
      final carrier = s.projLine;
      expect(carrier, isNotNull);
      expect(carrier!.isReal(), isFalse);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of a parent',
      (p, q, k) {
        if (p.closeTo(q, 1e-3)) {
          return;
        }
        final plain = Segment(
          id: 's1',
          point1: StubProjectivePoint(ProjPoint.lift(p)),
          point2: StubProjectivePoint(ProjPoint.lift(q)),
        );
        final scaled = Segment(
          id: 's2',
          point1: StubProjectivePoint(ProjPoint.lift(p).scaledBy(k)),
          point2: StubProjectivePoint(ProjPoint.lift(q)),
        );
        expect(scaled.projLine!.closeTo(plain.projLine!), isTrue);
        expect(scaled.line!.closeTo(plain.line!), isTrue);
      },
    );
  });
}
