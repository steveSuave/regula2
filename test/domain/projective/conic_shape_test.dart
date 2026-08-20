import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/circles.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/projective/conics.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/tolerances.dart';

/// `a·x² + b·xy + c·y² + d·x + e·y + f = 0`.
ConicMatrix conic(double a, double b, double c, double d, double e, double f) =>
    ConicMatrix.coefficients(a, b, c, d, e, f);

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

    test('a slanted parabola classifies and draws, though its double root '
        'is not bitwise real (Phase 120b)', () {
      // 16x² + 24xy + 9y² − 130x + 90y + 100 = 0, i.e. (4x+3y)² = …: the
      // focus-directrix parabola of F = (2, −1) and 3x − 4y + 5 = 0. Its
      // quadratic block has determinant exactly zero, but the balanced
      // frame's discriminant rounds slightly negative, so the doubled meet
      // with ℓ∞ comes back a conjugate pair a hair off the real axis.
      // Reading realness before coincidence sent this into the ellipse
      // branch, to be probed through a centre that is genuinely at
      // infinity — mostly surviving as a huge finite one, and measurably
      // often (13 in 3000 sampled parabolas) collapsing to `empty`, so the
      // curve did not draw at all.
      final slanted = conic(16, 24, 9, -130, 90, 100);
      final shape = ConicShape.of(slanted);
      expect(shape.kind, ConicClass.parabola);
      expect(shape.isDrawable, isTrue);
      // The seed is real and genuinely on the conic — it is the null
      // direction of the quadratic block, not the perturbed root.
      final seed = shape.basePoint!;
      expect(seed.isReal(), isTrue);
      expect(slanted.containsPoint(seed), isTrue);
      final strokes = shape.polylines(
        min: const Vec2(-30, -30),
        max: const Vec2(30, 30),
      );
      expect(strokes, isNotEmpty);
      for (final p in strokes.expand((s) => s.points)) {
        expect(
          16 * p.x * p.x +
              24 * p.x * p.y +
              9 * p.y * p.y -
              130 * p.x +
              90 * p.y +
              100,
          closeTo(0, 1e-6 * (1 + p.norm * p.norm)),
        );
      }
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
      expect(
        doubled.lines.single.toLineEq()!.closeTo(
          ProjLine.real(1, 0, 0).toLineEq()!,
        ),
        isTrue,
      );
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

      Glados(any.pencilAngle).test('${entry.key}: pointAt stays on the conic', (
        phi,
      ) {
        final shape = ConicShape.of(entry.value);
        final p = shape.pointAt(phi);
        expect(p.isZero, isFalse);
        expect(p.isReal(), isTrue);
        expect(entry.value.containsPoint(p), isTrue, reason: 'φ = $phi');
      });

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

    ({Vec2 min, Vec2 max}) boundsOf(List<Vec2> points) =>
        (min: points.reduce(min), max: points.reduce(max));

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
      expect(
        stroke.points.first.distanceTo(stroke.points.last),
        greaterThan(0),
      );
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
      expect(
        stroke.points.first.distanceTo(stroke.points.last),
        closeTo(2, 1e-6),
      );
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
        expect(ConicShape.of(a).polylines(min: box.min, max: box.max), isEmpty);
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

    /// The worst distance from the true curve to the chord it was
    /// approximated by, over every segment of every stroke — measured at
    /// the *curve's* midpoint between the two vertices' parameters, which
    /// is what the walk's own acceptance test looks at.
    double worstSagitta(ConicShape shape, List<ConicPolyline> strokes) {
      var worst = 0.0;
      for (final stroke in strokes) {
        final points = stroke.points;
        for (var i = 0; i + 1 < points.length; i++) {
          final a = points[i];
          final b = points[i + 1];
          final pa = shape.parameterOf(ProjPoint.real(a.x, a.y));
          final pb = shape.parameterOf(ProjPoint.real(b.x, b.y));
          if (pa == null || pb == null) continue;
          // The pencil parameter is π-periodic; take the short way round.
          var span = pb - pa;
          if (span.abs() > math.pi / 2) span -= span.sign * math.pi;
          final mid = shape.chartPointAt(pa + span / 2);
          if (mid == null) continue;
          final chordMid = Vec2(0.5 * (a.x + b.x), 0.5 * (a.y + b.y));
          final sagitta = mid.distanceTo(chordMid);
          if (sagitta > worst) worst = sagitta;
        }
      }
      return worst;
    }

    // Phase 120c. Both figures are from saved user documents that drew as
    // visible polygons: the walk hit `maxDepth` and emitted the chord
    // anyway. The sweep parameter is a pencil angle, so |dX/dφ| spreads by
    // ~1e7 on these — about 24 bisections' worth, twice the old cap of 12.
    // Neither needs more than a fraction of the sample budget; the
    // assertions below pin that it is depth, not cost, that was wrong.
    /// The world box a `canvasSize` canvas covers at `pan`/`scale` —
    /// `CanvasViewport.visibleWorldBox` without the presentation layer.
    ({Vec2 min, Vec2 max}) worldBox(
      Vec2 pan,
      double scale,
      double w,
      double h,
    ) {
      const margin = 8.0;
      return (
        min: Vec2(pan.x - margin / scale, pan.y - (h + margin) / scale),
        max: Vec2(pan.x + (w + margin) / scale, pan.y + margin / scale),
      );
    }

    test('an ellipse written far from the origin meets its flatness', () {
      // square-ellipse.rgl: a bifocal conic about a focal pair ~2000 world
      // units out, at the document's own viewport — 0.14 px per world
      // unit, so half a pixel is 3.6 units.
      final shape = ConicShape.of(
        bifocalConicOf(
          Vec2(-1730.493482610943, 2125.130820547624),
          Vec2(-496.3195485298029, 2181.511437724128),
          Vec2(-1309.501527037075, 2903.5892335453036),
          difference: false,
        ),
      );
      expect(shape.kind, ConicClass.ellipse);
      const scale = 0.14050706424869222;
      final box = worldBox(
        Vec2(-5308.188376016837, 5505.715962582011),
        scale,
        960,
        720,
      );
      const flatness = 0.5 / scale;
      final strokes = shape.polylines(
        min: box.min,
        max: box.max,
        flatness: flatness,
      );
      expect(worstSagitta(shape, strokes), lessThanOrEqualTo(flatness));
      // Depth was the binding constraint, not the budget: capped at 12 the
      // same call strays many times its tolerance.
      expect(
        worstSagitta(
          shape,
          shape.polylines(
            min: box.min,
            max: box.max,
            flatness: flatness,
            maxDepth: 12,
          ),
        ),
        greaterThan(5 * flatness),
      );
    });

    test('both branches of a hyperbola meet their flatness', () {
      // square-hyperbola.rgl, viewed at 1 px per world unit. The second
      // branch is the one that drew as three straight facets.
      final shape = ConicShape.of(
        ConicMatrix.throughFivePoints([
          ProjPoint.real(501.20703125, -516.53515625),
          ProjPoint.real(616.54296875, -234.26171875),
          ProjPoint.real(554.46875, -362.6640625),
          ProjPoint.real(675.2578125, -237.38671875),
          ProjPoint.real(945.7109375, -407.140625),
        ])!,
      );
      expect(shape.kind, ConicClass.hyperbola);
      final box = worldBox(Vec2(42, 214), 1, 891, 864);
      final strokes = shape.polylines(
        min: box.min,
        max: box.max,
        flatness: 0.5,
      );
      expect(strokes, hasLength(2));
      expect(worstSagitta(shape, strokes), lessThanOrEqualTo(0.5));
      expect(
        worstSagitta(
          shape,
          shape.polylines(
            min: box.min,
            max: box.max,
            flatness: 0.5,
            maxDepth: 12,
          ),
        ),
        greaterThan(100),
      );
    });

    test('the deeper walk spends the same samples, not more', () {
      // maxSamples is the cost cap and it was never the binding one — the
      // two figures above draw identically with a budget 50× larger.
      final shape = ConicShape.of(
        ConicMatrix.throughFivePoints([
          ProjPoint.real(501.20703125, -516.53515625),
          ProjPoint.real(616.54296875, -234.26171875),
          ProjPoint.real(554.46875, -362.6640625),
          ProjPoint.real(675.2578125, -237.38671875),
          ProjPoint.real(945.7109375, -407.140625),
        ])!,
      );
      final box = worldBox(Vec2(42, 214), 1, 891, 864);
      final counts = [
        for (final budget in [4000, 200000])
          shape
              .polylines(
                min: box.min,
                max: box.max,
                flatness: 0.5,
                maxSamples: budget,
              )
              .map((s) => s.points.length)
              .toList(),
      ];
      expect(counts[0], counts[1]);
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
      //
      // It is also what pins the Phase 120b coincidence boundary from the
      // other side: the meets are at ±i√δ, so they read as one double root
      // below δ ≈ 2.5e-13 and this ellipse clears that by a factor of 4.
      // A *genuine* parabola's rounding noise is ~√(machine eps) ≈ 1e-8,
      // two orders inside the threshold — so the margin is wide on the
      // side that matters, and an ellipse that loses it is a million-to-one
      // sliver that draws identically either way.
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
      final horizontal = shape.extremesAlong(0)
        ..sort((a, b) => a.x.compareTo(b.x));
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

  group('extentAlong', () {
    /// `x²/9 + y²/4 = 1` shifted to (3, −1): a circle-free ellipse with
    /// known extremes, so the numbers are checkable by hand.
    ConicMatrix ellipseAt(Vec2 centre, double a, double b) => ConicMatrix(
      Complex(1 / (a * a)),
      Complex.zero,
      Complex(1 / (b * b)),
      Complex(-centre.x / (a * a)),
      Complex(-centre.y / (b * b)),
      Complex(
        centre.x * centre.x / (a * a) + centre.y * centre.y / (b * b) - 1,
      ),
    );

    test('a lifted circle gives centre ± radius, in any direction', () {
      final shape = ConicShape.of(
        circleWithRadius(ProjPoint.lift(const Vec2(3, -1)), 2),
      );
      expect(shape.kind, ConicClass.ellipse);
      expect(shape.extentAlong(1, 0)!.min, closeTo(1, 1e-9));
      expect(shape.extentAlong(1, 0)!.max, closeTo(5, 1e-9));
      expect(shape.extentAlong(0, 1)!.min, closeTo(-3, 1e-9));
      expect(shape.extentAlong(0, 1)!.max, closeTo(1, 1e-9));
      // Along the diagonal the centre projects to (3 − 1)/√2 = √2, and a
      // disc's support is that ± the radius whatever the direction.
      final d = 1 / math.sqrt(2);
      expect(shape.extentAlong(d, d)!.min, closeTo(math.sqrt2 - 2, 1e-9));
      expect(shape.extentAlong(d, d)!.max, closeTo(math.sqrt2 + 2, 1e-9));
    });

    test('an ellipse is not a disc: the support turns with the direction', () {
      final shape = ConicShape.of(ellipseAt(const Vec2(3, -1), 3, 2));
      expect(shape.extentAlong(1, 0), (min: 0.0, max: 6.0));
      expect(shape.extentAlong(0, 1)!.min, closeTo(-3, 1e-9));
      expect(shape.extentAlong(0, 1)!.max, closeTo(1, 1e-9));
      // Semi-diameter along a unit direction u is √(a²u_x² + b²u_y²), so
      // at 45° it is √((9 + 4)/2) rather than either semi-axis.
      final d = 1 / math.sqrt(2);
      final centre = 3 * d - 1 * d;
      final half = math.sqrt((9 + 4) / 2);
      expect(shape.extentAlong(d, d)!.min, closeTo(centre - half, 1e-9));
      expect(shape.extentAlong(d, d)!.max, closeTo(centre + half, 1e-9));
    });

    test('the interval scales with a non-unit direction', () {
      final shape = ConicShape.of(
        circleWithRadius(ProjPoint.lift(const Vec2(3, -1)), 2),
      );
      expect(shape.extentAlong(2, 0)!.min, closeTo(2, 1e-9));
      expect(shape.extentAlong(2, 0)!.max, closeTo(10, 1e-9));
    });

    test('only the ellipse answers — the unbounded classes give null', () {
      // `extremesAlong` finds real tangent points on a hyperbola too, and
      // that is exactly why the class gate is here rather than the
      // arithmetic deciding: the curve runs out between them.
      final hyperbola = ConicMatrix(
        Complex.one,
        Complex.zero,
        Complex(-1),
        Complex.zero,
        Complex.zero,
        Complex(-1),
      );
      expect(ConicShape.of(hyperbola).kind, ConicClass.hyperbola);
      expect(ConicShape.of(hyperbola).extremesAlong(0), isNotEmpty);
      expect(ConicShape.of(hyperbola).extentAlong(1, 0), isNull);

      final parabola = ConicMatrix(
        Complex.one,
        Complex.zero,
        Complex.zero,
        Complex.zero,
        Complex(-0.5),
        Complex.zero,
      );
      expect(ConicShape.of(parabola).kind, ConicClass.parabola);
      expect(ConicShape.of(parabola).extentAlong(1, 0), isNull);
    });
  });

  group('parameterNear and the complex continuation (Phase 132)', () {
    ConicShape ellipse() => ConicShape.of(
      ConicMatrix.throughFivePoints([
        ProjPoint.real(4, 0),
        ProjPoint.real(0, 3),
        ProjPoint.real(-4, 0),
        ProjPoint.real(0, -3),
        ProjPoint.real(2.4, 2.4),
      ])!,
    );

    test('parameterNear reports where distanceTo measured', () {
      final shape = ellipse();
      for (final p in [
        const Vec2(3.6, 1.3),
        const Vec2(-3.9, 0.2),
        const Vec2(0.1, -2.9),
        const Vec2(10, 10),
        Vec2.zero,
      ]) {
        final phi = shape.parameterNear(p)!;
        expect(
          shape.chartPointAt(phi)!.distanceTo(p),
          closeTo(shape.distanceTo(p), 1e-6),
          reason: 'the two share one search, so they cannot disagree',
        );
      }
    });

    test('parameterNear beats every sample of the curve', () {
      final shape = ellipse();
      const p = Vec2(3.6, 1.3);
      final best = shape.chartPointAt(shape.parameterNear(p)!)!.distanceTo(p);
      for (var i = 0; i < 720; i++) {
        final v = shape.chartPointAt(math.pi * i / 720);
        if (v != null) expect(v.distanceTo(p), greaterThan(best - 1e-9));
      }
    });

    test('pointAtComplex reproduces pointAt bitwise on a real angle', () {
      // The property tracing depends on: a detour that returns to the
      // real axis must rejoin the real evaluation exactly, so the
      // commit's static solve lands on the same point.
      final shape = ellipse();
      for (var i = 0; i < 32; i++) {
        final phi = math.pi * i / 32;
        final real = shape.pointAt(phi);
        final complex = shape.pointAtComplex(Complex(phi));
        expect(complex.x.re, real.x.re);
        expect(complex.x.im, real.x.im);
        expect(complex.y.re, real.y.re);
        expect(complex.y.im, real.y.im);
        expect(complex.w.re, real.w.re);
        expect(complex.w.im, real.w.im);
      }
    });

    test('a complex angle leaves the real axis and stays on the conic', () {
      final shape = ellipse();
      final off = shape.pointAtComplex(const Complex(0.7, 0.3));
      expect(off.isReal(), isFalse, reason: 'a genuine detour');
      expect(
        shape.conic.evaluate(off).abs,
        lessThan(1e-9),
        reason: 'the conic equation is what pointAt solves, over ℂ as over ℝ',
      );
    });

    test('an unparameterized shape answers null rather than a point', () {
      final empty = ConicShape.of(
        const ConicMatrix(
          Complex.one,
          Complex.zero,
          Complex.one,
          Complex.zero,
          Complex.zero,
          Complex.one,
        ),
      );
      expect(empty.isParameterized, isFalse);
      expect(empty.parameterNear(Vec2.zero), isNull);
      expect(empty.pointAtComplex(Complex.zero).isZero, isTrue);
    });
  });

  group('chartLiftAt: the pencil value a tracing consumer can take '
      '(Phase 132c)', () {
    // `PointOnObject.tracedPosition` takes a homogeneous value whose `w`
    // is exactly one or exactly zero, because `position` reads x and y
    // straight back without dividing. `pointAtComplex` is polynomial and
    // homogeneous, so it cannot serve that — this is the lift that can.

    test('the raw pencil value is not in the chart, and not by a little', () {
      // Why the method exists. The scale is arbitrary and the *sign* is
      // too, which is the half that bites: a consumer reading the chart
      // back would get the point reflected through the origin.
      final shape = ConicShape.of(conic(1 / 16, 0, 1 / 4, 0, 0, -1));
      final raw = shape.pointAtComplex(const Complex(0.3));
      expect(raw.w.re, closeTo(-0.0788, 1e-3));
      expect(raw.x.re, isNot(closeTo(shape.chartPointAt(0.3)!.x, 1)));
    });

    test('a real angle lifts to the chart point, bit for bit', () {
      for (final matrix in [unitCircle, ellipse, hyperbola, parabola]) {
        final shape = ConicShape.of(matrix);
        for (var i = 0; i < 64; i++) {
          final phi = math.pi * i / 64;
          final lifted = shape.chartLiftAt(Complex(phi));
          final chart = shape.chartPointAt(phi);
          if (chart == null) {
            expect(lifted.w, Complex.zero, reason: 'the point at infinity');
            expect(lifted.isZero, isFalse, reason: 'a direction, not nothing');
            continue;
          }
          expect(lifted.w, Complex.one);
          expect(lifted.x.re, chart.x);
          expect(lifted.y.re, chart.y);
        }
      }
    });

    test('a complex angle lifts to the same projective point', () {
      // The lift is a rescaling, so nothing about the geometry moves —
      // only the representative the chart readers see.
      final shape = ConicShape.of(ellipse);
      for (final phi in [
        const Complex(0.4, 0.2),
        const Complex(1.9, -0.7),
        const Complex(2.8, 0.05),
      ]) {
        final lifted = shape.chartLiftAt(phi);
        expect(lifted.w, Complex.one);
        expect(lifted.closeTo(shape.pointAtComplex(phi)), isTrue);
      }
    });

    test('the crossing at infinity gives the direction, not a huge point', () {
      // `x² − y² = 1` meets the line at infinity at (1 : ±1 : 0), and the
      // lift says so exactly rather than dividing by a `w` the projection
      // has already called negligible.
      final shape = ConicShape.of(hyperbola);
      final phi = shape.parameterOf(
        const ProjPoint(Complex.one, Complex.one, Complex.zero),
      )!;
      final lifted = shape.chartLiftAt(Complex(phi));
      expect(shape.chartPointAt(phi), isNull);
      expect(lifted.w, Complex.zero);
      expect((lifted.y / lifted.x).re.abs(), closeTo(1, 1e-6));
    });

    test('a shape with no parameterization lifts to nothing', () {
      for (final matrix in [imaginaryEllipse, crossingLines, originPoint]) {
        expect(ConicShape.of(matrix).chartLiftAt(Complex.zero).isZero, isTrue);
      }
    });
  });

  group('infinityParameters: where the curve leaves the chart '
      '(Phase 132c)', () {
    test('the count is the class: none, one, two', () {
      expect(ConicShape.of(ellipse).infinityParameters, isEmpty);
      expect(ConicShape.of(unitCircle).infinityParameters, isEmpty);
      // A parabola's tangency at infinity is a double root and counts
      // once — it is one cut, not two coincident ones.
      expect(ConicShape.of(parabola).infinityParameters, hasLength(1));
      expect(ConicShape.of(hyperbola).infinityParameters, hasLength(2));
      for (final matrix in [imaginaryEllipse, crossingLines, originPoint]) {
        expect(ConicShape.of(matrix).infinityParameters, isEmpty);
      }
    });

    test('the curve really has no chart point there, and does '
        'on either side', () {
      for (final matrix in [parabola, hyperbola]) {
        final shape = ConicShape.of(matrix);
        for (final phi in shape.infinityParameters) {
          expect(shape.chartPointAt(phi), isNull);
          expect(shape.chartLiftAt(Complex(phi)).w, Complex.zero);
          expect(shape.chartPointAt(phi + 0.05), isNotNull);
          expect(shape.chartPointAt(phi - 0.05), isNotNull);
        }
      }
    });

    test('sorted, inside one period, and they move with the conic', () {
      // One of a hyperbola's two cuts always sits at 0 or π/2 — its base
      // point *is* one of its points at infinity — and the other lands
      // wherever the matrix puts it. That is why a locus grid has to be
      // cut on them rather than hoping a uniform one lands there.
      final seen = <double>{};
      for (var i = 0; i < 20; i++) {
        final shape = ConicShape.of(
          conic(1, 0.2 + i * 0.05, -0.3, 0.2, -1.1, -2),
        );
        expect(shape.kind, ConicClass.hyperbola);
        final cuts = shape.infinityParameters;
        expect(cuts, hasLength(2));
        expect(cuts.first, lessThan(cuts.last));
        for (final phi in cuts) {
          expect(phi, inInclusiveRange(0, math.pi));
        }
        seen.add((cuts.first * 1000).roundToDouble());
      }
      expect(seen.length, greaterThan(10), reason: 'they are not pinned');
    });
  });

  group('frameSeeds / carryParameterFrom (Phase 132d)', () {
    /// `x'²/a² + y'²/b² = 1` rotated by [theta] about its own centre,
    /// which sits at a *generic* spot: centred exactly on the origin the
    /// balanced frame is exact and the discrete frame choices never
    /// switch, so that configuration cannot exercise the carry at all.
    ConicMatrix rotatedEllipse(
      double a,
      double b,
      double theta, {
      Vec2 centre = const Vec2(0.4, 0.7),
    }) {
      final aa = 1 / (a * a), bb = 1 / (b * b);
      final c = math.cos(theta), s = math.sin(theta);
      final q11 = aa * c * c + bb * s * s;
      final q12 = (aa - bb) * s * c;
      final q22 = aa * s * s + bb * c * c;
      return conic(
        q11,
        2 * q12,
        q22,
        -2 * (q11 * centre.x + q12 * centre.y),
        -2 * (q12 * centre.x + q22 * centre.y),
        q11 * centre.x * centre.x +
            2 * q12 * centre.x * centre.y +
            q22 * centre.y * centre.y -
            1,
      );
    }

    test('the canonical base point is bitwise a member of frameSeeds, '
        'for all three curve classes', () {
      final shapes = [
        for (var i = 0; i < 40; i++) ConicShape.of(rotatedEllipse(4, 1, i * math.pi / 40)),
        for (var i = 0; i < 20; i++)
          ConicShape.of(conic(1, 0.2 + i * 0.05, -0.3, 0.2, -1.1, -2)),
        ConicShape.of(parabola),
        ConicShape.of(conic(1, 2, 1, -13, 9, 10)), // slanted parabola-ish
      ];
      for (final shape in shapes) {
        if (!shape.isParameterized) continue;
        expect(
          shape.frameSeeds.any((seed) => seed == shape.basePoint),
          isTrue,
          reason:
              '${shape.kind}: the canonical choice must be an element of '
              'the seed list, or a frame switch is undecidable',
        );
      }
    });

    test('a conic with no curve has no frame seeds', () {
      expect(ConicShape.of(imaginaryEllipse).frameSeeds, isEmpty);
      expect(ConicShape.of(crossingLines).frameSeeds, isEmpty);
    });

    test('a rigid rotation of an elongated ellipse: the fixed angle jumps '
        'and the carried angle does not', () {
      // The Session 146 measurement, as a regression: `ConicShape` picks
      // its base point and axis pair per matrix, and over a smooth
      // rotation those discrete choices switch — a *fixed* pencil angle
      // then names a point that jumps by world units. Carrying the angle
      // across each step must keep the named point continuous, and must
      // return the angle *identically* wherever no switch happened.
      const steps = 600;
      var phi = 0.9;
      const fixedPhi = 0.9;
      var previous = ConicShape.of(rotatedEllipse(4, 1, 0));
      var carriedPoint = previous.chartPointAt(phi)!;
      var fixedPoint = previous.chartPointAt(fixedPhi)!;
      var carriedMax = 0.0;
      var fixedMax = 0.0;
      var switches = 0;
      for (var i = 1; i <= steps; i++) {
        final shape = ConicShape.of(
          rotatedEllipse(4, 1, math.pi * i / steps),
        );
        final carried = shape.carryParameterFrom(previous, phi);
        expect(carried, isNotNull, reason: 'no class change on this path');
        if (carried != phi) switches++;
        phi = carried!;
        final point = shape.chartPointAt(phi);
        expect(point, isNotNull);
        carriedMax = math.max(carriedMax, point!.distanceTo(carriedPoint));
        carriedPoint = point;
        final fixed = shape.chartPointAt(fixedPhi);
        if (fixed != null) {
          fixedMax = math.max(fixedMax, fixed.distanceTo(fixedPoint));
          fixedPoint = fixed;
        }
        previous = shape;
      }
      // The sweep must actually cross switches, or the carry was never
      // exercised; and π of rigid rotation brings the figure back onto
      // itself, so the carried point must close up too.
      expect(switches, greaterThan(0));
      expect(fixedMax, greaterThan(1.0), reason: 'the defect this pins');
      expect(carriedMax, lessThan(0.2), reason: 'continuity across switches');
    });

    test('where the frame is stable the carry is a bitwise no-op', () {
      // A near-circular ellipse rotating: measured clean in Session 146
      // (no switches at all), so every step must hand the angle back
      // identically — the common case pays nothing and drifts nowhere.
      var previous = ConicShape.of(rotatedEllipse(2, 1.9, 0));
      for (var i = 1; i <= 200; i++) {
        final shape = ConicShape.of(
          rotatedEllipse(2, 1.9, math.pi * i / 200),
        );
        expect(shape.carryParameterFrom(previous, 1.234), 1.234);
        previous = shape;
      }
    });

    test('a carry across a switch keeps the named point where it was', () {
      // Find one switch on the elongated sweep and check the exactness
      // claim directly: the two frames name (almost) the same chart point
      // at the old and carried angles, at the very matrix the switch was
      // detected on.
      const steps = 600;
      var phi = 0.9;
      var previous = ConicShape.of(rotatedEllipse(4, 1, 0));
      var checked = 0;
      for (var i = 1; i <= steps; i++) {
        final shape = ConicShape.of(
          rotatedEllipse(4, 1, math.pi * i / steps),
        );
        final carried = shape.carryParameterFrom(previous, phi)!;
        if (carried != phi) {
          final before = previous.chartPointAt(phi);
          final after = shape.chartPointAt(carried);
          if (before != null && after != null) {
            // One rotation step moves a point of this figure by at most
            // ~4·π/600 ≈ 0.021; the switch must not add to that scale.
            expect(after.distanceTo(before), lessThan(0.05));
            checked++;
          }
        }
        phi = carried;
        previous = shape;
      }
      expect(checked, greaterThan(0));
    });

    test('carrying there and back returns the original angle', () {
      // Two frames straddling a switch: A→B→A must be the identity up to
      // arithmetic, or a cancelled gesture would leave a residue.
      const steps = 600;
      var phi = 0.9;
      var previous = ConicShape.of(rotatedEllipse(4, 1, 0));
      for (var i = 1; i <= steps; i++) {
        final shape = ConicShape.of(
          rotatedEllipse(4, 1, math.pi * i / steps),
        );
        final carried = shape.carryParameterFrom(previous, phi)!;
        if (carried != phi) {
          // Not bitwise: the two carries run on matrices one step apart,
          // so the residue is the frame drift over that step (measured
          // 6.3e-4 here, second order in the step). Bitwise restoration
          // is the session snapshot's job, not this arithmetic's.
          final back = previous.carryParameterFrom(shape, carried)!;
          expect(angularGap(back, phi), lessThan(1e-2));
        }
        phi = carried;
        previous = shape;
      }
    });

    test('a class change carries nothing — the caller falls back', () {
      final asEllipse = ConicShape.of(ellipse);
      final asHyperbola = ConicShape.of(hyperbola);
      expect(asHyperbola.carryParameterFrom(asEllipse, 0.5), isNull);
      expect(asEllipse.carryParameterFrom(asHyperbola, 0.5), isNull);
      expect(
        asEllipse.carryParameterFrom(ConicShape.of(crossingLines), 0.5),
        isNull,
      );
    });

    test('a hyperbola rotating: switches are carried too', () {
      // The hyperbola's base point is one of its two meets with ℓ∞, and
      // the pair swaps order as the asymptotes turn — the same defect in
      // the class whose base cannot be anything finite.
      const steps = 400;
      var phi = 0.3;
      var previous = ConicShape.of(conic(1, 0, -0.25, 0, 0, -1));
      var switches = 0;
      for (var i = 1; i <= steps; i++) {
        final t = math.pi * i / steps;
        final c = math.cos(t), s = math.sin(t);
        // x²/1 − y²/4 = 1 rotated by t.
        const aa = 1.0, bb = -0.25;
        final shape = ConicShape.of(
          conic(
            aa * c * c + bb * s * s,
            2 * (aa - bb) * s * c,
            aa * s * s + bb * c * c,
            0,
            0,
            -1,
          ),
        );
        expect(shape.kind, ConicClass.hyperbola);
        final carried = shape.carryParameterFrom(previous, phi);
        expect(carried, isNotNull);
        if (carried != phi) switches++;
        phi = carried!;
        previous = shape;
      }
      expect(switches, greaterThan(0));
    });
  });
}
