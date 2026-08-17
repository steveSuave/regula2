import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  BifocalConic conicOf(Vec2 a, Vec2 b, Vec2 p, {required bool difference}) =>
      BifocalConic(
        id: 'k',
        focus1: FreePoint(id: 'f1', position: a),
        focus2: FreePoint(id: 'f2', position: b),
        point: FreePoint(id: 'p', position: p),
        difference: difference,
      );

  group('BifocalConic', () {
    test('the textbook ellipse: foci (±3, 0) through (5, 0)', () {
      final k = conicOf(
        const Vec2(-3, 0),
        const Vec2(3, 0),
        const Vec2(5, 0),
        difference: false,
      );
      expect(k.isDefined, isTrue);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(1 / 25, 0, 1 / 16, 0, 0, -1)),
        isTrue,
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.ellipse);
      expect(k.circle, isNull, reason: 'a genuine ellipse is not a circle');
    });

    test('the textbook hyperbola: foci (±5, 0) through (3, 0)', () {
      final k = conicOf(
        const Vec2(-5, 0),
        const Vec2(5, 0),
        const Vec2(3, 0),
        difference: true,
      );
      expect(k.isDefined, isTrue);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(1 / 9, 0, -1 / 16, 0, 0, -1)),
        isTrue,
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.hyperbola);
    });

    test('both branches pass through the point that defined them', () {
      const p = Vec2(1, 4);
      for (final difference in const [false, true]) {
        final k = conicOf(
          const Vec2(-3, 0),
          const Vec2(3, 0),
          p,
          difference: difference,
        );
        expect(
          ConicShape.of(k.conic!).distanceTo(p),
          lessThan(1e-9),
          reason: 'difference: $difference',
        );
      }
    });

    test('parents are the two foci then the point', () {
      final k = conicOf(
        const Vec2(-3, 0),
        const Vec2(3, 0),
        const Vec2(5, 0),
        difference: false,
      );
      expect(k.parents.map((o) => o.id), ['f1', 'f2', 'p']);
    });

    test('coincident foci are refused — the circle is another kind', () {
      final k = conicOf(
        const Vec2(2, 2),
        const Vec2(2, 2),
        const Vec2(5, 0),
        difference: false,
      );
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });

    test('sum branch, point on the segment: the axis doubled, still drawn', () {
      final k = conicOf(
        const Vec2(-3, 0),
        const Vec2(3, 0),
        const Vec2(1, 0),
        difference: false,
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.doubleLine);
      expect(
        ConicShape.of(k.conic!).lines.single.closeTo(ProjLine.real(0, 1, 0)),
        isTrue,
      );
      expect(k.isDefined, isTrue, reason: 'a doubled line is still ink');
    });

    test('difference branch, equidistant point: the bisector doubled', () {
      final k = conicOf(
        const Vec2(-3, 0),
        const Vec2(3, 0),
        const Vec2(0, 4),
        difference: true,
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.doubleLine);
      expect(
        ConicShape.of(k.conic!).lines.single.closeTo(ProjLine.real(1, 0, 0)),
        isTrue,
        reason: '|XF₁| = |XF₂| *is* the perpendicular bisector',
      );
    });

    test('drag through coincident foci: undefined, then recovers', () {
      final construction = Construction();
      final f1 = FreePoint(id: 'f1', position: const Vec2(-3, 0));
      final f2 = FreePoint(id: 'f2', position: const Vec2(3, 0));
      final p = FreePoint(id: 'p', position: const Vec2(5, 0));
      final k = BifocalConic(
        id: 'k',
        focus1: f1,
        focus2: f2,
        point: p,
        difference: false,
      );
      construction
        ..add(f1)
        ..add(f2)
        ..add(p)
        ..add(k);

      construction.moveFreePoint('f2', const Vec2(-3, 0));
      expect(k.isDefined, isFalse);

      construction.moveFreePoint('f2', const Vec2(3, 0));
      expect(k.isDefined, isTrue);
      expect(ConicShape.of(k.conic!).kind, ConicClass.ellipse);
    });

    test('an undefined parent leaves it undefined', () {
      final k = BifocalConic(
        id: 'k',
        focus1: StubProjectivePoint(ProjPoint.real(-3, 0), id: 'f1'),
        focus2: StubProjectivePoint(ProjPoint.real(3, 0), id: 'f2'),
        point: StubProjectivePoint(null, id: 'p'),
        difference: false,
      );
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });

    test('a parent at infinity has no chart point, so no conic', () {
      // The metric boundary's realness gate: the semi-axis is a distance,
      // and a point at infinity has none.
      final k = BifocalConic(
        id: 'k',
        focus1: StubProjectivePoint(ProjPoint.real(-3, 0), id: 'f1'),
        focus2: StubProjectivePoint(ProjPoint.real(3, 0), id: 'f2'),
        point: StubProjectivePoint(
          const ProjPoint(Complex.one, Complex.zero, Complex.zero),
          id: 'p',
        ),
        difference: false,
      );
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });
  });

  group('projective semantics (Phase 120b)', () {
    Glados3(any.nonZeroComplex, any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of the parents',
      (s1, s2, s3) {
        final f1 = StubProjectivePoint(ProjPoint.real(-3, 0), id: 'f1');
        final f2 = StubProjectivePoint(ProjPoint.real(3, 0), id: 'f2');
        final p = StubProjectivePoint(ProjPoint.real(1, 4), id: 'p');
        final k = BifocalConic(
          id: 'k',
          focus1: f1,
          focus2: f2,
          point: p,
          difference: false,
        );
        final reference = k.conic!;
        f1.value = f1.value!.scaledBy(s1);
        f2.value = f2.value!.scaledBy(s2);
        p.value = p.value!.scaledBy(s3);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
      },
    );

    Glados(any.vec2).test(
      'the defining sum or difference holds all the way round the curve',
      (raw) {
        const a = Vec2(1, 2);
        const b = Vec2(6, 5);
        final p = raw / 100;
        for (final difference in const [false, true]) {
          final k = conicOf(a, b, p, difference: difference);
          final conic = k.conic;
          if (conic == null) return;
          final shape = ConicShape.of(conic);
          if (shape.kind != ConicClass.ellipse &&
              shape.kind != ConicClass.hyperbola) {
            continue; // a degenerate limit; pinned above
          }
          final target = difference
              ? (p.distanceTo(a) - p.distanceTo(b)).abs()
              : p.distanceTo(a) + p.distanceTo(b);
          for (var i = 0; i < 8; i++) {
            final x = shape.chartPointAt(math.pi * i / 8);
            if (x == null) continue;
            final value = difference
                ? (x.distanceTo(a) - x.distanceTo(b)).abs()
                : x.distanceTo(a) + x.distanceTo(b);
            expect(value, closeTo(target, 1e-6 * (1 + x.norm)));
          }
        }
      },
    );
  });
}
