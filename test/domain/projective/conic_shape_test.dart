import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tolerances.dart';

/// `a·x² + b·xy + c·y² + d·x + e·y + f = 0`.
ConicMatrix conic(
  double a,
  double b,
  double c,
  double d,
  double e,
  double f,
) => ConicMatrix.coefficients(a, b, c, d, e, f);

final unitCircle = conic(1, 0, 1, 0, 0, -1);
final ellipse = conic(1 / 4, 0, 1 / 9, 0, 0, -1); // x²/4 + y²/9 = 1
final parabola = conic(0, 0, 1, -4, 0, 0); // y² = 4x
final hyperbola = conic(1, 0, -1, 0, 0, -1); // x² − y² = 1
final imaginaryEllipse = conic(1, 0, 1, 0, 0, 1); // x² + y² + 1 = 0
final crossingLines = conic(1, 0, -1, 0, 0, 0); // y = ±x
final parallelLines = conic(1, 0, 0, 0, 0, -1); // x = ±1
final originPoint = conic(1, 0, 1, 0, 0, 0); // x² + y² = 0
final doubleLine = conic(1, 0, 0, 0, 0, 0); // x = 0, doubled

/// Cyclic distance between two pencil angles, which live on RP¹.
double angularGap(double a, double b) {
  final d = (a - b).abs() % math.pi;
  return math.min(d, math.pi - d);
}

extension on Any {
  /// A pencil angle on a 0.0001 grid covering `[0, π)`.
  Generator<double> get pencilAngle =>
      intInRange(0, 31415).map((i) => i / 10000);

  /// A nonzero real scale on a 0.01 grid in [-20, 20], never near zero.
  Generator<double> get rescale => intInRange(-2000, 2001).map((i) {
    final k = i / 100;
    return k.abs() >= 0.5 ? k : k + 1;
  });
}

