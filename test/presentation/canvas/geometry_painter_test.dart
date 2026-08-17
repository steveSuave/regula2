import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';

import '../../projective_stubs.dart';

/// Pixel-accurate rendering is Phase 12's golden tests; here we assert
/// the painter accepts every current object kind — including undefined
/// and invisible ones — without throwing.
void main() {
  GeometryPainter painterFor(
    Construction construction, {
    int revision = 0,
    Set<String> selectedIds = const {},
    Set<String> previewObjectIds = const {},
    bool showHidden = false,
    bool showAxes = false,
    bool showGrid = false,
    CanvasViewport viewport = const CanvasViewport(ViewportState()),
  }) => GeometryPainter(
    construction: construction,
    viewport: viewport,
    revision: revision,
    defaultColor: const Color(0xFF000000),
    selectionColor: const Color(0xFF0000FF),
    selectedIds: selectedIds,
    previewObjectIds: previewObjectIds,
    showHidden: showHidden,
    showAxes: showAxes,
    showGrid: showGrid,
  );

  void paintOnce(GeometryPainter painter) {
    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), const Size(800, 600));
    recorder.endRecording();
  }

  group('GeometryPainter', () {
    test('paints every object kind without throwing', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(Midpoint(id: 'm', point1: a, point2: b))
        ..add(Segment(id: 's', point1: a, point2: b))
        ..add(Ray(id: 'r', origin: a, through: c))
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: c))
        ..add(CircleCenterPoint(id: 'k', center: a, onCircle: b))
        ..add(Arc(id: 'arc', start: b, via: c, end: a))
        ..add(Sector(id: 'w', center: a, start: b, end: c))
        ..add(VertexAngle(id: 'g', arm1: b, vertex: a, arm2: c));
      final circle = construction.byId('k')!;
      final driver = PointOnObject(id: 'drv', curve: circle, parameter: 0);
      final traced = Midpoint(id: 'tr', point1: driver, point2: c);
      construction
        ..add(driver)
        ..add(traced)
        ..add(
          Locus(id: 'loc', driver: driver, traced: traced, sampleCount: 16),
        );

      paintOnce(painterFor(construction));
    });

    test('skips undefined and invisible objects without throwing', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      construction
        ..add(a)
        ..add(b)
        // Undefined: line through coincident points.
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(
          FreePoint(
            id: 'h',
            position: const Vec2(1, 1),
            attributes: const ObjectAttributes(visible: false),
          ),
        );

      paintOnce(painterFor(construction));
    });

    test('paints labels on named objects without throwing', () {
      const named = ObjectAttributes(name: 'A');
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero, attributes: named);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(Segment(id: 's', point1: a, point2: b, attributes: named))
        ..add(Ray(id: 'r', origin: a, through: c, attributes: named))
        ..add(
          LineThroughTwoPoints(
            id: 'l',
            point1: a,
            point2: c,
            attributes: named,
          ),
        )
        ..add(
          CircleCenterPoint(id: 'k', center: a, onCircle: b, attributes: named),
        )
        ..add(Arc(id: 'arc', start: b, via: c, end: a, attributes: named))
        ..add(Sector(id: 'w', center: a, start: b, end: c, attributes: named))
        ..add(
          VertexAngle(id: 'g', arm1: b, vertex: a, arm2: c, attributes: named),
        )
        // labelVisible off: name present but no label painted.
        ..add(
          FreePoint(
            id: 'q',
            position: const Vec2(1, 1),
            attributes: const ObjectAttributes(name: 'Q', labelVisible: false),
          ),
        );

      paintOnce(painterFor(construction));
    });

    test('paints preview markers without throwing', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));
      final painter = GeometryPainter(
        construction: construction,
        viewport: const CanvasViewport(ViewportState()),
        revision: 0,
        defaultColor: const Color(0xFF000000),
        selectionColor: const Color(0xFF0000FF),
        previewMarkers: const [Vec2.zero, Vec2(3, 4)],
      );

      paintOnce(painter);
    });

    test('paints selection halos on every object kind without throwing', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(Segment(id: 's', point1: a, point2: b))
        ..add(Ray(id: 'r', origin: a, through: c))
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: c))
        ..add(CircleCenterPoint(id: 'k', center: a, onCircle: b))
        ..add(Arc(id: 'arc', start: b, via: c, end: a))
        ..add(Sector(id: 'w', center: a, start: b, end: c))
        ..add(VertexAngle(id: 'g', arm1: b, vertex: a, arm2: c));

      final everything = {for (final object in construction.objects) object.id};
      paintOnce(painterFor(construction, selectedIds: everything));
    });

    test('paints tool-input halos without throwing', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b));

      paintOnce(painterFor(construction, previewObjectIds: const {'s', 'a'}));
    });

    test('showHidden paints dimmed hidden objects without throwing', () {
      const hidden = ObjectAttributes(visible: false);
      const hiddenNamed = ObjectAttributes(visible: false, name: 'S');
      const hiddenFilled = ObjectAttributes(
        visible: false,
        fillAlpha: 0.25,
        name: 'W',
      );
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero, attributes: hidden);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(Segment(id: 's', point1: a, point2: b, attributes: hiddenNamed))
        ..add(
          Sector(
            id: 'w',
            center: a,
            start: b,
            end: c,
            attributes: hiddenFilled,
          ),
        );

      // Dimmed halo too: hiding keeps the selection.
      paintOnce(
        painterFor(
          construction,
          showHidden: true,
          selectedIds: const {'a', 's'},
        ),
      );
    });

    test('paints axes and grid at any viewport without throwing', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      // Origin on-screen, off-screen (labels ride the axes), zoomed to
      // both clamp ends, and each toggle alone.
      for (final state in const [
        ViewportState(pan: Vec2(-5, 5), scale: 40),
        ViewportState(pan: Vec2(1000, 1000), scale: 1),
        ViewportState(scale: 0.05),
        ViewportState(scale: 50),
      ]) {
        paintOnce(
          painterFor(
            construction,
            showAxes: true,
            showGrid: true,
            viewport: CanvasViewport(state),
          ),
        );
      }
      paintOnce(painterFor(construction, showAxes: true));
      paintOnce(painterFor(construction, showGrid: true));
    });

    test('paints huge-screen-radius circles, arcs and sectors without '
        'throwing', () {
      // World radius 10000 at scale 50 → 500k px on screen, far past
      // largeRadiusThreshold: the sampled-polyline fallback runs. Dashed
      // + filled + selected + named exercises every branch of it.
      const styled = ObjectAttributes(name: 'k', fillAlpha: 0.2, dashPeriod: 8);
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(10000, 0));
      final c = FreePoint(id: 'c', position: const Vec2(0, 10000));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(
          CircleCenterPoint(
            id: 'k',
            center: a,
            onCircle: b,
            attributes: styled,
          ),
        )
        ..add(Arc(id: 'arc', start: b, via: c, end: a))
        ..add(
          Sector(
            id: 'w',
            center: a,
            start: b,
            end: c,
            attributes: const ObjectAttributes(fillAlpha: 0.2),
          ),
        );

      for (final pan in const [
        Vec2(9990, 3), // rim crosses the canvas
        Vec2(5000, 0), // viewport deep inside the disc
        Vec2(30000, 0), // circle fully off screen
        Vec2.zero, // center on canvas, rim far away
      ]) {
        paintOnce(
          painterFor(
            construction,
            selectedIds: const {'k', 'arc', 'w'},
            viewport: CanvasViewport(ViewportState(pan: pan, scale: 50)),
          ),
        );
      }
    });

    test('shouldRepaint keys on showAxes and showGrid', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      final base = painterFor(construction);
      expect(
        painterFor(construction, showAxes: true).shouldRepaint(base),
        isTrue,
      );
      expect(
        painterFor(construction, showGrid: true).shouldRepaint(base),
        isTrue,
      );
      expect(painterFor(construction).shouldRepaint(base), isFalse);
    });

    test('shouldRepaint keys on showHidden', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      final base = painterFor(construction);
      expect(
        painterFor(construction, showHidden: true).shouldRepaint(base),
        isTrue,
        reason: 'activating Show/Hide must dim hidden objects in',
      );
      expect(painterFor(construction).shouldRepaint(base), isFalse);
    });

    test('shouldRepaint keys on preview markers', () {
      final construction = Construction();
      GeometryPainter withMarkers(List<Vec2> markers) => GeometryPainter(
        construction: construction,
        viewport: const CanvasViewport(ViewportState()),
        revision: 0,
        defaultColor: const Color(0xFF000000),
        selectionColor: const Color(0xFF0000FF),
        previewMarkers: markers,
      );

      final base = withMarkers(const [Vec2(1, 1)]);
      expect(withMarkers(const [Vec2(1, 1)]).shouldRepaint(base), isFalse);
      expect(
        withMarkers(const [Vec2(1, 1), Vec2(2, 2)]).shouldRepaint(base),
        isTrue,
      );
      expect(
        withMarkers(const []).shouldRepaint(base),
        isTrue,
        reason: 'markers must clear on commit/reset',
      );
    });

    test('shouldRepaint keys on construction instance, revision and '
        'viewport state', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      final base = painterFor(construction);
      expect(base.shouldRepaint(painterFor(construction)), isFalse);
      expect(painterFor(construction, revision: 1).shouldRepaint(base), isTrue);
      expect(
        painterFor(Construction()).shouldRepaint(base),
        isTrue,
        reason:
            'replace() swaps the construction but resets the revision '
            'to 0 — the instance change alone must trigger a repaint',
      );

      final panned = GeometryPainter(
        construction: construction,
        viewport: const CanvasViewport(ViewportState(pan: Vec2(1, 0))),
        revision: 0,
        defaultColor: const Color(0xFF000000),
        selectionColor: const Color(0xFF0000FF),
      );
      expect(panned.shouldRepaint(base), isTrue);
    });

    test('shouldRepaint keys on the preview-object-id set', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      final base = painterFor(construction, previewObjectIds: const {'a'});
      expect(
        painterFor(
          construction,
          previewObjectIds: const {'a'},
        ).shouldRepaint(base),
        isFalse,
        reason: 'set equality, not identity — the canvas rebuilds sets',
      );
      expect(
        painterFor(construction).shouldRepaint(base),
        isTrue,
        reason: 'the halo must clear on commit/reset',
      );
    });

    test('shouldRepaint keys on the selected-id set', () {
      final construction = Construction()
        ..add(FreePoint(id: 'a', position: Vec2.zero));

      final base = painterFor(construction, selectedIds: const {'a'});
      expect(
        painterFor(construction, selectedIds: const {'a'}).shouldRepaint(base),
        isFalse,
        reason: 'set equality, not identity — the provider rebuilds sets',
      );
      expect(
        painterFor(construction).shouldRepaint(base),
        isTrue,
        reason: 'clearing the selection must drop the halo',
      );
      expect(
        painterFor(construction, selectedIds: const {'b'}).shouldRepaint(base),
        isTrue,
      );
    });

    group('locus paths (Phase 39)', () {
      test('one path per multi-sample run; isolated samples draw nothing', () {
        final construction = Construction()
          ..add(
            _StubLocus(
              id: 'loc',
              samples: const [
                Vec2(0, 0), Vec2(2, 0), null, Vec2(4, 0), // isolated
                null, Vec2(6, 0), Vec2(8, 0), Vec2(8, 2), //
              ],
            ),
          );
        final canvas = _PathRecordingCanvas();
        painterFor(construction).paint(canvas, const Size(800, 600));
        expect(
          canvas.paths,
          hasLength(2),
          reason: 'two runs of ≥ 2 samples; the lone sample is skipped',
        );
        for (final path in canvas.paths) {
          expect(path.computeMetrics().single.isClosed, isFalse);
        }
      });

      test('an all-gap locus paints no path', () {
        final construction = Construction()
          ..add(_StubLocus(id: 'loc', samples: const [null, null, null]));
        final canvas = _PathRecordingCanvas();
        painterFor(construction).paint(canvas, const Size(800, 600));
        expect(canvas.paths, isEmpty);
      });

      test('a gapless circle-host locus closes into one loop', () {
        final construction = Construction();
        final center = FreePoint(id: 'o', position: Vec2.zero);
        final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
        final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
        final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
        final p = FreePoint(id: 'p', position: const Vec2(4, 0));
        final traced = Midpoint(id: 'tr', point1: driver, point2: p);
        construction
          ..add(center)
          ..add(rim)
          ..add(host)
          ..add(driver)
          ..add(p)
          ..add(traced)
          ..add(
            Locus(id: 'loc', driver: driver, traced: traced, sampleCount: 16),
          );
        final canvas = _PathRecordingCanvas();
        painterFor(construction).paint(canvas, const Size(800, 600));
        // Everything else in the scene strokes via drawLine/drawCircle,
        // so the recorded path is the locus polyline alone.
        expect(canvas.paths, hasLength(1));
        expect(
          canvas.paths.single.computeMetrics().single.isClosed,
          isTrue,
          reason: 'no gaps and a circle host: the loop closes',
        );
      });
    });

    group('conic strokes (Phase 119)', () {
      // Origin at the canvas centre, one screen px per world unit.
      const centred = CanvasViewport(ViewportState(pan: Vec2(-400, 300)));
      const size = Size(800, 600);

      List<Path> pathsFor(ConicMatrix conic, {double dashPeriod = 0}) {
        final construction = Construction()
          ..add(
            StubProjectiveConic(conic, id: 'k')
              ..attributes = ObjectAttributes(dashPeriod: dashPeriod),
          );
        final canvas = _PathRecordingCanvas();
        painterFor(construction, viewport: centred).paint(canvas, size);
        return canvas.paths;
      }

      test('an ellipse strokes one closed path', () {
        // x²/100² + y²/50² = 1 — comfortably inside the 800×600 canvas.
        final paths = pathsFor(
          ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
        );
        expect(paths, hasLength(1));
        final metrics = paths.single.computeMetrics().toList();
        expect(metrics.single.isClosed, isTrue);
        final bounds = paths.single.getBounds();
        // Screen bounds: 200 px wide (x semi-axis 100), 100 px tall.
        expect(bounds.width, closeTo(200, 1));
        expect(bounds.height, closeTo(100, 1));
        expect(bounds.center.dx, closeTo(400, 1));
        expect(bounds.center.dy, closeTo(300, 1));
      });

      test('a hyperbola strokes one open path per branch', () {
        // x²/100² − y²/100² = 1: both arms cross the canvas.
        final paths = pathsFor(
          ConicMatrix.coefficients(1 / 10000, 0, -1 / 10000, 0, 0, -1),
        );
        expect(paths, hasLength(2));
        for (final path in paths) {
          expect(path.computeMetrics().single.isClosed, isFalse);
        }
        final centres = paths.map((p) => p.getBounds().center.dx).toList()
          ..sort();
        expect(centres.first, lessThan(400), reason: 'the left branch');
        expect(centres.last, greaterThan(400), reason: 'the right branch');
      });

      test('a parabola strokes one open path', () {
        // y² = 200x, opening right from the origin.
        final paths = pathsFor(ConicMatrix.coefficients(0, 0, 1, -200, 0, 0));
        expect(paths, hasLength(1));
        expect(paths.single.computeMetrics().single.isClosed, isFalse);
      });

      test('a degenerate conic strokes its line pair', () {
        // y = ±x, both diagonals of the canvas.
        final paths = pathsFor(ConicMatrix.coefficients(1, 0, -1, 0, 0, 0));
        expect(paths, hasLength(2));
        for (final path in paths) {
          expect(path.computeMetrics().single.isClosed, isFalse);
        }
      });

      test('a circle-shaped conic keeps the circle arm', () {
        // Same object, but the conic projects to a centre and radius — it
        // must still go through drawCircle, so circle goldens cannot move.
        expect(
          pathsFor(ConicMatrix.coefficients(1, 0, 1, 0, 0, -10000)),
          isEmpty,
        );
      });

      test('a conic entirely off-screen strokes nothing', () {
        // (x − 10000)²/10² + y²/5² = 1 — a small ellipse (not a circle, so
        // it takes the conic arm) a long way past the canvas edge.
        final paths = pathsFor(
          ConicMatrix.coefficients(1, 0, 4, -20000, 0, 1e8 - 100),
        );
        expect(paths, isEmpty);
      });

      test('a conic with no real ink is never painted', () {
        // x² + y² + 1 = 0 — `isDefined` is false, so the paint loop skips
        // it before the arm is reached.
        final conic = ConicMatrix.coefficients(1, 0, 1, 0, 0, 1);
        expect(StubProjectiveConic(conic).isDefined, isFalse);
        expect(pathsFor(conic), isEmpty);
      });

      test('dashes apply to conic strokes', () {
        final solid = pathsFor(
          ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
        );
        final dashed = pathsFor(
          ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
          dashPeriod: 8,
        );
        expect(dashed, hasLength(1));
        expect(
          dashed.single.computeMetrics().length,
          greaterThan(solid.single.computeMetrics().length),
          reason: 'a dashed stroke is many subpaths',
        );
      });

      test('a fill attribute on a conic paints nothing extra (Phase 120)', () {
        // A conic bounds nothing the painter can close, so the fill pass
        // skips it — and, before Phase 120, unwrapped a null `circle` and
        // crashed the frame the moment a user ticked Fill on one. The
        // inspector withholds the row to match.
        final plain = pathsFor(
          ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
        );
        final construction = Construction()
          ..add(
            StubProjectiveConic(
              ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
              id: 'k',
            )..attributes = const ObjectAttributes(fillAlpha: 0.25),
          );
        final canvas = _PathRecordingCanvas();
        painterFor(construction, viewport: centred).paint(canvas, size);
        expect(canvas.paths, hasLength(plain.length));
      });

      test('a selected conic strokes twice — halo, then stroke', () {
        final construction = Construction()
          ..add(
            StubProjectiveConic(
              ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
              id: 'k',
            ),
          );
        final canvas = _PathRecordingCanvas();
        painterFor(
          construction,
          viewport: centred,
          selectedIds: {'k'},
        ).paint(canvas, size);
        expect(canvas.paths, hasLength(2));
      });

      test('zooming out does not multiply the sample count', () {
        // Flatness is a screen-space budget, so a smaller on-screen conic
        // is a cheaper polyline, never a denser one.
        final near = pathsFor(
          ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
        );
        final construction = Construction()
          ..add(
            StubProjectiveConic(
              ConicMatrix.coefficients(1 / 10000, 0, 1 / 2500, 0, 0, -1),
              id: 'k',
            ),
          );
        final canvas = _PathRecordingCanvas();
        painterFor(
          construction,
          viewport: const CanvasViewport(
            ViewportState(pan: Vec2(-4000, 3000), scale: 0.1),
          ),
        ).paint(canvas, size);
        expect(
          canvas.paths.single.computeMetrics().single.length,
          lessThan(near.single.computeMetrics().single.length),
        );
      });
    });

    group('line clipping (Phase 44)', () {
      const size = Size(800, 600);
      const viewport = CanvasViewport(ViewportState());

      (Construction, LineThroughTwoPoints) lineScene(int lineClip) {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(40, 0));
        final line = LineThroughTwoPoints(
          id: 'l',
          point1: a,
          point2: b,
          attributes: ObjectAttributes(lineClip: lineClip),
        );
        construction
          ..add(a)
          ..add(b)
          ..add(line);
        return (construction, line);
      }

      test('a mode-1 line strokes exactly its defining pair', () {
        final (construction, _) = lineScene(1);
        final canvas = _LineRecordingCanvas();
        painterFor(construction).paint(canvas, size);
        expect(canvas.lines, hasLength(1));
        final (p1, p2) = canvas.lines.single;
        expect(
          {p1, p2},
          {
            viewport.worldToScreen(Vec2.zero),
            viewport.worldToScreen(const Vec2(40, 0)),
          },
        );
      });

      test('a mode-2 line strokes to the outermost incident point', () {
        final (construction, line) = lineScene(2);
        construction.add(
          PointOnObject.near(id: 'g', curve: line, position: const Vec2(70, 0)),
        );
        final canvas = _LineRecordingCanvas();
        painterFor(construction).paint(canvas, size);
        expect(canvas.lines, hasLength(1));
        final (p1, p2) = canvas.lines.single;
        expect(
          {p1, p2},
          {
            viewport.worldToScreen(Vec2.zero),
            viewport.worldToScreen(const Vec2(70, 0)),
          },
        );
      });

      test('a mode-0 line keeps the far-overdraw stroke', () {
        final (construction, _) = lineScene(0);
        final canvas = _LineRecordingCanvas();
        painterFor(construction).paint(canvas, size);
        expect(canvas.lines, hasLength(1));
        final (p1, p2) = canvas.lines.single;
        expect(
          (p1 - p2).distance,
          greaterThan(size.width + size.height),
          reason: 'unclipped: drawn far past the canvas on both sides',
        );
      });

      test('a mode-2 ray clamps its far end at the through point', () {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(40, 0));
        construction
          ..add(a)
          ..add(b)
          ..add(
            Ray(
              id: 'r',
              origin: a,
              through: b,
              attributes: const ObjectAttributes(lineClip: 2),
            ),
          );
        final canvas = _LineRecordingCanvas();
        painterFor(construction).paint(canvas, size);
        expect(canvas.lines, hasLength(1));
        final (p1, p2) = canvas.lines.single;
        expect(
          {p1, p2},
          {
            viewport.worldToScreen(Vec2.zero),
            viewport.worldToScreen(const Vec2(40, 0)),
          },
        );
      });
    });

    group('equal-mark ticks (Phase 51)', () {
      const size = Size(800, 600);
      const viewport = CanvasViewport(ViewportState());

      Construction segmentScene(int tickMarks, {Vec2 end = const Vec2(40, 0)}) {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: end);
        construction
          ..add(a)
          ..add(b)
          ..add(
            Segment(
              id: 's',
              point1: a,
              point2: b,
              attributes: ObjectAttributes(tickMarks: tickMarks),
            ),
          );
        return construction;
      }

      test('tickMarks 0 draws the stroke alone', () {
        final canvas = _LineRecordingCanvas();
        painterFor(segmentScene(0)).paint(canvas, size);
        expect(canvas.lines, hasLength(1));
      });

      test('two ticks: perpendicular, centered as a group on the midpoint', () {
        final canvas = _LineRecordingCanvas();
        painterFor(segmentScene(2)).paint(canvas, size);
        expect(canvas.lines, hasLength(3), reason: 'the stroke plus two ticks');
        final stroke = canvas.lines.first;
        final segmentDirection = stroke.$2 - stroke.$1;
        final screenMidpoint = (stroke.$1 + stroke.$2) / 2;
        final ticks = canvas.lines.skip(1);
        final tickCenters = <Offset>[];
        for (final (p1, p2) in ticks) {
          final tick = p2 - p1;
          expect(
            tick.distance,
            closeTo(10, 1e-9),
            reason: 'ticks are 10 logical px long',
          );
          expect(
            tick.dx * segmentDirection.dx + tick.dy * segmentDirection.dy,
            closeTo(0, 1e-6),
            reason: 'ticks are perpendicular to the segment',
          );
          tickCenters.add((p1 + p2) / 2);
        }
        final groupCenter =
            tickCenters.reduce((a, b) => a + b) / tickCenters.length.toDouble();
        expect(
          (groupCenter - screenMidpoint).distance,
          closeTo(0, 1e-6),
          reason: 'the tick group is centered on the segment midpoint',
        );
        expect(
          (tickCenters[0] - tickCenters[1]).distance,
          closeTo(5, 1e-9),
          reason: 'adjacent ticks sit 5 logical px apart',
        );
      });

      test('one tick sits exactly on the midpoint', () {
        final canvas = _LineRecordingCanvas();
        painterFor(segmentScene(1)).paint(canvas, size);
        expect(canvas.lines, hasLength(2));
        final (p1, p2) = canvas.lines.last;
        expect(
          ((p1 + p2) / 2 - viewport.worldToScreen(const Vec2(20, 0))).distance,
          closeTo(0, 1e-6),
        );
      });

      test('a dashed segment still draws solid ticks', () {
        final construction = Construction();
        final a = FreePoint(id: 'a', position: Vec2.zero);
        final b = FreePoint(id: 'b', position: const Vec2(40, 0));
        construction
          ..add(a)
          ..add(b)
          ..add(
            Segment(
              id: 's',
              point1: a,
              point2: b,
              attributes: const ObjectAttributes(tickMarks: 3, dashPeriod: 8),
            ),
          );
        final canvas = _LineRecordingCanvas();
        painterFor(construction).paint(canvas, size);
        // The dashed stroke goes through drawPath, so drawLine records
        // the ticks alone.
        expect(canvas.lines, hasLength(3));
      });

      test('a degenerate segment draws no ticks', () {
        final canvas = _LineRecordingCanvas();
        painterFor(segmentScene(3, end: Vec2.zero)).paint(canvas, size);
        expect(
          canvas.lines,
          isEmpty,
          reason:
              'a coincident-endpoint segment paints nothing — and '
              'the tick guard must not divide by its zero length',
        );
      });
    });
  });

  /// Phase 126: the fundamental conic of a non-Euclidean document.
  group('the absolute', () {
    const viewport = CanvasViewport(ViewportState(scale: 120));
    const size = Size(800, 600);

    test('only hyperbolic has a real absolute to draw', () {
      // Not three cases of one rule but three different facts. The
      // hyperbolic absolute is the unit circle and bounds the plane; the
      // elliptic one has no real points and bounds nothing, elliptic
      // space having no edge; the Euclidean one is the line at infinity,
      // real but in no chart. Drawing something for either of the last
      // two would be inventing an edge that is not in the geometry.
      expect(absoluteDisc(FundamentalConic.euclidean, viewport), isNull);
      expect(absoluteDisc(FundamentalConic.elliptic, viewport), isNull);
      expect(absoluteDisc(FundamentalConic.hyperbolic, viewport), isNotNull);
    });

    test('it is the unit circle, in world units, at any view state', () {
      for (final state in [
        const ViewportState(scale: 120),
        const ViewportState(scale: 37.5, pan: Vec2(2, -1)),
        const ViewportState(scale: 200, rotation: 0.7),
      ]) {
        final view = CanvasViewport(state);
        final disc = absoluteDisc(FundamentalConic.hyperbolic, view)!;
        expect(disc.radius, closeTo(view.worldToScreenLength(1), 1e-9));
        expect(disc.centre, view.worldToScreen(Vec2.zero));
        // A circle stays a circle under rotation, which is why the
        // painter can take centre and radius from the viewport instead of
        // projecting the conic.
        expect(
          (view.worldToScreen(const Vec2(1, 0)) - disc.centre).distance,
          closeTo(disc.radius, 1e-9),
        );
        expect(
          (view.worldToScreen(const Vec2(0, -1)) - disc.centre).distance,
          closeTo(disc.radius, 1e-9),
        );
      }
    });

    test('a degenerate view draws nothing rather than throwing', () {
      expect(
        absoluteDisc(
          FundamentalConic.hyperbolic,
          const CanvasViewport(ViewportState(scale: 0)),
        ),
        isNull,
      );
    });

    test('a Euclidean document paints exactly what it did before', () {
      // The goldens say this too, byte for byte; this says *why* they
      // still can, at the one call the phase added to `paint`.
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-1, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0.5));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b));
      final canvas = _CircleRecordingCanvas();
      painterFor(construction, viewport: viewport).paint(canvas, size);
      expect(
        canvas.circles.where((c) => c.$2 == viewport.worldToScreenLength(1)),
        isEmpty,
      );
    });

    test('a hyperbolic document strokes it and washes the outside', () {
      final construction = Construction(
        kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
      );
      construction.add(FreePoint(id: 'a', position: const Vec2(0.2, 0.1)));

      final circles = _CircleRecordingCanvas();
      painterFor(construction, viewport: viewport).paint(circles, size);
      final disc = absoluteDisc(FundamentalConic.hyperbolic, viewport)!;
      expect(
        circles.circles.any(
          (c) => c.$1 == disc.centre && (c.$2 - disc.radius).abs() < 1e-9,
        ),
        isTrue,
      );

      // And the wash: the region outside the disc, so a point well beyond
      // the boundary is inside the painted path and one inside the disc
      // is not. That is the whole message — out there is not the plane.
      final paths = _PathRecordingCanvas();
      painterFor(construction, viewport: viewport).paint(paths, size);
      expect(paths.paths, hasLength(1));
      final outside = paths.paths.single;
      expect(
        outside.contains(viewport.worldToScreen(const Vec2(2.5, 0))),
        isTrue,
      );
      expect(
        outside.contains(viewport.worldToScreen(const Vec2(0.3, 0))),
        isFalse,
      );
    });
  });
}

