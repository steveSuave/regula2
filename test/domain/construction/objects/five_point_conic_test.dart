import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/proj_transform.dart';

import '../../../projective_stubs.dart';
import '../../projective/generators.dart';

/// The five parents as free points at [positions].
FivePointConic conicThrough(List<Vec2> positions, {String id = 'k'}) =>
    FivePointConic(
      id: id,
      points: [
        for (final (i, p) in positions.indexed)
          FreePoint(id: 'p$i', position: p),
      ],
    );

/// The five parents as projective stubs — for parents at infinity or with
/// complex coordinates, which no free point can hold.
FivePointConic conicThroughProjective(List<ProjPoint> points) => FivePointConic(
  id: 'k',
  points: [
    for (final (i, p) in points.indexed) StubProjectivePoint(p, id: 'p$i'),
  ],
);

void main() {
  group('FivePointConic', () {
    test('five points of a circle give back that circle', () {
      const centre = Vec2(2, 1);
      const radius = 5.0;
      final k = conicThrough([
        for (var i = 0; i < 5; i++)
          centre + Vec2(radius * math.cos(i * 1.1), radius * math.sin(i * 1.1)),
      ]);
      expect(k.isDefined, isTrue);
      expect(k.circle!.center.closeTo(centre), isTrue);
      expect(k.circle!.radius, closeTo(radius, 1e-9));
      // A circle-shaped conic still projects, so the painter and the
      // hit-tester take their circle arm — nothing special-cases it.
      expect(ConicShape.of(k.conic!).kind, ConicClass.ellipse);
    });

    test('an ellipse: through its parents, and classified as one', () {
      final points = [
        for (final t in const [0.0, 1.0, 2.0, 3.0, 4.0])
          Vec2(2 * math.cos(t), math.sin(t)),
      ];
      final k = conicThrough(points);
      expect(k.isDefined, isTrue);
      expect(k.circle, isNull, reason: 'a genuine ellipse is not a circle');
      expect(ConicShape.of(k.conic!).kind, ConicClass.ellipse);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(0.25, 0, 1, 0, 0, -1)),
        isTrue,
      );
      for (final p in points) {
        expect(k.conic!.containsPoint(ProjPoint.lift(p)), isTrue);
      }
    });

    test('a parabola: y = x² through five of its points', () {
      final points = [
        for (final t in const [-2.0, -1.0, 0.0, 1.0, 2.0]) Vec2(t, t * t),
      ];
      final k = conicThrough(points);
      expect(k.isDefined, isTrue);
      expect(ConicShape.of(k.conic!).kind, ConicClass.parabola);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(1, 0, 0, 0, -1, 0)),
        isTrue,
      );
    });

    test('a hyperbola: xy = 1 through five of its points', () {
      final points = [
        for (final t in const [-2.0, -1.0, 1.0, 2.0, 3.0]) Vec2(t, 1 / t),
      ];
      final k = conicThrough(points);
      expect(k.isDefined, isTrue);
      expect(ConicShape.of(k.conic!).kind, ConicClass.hyperbola);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(0, 1, 0, 0, 0, -1)),
        isTrue,
      );
    });

    test('parents are the five points, in order', () {
      final k = conicThrough(const [
        Vec2(1, 0),
        Vec2(0, 1),
        Vec2(-1, 0),
        Vec2(0, -1),
        Vec2(0.6, 0.8),
      ]);
      expect(k.parents.map((p) => p.id), ['p0', 'p1', 'p2', 'p3', 'p4']);
    });

    test('exactly five points, enforced at construction', () {
      List<GeoPoint> free(int n) => [
        for (var i = 0; i < n; i++)
          FreePoint(id: 'p$i', position: Vec2(i.toDouble(), 0)),
      ];
      expect(
        () => FivePointConic(id: 'k', points: free(4)),
        throwsArgumentError,
      );
      expect(
        () => FivePointConic(id: 'k', points: free(6)),
        throwsArgumentError,
      );
    });

    test('coincident parents leave a pencil, so undefined', () {
      final k = conicThrough(const [
        Vec2(1, 0),
        Vec2(0, 1),
        Vec2(-1, 0),
        Vec2(0, -1),
        Vec2(1, 0),
      ]);
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
      expect(k.circle, isNull);
    });

    test('an undefined parent leaves it undefined', () {
      final k = FivePointConic(
        id: 'k',
        points: [
          StubProjectivePoint(ProjPoint.real(1, 0), id: 'p0'),
          StubProjectivePoint(ProjPoint.real(0, 1), id: 'p1'),
          StubProjectivePoint(ProjPoint.real(-1, 0), id: 'p2'),
          StubProjectivePoint(ProjPoint.real(0, -1), id: 'p3'),
          StubProjectivePoint(null, id: 'p4'),
        ],
      );
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });

    test('four collinear points determine no conic', () {
      final k = conicThrough(const [
        Vec2(0, 0),
        Vec2(1, 1),
        Vec2(2, 2),
        Vec2(3, 3),
        Vec2(0, 5),
      ]);
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });

    test('five collinear points determine no conic', () {
      final k = conicThrough(const [
        Vec2(0, 0),
        Vec2(1, 1),
        Vec2(2, 2),
        Vec2(3, 3),
        Vec2(4, 4),
      ]);
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);
    });

    test('three on one line and two on another: the line pair, drawable', () {
      // A conic meets a line in two points unless it contains it, so a
      // three-plus-two set still determines exactly one conic — and it is
      // degenerate. Ink, therefore defined.
      final k = conicThrough(const [
        Vec2(0, 0),
        Vec2(1, 0),
        Vec2(2, 0),
        Vec2(0, 1),
        Vec2(1, 2),
      ]);
      expect(k.isDefined, isTrue);
      expect(k.circle, isNull);
      expect(ConicShape.of(k.conic!).kind, ConicClass.linePair);
      final expected = ConicMatrix.linePair(
        ProjLine.lift(LineEq.throughPoints(Vec2.zero, const Vec2(2, 0))),
        ProjLine.lift(LineEq.throughPoints(const Vec2(0, 1), const Vec2(1, 2))),
      );
      expect(k.conic!.closeTo(expected), isTrue);
    });

    test('drag through coincidence: undefined, then recovers', () {
      final construction = Construction();
      final positions = const [
        Vec2(1, 0),
        Vec2(0, 1),
        Vec2(-1, 0),
        Vec2(0, -1),
        Vec2(0.6, 0.8),
      ];
      final points = [
        for (final (i, p) in positions.indexed)
          FreePoint(id: 'p$i', position: p),
      ];
      final k = FivePointConic(id: 'k', points: points);
      for (final p in points) {
        construction.add(p);
      }
      construction.add(k);

      construction.moveFreePoint('p4', const Vec2(1, 0));
      expect(k.isDefined, isFalse);
      expect(k.conic, isNull);

      construction.moveFreePoint('p4', const Vec2(0.6, 0.8));
      expect(k.isDefined, isTrue);
      expect(k.circle!.center.closeTo(Vec2.zero), isTrue);
      expect(k.circle!.radius, closeTo(1, 1e-9));
    });
  });

  group('projective semantics (Phase 120)', () {
    test('points at infinity are ordinary parents', () {
      // The two asymptotic directions of xy = 1, plus three of its finite
      // points, determine it exactly.
      final k = conicThroughProjective([
        ProjPoint.real(1, 1),
        ProjPoint.real(2, 0.5),
        ProjPoint.real(-1, -1),
        const ProjPoint(Complex.one, Complex.zero, Complex.zero),
        const ProjPoint(Complex.zero, Complex.one, Complex.zero),
      ]);
      expect(k.isDefined, isTrue);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(0, 1, 0, 0, 0, -1)),
        isTrue,
      );
    });

    test('an isolated point has a real point but no curve, so no ink', () {
      // Three points on y = ix and two on y = −ix: the conic is the
      // conjugate line pair x² + y² = 0, whose only real point is the
      // origin. `isDrawable` is false — a conic's ink is its curve.
      const i = Complex.i;
      final k = conicThroughProjective([
        for (final t in const [1.0, 2.0, 3.0])
          ProjPoint(Complex(t), i.scale(t), Complex.one),
        for (final t in const [1.0, 2.0])
          ProjPoint(Complex(t), i.scale(-t), Complex.one),
      ]);
      expect(k.conic, isNotNull);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(1, 0, 1, 0, 0, 0)),
        isTrue,
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.isolatedPoint);
      expect(k.isDefined, isFalse);
    });

    test('an imaginary ellipse has no real point at all, so no ink', () {
      // Five points of x² + y² + 1 = 0, which no real point satisfies.
      const i = Complex.i;
      final k = conicThroughProjective([
        ProjPoint(Complex.zero, i, Complex.one),
        ProjPoint(Complex.zero, -i, Complex.one),
        ProjPoint(Complex.one, i.scale(math.sqrt2), Complex.one),
        ProjPoint(Complex.one, i.scale(-math.sqrt2), Complex.one),
        ProjPoint(const Complex(2), i.scale(math.sqrt(5)), Complex.one),
      ]);
      expect(k.conic, isNotNull);
      expect(
        k.conic!.closeTo(ConicMatrix.coefficients(1, 0, 1, 0, 0, 1)),
        isTrue,
      );
      expect(ConicShape.of(k.conic!).kind, ConicClass.empty);
      expect(k.isDefined, isFalse);
    });

    Glados(
      any.combine5(
        any.nonZeroComplex,
        any.nonZeroComplex,
        any.nonZeroComplex,
        any.nonZeroComplex,
        any.nonZeroComplex,
        (Complex a, Complex b, Complex c, Complex d, Complex e) => [
          a,
          b,
          c,
          d,
          e,
        ],
      ),
    ).test('recompute is invariant under complex rescaling of parents', (
      scalars,
    ) {
      final stubs = [
        for (final (i, p) in const [
          Vec2(1, 0),
          Vec2(0, 1),
          Vec2(-1, 0),
          Vec2(0, -1),
          Vec2(0.6, 0.8),
        ].indexed)
          StubProjectivePoint(ProjPoint.lift(p), id: 'p$i'),
      ];
      final k = FivePointConic(id: 'k', points: stubs);
      final reference = k.conic!;
      for (final (i, s) in scalars.indexed) {
        stubs[i].value = stubs[i].value!.scaledBy(s);
      }
      k.recompute();
      expect(k.conic!.closeTo(reference), isTrue);
      expect(k.circle!.center.closeTo(Vec2.zero, 1e-9), isTrue);
      expect(k.circle!.radius, closeTo(1, 1e-9));
    });

    // A similarity with bounded translation and a ratio bounded away from
    // zero: always invertible, and never so far from the origin that the
    // reconstruction is asking the representation for digits it does not
    // have (the |centre| ≈ 1/√eps wall pinned in Phase 119).
    final similarities = any.combine4(
      any.component.map((c) => c / 10),
      any.component.map((c) => c / 10),
      any.component,
      any.component.map((c) => c / 500),
      (double tx, double ty, double angle, double ratio) =>
          ProjTransform.translation(tx, ty)
              .compose(
                ProjTransform.rotation(ProjPoint.real(0, 0), angle / 300),
              )
              .compose(
                ProjTransform.homothety(
                  ProjPoint.real(0, 0),
                  ratio.abs() >= 0.2 ? ratio : ratio + 0.5,
                ),
              ),
    );

    Glados2(similarities, any.intInRange(0, 3)).test(
      'five points of a conic reconstruct it, in every class',
      (transform, which) {
        final (base, samples) = switch (which) {
          0 => (
            ConicMatrix.coefficients(0.25, 0, 1, 0, 0, -1),
            [
              for (final t in const [0.0, 1.0, 2.0, 3.0, 4.0])
                Vec2(2 * math.cos(t), math.sin(t)),
            ],
          ),
          1 => (
            ConicMatrix.coefficients(1, 0, 0, 0, -1, 0),
            [
              for (final t in const [-2.0, -1.0, 0.0, 1.0, 2.0]) Vec2(t, t * t),
            ],
          ),
          _ => (
            ConicMatrix.coefficients(0, 1, 0, 0, 0, -1),
            [
              for (final t in const [-2.0, -1.0, 1.0, 2.0, 3.0]) Vec2(t, 1 / t),
            ],
          ),
        };
        final k = conicThroughProjective([
          for (final p in samples) transform.apply(ProjPoint.lift(p)),
        ]);
        expect(k.isDefined, isTrue);
        expect(k.conic!.closeTo(transform.applyToConic(base), 1e-6), isTrue);
        // A similarity fixes the line at infinity, so it fixes the class —
        // for the two *open* classes. A parabola is the measure-zero wall
        // between them: its doubled meet with ℓ∞ is only √eps-accurate, so a
        // reconstructed one reads as whichever side the rounding lands on.
        // Harmless, because `kind` labels the curve and never selects a code
        // path (PLAN §119: a parabola's arm is not a case, it is the arc
        // between the parameters where the curve passes through infinity).
        expect(
          ConicShape.of(k.conic!).kind,
          which == 1
              ? isIn(const [
                  ConicClass.parabola,
                  ConicClass.ellipse,
                  ConicClass.hyperbola,
                ])
              : ConicShape.of(base).kind,
        );
      },
    );
  });
}
