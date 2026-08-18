import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/export/png_exporter.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/fit_viewport.dart';
import 'package:regula/presentation/canvas/label_layout.dart';
import 'package:regula/presentation/theme/app_theme.dart';

/// Phase 126b: the three things a Cayley–Klein document needs from the
/// *presentation* layer, each of which was wrong on first release.
///
/// All three sat outside what `ck_kind_coverage_test` can see. That gate
/// asks whether a kind's value responds to the absolute; every one of
/// these bugs was a correct value that never reached the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hyperbolic = DocumentKernel(metric: FundamentalConic.hyperbolic);
  const elliptic = DocumentKernel(metric: FundamentalConic.elliptic);

  group('an angle label shows the measure, not the marker', () {
    /// The reported bug: a triangle built in the hyperbolic plane
    /// labelled its three corners so they summed to exactly 180°.
    /// `labelText` read `angle.measure` — the chart sweep of the drawn
    /// arc — where it meant `GeoAngle.measure`.
    ({double sum, List<String> labels}) cornerLabels(DocumentKernel kernel) {
      final construction = Construction(kernel: kernel);
      final a = FreePoint(id: 'a', position: const Vec2(-0.5, -0.3));
      final b = FreePoint(id: 'b', position: const Vec2(0.5, -0.3));
      final c = FreePoint(id: 'c', position: const Vec2(0, 0.55));
      construction
        ..add(a)
        ..add(b)
        ..add(c);
      const shown = ObjectAttributes(showValue: true);
      var sum = 0.0;
      final labels = <String>[];
      for (final (vertex, arm1, arm2) in [(a, b, c), (b, c, a), (c, a, b)]) {
        final angle = VertexAngle(
          id: 'angle-${vertex.id}',
          arm1: arm1,
          vertex: vertex,
          arm2: arm2,
          attributes: shown,
        );
        construction.add(angle);
        sum += angle.measure!;
        labels.add(labelText(angle)!);
      }
      return (sum: sum, labels: labels);
    }

    /// The degrees in a `123.4°`-shaped label.
    double degrees(String label) =>
        double.parse(label.replaceAll(RegExp(r'[^0-9.\-]'), ''));

    test('the labels total what the measures total, in every geometry', () {
      for (final kernel in [const DocumentKernel(), hyperbolic, elliptic]) {
        final result = cornerLabels(kernel);
        final labelled = result.labels.map(degrees).reduce((a, b) => a + b);
        expect(
          labelled,
          // Each label is rounded to its own decimals before being read
          // back, so three of them can drift by half a step each.
          closeTo(result.sum * 180 / 3.141592653589793, 0.2),
          reason: kernel.metric.name,
        );
      }
    });

    test('and they do not all read 180°, which is the bug', () {
      // Stated as its own case because the test above passes vacuously if
      // both sides read the same wrong number.
      final euclidean = cornerLabels(const DocumentKernel()).labels;
      expect(euclidean.map(degrees).reduce((a, b) => a + b), closeTo(180, 0.2));
      expect(
        cornerLabels(hyperbolic).labels.map(degrees).reduce((a, b) => a + b),
        lessThan(179),
      );
      expect(
        cornerLabels(elliptic).labels.map(degrees).reduce((a, b) => a + b),
        greaterThan(181),
      );
    });
  });

  group('a Cayley-Klein circle is drawable', () {
    /// The second reported bug — "I see no circle in hyperbolic mode".
    /// A CK circle is a conic *bitangent to the absolute*, so it projects
    /// to no centre and radius, so `circle` is null, so `isDefined` was
    /// false and the painter skipped it before ever reaching the conic
    /// arm it would have drawn correctly.
    CompassCircle circleIn(DocumentKernel kernel) {
      final construction = Construction(kernel: kernel);
      final centre = FreePoint(id: 'o', position: const Vec2(0.4, 0));
      final rim = FreePoint(id: 'r', position: const Vec2(0.7, 0));
      construction
        ..add(centre)
        ..add(rim);
      final circle = CompassCircle(
        id: 'k',
        center: centre,
        radiusPoint1: centre,
        radiusPoint2: rim,
      );
      construction.add(circle);
      return circle;
    }

    test('it has no centre and radius — and is defined anyway', () {
      final circle = circleIn(hyperbolic);
      expect(circle.circle, isNull, reason: 'a CK circle is not a circle');
      expect(circle.conic, isNotNull);
      expect(circle.isDefined, isTrue);
    });

    test('the Euclidean one still answers the old way', () {
      final circle = circleIn(const DocumentKernel());
      expect(circle.circle, isNotNull);
      expect(circle.isDefined, isTrue);
    });

    test('a degenerate Euclidean circle stays undefined', () {
      // The narrow arm is what keeps Euclidean behaviour bit-identical.
      // Collinear defining points give a degenerate *line-pair* conic,
      // which `ConicShape` calls drawable and `isParameterized` does not
      // — so it goes on reporting itself undefined, exactly as before.
      // (Had the new arm asked `isDrawable`, this would have started
      // painting, and the goldens would have moved.)
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(c);
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      construction.add(circle);
      expect(circle.circle, isNull, reason: 'collinear: no circle');
      expect(circle.conic, isNotNull, reason: 'but a real line-pair conic');
      expect(ConicShape.of(circle.conic!).isDrawable, isTrue);
      expect(circle.isDefined, isFalse);
    });
  });

  group('the view frames the plane the geometry lives in', () {
    // The third: the absolute is the unit circle in *world* units and the
    // default scale is one pixel per world unit, so the whole hyperbolic
    // plane was a two-pixel dot at the origin while the figure sat
    // hundreds of units outside it — outside the plane, where the angles
    // collapse. The mode was present and invisible.
    const size = Size(1000, 700);

    test('hyperbolic frames the unit disc', () {
      final framed = fittedToAbsolute(FundamentalConic.hyperbolic, size)!;
      final viewport = CanvasViewport(framed);
      final centre = viewport.worldToScreen(Vec2.zero);
      final radius = viewport.worldToScreenLength(1);
      // Centred, and as large as the short side allows with the margin.
      expect(centre.dx, closeTo(size.width / 2, 1e-9));
      expect(centre.dy, closeTo(size.height / 2, 1e-9));
      expect(radius * 2, closeTo(size.height - 2 * fitMarginPx, 1e-9));
    });

    test('the other two leave the view alone, and that is not laziness', () {
      // Neither has a privileged region: elliptic has no real absolute and
      // no boundary, Euclidean's is the line at infinity. There is nothing
      // to frame, so moving the view would be arbitrary.
      expect(fittedToAbsolute(FundamentalConic.euclidean, size), isNull);
      expect(fittedToAbsolute(FundamentalConic.elliptic, size), isNull);
    });

    test('the disc may zoom past what a fit is allowed to', () {
      // The two ceilings answer different questions (see
      // `CanvasViewport.maxFitScale`): a fit must not blow a small figure
      // up to fill the window, but the absolute is not a small figure —
      // it is the whole plane, and at the fit ceiling of 50 it would be
      // 100 pixels across and unusable.
      final framed = fittedToAbsolute(FundamentalConic.hyperbolic, size)!;
      expect(framed.scale, greaterThan(CanvasViewport.maxFitScale));
      expect(framed.scale, lessThanOrEqualTo(CanvasViewport.maxScale));
    });

    test('a canvas smaller than its own margins frames nothing', () {
      expect(
        fittedToAbsolute(FundamentalConic.hyperbolic, const Size(40, 40)),
        isNull,
      );
    });

    test('framing keeps the view angle, like every other fit', () {
      final framed = fittedToAbsolute(
        FundamentalConic.hyperbolic,
        size,
        rotation: 0.6,
      )!;
      expect(framed.rotation, 0.6);
      // A circle stays a circle under rotation, so the disc still fits.
      final viewport = CanvasViewport(framed);
      expect(
        (viewport.worldToScreen(const Vec2(0, 1)) -
                viewport.worldToScreen(Vec2.zero))
            .distance,
        closeTo(viewport.worldToScreenLength(1), 1e-9),
      );
    });
  });

  group('the region outside the plane is visibly outside', () {
    // Reported after 126b's first pass: "the hyperbolic circle has the
    // same background colour as the outer space". The wash was being
    // drawn, in the right shape — it was one alpha of 0.09 applied to the
    // absolute's colour, which measures a 5 % luminance step over the
    // light canvas. Correct and invisible are different things.
    //
    // The fix is a per-theme colour rather than a bigger shared alpha:
    // the two canvases start from opposite ends, so the same alpha that
    // is barely a tint over white is a large lift over near-black.
    const size = Size(400, 300);

    /// Relative luminance, sRGB-encoded — good enough to compare two
    /// washes of one hue, which is all this is for.
    double luminance(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

    Future<double> step(Color background, Color wash) async {
      final construction = Construction(kernel: hyperbolic);
      construction.add(FreePoint(id: 'a', position: const Vec2(0.1, 0.1)));
      final state = fittedToAbsolute(FundamentalConic.hyperbolic, size)!;
      final image = await renderConstructionImage(
        construction,
        viewport: state,
        logicalSize: size,
        background: background,
        absoluteOutsideColor: wash,
        defaultColor: const Color(0xFF000000),
      );
      final view = CanvasViewport(state);
      final centre = view.worldToScreen(Vec2.zero);
      final radius = view.worldToScreenLength(1);
      final data = (await image.toByteData())!;
      Color at(int x, int y) {
        final o = (y * image.width + x) * 4;
        return Color.fromARGB(
          data.getUint8(o + 3),
          data.getUint8(o),
          data.getUint8(o + 1),
          data.getUint8(o + 2),
        );
      }

      final inside = at(centre.dx.round(), centre.dy.round());
      final outside = at((centre.dx + radius * 1.2).round(), centre.dy.round());
      image.dispose();
      return (luminance(inside) - luminance(outside)).abs();
    }

    test('the light canvas separates inside from outside', () async {
      final theme = AppTheme.light().extension<CanvasColors>()!;
      expect(
        await step(const Color(0xFFFFFFFF), theme.absoluteOutside),
        greaterThan(0.10),
      );
    });

    test('and so does the dark one, at its own alpha', () async {
      final theme = AppTheme.dark().extension<CanvasColors>()!;
      expect(
        await step(const Color(0xFF14181D), theme.absoluteOutside),
        greaterThan(0.06),
      );
    });

    test('the old single alpha would not have passed either', () async {
      // The regression itself, kept as a case: 0.09 of the absolute's
      // colour is what shipped, and it is what "the same background
      // colour" looked like.
      expect(
        await step(
          const Color(0xFFFFFFFF),
          const Color(0xFFB26A00).withValues(alpha: 0.09),
        ),
        lessThan(0.06),
      );
    });
  });
}
