import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';

void main() {
  group('Sector', () {
    test('start fixes radius and start angle; end fixes only the angle', () {
      final c = FreePoint(id: 'c', position: Vec2.zero);
      final s = FreePoint(id: 's', position: const Vec2(2, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 5));
      final sector = Sector(id: 'w', center: c, start: s, end: e);

      expect(sector.circle!.center, Vec2.zero);
      expect(sector.circle!.radius, closeTo(2, 1e-9));
      expect(sector.startAngle, closeTo(0, 1e-9));
      expect(sector.sweep, closeTo(math.pi / 2, 1e-9));
      expect(sector.startRim!.closeTo(const Vec2(2, 0)), isTrue);
      expect(
        sector.endRim!.closeTo(const Vec2(0, 2)),
        isTrue,
        reason: "end's distance from the center must not matter",
      );
      expect(sector.parents, [c, s, e]);
    });

    test('the sweep is always counter-clockwise from start to end', () {
      final c = FreePoint(id: 'c', position: Vec2.zero);
      final s = FreePoint(id: 's', position: const Vec2(0, 5));
      final e = FreePoint(id: 'e', position: const Vec2(2, 0));
      final sector = Sector(id: 'w', center: c, start: s, end: e);

      expect(
        sector.sweep,
        closeTo(3 * math.pi / 2, 1e-9),
        reason: 'swapped start/end covers the complementary wedge',
      );
    });

    test('containsAngle covers exactly the wedge, endpoints included', () {
      final sector = Sector(
        id: 'w',
        center: FreePoint(id: 'c', position: Vec2.zero),
        start: FreePoint(id: 's', position: const Vec2(2, 0)),
        end: FreePoint(id: 'e', position: const Vec2(0, 5)),
      );

      expect(sector.containsAngle(0), isTrue);
      expect(sector.containsAngle(math.pi / 4), isTrue);
      expect(sector.containsAngle(math.pi / 2), isTrue);
      expect(sector.containsAngle(math.pi), isFalse);
      expect(sector.containsAngle(-math.pi / 4), isFalse);
    });

    test('angularExtent is the wedge; clampAngle confines carrier angles '
        'to it', () {
      final sector = Sector(
        id: 'w',
        center: FreePoint(id: 'c', position: Vec2.zero),
        start: FreePoint(id: 's', position: const Vec2(2, 0)),
        end: FreePoint(id: 'e', position: const Vec2(0, 5)),
      );

      final (start, sweep) = sector.angularExtent!;
      expect(start, closeTo(0, 1e-9));
      expect(sweep, closeTo(math.pi / 2, 1e-9));
      expect(
        sector.clampAngle(math.pi / 4),
        math.pi / 4,
        reason: 'inside angles pass through untouched',
      );
      expect(sector.clampAngle(-math.pi / 6), closeTo(0, 1e-9));
      expect(sector.clampAngle(3 * math.pi / 4), closeTo(math.pi / 2, 1e-9));
    });

    test('undefined while start or end sits on the center; recovers', () {
      final construction = Construction();
      final c = FreePoint(id: 'c', position: Vec2.zero);
      final s = FreePoint(id: 's', position: const Vec2(2, 0));
      final e = FreePoint(id: 'e', position: const Vec2(0, 3));
      final sector = Sector(id: 'w', center: c, start: s, end: e);
      construction
        ..add(c)
        ..add(s)
        ..add(e)
        ..add(sector);

      construction.moveFreePoint('s', Vec2.zero);
      expect(sector.isDefined, isFalse);
      expect(sector.startRim, isNull);
      expect(sector.endRim, isNull);
      expect(sector.containsAngle(0), isFalse);
      expect(sector.angularExtent, isNull);

      construction.moveFreePoint('s', const Vec2(2, 0));
      expect(sector.isDefined, isTrue);

      construction.moveFreePoint('e', Vec2.zero);
      expect(sector.isDefined, isFalse);
    });
  });

  group('projective semantics (Phase 109)', () {
    test('recompute is invariant under complex rescaling of parents', () {
      final c = StubProjectivePoint(ProjPoint.real(0, 0), id: 'c');
      final s = StubProjectivePoint(ProjPoint.real(2, 0), id: 's');
      final e = StubProjectivePoint(ProjPoint.real(0, 7), id: 'e');
      final sector = Sector(id: 'k', center: c, start: s, end: e);
      final reference = sector.conic!;
      c.value = c.value!.scaledBy(const Complex(0, 2));
      s.value = s.value!.scaledBy(const Complex(-3, 1));
      e.value = e.value!.scaledBy(const Complex(0.5, 0.5));
      sector.recompute();
      expect(sector.conic!.closeTo(reference), isTrue);
      expect(sector.circle!.radius, closeTo(2, 1e-9));
      expect(sector.startAngle!, closeTo(0, 1e-9));
      expect(sector.sweep!, closeTo(math.pi / 2, 1e-9));
    });

    test('an end off the chart keeps the carrier and loses only the wedge '
        '(Phase 136c)', () {
      // The defect the audit was looking for: `circleThrough(center,
      // start)` reads no chart at all, but the old guard nulled the
      // carrier the moment any parent lost its affine position. A pass
      // that complexifies `end` then had nothing to continue along.
      final c = FreePoint(id: 'c', position: Vec2.zero);
      final s = FreePoint(id: 's', position: const Vec2(2, 0));
      final e = StubProjectivePoint(
        ProjPoint(const Complex(0, 5), const Complex(3, 0), Complex.one),
        id: 'e',
      );
      final sector = Sector(id: 'k', center: c, start: s, end: e);

      final carrier = sector.conic;
      expect(carrier, isNotNull, reason: 'the carrier does not read the chart');
      expect(carrier!.isReal(), isTrue, reason: 'center and start are real');
      expect(
        carrier.toCircleEq()!.radius,
        closeTo(2, 1e-9),
        reason: 'and it is the circle center-through-start it always was',
      );

      expect(sector.isDefined, isFalse, reason: 'the wedge is unchanged');
      expect(sector.circle, isNull);
      expect(sector.startAngle, isNull);
      expect(sector.sweep, isNull);
      expect(sector.angularExtent, isNull);
      expect(sector.startRim, isNull);
      expect(sector.endRim, isNull);
      expect(sector.containsAngle(0), isFalse);
    });

    test('an end at infinity is the same split, and the carrier stays real '
        '(Phase 136c)', () {
      final sector = Sector(
        id: 'k',
        center: FreePoint(id: 'c', position: Vec2.zero),
        start: FreePoint(id: 's', position: const Vec2(2, 0)),
        end: StubProjectivePoint(ProjPoint.real(1, 1, 0), id: 'e'),
      );
      expect(sector.conic, isNotNull);
      expect(sector.conic!.toCircleEq()!.radius, closeTo(2, 1e-9));
      expect(sector.isDefined, isFalse);
      expect(sector.circle, isNull);
    });

    test('an end coincident with the center is the wedge\'s degeneracy, not '
        'the carrier\'s (Phase 136c)', () {
      // `end` fixes only the end angle, so it was never in the carrier —
      // but it does collapse the angle, so the wedge stays undefined and
      // `isDefined` reads exactly as it did before the split.
      final sector = Sector(
        id: 'k',
        center: FreePoint(id: 'c', position: const Vec2(1, 1)),
        start: FreePoint(id: 's', position: const Vec2(3, 1)),
        end: FreePoint(id: 'e', position: const Vec2(1 + 1e-12, 1)),
      );
      expect(sector.isDefined, isFalse);
      expect(sector.circle, isNull);
      expect(sector.sweep, isNull);
      expect(sector.conic, isNotNull);
      expect(sector.conic!.toCircleEq()!.radius, closeTo(2, 1e-9));
    });

    test('a complex start hides the carrier from static intersection '
        '(Phase 136c)', () {
      // The other half of the split, as in `Segment`: the carrier exists
      // for a pass that asked for it, and `intersectionCandidates`
      // refuses complex carriers on its own (the Phase 110 realness
      // gate), so no static answer anywhere moves.
      final sector = Sector(
        id: 'k',
        center: FreePoint(id: 'c', position: Vec2.zero),
        start: StubProjectivePoint(
          ProjPoint(const Complex(2, 0.5), const Complex(0, 0), Complex.one),
          id: 's',
        ),
        end: FreePoint(id: 'e', position: const Vec2(0, 5)),
      );
      expect(sector.conic, isNotNull);
      expect(sector.conic!.isReal(), isFalse);
      expect(sector.isDefined, isFalse);
      expect(sector.circle, isNull);
    });

    test('a start within relative tolerance of the center is undefined '
        '(V2: closeTo replaces exact equality)', () {
      final sector = Sector(
        id: 'k',
        center: FreePoint(id: 'c', position: const Vec2(1, 1)),
        start: FreePoint(id: 's', position: const Vec2(1 + 1e-12, 1)),
        end: FreePoint(id: 'e', position: const Vec2(3, 1)),
      );
      expect(sector.isDefined, isFalse);
      expect(sector.conic, isNull);
    });
  });
}
