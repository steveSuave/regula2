import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/fit_viewport.dart';

void main() {
  FreePoint point(
    String id,
    double x,
    double y, {
    ObjectAttributes attributes = const ObjectAttributes(),
  }) => FreePoint(id: id, position: Vec2(x, y), attributes: attributes);

  group('visibleWorldBounds', () {
    test('null on nothing, on hidden-only, and on lines-only', () {
      expect(visibleWorldBounds(const []), isNull);
      expect(
        visibleWorldBounds([
          point('h', 1, 2, attributes: const ObjectAttributes(visible: false)),
        ]),
        isNull,
      );
      final a = point(
        'a',
        0,
        0,
        attributes: const ObjectAttributes(visible: false),
      );
      final b = point(
        'b',
        4,
        0,
        attributes: const ObjectAttributes(visible: false),
      );
      expect(
        visibleWorldBounds([
          a,
          b,
          LineThroughTwoPoints(id: 'l', point1: a, point2: b),
        ]),
        isNull,
        reason: 'an unbounded carrier contributes no extent of its own',
      );
    });

    test('points span their extremes; hidden points are skipped', () {
      final bounds = visibleWorldBounds([
        point('a', -3, 2),
        point('b', 5, -7),
        point(
          'h',
          100,
          100,
          attributes: const ObjectAttributes(visible: false),
        ),
      ]);
      expect(bounds, isNotNull);
      expect(bounds!.min, const Vec2(-3, -7));
      expect(bounds.max, const Vec2(5, 2));
    });

    test('a circle contributes its full disc', () {
      final center = point('c', 10, 10);
      final rim = point('r', 13, 10);
      final bounds = visibleWorldBounds([
        center,
        rim,
        CircleCenterPoint(id: 'k', center: center, onCircle: rim),
      ]);
      expect(bounds!.min, const Vec2(7, 7));
      expect(bounds.max, const Vec2(13, 13));
    });

    test('a Cayley–Klein circle contributes its conic\'s box', () {
      // A CK circle is a conic bitangent to the absolute, so it projects
      // to no centre and radius and contributed *nothing* here until
      // Phase 130 — which is why fit-to-construction under-framed a
      // hyperbolic document.
      final construction = Construction(
        kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
      );
      final centre = point('c', 0.2, 0);
      final rim = point('r', 0.5, 0);
      construction
        ..add(centre)
        ..add(rim)
        ..add(CircleCenterPoint(id: 'k', center: centre, onCircle: rim));
      final circle = construction.byId('k')! as GeoCircle;
      expect(circle.isDefined, isTrue);
      expect(
        circle.circle,
        isNull,
        reason: 'no centre-and-radius projection to frame it by',
      );

      expect(visibleWorldBounds([centre, rim]), (
        min: const Vec2(0.2, 0),
        max: const Vec2(0.5, 0),
      ), reason: 'the two points alone frame a segment of the x axis');

      final bounds = visibleWorldBounds(construction.objects)!;
      expect(
        bounds.max.x,
        closeTo(0.5, 1e-9),
        reason: 'the rim point is the rightmost point of the circle',
      );
      // And the leftmost is *not* its mirror at 0.2 − 0.3: equal
      // hyperbolic distance covers less chart distance the closer it
      // runs to the boundary. Along a diameter of the Klein disc the
      // hyperbolic coordinate is artanh(x), so the other end is
      // tanh(2·artanh(0.2) − artanh(0.5)) = −1/7 exactly.
      expect(bounds.min.x, closeTo(-1 / 7, 1e-9));
      expect(
        bounds.max.y,
        closeTo(0.32732683535, 1e-9),
        reason: 'and it reaches off the axis, which neither point reports',
      );
      expect(bounds.min.y, closeTo(-bounds.max.y, 1e-12));
    });

    test('an unbounded conic still contributes nothing', () {
      // `extremesAlong` finds real tangent points on a hyperbola, so the
      // gate is the conic's *class* rather than the arithmetic running
      // out — a box built on them would frame a curve that leaves it.
      final hyperbola = _StubConic(
        ConicMatrix(
          Complex.one,
          Complex.zero,
          Complex(-1),
          Complex.zero,
          Complex.zero,
          Complex(-1),
        ),
      );
      expect(ConicShape.of(hyperbola.conic!).kind, ConicClass.hyperbola);
      expect(visibleWorldBounds([hyperbola]), isNull);
    });

    test('an angle contributes its vertex', () {
      final arm1 = point(
        'a',
        0,
        5,
        attributes: const ObjectAttributes(visible: false),
      );
      final vertex = point(
        'v',
        2,
        3,
        attributes: const ObjectAttributes(visible: false),
      );
      final arm2 = point(
        'b',
        4,
        5,
        attributes: const ObjectAttributes(visible: false),
      );
      final bounds = visibleWorldBounds([
        arm1,
        vertex,
        arm2,
        VertexAngle(id: 'ang', arm1: arm1, vertex: vertex, arm2: arm2),
      ]);
      expect(bounds!.min, const Vec2(2, 3));
      expect(bounds.max, const Vec2(2, 3));
    });
  });

  group('fittedViewport', () {
    const canvas = Size(800, 600);

    test('null when nothing to frame or the canvas has no area', () {
      expect(fittedViewport(const [], canvas), isNull);
      expect(fittedViewport([point('a', 1, 1)], Size.zero), isNull);
    });

    test('centers the extent and scales to the tight axis with margin', () {
      // 100 world units wide, 10 tall: width is the tight constraint.
      final state = fittedViewport([
        point('a', 0, 0),
        point('b', 100, 10),
      ], canvas);
      expect(state, isNotNull);
      expect(state!.scale, closeTo((800 - 2 * fitMarginPx) / 100, 1e-12));

      final viewport = CanvasViewport(state);
      expect(viewport.worldToScreen(const Vec2(50, 5)).dx, closeTo(400, 1e-9));
      expect(viewport.worldToScreen(const Vec2(50, 5)).dy, closeTo(300, 1e-9));
      // Both corners on-canvas, margin respected.
      for (final corner in const [Vec2(0, 0), Vec2(100, 10)]) {
        final screen = viewport.worldToScreen(corner);
        expect(
          screen.dx,
          inInclusiveRange(fitMarginPx - 1e-9, 800 - fitMarginPx + 1e-9),
        );
        expect(screen.dy, inInclusiveRange(0, 600));
      }
    });

    test('a single point centers at 100 % instead of zooming to the clamp', () {
      final state = fittedViewport([point('a', 40, -20)], canvas)!;
      expect(state.scale, 1);
      expect(
        CanvasViewport(state).worldToScreen(const Vec2(40, -20)),
        const Offset(400, 300),
      );
    });

    test('scale clamps at both extremes', () {
      final vast = fittedViewport([
        point('a', 0, 0),
        point('b', 1e9, 0),
      ], canvas)!;
      expect(vast.scale, CanvasViewport.minScale);

      final microscopic = fittedViewport([
        point('a', 0, 0),
        point('b', 1e-9, 0),
      ], canvas)!;
      // The *fit* ceiling, which stopped being the same number as the
      // zoom ceiling in Phase 126b: a hyperbolic document needs to zoom
      // far past what a fit should ever blow a small figure up to.
      expect(microscopic.scale, CanvasViewport.maxFitScale);
    });

    test('a rotated fit keeps the angle and scales to the rotated '
        'extents (Phase 61)', () {
      // A world-horizontal pair stands vertical on screen at θ = π/2,
      // so the fit must scale by the canvas *height*, not width.
      final state = fittedViewport(
        [point('a', 0, 0), point('b', 100, 0)],
        canvas,
        rotation: math.pi / 2,
      )!;
      expect(state.rotation, math.pi / 2);
      expect(state.scale, closeTo((600 - 2 * fitMarginPx) / 100, 1e-12));

      final viewport = CanvasViewport(state);
      final a = viewport.worldToScreen(const Vec2(0, 0));
      final b = viewport.worldToScreen(const Vec2(100, 0));
      expect(
        (a + b) / 2,
        offsetMoreOrLessEquals(const Offset(400, 300), epsilon: 1e-6),
      );
      for (final screen in [a, b]) {
        expect(
          screen.dx,
          inInclusiveRange(fitMarginPx - 1e-9, 800 - fitMarginPx + 1e-9),
        );
        expect(
          screen.dy,
          inInclusiveRange(fitMarginPx - 1e-9, 600 - fitMarginPx + 1e-9),
        );
      }
    });

    test('an arbitrary view angle centers the framed extremes', () {
      final state = fittedViewport(
        [point('a', -30, 10), point('b', 50, -25)],
        canvas,
        rotation: 0.7,
      )!;
      expect(state.rotation, 0.7);
      final viewport = CanvasViewport(state);
      final a = viewport.worldToScreen(const Vec2(-30, 10));
      final b = viewport.worldToScreen(const Vec2(50, -25));
      // Two points span the view-frame box, so their screen midpoint is
      // the box center — pinned to the canvas center at any angle.
      expect(
        (a + b) / 2,
        offsetMoreOrLessEquals(const Offset(400, 300), epsilon: 1e-6),
      );
      for (final screen in [a, b]) {
        expect(
          screen.dx,
          inInclusiveRange(fitMarginPx - 1e-9, 800 - fitMarginPx + 1e-9),
        );
        expect(
          screen.dy,
          inInclusiveRange(fitMarginPx - 1e-9, 600 - fitMarginPx + 1e-9),
        );
      }
    });

    test('a rotated disc stays tightly framed — the box rotates as '
        'center ± radius', () {
      // A lone disc's view-frame box is 60 × 60 at any angle; rotating
      // box *corners* instead would break this scale.
      final center = point(
        'c',
        10,
        10,
        attributes: const ObjectAttributes(visible: false),
      );
      final rim = point(
        'r',
        40,
        10,
        attributes: const ObjectAttributes(visible: false),
      );
      final state = fittedViewport(
        [
          center,
          rim,
          CircleCenterPoint(id: 'k', center: center, onCircle: rim),
        ],
        canvas,
        rotation: 0.7,
      )!;
      expect(state.scale, closeTo((600 - 2 * fitMarginPx) / 60, 1e-12));
      expect(
        CanvasViewport(state).worldToScreen(const Vec2(10, 10)),
        offsetMoreOrLessEquals(const Offset(400, 300), epsilon: 1e-6),
      );
    });

    test('a locus contributes its core samples, not its diverging arms '
        '(Phase 39f)', () {
      // A projective line-host sweep carries diverging arms to
      // astronomically far positions; fitting on the full trace would
      // shrink the figure to a dot.
      final bounds = visibleWorldBounds([
        _StubLocus(
          id: 'loc',
          samples: const [Vec2(-1e6, 1e5), Vec2(0, 0), Vec2(1e6, 1e5)],
          coreSamples: const [Vec2(0, 0), Vec2(4, 2)],
        ),
      ])!;
      expect(bounds.min, const Vec2(0, 0));
      expect(bounds.max, const Vec2(4, 2));
    });
  });
}

/// A [GeoLocus] with hand-picked samples and core samples (cf. the
/// painter's stub): fit consumes the kind accessors only.
class _StubLocus extends GeoLocus {
  _StubLocus({
    required super.id,
    required this._samples,
    required this._coreSamples,
  });

  final List<Vec2?>? _samples;
  final List<Vec2> _coreSamples;

  @override
  List<Vec2?>? get samples => _samples;

  @override
  List<Vec2>? get coreSamples => _coreSamples;

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {}
}

/// A conic-valued object with no chart circle — enough of a [GeoCircle]
/// for `visibleWorldBounds` to ask it the one question it asks.
class _StubConic extends GeoCircle {
  _StubConic(this._conic) : super(id: 'stub');

  final ConicMatrix _conic;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => null;

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {}
}
