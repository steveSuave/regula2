@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/incenter.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/length_measurement.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/presentation/canvas/canvas_viewport.dart';
import 'package:regula/presentation/canvas/fit_viewport.dart';
import 'package:regula/presentation/canvas/geometry_painter.dart';
import 'package:regula/presentation/theme/app_theme.dart';

/// Pixel goldens for every concrete object kind, light + dark — one scene
/// per sealed kind plus a decorations scene (labels, custom attributes,
/// selection halos, preview markers).
///
/// Goldens are rendered with the test framework's default font (Ahem), so
/// labels appear as solid boxes: position and metrics are locked, glyph
/// shapes are not. Regenerate on macOS with
/// `flutter test --update-goldens --tags golden`; CI excludes the tag.
void main() {
  const hidden = ObjectAttributes(visible: false);
  const canvasSize = Size(640, 480);
  const sceneKey = ValueKey('golden-scene');

  Future<void> expectSceneGolden(
    WidgetTester tester, {
    required Construction construction,
    required ThemeData theme,
    required String golden,
    Set<String> selectedIds = const {},
    List<Vec2> previewMarkers = const [],
    bool showAxes = false,
    bool showGrid = false,
    ViewportState? viewport,
  }) async {
    final viewportState =
        viewport ??
        fittedViewport(construction.objects, canvasSize) ??
        const ViewportState();
    final canvasColors = theme.extension<CanvasColors>()!;
    final painter = GeometryPainter(
      construction: construction,
      viewport: CanvasViewport(viewportState),
      revision: 0,
      defaultColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.tertiary,
      selectedIds: selectedIds,
      previewMarkers: previewMarkers,
      showAxes: showAxes,
      showGrid: showGrid,
      axisColor: canvasColors.axis,
      gridColor: canvasColors.grid,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: sceneKey,
              // The real canvas paints over the scaffold; the golden's
              // boundary needs its own background to capture that surface.
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: SizedBox.fromSize(
                  size: canvasSize,
                  child: CustomPaint(painter: painter),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(sceneKey),
      matchesGoldenFile('goldens/$golden.png'),
    );
  }

  /// Every point kind: three visible free points spanning a triangle, the
  /// derived points over them, and hidden scaffolding (an extra free
  /// point, two lines, a circle) for the kinds that need curve parents.
  Construction pointsScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(8, 0));
    final c = FreePoint(id: 'c', position: const Vec2(2, 6));
    final d = FreePoint(
      id: 'd',
      position: const Vec2(8, 4),
      attributes: hidden,
    );
    final lineAd = LineThroughTwoPoints(
      id: 'lad',
      point1: a,
      point2: d,
      attributes: hidden,
    );
    final lineBc = LineThroughTwoPoints(
      id: 'lbc',
      point1: b,
      point2: c,
      attributes: hidden,
    );
    final circle = CircleCenterPoint(
      id: 'k',
      center: d,
      onCircle: b,
      attributes: hidden,
    );
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(d)
      ..add(lineAd)
      ..add(lineBc)
      ..add(circle)
      ..add(Midpoint(id: 'm', point1: a, point2: b))
      ..add(SegmentRatioPoint(id: 'sr', point1: a, point2: c, ratio: 0.75))
      ..add(Centroid(id: 'ce', vertex1: a, vertex2: b, vertex3: c))
      ..add(Orthocenter(id: 'or', vertex1: a, vertex2: b, vertex3: c))
      ..add(Incenter(id: 'ic', vertex1: a, vertex2: b, vertex3: c))
      ..add(Circumcenter(id: 'cc', vertex1: a, vertex2: b, vertex3: c))
      ..add(
        IntersectionPoint(
          id: 'x',
          curve1: lineAd,
          curve2: lineBc,
          branchIndex: 0,
        ),
      )
      ..add(PointOnObject(id: 'po', curve: circle, parameter: 0.7));
    return construction;
  }

  /// Every line kind over three visible anchor points.
  Construction linesScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(6, 0));
    final c = FreePoint(id: 'c', position: const Vec2(1, 4));
    final segment = Segment(id: 's', point1: a, point2: b);
    final ray = Ray(id: 'r', origin: a, through: c);
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(segment)
      ..add(ray)
      ..add(LineThroughTwoPoints(id: 'l', point1: b, point2: c))
      ..add(PerpendicularLine(id: 'pp', through: c, reference: segment))
      ..add(ParallelLine(id: 'pl', through: b, reference: ray))
      ..add(AngleBisectorLine(id: 'ab', arm1: b, vertex: a, arm2: c));
    return construction;
  }

  /// Every circle kind, spread out so the carriers stay distinguishable.
  Construction circlesScene() {
    final construction = Construction();
    final o = FreePoint(id: 'o', position: Vec2.zero);
    final p = FreePoint(id: 'p', position: const Vec2(3, 0));
    final p1 = FreePoint(id: 'p1', position: const Vec2(7, 0));
    final p2 = FreePoint(id: 'p2', position: const Vec2(11, 2));
    final p3 = FreePoint(id: 'p3', position: const Vec2(9, 4));
    final r1 = FreePoint(id: 'r1', position: const Vec2(0, 6));
    final r2 = FreePoint(id: 'r2', position: const Vec2(2, 6));
    final k = FreePoint(id: 'k', position: const Vec2(5, 7));
    final s1 = FreePoint(id: 's1', position: const Vec2(-2, -4));
    final s2 = FreePoint(id: 's2', position: const Vec2(0, -2));
    final s3 = FreePoint(id: 's3', position: const Vec2(2, -4));
    final t = FreePoint(id: 't', position: const Vec2(9, -4));
    final u = FreePoint(id: 'u', position: const Vec2(11, -4));
    final v = FreePoint(id: 'v', position: const Vec2(9, -1));
    construction
      ..add(o)
      ..add(p)
      ..add(p1)
      ..add(p2)
      ..add(p3)
      ..add(r1)
      ..add(r2)
      ..add(k)
      ..add(s1)
      ..add(s2)
      ..add(s3)
      ..add(t)
      ..add(u)
      ..add(v)
      ..add(CircleCenterPoint(id: 'c1', center: o, onCircle: p))
      ..add(ThreePointCircle(id: 'c2', point1: p1, point2: p2, point3: p3))
      ..add(
        CompassCircle(id: 'c3', radiusPoint1: r1, radiusPoint2: r2, center: k),
      )
      ..add(Arc(id: 'arc', start: s1, via: s2, end: s3))
      ..add(Sector(id: 'sec', center: t, start: u, end: v));
    return construction;
  }

  /// Both angle kinds: a directed vertex angle and the always-acute angle
  /// between two crossing lines.
  Construction anglesScene() {
    final construction = Construction();
    final arm1 = FreePoint(id: 'a1', position: const Vec2(4, 0));
    final vertex = FreePoint(id: 'vx', position: Vec2.zero);
    final arm2 = FreePoint(id: 'a2', position: const Vec2(1, 3));
    final e = FreePoint(id: 'e', position: const Vec2(6, 0));
    final f = FreePoint(id: 'f', position: const Vec2(10, 3));
    final g = FreePoint(id: 'g', position: const Vec2(6, 3));
    final h = FreePoint(id: 'h', position: const Vec2(10, 0));
    final line1 = LineThroughTwoPoints(id: 'l1', point1: e, point2: f);
    final line2 = LineThroughTwoPoints(id: 'l2', point1: g, point2: h);
    construction
      ..add(arm1)
      ..add(vertex)
      ..add(arm2)
      ..add(e)
      ..add(f)
      ..add(g)
      ..add(h)
      ..add(line1)
      ..add(line2)
      ..add(VertexAngle(id: 'va', arm1: arm1, vertex: vertex, arm2: arm2))
      ..add(LineAngle(id: 'la', line1: line1, line2: line2));
    return construction;
  }

  /// Attribute and overlay rendering: a label, custom color / stroke /
  /// point size, a filled sector, selection halos and preview markers.
  Construction decorationsScene() {
    final construction = Construction();
    final a = FreePoint(
      id: 'a',
      position: Vec2.zero,
      attributes: const ObjectAttributes(name: 'A'),
    );
    final b = FreePoint(id: 'b', position: const Vec2(4, 0));
    final c = FreePoint(id: 'c', position: const Vec2(4, 3));
    final center = FreePoint(id: 'k', position: const Vec2(8, 2));
    final rim = FreePoint(id: 'rim', position: const Vec2(10, 2));
    final secEnd = FreePoint(id: 'se', position: const Vec2(8, 4));
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(center)
      ..add(rim)
      ..add(secEnd)
      ..add(
        Segment(
          id: 's',
          point1: b,
          point2: c,
          attributes: const ObjectAttributes(
            colorArgb: 0xFFE64A19,
            strokeWidth: 4,
            tickMarks: 2,
          ),
        ),
      )
      ..add(
        Segment(
          id: 'dash',
          point1: a,
          point2: c,
          attributes: const ObjectAttributes(dashPeriod: 8, tickMarks: 1),
        ),
      )
      ..add(
        FreePoint(
          id: 'big',
          position: const Vec2(2, 3),
          attributes: const ObjectAttributes(
            colorArgb: 0xFF2E7D32,
            pointSize: 8,
          ),
        ),
      )
      ..add(
        CircleCenterPoint(
          id: 'circ',
          center: center,
          onCircle: rim,
          attributes: const ObjectAttributes(dashPeriod: 12),
        ),
      )
      ..add(
        Sector(
          id: 'fill',
          center: center,
          start: rim,
          end: secEnd,
          attributes: const ObjectAttributes(fillAlpha: 0.25),
        ),
      );
    return construction;
  }

  /// Phase 22 marker styling: the automatic right-angle square (unfilled,
  /// and filled via a LineAngle over a real PerpendicularLine — the
  /// fp-exact π/2 source), a filled wedge, a non-default marker radius,
  /// and a filled sector.
  Construction markerStylesScene() {
    final construction = Construction();
    final v1 = FreePoint(id: 'v1', position: Vec2.zero);
    final a1 = FreePoint(id: 'a1', position: const Vec2(3, 0));
    final b1 = FreePoint(id: 'b1', position: const Vec2(0, 3));
    final v2 = FreePoint(id: 'v2', position: const Vec2(7, 0));
    final a2 = FreePoint(id: 'a2', position: const Vec2(10, 0));
    final b2 = FreePoint(id: 'b2', position: const Vec2(9, 2));
    final v3 = FreePoint(id: 'v3', position: const Vec2(14, 0));
    final a3 = FreePoint(id: 'a3', position: const Vec2(17, 0));
    final b3 = FreePoint(id: 'b3', position: const Vec2(15, 3));
    final p1 = FreePoint(id: 'p1', position: const Vec2(1, 6));
    final p2 = FreePoint(id: 'p2', position: const Vec2(5, 6));
    final baseline = LineThroughTwoPoints(id: 'bl', point1: p1, point2: p2);
    final perp = PerpendicularLine(id: 'pp', through: p2, reference: baseline);
    final center = FreePoint(id: 'k', position: const Vec2(11, 5));
    final rim = FreePoint(id: 'rim', position: const Vec2(13, 5));
    final secEnd = FreePoint(id: 'se', position: const Vec2(11, 7));
    construction
      ..add(v1)
      ..add(a1)
      ..add(b1)
      ..add(v2)
      ..add(a2)
      ..add(b2)
      ..add(v3)
      ..add(a3)
      ..add(b3)
      ..add(p1)
      ..add(p2)
      ..add(baseline)
      ..add(perp)
      ..add(center)
      ..add(rim)
      ..add(secEnd)
      // Perpendicular arms → sweep exactly π/2 → the automatic square.
      ..add(VertexAngle(id: 'right', arm1: a1, vertex: v1, arm2: b1))
      ..add(
        VertexAngle(
          id: 'filled',
          arm1: a2,
          vertex: v2,
          arm2: b2,
          attributes: const ObjectAttributes(fillAlpha: 0.25),
        ),
      )
      ..add(
        VertexAngle(
          id: 'xl',
          arm1: a3,
          vertex: v3,
          arm2: b3,
          attributes: const ObjectAttributes(angleMarkerRadius: 36),
        ),
      )
      // A right angle from a real perpendicular construction, filled and
      // resized: square + fill + radius in one marker.
      ..add(
        LineAngle(
          id: 'lright',
          line1: baseline,
          line2: perp,
          attributes: const ObjectAttributes(
            angleMarkerRadius: 28,
            fillAlpha: 0.25,
          ),
        ),
      )
      ..add(
        Sector(
          id: 'fillsec',
          center: center,
          start: rim,
          end: secEnd,
          attributes: const ObjectAttributes(fillAlpha: 0.4),
        ),
      );
    return construction;
  }

  /// Phase 37 polygons and disc fill: a filled pentagon (the tool's
  /// default 0.25 alpha), a dashed unfilled triangle outline, and a full
  /// circle filled as a disc.
  Construction polygonsScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(5, 0));
    final c = FreePoint(id: 'c', position: const Vec2(6, 4));
    final d = FreePoint(id: 'd', position: const Vec2(2, 5));
    final e = FreePoint(id: 'e', position: const Vec2(-2, 3));
    final p = FreePoint(id: 'p', position: const Vec2(9, 0));
    final q = FreePoint(id: 'q', position: const Vec2(12, 2));
    final r = FreePoint(id: 'r', position: const Vec2(9, 4));
    final center = FreePoint(id: 'k', position: const Vec2(16, 2));
    final rim = FreePoint(id: 'rim', position: const Vec2(18, 2));
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(d)
      ..add(e)
      ..add(p)
      ..add(q)
      ..add(r)
      ..add(center)
      ..add(rim)
      ..add(
        Polygon(
          id: 'pent',
          vertices: [a, b, c, d, e],
          attributes: const ObjectAttributes(fillAlpha: 0.25),
        ),
      )
      ..add(
        Polygon(
          id: 'tri',
          vertices: [p, q, r],
          attributes: const ObjectAttributes(
            dashPeriod: 8,
            colorArgb: 0xFF2E7D32,
          ),
        ),
      )
      ..add(
        CircleCenterPoint(
          id: 'disc',
          center: center,
          onCircle: rim,
          attributes: const ObjectAttributes(fillAlpha: 0.25),
        ),
      );
    return construction;
  }

  /// Phase 35 show-value labels: a named measured segment ('c = 5.00'),
  /// a value-only segment ('4.00' — no name part), a name-only segment
  /// beside them for contrast, and a measured right angle ('90.0°').
  Construction measuresScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(3, 4));
    final c = FreePoint(id: 'c', position: const Vec2(7, 0));
    final d = FreePoint(id: 'd', position: const Vec2(11, 0));
    final e = FreePoint(id: 'e', position: const Vec2(7, -3));
    final f = FreePoint(id: 'f', position: const Vec2(11, -3));
    final arm1 = FreePoint(id: 'm1', position: const Vec2(9, 5));
    final vertex = FreePoint(id: 'vx', position: const Vec2(6, 5));
    final arm2 = FreePoint(id: 'm2', position: const Vec2(6, 8));
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(d)
      ..add(e)
      ..add(f)
      ..add(arm1)
      ..add(vertex)
      ..add(arm2)
      // A 3–4–5 hypotenuse: 'c = 5.00'.
      ..add(
        Segment(
          id: 'named',
          point1: a,
          point2: b,
          attributes: const ObjectAttributes(name: 'c', showValue: true),
        ),
      )
      // Unnamed: the bare value '4.00'.
      ..add(
        Segment(
          id: 'bare',
          point1: c,
          point2: d,
          attributes: const ObjectAttributes(showValue: true),
        ),
      )
      // Name only — pre-35 rendering for contrast.
      ..add(
        Segment(
          id: 'plain',
          point1: e,
          point2: f,
          attributes: const ObjectAttributes(name: 'g'),
        ),
      )
      // Perpendicular arms: the right-angle square plus '90.0°'.
      ..add(
        VertexAngle(
          id: 'ang',
          arm1: arm1,
          vertex: vertex,
          arm2: arm2,
          attributes: const ObjectAttributes(showValue: true),
        ),
      );
    return construction;
  }

  /// Phase 38 measurement texts: a named distance ('a = 5.00'), a bare
  /// one ('3.00'), a polygon area at the vertex average and a circle
  /// area at the center — text riding the label machinery over a filled
  /// region and a plain circle.
  Construction measurementsScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(3, 4));
    final c = FreePoint(id: 'c', position: const Vec2(5, 8));
    final d = FreePoint(id: 'd', position: const Vec2(8, 8));
    final p1 = FreePoint(id: 'p1', position: const Vec2(6, 0));
    final p2 = FreePoint(id: 'p2', position: const Vec2(10, 0));
    final p3 = FreePoint(id: 'p3', position: const Vec2(10, 3));
    final p4 = FreePoint(id: 'p4', position: const Vec2(6, 3));
    final center = FreePoint(id: 'o', position: const Vec2(14, 5));
    final rim = FreePoint(id: 'rim', position: const Vec2(16, 5));
    final polygon = Polygon(
      id: 'poly',
      vertices: [p1, p2, p3, p4],
      attributes: const ObjectAttributes(fillAlpha: 0.25),
    );
    final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(d)
      ..add(p1)
      ..add(p2)
      ..add(p3)
      ..add(p4)
      ..add(center)
      ..add(rim)
      ..add(polygon)
      ..add(circle)
      // A 3–4–5 pair: 'a = 5.00'.
      ..add(
        DistanceMeasurement(
          id: 'named',
          point1: a,
          point2: b,
          attributes: const ObjectAttributes(name: 'a'),
        ),
      )
      // Unnamed: the bare '3.00'.
      ..add(DistanceMeasurement(id: 'bare', point1: c, point2: d))
      // '12.00' at the rectangle's vertex average, 'πr² ≈ 12.57' at the
      // circle center.
      ..add(
        AreaMeasurement(
          id: 'parea',
          subject: polygon,
          attributes: const ObjectAttributes(name: 'b'),
        ),
      )
      ..add(AreaMeasurement(id: 'carea', subject: circle))
      // '2πr ≈ 12.57' hanging from the top of the same circle's rim.
      ..add(LengthMeasurement(id: 'clen', subject: circle));
    return construction;
  }

  /// Phase 39 loci: a tangency-bounded trace (the midpoint between the
  /// driver and perpendicular-through-driver ∩ circle, at half height so
  /// it doesn't hide on the circle's rim) — since Phase 39b the linkage
  /// continuation flips the intersection branch at |x| = 4 and closes it
  /// into a full half-height ellipse — and a dashed closed loop
  /// (circle-host midpoint trace at half scale).
  Construction locusScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(-6, 0));
    final b = FreePoint(id: 'b', position: const Vec2(6, 0));
    final axis = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final driver = PointOnObject(id: 'drv', curve: axis, parameter: 1);
    final perpendicular = PerpendicularLine(
      id: 'perp',
      through: driver,
      reference: axis,
    );
    final center = FreePoint(id: 'o', position: Vec2.zero);
    final rim = FreePoint(id: 'rim', position: const Vec2(0, 4));
    final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
    final crossing = IntersectionPoint(
      id: 'x',
      curve1: perpendicular,
      curve2: circle,
      branchIndex: 0,
    );
    final traced = Midpoint(id: 'tr', point1: driver, point2: crossing);
    final loopCenter = FreePoint(id: 'o2', position: const Vec2(12, 2));
    final loopRim = FreePoint(id: 'r2', position: const Vec2(14, 2));
    final loopHost = CircleCenterPoint(
      id: 'k2',
      center: loopCenter,
      onCircle: loopRim,
    );
    final loopDriver = PointOnObject(id: 'drv2', curve: loopHost, parameter: 0);
    final loopAnchor = FreePoint(id: 'p2', position: const Vec2(16, 2));
    final loopTraced = Midpoint(
      id: 'tr2',
      point1: loopDriver,
      point2: loopAnchor,
    );
    construction
      ..add(a)
      ..add(b)
      ..add(axis)
      ..add(driver)
      ..add(perpendicular)
      ..add(center)
      ..add(rim)
      ..add(circle)
      ..add(crossing)
      ..add(traced)
      // Defined only while |x| <= 4: null runs at both ends of the sweep.
      ..add(
        Locus(
          id: 'loc',
          driver: driver,
          traced: traced,
          sampleCount: 64,
          center: 0,
          halfSpan: 6,
        ),
      )
      ..add(loopCenter)
      ..add(loopRim)
      ..add(loopHost)
      ..add(loopDriver)
      ..add(loopAnchor)
      ..add(loopTraced)
      // Gapless circle host: the polyline closes; dashed to exercise the
      // dash-capable stroke.
      ..add(
        Locus(
          id: 'loop',
          driver: loopDriver,
          traced: loopTraced,
          sampleCount: 48,
          attributes: const ObjectAttributes(dashPeriod: 8),
        ),
      );
    return construction;
  }

  /// Phase 44 line clipping: a mode-1 line stroked (dashed) exactly over
  /// its defining pair, a mode-2 line stretched to a glued point beyond
  /// the pair, a mode-2 ray clamped at its through point, and a mode-0
  /// line for contrast running across the whole frame.
  Construction clipsScene() {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(0, 6));
    final b = FreePoint(id: 'b', position: const Vec2(4, 6));
    final c = FreePoint(id: 'c', position: const Vec2(0, 3));
    final d = FreePoint(id: 'd', position: const Vec2(4, 3));
    final e = FreePoint(id: 'e', position: Vec2.zero);
    final f = FreePoint(id: 'f', position: const Vec2(4, 0));
    final g = FreePoint(id: 'g', position: const Vec2(0, -3));
    final h = FreePoint(id: 'h', position: const Vec2(4, -3));
    final mode2 = LineThroughTwoPoints(
      id: 'l2',
      point1: c,
      point2: d,
      attributes: const ObjectAttributes(lineClip: 2),
    );
    construction
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(d)
      ..add(e)
      ..add(f)
      ..add(g)
      ..add(h)
      ..add(
        LineThroughTwoPoints(
          id: 'l1',
          point1: a,
          point2: b,
          attributes: const ObjectAttributes(lineClip: 1, dashPeriod: 8),
        ),
      )
      ..add(mode2)
      ..add(
        PointOnObject.near(
          id: 'glue',
          curve: mode2,
          position: const Vec2(7, 3),
        ),
      )
      ..add(
        Ray(
          id: 'ray',
          origin: e,
          through: f,
          attributes: const ObjectAttributes(lineClip: 2),
        ),
      )
      ..add(LineThroughTwoPoints(id: 'l0', point1: g, point2: h));
    return construction;
  }

  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};
  final scenes = {
    'points': pointsScene,
    'lines': linesScene,
    'circles': circlesScene,
    'angles': anglesScene,
    'markers': markerStylesScene,
    'measures': measuresScene,
    'polygons': polygonsScene,
    'measurements': measurementsScene,
    'locus': locusScene,
    'clips': clipsScene,
  };

  for (final MapEntry(key: themeName, value: theme) in themes.entries) {
    for (final MapEntry(key: sceneName, value: buildScene) in scenes.entries) {
      testWidgets('$sceneName scene — $themeName', (tester) async {
        await expectSceneGolden(
          tester,
          construction: buildScene(),
          theme: theme,
          golden: '${sceneName}_$themeName',
        );
      });
    }

    testWidgets('decorations scene — $themeName', (tester) async {
      await expectSceneGolden(
        tester,
        construction: decorationsScene(),
        theme: theme,
        golden: 'decorations_$themeName',
        selectedIds: const {'k', 'circ'},
        previewMarkers: const [Vec2(0, 4), Vec2(2, 5)],
      );
    });

    // Phase 43: the grid scene's machinery under a rotated view (0.5 rad
    // CCW) plus the other rotation-sensitive paths — grid and axes rotate
    // with the content, the right-angle square and filled sector follow
    // their world geometry, the infinite line crosses the frame at the
    // rotated slope, and the point label stays screen-upright.
    testWidgets('rotated scene — $themeName', (tester) async {
      final construction = Construction();
      final a = FreePoint(
        id: 'a',
        position: const Vec2(-3, -2),
        attributes: const ObjectAttributes(name: 'A'),
      );
      final b = FreePoint(id: 'b', position: const Vec2(4, 3));
      final vertex = FreePoint(id: 'vx', position: const Vec2(2, -2));
      final arm1 = FreePoint(id: 'm1', position: const Vec2(4, -2));
      final arm2 = FreePoint(id: 'm2', position: const Vec2(2, 0));
      final center = FreePoint(id: 'k', position: const Vec2(-4, 2));
      final rim = FreePoint(id: 'rim', position: const Vec2(-2, 2));
      final secEnd = FreePoint(id: 'se', position: const Vec2(-4, 4));
      construction
        ..add(a)
        ..add(b)
        ..add(vertex)
        ..add(arm1)
        ..add(arm2)
        ..add(center)
        ..add(rim)
        ..add(secEnd)
        ..add(LineThroughTwoPoints(id: 'l', point1: a, point2: b))
        ..add(Segment(id: 's', point1: vertex, point2: arm1))
        // Perpendicular arms → the automatic right-angle square.
        ..add(VertexAngle(id: 'ra', arm1: arm1, vertex: vertex, arm2: arm2))
        ..add(
          Sector(
            id: 'sec',
            center: center,
            start: rim,
            end: secEnd,
            attributes: const ObjectAttributes(fillAlpha: 0.25),
          ),
        );
      await expectSceneGolden(
        tester,
        construction: construction,
        theme: theme,
        golden: 'rotated_$themeName',
        showAxes: true,
        showGrid: true,
        viewport: const ViewportState(
          pan: Vec2(-8, 6),
          scale: 40,
          rotation: 0.5,
        ),
      );
    });

    // Phase 36: axes + grid behind a small construction. A fixed viewport
    // (origin centered, 40 px per unit → step 2 grid, tick labels at even
    // integers) keeps the background layer deterministic instead of
    // depending on fit framing.
    testWidgets('grid scene — $themeName', (tester) async {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-3, -2));
      final b = FreePoint(id: 'b', position: const Vec2(4, 3));
      construction
        ..add(a)
        ..add(b)
        ..add(Segment(id: 's', point1: a, point2: b));
      await expectSceneGolden(
        tester,
        construction: construction,
        theme: theme,
        golden: 'grid_$themeName',
        showAxes: true,
        showGrid: true,
        viewport: const ViewportState(pan: Vec2(-8, 6), scale: 40),
      );
    });
  }
}
