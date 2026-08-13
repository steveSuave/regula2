import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  group('PerpendicularLine', () {
    test(
      'contains the through-point and is perpendicular to the reference',
      () {
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(4, 2));
        final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
        final p = FreePoint(id: 'p', position: const Vec2(1, 5));
        final perp = PerpendicularLine(id: 'k', through: p, reference: ref);

        expect(perp.parents, [p, ref]);
        expect(perp.line!.contains(p.position), isTrue);
        expect(
          perp.line!.direction.dot(ref.line!.direction),
          closeTo(0, 1e-12),
        );
      },
    );

    test('a through-point on the reference line itself is fine', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final perp = PerpendicularLine(id: 'k', through: a, reference: ref);

      expect(perp.line!.contains(a.position), isTrue);
      expect(perp.line!.direction.dot(ref.line!.direction), closeTo(0, 1e-12));
    });

    test("a segment's carrier serves as the reference", () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final seg = Segment(id: 's', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(2, 3));
      final perp = PerpendicularLine(id: 'k', through: p, reference: seg);

      // Vertical line x = 2.
      expect(perp.line!.contains(const Vec2(2, -100)), isTrue);
      expect(perp.line!.contains(const Vec2(2, 100)), isTrue);
    });

    test(
      'reference degenerates (coincident points): undefined, then recovers',
      () {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(4, 0));
        final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
        final p = FreePoint(id: 'p', position: const Vec2(1, 5));
        final perp = PerpendicularLine(id: 'k', through: p, reference: ref);
        construction
          ..add(a)
          ..add(b)
          ..add(ref)
          ..add(p)
          ..add(perp);

        construction.moveFreePoint('b', const Vec2(0, 0));
        expect(perp.isDefined, isFalse);
        expect(perp.line, isNull);

        construction.moveFreePoint('b', const Vec2(0, 4));
        expect(perp.isDefined, isTrue);
        expect(perp.line!.contains(p.position), isTrue);
        expect(
          perp.line!.direction.dot(ref.line!.direction),
          closeTo(0, 1e-12),
        );
      },
    );

    test('through-point goes undefined: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      final o = Circumcenter(id: 'o', vertex1: a, vertex2: b, vertex3: c);
      final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final perp = PerpendicularLine(id: 'k', through: o, reference: ref);
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(o)
        ..add(ref)
        ..add(perp);

      construction.moveFreePoint('c', const Vec2(2, 0)); // collinear
      expect(perp.isDefined, isFalse);

      construction.moveFreePoint('c', const Vec2(0, 3));
      expect(perp.isDefined, isTrue);
      expect(perp.line!.contains(o.position!), isTrue);
    });

    test('tracks a moving through-point', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final ref = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final perp = PerpendicularLine(id: 'k', through: p, reference: ref);
      construction
        ..add(a)
        ..add(b)
        ..add(ref)
        ..add(p)
        ..add(perp);

      construction.moveFreePoint('p', const Vec2(-3, 7));
      expect(perp.line!.contains(const Vec2(-3, 7)), isTrue);
      expect(perp.line!.direction.dot(ref.line!.direction), closeTo(0, 1e-12));
    });
  });

  group('projective semantics (Phase 107)', () {
    test('reference at the line at infinity: undefined (zero carrier)', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 5));
      final ref = StubProjectiveLine(ProjLine.infinity);
      final perp = PerpendicularLine(id: 'k', through: p, reference: ref);
      expect(perp.isDefined, isFalse);
      expect(perp.projLine, isNull);
    });

    Glados3(any.vec2, any.vec2, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of either parent',
      (a, b, k) {
        if (a.closeTo(b, 1e-3)) {
          return;
        }
        final refLine = LineEq.throughPoints(a, b);
        final plain = PerpendicularLine(
          id: 'k1',
          through: StubProjectivePoint(ProjPoint.real(-3, 7)),
          reference: StubProjectiveLine(ProjLine.lift(refLine)),
        );
        final scaled = PerpendicularLine(
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
