import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/proj_transform.dart';

import 'generators.dart';

/// Affine agreement up to a relative tolerance — mapped coordinates reach
/// ~1e6 with the grid generators, where `Vec2.closeTo`'s absolute default
/// is meaninglessly tight.
void expectVecClose(Vec2? got, Vec2 expected) {
  expect(got, isNotNull);
  final tol = 1e-8 * (1 + expected.norm + got!.norm);
  expect(
    got.distanceTo(expected),
    lessThanOrEqualTo(tol),
    reason: 'expected $expected, got $got',
  );
}

void main() {
  group('identity', () {
    Glados(any.projPoint).test('fixes every point', (p) {
      expect(ProjTransform.identity.apply(p).closeTo(p), isTrue);
    });

    Glados(any.projLine).test('fixes every line', (l) {
      expect(ProjTransform.identity.applyToLine(l).closeTo(l), isTrue);
    });

    test('fixes a conic', () {
      final a = ConicMatrix.lift(CircleEq(const Vec2(3, -2), 1.5));
      expect(ProjTransform.identity.applyToConic(a).closeTo(a), isTrue);
    });
  });

  group('Euclidean constructors (affine agreement)', () {
    Glados2(any.vec2, any.vec2).test('translation moves by the delta', (p, t) {
      final m = ProjTransform.translation(t.x, t.y);
      expectVecClose(m.apply(ProjPoint.lift(p)).toVec2(), p + t);
    });

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'translationTaking agrees with the affine delta',
      (p, from, to) {
        final m = ProjTransform.translationTaking(
          ProjPoint.lift(from),
          ProjPoint.lift(to),
        );
        expectVecClose(m.apply(ProjPoint.lift(p)).toVec2(), p + (to - from));
      },
    );

    test('translationTaking with an endpoint at infinity is singular and '
        'sends finite points to infinity', () {
      final m = ProjTransform.translationTaking(
        ProjPoint.real(1, 2),
        ProjPoint.real(3, 4, 0),
      );
      expect(m.det.abs, lessThanOrEqualTo(1e-15));
      final image = m.apply(ProjPoint.real(5, 6));
      expect(image.isZero, isFalse);
      expect(image.isFinite(), isFalse);
    });

    Glados3(any.vec2, any.vec2, any.component).test(
      'rotation agrees with the affine formula',
      (p, c, a) {
        final angle = a / 300;
        final m = ProjTransform.rotation(ProjPoint.lift(c), angle);
        expectVecClose(
          m.apply(ProjPoint.lift(p)).toVec2(),
          c + (p - c).rotated(angle),
        );
      },
    );

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'reflection agrees with LineEq.reflect',
      (v, p, q) {
        if (p.closeTo(q, 1e-3)) {
          return;
        }
        final line = LineEq.throughPoints(p, q);
        final m = ProjTransform.reflection(ProjLine.lift(line));
        expectVecClose(m.apply(ProjPoint.lift(v)).toVec2(), line.reflect(v));
      },
    );

    Glados2(any.vec2, any.vec2).test(
      'point reflection: the center is the midpoint',
      (p, c) {
        final m = ProjTransform.pointReflection(ProjPoint.lift(c));
        final image = m.apply(ProjPoint.lift(p)).toVec2();
        expectVecClose(image, c * 2 - p);
      },
    );

    Glados3(any.vec2, any.vec2, any.component).test(
      'homothety agrees with the affine formula',
      (p, c, r) {
        final ratio = r.abs() >= 0.5 ? r : r + 1;
        final m = ProjTransform.homothety(ProjPoint.lift(c), ratio);
        expectVecClose(m.apply(ProjPoint.lift(p)).toVec2(), c.lerp(p, ratio));
      },
    );

    Glados(any.vec2)
        .test('homothety fixes its center; ratio 1 is identity', (c) {
          final center = ProjPoint.lift(c);
          expect(
            ProjTransform.homothety(center, 7.5).apply(center).closeTo(center),
            isTrue,
          );
          expect(
            ProjTransform.homothety(center, 1).closeTo(ProjTransform.identity),
            isTrue,
          );
        });
  });

  group('composition and adjugate', () {
    Glados3(any.similarity, any.similarity, any.projPoint).test(
      'compose applies the right factor first',
      (m, n, p) {
        final composed = m.compose(n).apply(p);
        final stepwise = m.apply(n.apply(p));
        if (composed.isZero || stepwise.isZero) {
          return;
        }
        expect(composed.closeTo(stepwise), isTrue);
      },
    );

    Glados(any.similarity)
        .test('a similarity composed with its adjugate is the identity', (m) {
          expect(m.compose(m.adjugate).closeTo(ProjTransform.identity), isTrue);
          expect(m.adjugate.compose(m).closeTo(ProjTransform.identity), isTrue);
        });

    Glados2(any.similarity, any.projPoint).test('adjugate round-trips points', (
      m,
      p,
    ) {
      expect(m.adjugate.apply(m.apply(p)).closeTo(p), isTrue);
    });

    Glados2(any.projTransform, any.projPoint).test(
      'general invertible transforms round-trip points',
      (m, p) {
        final f2 = m.norm2;
        // Skip near-singular matrices: |det| ≤ 1e-3·‖M‖³.
        if (m.det.abs2 <= 1e-6 * f2 * f2 * f2) {
          return;
        }
        expect(m.adjugate.apply(m.apply(p)).closeTo(p, 1e-6), isTrue);
      },
    );
  });

  group('covariance (points, lines, conics transform together)', () {
    Glados3(any.projTransform, any.projPoint, any.projPoint).test(
      'the join of images is the image of the join',
      (m, p, q) {
        final line = p.join(q);
        final imageJoin = m.apply(p).join(m.apply(q));
        final imageLine = m.applyToLine(line);
        if (line.isZero || imageJoin.isZero || imageLine.isZero) {
          return;
        }
        expect(imageLine.closeTo(imageJoin, 1e-6), isTrue);
      },
    );

    Glados2(any.similarity, any.vec2).test(
      'intersection points of a line and a circle map onto the '
      'image conic and image line',
      (m, c) {
        final conic = ConicMatrix.lift(CircleEq(c, 2.5));
        final line = ProjLine.lift(
          LineEq.throughPoints(c + const Vec2(-3, 0.5), c + const Vec2(4, 1)),
        );
        final imageConic = m.applyToConic(conic);
        final imageLine = m.applyToLine(line);
        for (final p in intersectLineConic(line, conic)) {
          final image = m.apply(p);
          expect(imageConic.containsPoint(image, 1e-6), isTrue);
          expect(image.isIncidentTo(imageLine, 1e-6), isTrue);
        }
      },
    );

    Glados2(any.similarity, any.projPoint).test(
      'evaluate scales by det² under the congruence',
      (m, p) {
        final a = ConicMatrix.lift(CircleEq(const Vec2(1, -2), 1.5));
        final lhs = m.applyToConic(a).evaluate(m.apply(p));
        final d = m.det;
        final rhs = d * d * a.evaluate(p);
        final scale = 1 + lhs.abs + rhs.abs;
        expect((lhs - rhs).abs, lessThanOrEqualTo(1e-7 * scale));
      },
    );

    test('rigid motions carry a circle to the expected circle', () {
      final circle = CircleEq(const Vec2(2, 1), 1.5);
      final m = ProjTransform.translation(
        3,
        -4,
      ).compose(ProjTransform.rotation(ProjPoint.real(0.5, 0.25), 1.2));
      final expectedCenter =
          const Vec2(0.5, 0.25) +
          (circle.center - const Vec2(0.5, 0.25)).rotated(1.2) +
          const Vec2(3, -4);
      final image = m.applyToConic(ConicMatrix.lift(circle)).toCircleEq();
      expect(image, isNotNull);
      expect(image!.center.closeTo(expectedCenter, 1e-9), isTrue);
      expect(image.radius, closeTo(circle.radius, 1e-9));
    });

    test('a homothety scales the radius by |ratio|', () {
      final circle = CircleEq(const Vec2(2, 1), 1.5);
      final m = ProjTransform.homothety(ProjPoint.real(-1, 4), -3);
      final image = m.applyToConic(ConicMatrix.lift(circle)).toCircleEq();
      expect(image, isNotNull);
      expect(image!.radius, closeTo(4.5, 1e-9));
      expect(image.center.closeTo(const Vec2(-10, 13)), isTrue);
    });
  });

  group('the circular points under Euclidean maps', () {
    Glados(any.similarity)
        .test('direct similarities fix I and J individually', (m) {
          expect(m.apply(circularPointI).closeTo(circularPointI), isTrue);
          expect(m.apply(circularPointJ).closeTo(circularPointJ), isTrue);
        });

    Glados2(any.vec2, any.vec2).test('reflections swap I and J', (p, q) {
      if (p.closeTo(q, 1e-3)) {
        return;
      }
      final m = ProjTransform.reflection(
        ProjLine.lift(LineEq.throughPoints(p, q)),
      );
      expect(m.apply(circularPointI).closeTo(circularPointJ), isTrue);
      expect(m.apply(circularPointJ).closeTo(circularPointI), isTrue);
    });
  });

  group('rescaling invariance', () {
    Glados3(any.projTransform, any.projPoint, any.nonZeroComplex).test(
      'a rescaled matrix is the same map',
      (m, p, k) {
        final scaled = m.scaledBy(k);
        expect(scaled.closeTo(m), isTrue);
        final image = m.apply(p);
        if (!image.isZero) {
          expect(scaled.apply(p).closeTo(image), isTrue);
        }
      },
    );

    Glados2(any.similarity, any.nonZeroComplex).test(
      'line and conic images are rescaling-invariant',
      (m, k) {
        final scaled = m.scaledBy(k);
        final l = ProjLine.real(2, -1, 3);
        expect(scaled.applyToLine(l).closeTo(m.applyToLine(l)), isTrue);
        final a = ConicMatrix.lift(CircleEq(const Vec2(3, -2), 1.5));
        expect(scaled.applyToConic(a).closeTo(m.applyToConic(a)), isTrue);
      },
    );

    Glados2(any.similarity, any.nonZeroComplex).test(
      'isReal is invariant under complex rescaling',
      (m, k) {
        expect(m.isReal(), isTrue);
        expect(m.scaledBy(k).isReal(), isTrue);
      },
    );
  });

  group('degenerate inputs propagate', () {
    const zero = ProjTransform(
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
      Complex.zero,
    );

    test('the zero matrix is no map', () {
      expect(zero.isZero, isTrue);
      expect(zero.isReal(), isFalse);
      expect(zero.closeTo(zero), isFalse);
      expect(zero.apply(ProjPoint.real(1, 2)).isZero, isTrue);
      expect(zero.applyToLine(ProjLine.real(1, 2, 3)).isZero, isTrue);
    });

    test('rotation about a point at infinity is singular and sends finite '
        'points to infinity', () {
      final m = ProjTransform.rotation(ProjPoint.real(1, 2, 0), 1);
      expect(m.det.abs, lessThanOrEqualTo(1e-15));
      final image = m.apply(ProjPoint.real(3, 4));
      expect(image.isZero, isFalse);
      expect(image.isFinite(), isFalse);
    });

    test('reflection across the line at infinity is the zero matrix', () {
      expect(ProjTransform.reflection(ProjLine.infinity).isZero, isTrue);
    });

    test('reflection across an isotropic axis is singular', () {
      // A line through I: coefficients [1, i, 0] have a² + b² = 0.
      final m = ProjTransform.reflection(
        const ProjLine(Complex.one, Complex.i, Complex.zero),
      );
      expect(m.isZero, isFalse);
      expect(m.det.abs, lessThanOrEqualTo(1e-15));
    });

    test('a homothety of ratio 0 maps everything to its center', () {
      final m = ProjTransform.homothety(ProjPoint.real(2, -1), 0);
      expect(
        m.apply(ProjPoint.real(5, 7)).closeTo(ProjPoint.real(2, -1)),
        isTrue,
      );
      expect(m.det.abs, lessThanOrEqualTo(1e-15));
    });
  });
}