void main() {
  group('ConicShape.of classification', () {
    test('reads the three curve classes off the line at infinity', () {
      expect(ConicShape.of(unitCircle).kind, ConicClass.ellipse);
      expect(ConicShape.of(ellipse).kind, ConicClass.ellipse);
      expect(ConicShape.of(parabola).kind, ConicClass.parabola);
      expect(ConicShape.of(hyperbola).kind, ConicClass.hyperbola);
    });

    test('a rotated parabola is still a parabola', () {
      // y = x² rotated 45°: the axis direction is no longer a coordinate
      // axis, so the tangency at infinity is not read off a single entry.
      const t = math.pi / 4;
      final cos = math.cos(t), sin = math.sin(t);
      // (x cos + y sin)² − 4(−x sin + y cos) = 0.
      final rotated = conic(
        cos * cos,
        2 * cos * sin,
        sin * sin,
        4 * sin,
        -4 * cos,
        0,
      );
      expect(ConicShape.of(rotated).kind, ConicClass.parabola);
    });

    test('an imaginary ellipse is empty, not an ellipse', () {
      final shape = ConicShape.of(imaginaryEllipse);
      expect(shape.kind, ConicClass.empty);
      expect(shape.basePoint, isNull);
      expect(shape.isParameterized, isFalse);
    });

    test('degenerate conics split into their components', () {
      final crossing = ConicShape.of(crossingLines);
      expect(crossing.kind, ConicClass.linePair);
      expect(crossing.lines, hasLength(2));
      expect(crossing.lines.every((l) => l.isReal()), isTrue);
      // The two lines are y = x and y = −x, in some order.
      final directions = crossing.lines
          .map((l) => l.toLineEq()!.direction.y / l.toLineEq()!.direction.x)
          .map((slope) => slope.abs())
          .toList();
      expect(directions, everyElement(closeTo(1, 1e-9)));

      final parallel = ConicShape.of(parallelLines);
      expect(parallel.kind, ConicClass.linePair);
      expect(parallel.lines.every((l) => l.isReal()), isTrue);

      final doubled = ConicShape.of(doubleLine);
      expect(doubled.kind, ConicClass.doubleLine);
      expect(doubled.lines, hasLength(1));
      expect(doubled.lines.single.toLineEq()!.closeTo(ProjLine.real(1, 0, 0).toLineEq()!), isTrue);
    });

    test('conjugate complex components leave one real point', () {
      final shape = ConicShape.of(originPoint);
      expect(shape.kind, ConicClass.isolatedPoint);
      expect(shape.lines.any((l) => l.isReal()), isFalse);
      expect(shape.basePoint!.toVec2()!.closeTo(Vec2.zero, 1e-9), isTrue);
      expect(shape.isParameterized, isFalse);
    });

    test('the zero matrix and complex matrices are no real conic', () {
      const zero = ConicMatrix(
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex.zero,
      );
      expect(ConicShape.of(zero).kind, ConicClass.none);
      const complex = ConicMatrix(
        Complex.one,
        Complex.zero,
        Complex(1, 0.5),
        Complex.zero,
        Complex.zero,
        Complex(-1),
      );
      expect(ConicShape.of(complex).kind, ConicClass.none);
    });

    test('a circle from the kernel constructors classifies as an ellipse', () {
      final lifted = ConicMatrix.lift(CircleEq(Vec2(300, -120), 45));
      expect(ConicShape.of(lifted).kind, ConicClass.ellipse);
    });

    test('balancing carries the class far past the matrix-norm wall', () {
      // Raw `rank` gives up on these — the radius drowns in `ww` (see
      // conic_matrix_test) — and without the change of frame the painter
      // would classify a viewport-sized circle as a double line and draw a
      // straight stroke through it. Locus infinity tails reach these scales
      // deliberately.
      for (final scale in [1e2, 1e4, 1e6, 1e8]) {
        final centre = Vec2(3 * scale, -1.2 * scale);
        final shape = ConicShape.of(
          ConicMatrix.lift(CircleEq(centre, 0.45 * scale)),
        );
        expect(shape.kind, ConicClass.ellipse, reason: 'scale $scale');
        // And the parameterization still lands on the rim.
        for (final phi in [0.0, 0.7, 1.9, 3.0]) {
          final p = shape.chartPointAt(phi)!;
          expect(
            p.distanceTo(centre),
            closeTo(0.45 * scale, 1e-6 * scale),
            reason: 'scale $scale, φ = $phi',
          );
        }
      }
    });

    test('a tiny circle a long way out is still an ellipse', () {
      final shape = ConicShape.of(
        ConicMatrix.lift(CircleEq(Vec2(1e6, 1e6), 1)),
      );
      expect(shape.kind, ConicClass.ellipse);
      expect(
        shape.chartPointAt(0.4)!.distanceTo(Vec2(1e6, 1e6)),
        closeTo(1, 1e-6),
      );
    });

    Glados2(any.rescale, any.rescale).test(
      'classification is invariant under rescaling the matrix',
      (k, l) {
        for (final a in [
          unitCircle,
          parabola,
          hyperbola,
          imaginaryEllipse,
          crossingLines,
          originPoint,
          doubleLine,
        ]) {
          expect(
            ConicShape.of(a.scaledBy(Complex(k, l))).kind,
            ConicShape.of(a).kind,
            reason: 'scaled by ${Complex(k, l)}',
          );
        }
      },
    );
  });

  group('ConicShape parameterization', () {
    final curves = {
      'circle': unitCircle,
      'ellipse': ellipse,
      'parabola': parabola,
      'hyperbola': hyperbola,
    };

    for (final entry in curves.entries) {
      test('${entry.key}: the base point lies on the conic', () {
        final shape = ConicShape.of(entry.value);
        expect(shape.isParameterized, isTrue);
        expect(entry.value.containsPoint(shape.basePoint!), isTrue);
      });

      Glados(any.pencilAngle).test(
        '${entry.key}: pointAt stays on the conic',
        (phi) {
          final shape = ConicShape.of(entry.value);
          final p = shape.pointAt(phi);
          expect(p.isZero, isFalse);
          expect(p.isReal(), isTrue);
          expect(entry.value.containsPoint(p), isTrue, reason: 'φ = $phi');
        },
      );

      Glados(any.pencilAngle).test(
        '${entry.key}: parameterOf inverts pointAt',
        (phi) {
          final shape = ConicShape.of(entry.value);
          final back = shape.parameterOf(shape.pointAt(phi));
          expect(back, isNotNull);
          expect(angularGap(back!, phi), lessThan(1e-6), reason: 'φ = $phi');
        },
      );

      Glados(any.pencilAngle).test('${entry.key}: pointAt is π-periodic', (
        phi,
      ) {
        final shape = ConicShape.of(entry.value);
        expect(
          shape.pointAt(phi).closeTo(shape.pointAt(phi + math.pi), 1e-9),
          isTrue,
          reason: 'φ = $phi',
        );
      });
    }

    test('the parameterization is a bijection onto the whole curve', () {
      // Every point of the unit circle is hit exactly once over [0, π):
      // sweeping φ sweeps the polar angle monotonically through a full turn.
      final shape = ConicShape.of(unitCircle);
      final angles = [
        for (var i = 0; i < 720; i++)
          shape.chartPointAt(math.pi * i / 720)!.angle,
      ];
      final seen = angles.map((a) => (a / (math.pi / 90)).floor()).toSet();
      expect(seen.length, 180, reason: 'every 2° bucket of the turn is hit');
    });

    test('a hyperbola passes through infinity exactly twice', () {
      final shape = ConicShape.of(hyperbola);
      final undefined = <double>[];
      for (var i = 0; i < 20000; i++) {
        final phi = math.pi * i / 20000;
        if (!shape.pointAt(phi).isFinite()) undefined.add(phi);
      }
      // Sampling cannot land on the two exact parameters, but the near-
      // infinite stretches around them are two separated runs.
      final asymptotes = shape
          .polylines(min: Vec2(-1e6, -1e6), max: Vec2(1e6, 1e6))
          .length;
      expect(asymptotes, 2, reason: 'two branches');
      expect(undefined.length, lessThanOrEqualTo(2));
    });

    test('pointAt on a non-parameterized shape is the zero triple', () {
      final shape = ConicShape.of(crossingLines);
      expect(shape.pointAt(0.3).isZero, isTrue);
      expect(shape.parameterOf(ProjPoint.real(1, 1)), isNull);
      expect(shape.chartPointAt(0.3), isNull);
    });

    Glados2(any.pencilAngle, any.rescale).test(
      'the swept point set is invariant under rescaling the matrix',
      (phi, k) {
        final scaled = ConicShape.of(unitCircle.scaledBy(Complex(k)));
        expect(unitCircle.containsPoint(scaled.pointAt(phi)), isTrue);
      },
    );
  });

  group('ConicShape.polylines', () {
    Vec2 min(Vec2 a, Vec2 b) => Vec2(math.min(a.x, b.x), math.min(a.y, b.y));
    Vec2 max(Vec2 a, Vec2 b) => Vec2(math.max(a.x, b.x), math.max(a.y, b.y));

    ({Vec2 min, Vec2 max}) boundsOf(List<Vec2> points) => (
      min: points.reduce(min),
      max: points.reduce(max),
    );

    test('a fully visible circle is one closed loop covering the rim', () {
      final strokes = ConicShape.of(
        unitCircle,
      ).polylines(min: Vec2(-2, -2), max: Vec2(2, 2));
      expect(strokes, hasLength(1));
      final stroke = strokes.single;
      expect(stroke.closed, isTrue);
      for (final p in stroke.points) {
        expect(p.norm, closeTo(1, 1e-9));
      }
      final bounds = boundsOf(stroke.points);
      expect(bounds.min.x, closeTo(-1, 1e-3));
      expect(bounds.max.x, closeTo(1, 1e-3));
      expect(bounds.min.y, closeTo(-1, 1e-3));
      expect(bounds.max.y, closeTo(1, 1e-3));
      // No duplicated endpoint: the closing edge is the painter's to add.
      expect(stroke.points.first.distanceTo(stroke.points.last), greaterThan(0));
    });

    test('clipping is exact: a half-visible circle ends on the edge', () {
      final strokes = ConicShape.of(
        unitCircle,
      ).polylines(min: Vec2(0, -2), max: Vec2(2, 2));
      expect(strokes, hasLength(1));
      final stroke = strokes.single;
      expect(stroke.closed, isFalse);
      for (final p in stroke.points) {
        expect(p.norm, closeTo(1, 1e-9));
        expect(p.x, greaterThan(-1e-9));
      }
      expect(stroke.points.first.x, closeTo(0, 1e-9));
      expect(stroke.points.last.x, closeTo(0, 1e-9));
      expect(stroke.points.first.y.abs(), closeTo(1, 1e-9));
      expect(stroke.points.last.y.abs(), closeTo(1, 1e-9));
      // Entry and exit are the two ends of the same half, not the same point.
      expect(stroke.points.first.distanceTo(stroke.points.last), closeTo(2, 1e-6));
    });

    test('a circle outside the box draws nothing', () {
      expect(
        ConicShape.of(unitCircle).polylines(min: Vec2(5, 5), max: Vec2(6, 6)),
        isEmpty,
      );
    });

    test('a hyperbola draws its two branches, on their own sides', () {
      final strokes = ConicShape.of(
        hyperbola,
      ).polylines(min: Vec2(-3, -3), max: Vec2(3, 3));
      expect(strokes, hasLength(2));
      for (final stroke in strokes) {
        expect(stroke.closed, isFalse);
        for (final p in stroke.points) {
          expect(p.x * p.x - p.y * p.y, closeTo(1, 1e-6));
        }
      }
      final signs = strokes.map((s) => s.points.first.x.sign).toSet();
      expect(signs, {-1.0, 1.0}, reason: 'one branch per side');
      // Each branch runs from its vertex out to the box's vertical edges,
      // which it leaves at y = ±√8 — the exact clip, not the box corner.
      for (final stroke in strokes) {
        final bounds = boundsOf(stroke.points);
        expect(bounds.min.y, closeTo(-math.sqrt(8), 1e-6));
        expect(bounds.max.y, closeTo(math.sqrt(8), 1e-6));
        expect(bounds.max.x - bounds.min.x, closeTo(2, 1e-6));
      }
    });

    test('a parabola draws one arm reaching both box edges', () {
      final strokes = ConicShape.of(
        parabola,
      ).polylines(min: Vec2(-1, -4), max: Vec2(5, 4));
      expect(strokes, hasLength(1));
      final stroke = strokes.single;
      for (final p in stroke.points) {
        expect(p.y * p.y, closeTo(4 * p.x, 1e-6));
      }
      final bounds = boundsOf(stroke.points);
      expect(bounds.min.x, closeTo(0, 1e-6), reason: 'the vertex');
      expect(bounds.min.y, closeTo(-4, 1e-6));
      expect(bounds.max.y, closeTo(4, 1e-6));
    });

    test('degenerate conics draw their real line components, clipped', () {
      final crossing = ConicShape.of(
        crossingLines,
      ).polylines(min: Vec2(-1, -1), max: Vec2(1, 1));
      expect(crossing, hasLength(2));
      for (final stroke in crossing) {
        expect(stroke.points, hasLength(2));
        expect(stroke.closed, isFalse);
        for (final p in stroke.points) {
          expect(p.y.abs(), closeTo(p.x.abs(), 1e-9));
          expect(p.x.abs(), closeTo(1, 1e-9));
        }
      }

      final doubled = ConicShape.of(
        doubleLine,
      ).polylines(min: Vec2(-1, -2), max: Vec2(1, 2));
      expect(doubled, hasLength(1));
      expect(doubled.single.points.map((p) => p.x), everyElement(0));

      final parallel = ConicShape.of(
        parallelLines,
      ).polylines(min: Vec2(-3, -1), max: Vec2(3, 1));
      expect(parallel, hasLength(2));
      expect(
        parallel.expand((s) => s.points).map((p) => p.x.abs()),
        everyElement(closeTo(1, 1e-9)),
      );
    });

    test('a line pair partly outside the box draws only what fits', () {
      final strokes = ConicShape.of(
        parallelLines,
      ).polylines(min: Vec2(0.5, -1), max: Vec2(3, 1));
      expect(strokes, hasLength(1), reason: 'x = −1 misses the box');
      expect(strokes.single.points.map((p) => p.x), everyElement(1));
    });

    test('classes with no curve draw nothing', () {
      const box = (min: Vec2(-5, -5), max: Vec2(5, 5));
      for (final a in [imaginaryEllipse, originPoint]) {
        expect(
          ConicShape.of(a).polylines(min: box.min, max: box.max),
          isEmpty,
        );
      }
    });

    test('an inverted box draws nothing', () {
      expect(
        ConicShape.of(unitCircle).polylines(min: Vec2(2, 2), max: Vec2(-2, -2)),
        isEmpty,
      );
    });

    test('flatness bounds the sagitta and buys points for it', () {
      final shape = ConicShape.of(unitCircle);
      var previous = 0;
      for (final flatness in [0.1, 0.01, 0.001]) {
        final points = shape
            .polylines(min: Vec2(-2, -2), max: Vec2(2, 2), flatness: flatness)
            .single
            .points;
        expect(points.length, greaterThan(previous));
        previous = points.length;
        // The deepest the rim strays from a chord is its sagitta; on a unit
        // circle that is 1 − cos(half the subtended angle).
        for (var i = 0; i < points.length; i++) {
          final a = points[i];
          final b = points[(i + 1) % points.length];
          final chordMid = Vec2(0.5 * (a.x + b.x), 0.5 * (a.y + b.y));
          expect(1 - chordMid.norm, lessThanOrEqualTo(flatness * 1.5));
        }
      }
    });

    test('a huge conic in a small box stays within its sample budget', () {
      // A circle of radius 1e6 through a unit box: nearly a straight line,
      // and the clip must not walk the whole rim to find that out.
      final huge = ConicMatrix.lift(CircleEq(Vec2(0, -1000000), 1000000));
      final strokes = ConicShape.of(
        huge,
      ).polylines(min: Vec2(-1, -1), max: Vec2(1, 1));
      expect(strokes, hasLength(1));
      expect(strokes.single.points.length, lessThan(200));
      for (final p in strokes.single.points) {
        expect(p.x.abs(), lessThanOrEqualTo(1 + 1e-6));
        expect(p.y.abs(), lessThanOrEqualTo(1 + 1e-6));
      }
    });

    Glados2(any.rescale, any.rescale).test(
      'the drawn point set is invariant under rescaling the matrix',
      (k, l) {
        final scaled = ConicShape.of(
          unitCircle.scaledBy(Complex(k, l)),
        ).polylines(min: Vec2(-2, -2), max: Vec2(2, 2));
        expect(scaled, hasLength(1));
        for (final p in scaled.single.points) {
          expect(p.norm, closeTo(1, 1e-9));
        }
      },
    );
  });

  group('tolerances', () {
    test('a near-parabolic ellipse still classifies and draws', () {
      // δ = 1e-12: numerically a hair from a parabola, geometrically a very
      // elongated ellipse. The probe pair is what keeps it an ellipse.
      final elongated = conic(1e-12, 0, 1, -4, 0, 0);
      final shape = ConicShape.of(elongated);
      expect(shape.kind, ConicClass.ellipse);
      expect(elongated.containsPoint(shape.basePoint!), isTrue);
      final strokes = shape.polylines(min: Vec2(-1, -4), max: Vec2(5, 4));
      expect(strokes, isNotEmpty);
      for (final p in strokes.expand((s) => s.points)) {
        expect(1e-12 * p.x * p.x + p.y * p.y - 4 * p.x, closeTo(0, 1e-6));
      }
    });

    test('a tangency to the box edge does not split the stroke', () {
      // The unit circle is tangent to x = 1 from inside: that edge cuts the
      // parameter circle at a point the curve never actually leaves through.
      final strokes = ConicShape.of(
        unitCircle,
      ).polylines(min: Vec2(-2, -2), max: Vec2(1, 2));
      expect(strokes, hasLength(1));
      expect(strokes.single.closed, isTrue);
    });

    test('the default tolerance is the layer default', () {
      expect(
        ConicShape.of(unitCircle, projectiveEpsilon).kind,
        ConicShape.of(unitCircle).kind,
      );
    });
  });

  group('isDrawable and anchorPoint', () {
    test('ink is the curve or the real line components', () {
      expect(ConicShape.of(unitCircle).isDrawable, isTrue);
      expect(ConicShape.of(parabola).isDrawable, isTrue);
      expect(ConicShape.of(hyperbola).isDrawable, isTrue);
      expect(ConicShape.of(crossingLines).isDrawable, isTrue);
      expect(ConicShape.of(parallelLines).isDrawable, isTrue);
      expect(ConicShape.of(doubleLine).isDrawable, isTrue);
      // A real point is not ink: a conic's ink is its curve.
      expect(ConicShape.of(originPoint).isDrawable, isFalse);
      expect(ConicShape.of(imaginaryEllipse).isDrawable, isFalse);
      expect(
        ConicShape.of(
          const ConicMatrix(
            Complex.zero,
            Complex.zero,
            Complex.zero,
            Complex.zero,
            Complex.zero,
            Complex.zero,
          ),
        ).isDrawable,
        isFalse,
      );
    });

    test('the anchor lands on the curve', () {
      for (final a in [unitCircle, ellipse, parabola, hyperbola]) {
        final anchor = ConicShape.of(a).anchorPoint;
        expect(anchor, isNotNull);
        expect(a.containsPoint(ProjPoint.lift(anchor!)), isTrue);
      }
    });

    test('degenerate anchors are the crossing, or a point of a line', () {
      expect(
        ConicShape.of(crossingLines).anchorPoint!.closeTo(Vec2.zero, 1e-9),
        isTrue,
      );
      // Parallel lines meet at infinity: a point of one of them stands in.
      expect(
        ConicShape.of(parallelLines).anchorPoint!.x.abs(),
        closeTo(1, 1e-9),
      );
      expect(ConicShape.of(doubleLine).anchorPoint!.x, closeTo(0, 1e-9));
      // The isolated point is real even though it is not ink.
      expect(
        ConicShape.of(originPoint).anchorPoint!.closeTo(Vec2.zero, 1e-9),
        isTrue,
      );
      expect(ConicShape.of(imaginaryEllipse).anchorPoint, isNull);
    });
  });

  group('distanceTo', () {
    /// The outward unit normal of [a] at the chart point [v] — the
    /// gradient of the quadratic form, normalized.
    Vec2 normalAt(ConicMatrix a, Vec2 v) {
      final gx = (a.xx.re * v.x + a.xy.re * v.y + a.xw.re) * 2;
      final gy = (a.xy.re * v.x + a.yy.re * v.y + a.yw.re) * 2;
      return Vec2(gx, gy).normalized();
    }

    test('a point of the curve is at distance zero', () {
      for (final a in [unitCircle, ellipse, parabola, hyperbola]) {
        final shape = ConicShape.of(a);
        for (final phi in [0.1, 0.8, 1.5, 2.2, 2.9]) {
          final v = shape.chartPointAt(phi);
          if (v == null) continue;
          expect(shape.distanceTo(v), lessThan(1e-9), reason: 'φ = $phi');
        }
      }
    });

    test('a circle answers its own radius, inside and out', () {
      final shape = ConicShape.of(unitCircle);
      for (final r in [0.0, 0.25, 0.9, 1.0, 1.6, 40.0]) {
        expect(
          shape.distanceTo(Vec2(r, 0)),
          closeTo((r - 1).abs(), 1e-9),
          reason: 'r = $r',
        );
      }
    });

    test('off-curve distance is the offset along the normal', () {
      // Inside the evolute the foot of the normal is the closest point, so
      // stepping t along it must read back exactly t. This is the
      // monotone-off-curve property, stated where it is exact.
      for (final a in [unitCircle, ellipse]) {
        final shape = ConicShape.of(a);
        for (final phi in [0.3, 1.1, 2.0, 2.7]) {
          final v = shape.chartPointAt(phi)!;
          final n = normalAt(a, v);
          for (final t in [-0.4, -0.1, 0.1, 0.4, 0.9]) {
            expect(
              shape.distanceTo(v + n * t),
              closeTo(t.abs(), 1e-8),
              reason: 'φ = $phi, t = $t',
            );
          }
        }
      }
    });

    test('a hyperbola measures to the nearer branch', () {
      // x² − y² = 1. From (3, 0) the foot is *not* the vertex: minimizing
      // (x − 3)² + x² − 1 puts it at x = 1.5, √3.5 away — the case that
      // makes a real search worth having.
      final shape = ConicShape.of(hyperbola);
      expect(shape.distanceTo(const Vec2(3, 0)), closeTo(math.sqrt(3.5), 1e-8));
      expect(
        shape.distanceTo(const Vec2(-3, 0)),
        closeTo(math.sqrt(3.5), 1e-8),
      );
      // The origin sits between the branches, one unit from each vertex —
      // there the vertex *is* the foot.
      expect(shape.distanceTo(Vec2.zero), closeTo(1, 1e-8));
    });

    test('a degenerate conic measures to its nearest line', () {
      // y = ±x.
      final shape = ConicShape.of(crossingLines);
      expect(shape.distanceTo(const Vec2(2, 0)), closeTo(math.sqrt2, 1e-9));
      expect(shape.distanceTo(Vec2.zero), closeTo(0, 1e-9));
      // x = ±1: nearer to x = 1.
      expect(
        ConicShape.of(parallelLines).distanceTo(const Vec2(0.75, 40)),
        closeTo(0.25, 1e-9),
      );
      expect(
        ConicShape.of(doubleLine).distanceTo(const Vec2(3, -7)),
        closeTo(3, 1e-9),
      );
    });

    test('a conic with no ink is infinitely far', () {
      expect(ConicShape.of(imaginaryEllipse).distanceTo(Vec2.zero), isPositive);
      expect(
        ConicShape.of(imaginaryEllipse).distanceTo(Vec2.zero).isFinite,
        isFalse,
      );
      expect(
        ConicShape.of(originPoint).distanceTo(const Vec2(1, 1)).isFinite,
        isFalse,
        reason: 'an isolated point is not ink',
      );
    });

    Glados(any.pencilAngle).test('every swept point reads distance zero', (
      phi,
    ) {
      final shape = ConicShape.of(ellipse);
      final v = shape.chartPointAt(phi);
      if (v == null) return;
      expect(shape.distanceTo(v), lessThan(1e-8), reason: 'φ = $phi');
    });
  });

  group('extremesAlong', () {
    test('an ellipse extends to its semi-axes', () {
      // x²/4 + y²/9 = 1.
      final shape = ConicShape.of(ellipse);
      final horizontal = shape.extremesAlong(0)..sort((a, b) => a.x.compareTo(b.x));
      expect(horizontal, hasLength(2));
      expect(horizontal.first.x, closeTo(-2, 1e-9));
      expect(horizontal.last.x, closeTo(2, 1e-9));
      expect(horizontal.every((v) => v.y.abs() < 1e-9), isTrue);

      final vertical = shape.extremesAlong(math.pi / 2)
        ..sort((a, b) => a.y.compareTo(b.y));
      expect(vertical.first.y, closeTo(-3, 1e-9));
      expect(vertical.last.y, closeTo(3, 1e-9));
    });

    test('a rotated direction still touches the curve', () {
      final shape = ConicShape.of(ellipse);
      for (final angle in [0.4, 1.2, 2.5]) {
        final extremes = shape.extremesAlong(angle);
        expect(extremes, hasLength(2));
        for (final v in extremes) {
          expect(ellipse.containsPoint(ProjPoint.lift(v)), isTrue);
          // Nothing on the curve reaches further along the direction.
          final along = Vec2(math.cos(angle), math.sin(angle));
          final reach = extremes.map((e) => e.dot(along)).toList()..sort();
          for (var i = 0; i < 60; i++) {
            final sample = shape.chartPointAt(math.pi * i / 60)!;
            expect(sample.dot(along), greaterThanOrEqualTo(reach.first - 1e-9));
            expect(sample.dot(along), lessThanOrEqualTo(reach.last + 1e-9));
          }
        }
      }
    });

    test('a hyperbola has real extremes only across its axis', () {
      // x² − y² = 1: vertical tangents at (±1, 0); no horizontal ones.
      final shape = ConicShape.of(hyperbola);
      expect(shape.extremesAlong(0), hasLength(2));
      expect(shape.extremesAlong(math.pi / 2), isEmpty);
    });

    test('a conic with no curve has no extremes', () {
      expect(ConicShape.of(crossingLines).extremesAlong(0), isEmpty);
      expect(ConicShape.of(imaginaryEllipse).extremesAlong(0), isEmpty);
    });
  });
}