/// A [GeoLocus] with hand-picked samples (cf. the hit-tester's stub):
/// the painter consumes the kind accessor only, so runs and gaps can be
/// spelled out directly.
class _StubLocus extends GeoLocus {
  _StubLocus({required super.id, required List<Vec2?>? samples})
    : _samples = samples;

  final List<Vec2?>? _samples;

  @override
  List<Vec2?>? get samples => _samples;

  @override
  List<GeoObject> get parents => const [];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {}
}

/// Records the paths handed to [drawPath]; every other canvas call is a
/// no-op. Lets tests count polyline runs without decoding a picture.
class _PathRecordingCanvas implements Canvas {
  final List<Path> paths = [];

  @override
  void drawPath(Path path, Paint paint) {
    paths.add(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records the endpoint pairs handed to [drawLine]; every other canvas
/// call is a no-op. Points draw via drawCircle, so in a points-and-lines
/// scene the recorded pairs are the straight strokes alone.
class _LineRecordingCanvas implements Canvas {
  final List<(Offset, Offset)> lines = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add((p1, p2));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records the centre/radius pairs handed to [drawCircle]; every other
/// canvas call is a no-op.
class _CircleRecordingCanvas implements Canvas {
  final List<(Offset, double)> circles = [];

  @override
  void drawCircle(Offset centre, double radius, Paint paint) {
    circles.add((centre, radius));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
