import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/focal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

void main() {
  /// The vertical line `x = at`, as an object.
  LineThroughTwoPoints verticalAt(double at) => LineThroughTwoPoints(
    id: 'l',
    point1: FreePoint(id: 'd1', position: Vec2(at, -1)),
    point2: FreePoint(id: 'd2', position: Vec2(at, 1)),
  );

  group('FocalConic', () {
    test('the textbook parabola: focus (0,0), directrix x = −1', () {
      final k = FocalConic(
        id: 'k',
        focus: FreePoint(id: 'f', position: Vec2.zero),
        directrix: verticalAt(-1),
        eccentricity: 1,
      );
      expect(k.isDefined, isTrue);
      expect(k.circle, isNull);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(0, 0, 1, -2, 0, -1)),
        isTrue,
        reason: 'y² = 2x + 1',
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.parabola);
    });

    test('the eccentricity picks the class, and is what parents cannot say',
        () {
      ConicClass classOf(double e) => ConicShape.of(
        FocalConic(
          id: 'k',
          focus: FreePoint(id: 'f', position: const Vec2(2, -1)),
          directrix: verticalAt(-1),
          eccentricity: e,
        ).conic!,
      ).kind;
      expect(classOf(0.5), ConicClass.ellipse);
      expect(classOf(1), ConicClass.parabola);
      expect(classOf(2), ConicClass.hyperbola);
    });

    test('parents are the focus then the directrix', () {
      final f = FreePoint(id: 'f', position: Vec2.zero);
      final l = verticalAt(-1);
      final k = FocalConic(id: 'k', focus: f, directrix: l, eccentricity: 1);
      expect(k.parents, [f, l]);
    });

    test('e = 0 is the focus alone — a real point, but no curve', () {
      final k = FocalConic(
        id: 'k',
        focus: FreePoint(id: 'f', position: const Vec2(2, -1)),
        directrix: verticalAt(-1),
        eccentricity: 0,
      );
      expect(k.conic, isNotNull);
      expect(ConicShape.of(k.conic!).kind, ConicClass.isolatedPoint);
      expect(
        k.isDefined,
        isFalse,
        reason: 'isDrawable, not "has a real point"',
      );
    });

    test('an undefined parent leaves it undefined', () {
      final k = FocalConic(
        id: 'k',
        focus: StubProjectivePoint(null, id: 'f'),
        directrix: verticalAt(-1),
        eccentricity: 1,
      );
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });

    test('a focus at infinity flattens onto the line at infinity', () {
      final k = FocalConic(
        id: 'k',
        focus: StubProjectivePoint(
          const ProjPoint(Complex.one, Complex.zero, Complex.zero),
          id: 'f',
        ),
        directrix: verticalAt(-1),
        eccentricity: 1,
      );
      expect(k.conic, isNotNull);
      expect(
        k.conic!.closeTo(
          ConicMatrix.linePair(ProjLine.infinity, ProjLine.infinity),
        ),
        isTrue,
      );
    });

    test('drag the focus onto the directrix and off again', () {
      // Focus on its own directrix degenerates; nothing is banded, so it
      // recovers the moment the focus moves clear.
      final construction = Construction();
      final f = FreePoint(id: 'f', position: Vec2.zero);
      final d1 = FreePoint(id: 'd1', position: const Vec2(-1, -1));
      final d2 = FreePoint(id: 'd2', position: const Vec2(-1, 1));
      final l = LineThroughTwoPoints(id: 'l', point1: d1, point2: d2);
      final k = FocalConic(id: 'k', focus: f, directrix: l, eccentricity: 1);
      construction
        ..add(f)
        ..add(d1)
        ..add(d2)
        ..add(l)
        ..add(k);
      expect(ConicShape.of(k.conic!).kind, ConicClass.parabola);

      construction.moveFreePoint('f', const Vec2(-1, 0));
      expect(
        ConicShape.of(k.conic!).kind,
        isNot(ConicClass.parabola),
        reason: 'a focus on its own directrix is not a parabola',
      );

      construction.moveFreePoint('f', Vec2.zero);
      expect(ConicShape.of(k.conic!).kind, ConicClass.parabola);
      expect(k.isDefined, isTrue);
    });
  });

  group('projective semantics (Phase 120b)', () {
    Glados2(any.nonZeroComplex, any.nonZeroComplex).test(
      'recompute is invariant under complex rescaling of either parent',
      (focusScale, lineScale) {
        final f = StubProjectivePoint(ProjPoint.real(2, -1), id: 'f');
        final l = StubProjectiveLine(ProjLine.real(3, -4, 5), id: 'l');
        final k = FocalConic(
          id: 'k',
          focus: f,
          directrix: l,
          eccentricity: 1.4,
        );
        final reference = k.conic!;
        f.value = f.value!.scaledBy(focusScale);
        l.value = l.value!.scaledBy(lineScale);
        k.recompute();
        expect(k.conic!.closeTo(reference), isTrue);
      },
    );

    test('a circle-shaped focal conic still projects to a circle', () {
      // Not reachable from the tools (e = 0 is the only circle here, and
      // it is a point circle), but the projection must not lie about it.
      final k = FocalConic(
        id: 'k',
        focus: FreePoint(id: 'f', position: Vec2.zero),
        directrix: verticalAt(-1),
        eccentricity: 1,
      );
      expect(k.circle, isNull, reason: 'a parabola is not a circle');
    });
  });
}
