import 'package:glados/glados.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
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
      expect(s.clampParameter(inside), inside,
          reason: 'inside parameters pass through untouched');
      expect(s.clampParameter(min - 3), min);
      expect(s.clampParameter(max + 3), max);

      // Swapped parents: bounds still ordered, spanning the same world
      // endpoints regardless of the carrier's orientation.
      final reversed = Segment(id: 'r', point1: b, point2: a);
      final (rMin, rMax) = reversed.parameterExtent!;
      expect(rMin!, lessThan(rMax!));
      final ends = [
        reversed.line!.pointAt(rMin),
        reversed.line!.pointAt(rMax),
      ];
      expect(ends.any((p) => p.closeTo(const Vec2(1, 0))), isTrue);
      expect(ends.any((p) => p.closeTo(const Vec2(5, 0))), isTrue);
    });
  });

  group('projective semantics (Phase 107)', () {
    test('an endpoint at infinity leaves the segment wholly undefined', () {
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      final inf = StubProjectivePoint(ProjPoint.real(3, 4, 0));
      final s = Segment(id: 's', point1: a, point2: inf);
      expect(s.isDefined, isFalse);
      expect(s.line, isNull);
      expect(s.projLine, isNull,
          reason: 'a segment IS its drawn extent — carrier included');
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
    });
  });
}
