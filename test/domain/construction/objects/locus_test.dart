import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/trace_diagnostics.dart';

void main() {
  group('Locus chain', () {
    test('straight chain: driver first, traced last, in parent order', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final p = FreePoint(id: 'p', position: const Vec2(4, 0));
      final m1 = Midpoint(id: 'm1', point1: driver, point2: p);
      final m2 = Midpoint(id: 'm2', point1: m1, point2: p);
      final locus = Locus(id: 'loc', driver: driver, traced: m2);
      expect(locus.chain, [driver, m1, m2]);
    });

    test('diamond is counted once and stays topologically ordered', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final p = FreePoint(id: 'p', position: const Vec2(4, 0));
      final q = FreePoint(id: 'q', position: const Vec2(0, 4));
      final left = Midpoint(id: 'm1', point1: driver, point2: p);
      final right = Midpoint(id: 'm2', point1: driver, point2: q);
      final apex = Midpoint(id: 'm3', point1: left, point2: right);
      final locus = Locus(id: 'loc', driver: driver, traced: apex);
      expect(locus.chain.first, driver);
      expect(locus.chain.last, apex);
      expect(locus.chain, containsAll([left, right]));
      expect(locus.chain.length, 4, reason: 'each diamond arm exactly once');
    });

    test('ancestors independent of the driver are excluded', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final p = FreePoint(id: 'p', position: const Vec2(4, 0));
      // p is an ancestor of traced but does not depend on the driver;
      // sibling depends on the driver but is no ancestor of traced.
      final sibling = Midpoint(id: 'sib', point1: driver, point2: p);
      final traced = Midpoint(id: 'tr', point1: driver, point2: p);
      final locus = Locus(id: 'loc', driver: driver, traced: traced);
      expect(locus.chain, [driver, traced]);
      expect(locus.chain, isNot(contains(p)));
      expect(locus.chain, isNot(contains(sibling)));
    });

    test('chain is unmodifiable', () {
      final locus = _circleLocus(sampleCount: 4);
      expect(() => locus.chain.removeLast(), throwsUnsupportedError);
    });
  });

  group('Locus constructor validation', () {
    test('rejects a traced point independent of the driver', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final free = FreePoint(id: 'p', position: const Vec2(4, 0));
      expect(
        () => Locus(id: 'loc', driver: driver, traced: free),
        throwsArgumentError,
      );
    });

    test('rejects the driver itself as the traced point', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      expect(
        () => Locus(id: 'loc', driver: driver, traced: driver),
        throwsArgumentError,
      );
    });

    test('rejects degenerate params', () {
      final center = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final p = FreePoint(id: 'p', position: const Vec2(4, 0));
      final traced = Midpoint(id: 'tr', point1: driver, point2: p);
      Locus build({int sampleCount = 128, double halfSpan = 100}) => Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: sampleCount,
        halfSpan: halfSpan,
      );
      expect(() => build(sampleCount: 1), throwsArgumentError);
      expect(() => build(halfSpan: 0), throwsArgumentError);
      expect(() => build(halfSpan: double.nan), throwsArgumentError);
    });
  });

  group('Locus sweep', () {
    test('circle host: traced midpoint samples the half-scale circle', () {
      // Host: circle center (0,0) radius 2; traced = midpoint(driver, P)
      // with P at (4,0) — analytically the circle center (2,0) radius 1,
      // sample i at angle 2πi/n: (2 + cos, sin).
      final locus = _circleLocus(sampleCount: 16);
      final samples = locus.samples!;
      expect(samples.length, 16);
      for (var i = 0; i < samples.length; i++) {
        final angle = 2 * math.pi * i / 16;
        final sample = samples[i]!;
        expect(sample.x, closeTo(2 + math.cos(angle), 1e-12), reason: 'x[$i]');
        expect(sample.y, closeTo(math.sin(angle), 1e-12), reason: 'y[$i]');
      }
    });

    test('sector host: the sweep covers only the wedge, endpoints '
        'included', () {
      final center = FreePoint(id: 'c', position: Vec2.zero);
      final start = FreePoint(id: 's', position: const Vec2(2, 0));
      final end = FreePoint(id: 'e', position: const Vec2(0, 2));
      final host = Sector(id: 'w', center: center, start: start, end: end);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final p = FreePoint(id: 'p', position: const Vec2(4, 0));
      final traced = Midpoint(id: 'tr', point1: driver, point2: p);
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 9,
      );

      // Midpoint of the radius-2 wedge with P(4,0): a quarter circle
      // around (2,0), radius 1 — sample i at angle (π/2)·i/8, both
      // wedge ends included (the stroke is open, never a full turn).
      final samples = locus.samples!;
      expect(samples.length, 9);
      for (var i = 0; i < samples.length; i++) {
        final angle = math.pi / 2 * i / 8;
        expect(
          samples[i]!.x,
          closeTo(2 + math.cos(angle), 1e-12),
          reason: 'x[$i]',
        );
        expect(samples[i]!.y, closeTo(math.sin(angle), 1e-12), reason: 'y[$i]');
      }
    });

    test('segment host: the sweep covers only the span, endpoints '
        'included', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final host = Segment(id: 's', point1: a, point2: b);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 1);
      final traced = Midpoint(id: 'tr', point1: driver, point2: driver);
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 5,
      );

      // Identity trace: samples read the sweep domain directly — uniform
      // over [0, 4], both endpoints included, nothing on the carrier
      // beyond them.
      final samples = locus.samples!;
      expect(samples.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(
          samples[i]!.closeTo(Vec2(i.toDouble(), 0)),
          isTrue,
          reason: 'sample $i',
        );
      }
      expect(
        locus.coreSamples,
        hasLength(5),
        reason: 'a bounded sweep has no far-out samples — all core',
      );
    });

    test('ray host: the sweep starts at the origin and runs only along '
        'the ray', () {
      final o = FreePoint(id: 'o', position: const Vec2(1, 0));
      final t = FreePoint(id: 't', position: const Vec2(2, 0));
      final host = Ray(id: 'r', origin: o, through: t);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 1);
      final traced = Midpoint(id: 'tr', point1: driver, point2: driver);
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 4,
        center: 1,
        halfSpan: 100,
      );

      // Identity trace, diverging: the infinity tail rejects (increments
      // never decay), so the samples are exactly the half-bounded tan
      // grid t = 1 + 100·tan((π/2)·i/4) — anchored on the ray origin,
      // never behind it.
      final samples = locus.samples!;
      expect(samples.length, 4);
      expect(
        samples.first!.closeTo(const Vec2(1, 0)),
        isTrue,
        reason: 'the first sample sits exactly on the ray origin',
      );
      for (var i = 0; i < 4; i++) {
        final expected = 1 + 100 * math.tan(math.pi / 2 * i / 4);
        expect(samples[i]!.x, closeTo(expected, 1e-9), reason: 'x[$i]');
        expect(samples[i]!.y, closeTo(0, 1e-12), reason: 'y[$i]');
      }
    });

    test('line host: projective tan grid focused on [center ± halfSpan] '
        '(Phase 39f)', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final host = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 3);
      // Midpoint of the driver with itself is the driver's own position:
      // the identity trace, so samples read the sweep domain directly.
      final traced = Midpoint(id: 'tr', point1: driver, point2: driver);
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 3,
        center: 0,
        halfSpan: 100,
      );
      // The identity trace diverges, so the infinity tails reject
      // (increments double rung to rung) and the samples are exactly the
      // uniform grid: t = center + halfSpan·tan(φ), φ cell-centered over
      // (−π/2, π/2) — for n = 3 that is −π/3, 0, π/3.
      final samples = locus.samples!;
      expect(samples.length, 3);
      expect(samples[1]!.distanceTo(Vec2.zero), closeTo(0, 1e-12));
      expect(samples[0]!.norm, closeTo(100 * math.tan(math.pi / 3), 1e-9));
      expect(samples[2]!.norm, closeTo(100 * math.tan(math.pi / 3), 1e-9));
      expect(
        (samples[0]! + samples[2]!).norm,
        closeTo(0, 1e-9),
        reason: 'the grid sits symmetrically about the focus center',
      );
      expect(
        locus.coreSamples,
        hasLength(1),
        reason:
            'only the center sample lies inside the focus window — '
            'coreSamples is the bounded slice fit and labels consume',
      );
      expect(
        locus.coreSamples!.single.distanceTo(Vec2.zero),
        closeTo(0, 1e-12),
      );
    });

    test('restores the driver bit-exactly', () {
      final locus = _circleLocus(sampleCount: 32, driverParameter: 0.7531);
      final driver = locus.driver;
      final positionBefore = driver.position;
      locus.recompute();
      expect(driver.parameter, 0.7531);
      expect(driver.position, positionBefore);
      // The whole chain settled back: traced matches a fresh recompute.
      final traced = locus.traced;
      final tracedBefore = traced.position;
      traced.recompute();
      expect(traced.position, tracedBefore);
    });

    test('sliding the driver leaves the samples unchanged', () {
      final construction = Construction();
      final locus = _circleLocus(sampleCount: 16, into: construction);
      final before = List.of(locus.samples!);
      construction.setPointOnObjectParameter('drv', 2.2);
      expect(locus.samples, before);
    });

    test('upstream free-point drag recomputes with one notification', () {
      final construction = Construction();
      final locus = _circleLocus(sampleCount: 16, into: construction);
      final before = List.of(locus.samples!);
      var notifications = 0;
      construction.addListener(() => notifications++);
      // Move P (4,0) → (6,0): the traced midpoints shift right by 1.
      construction.moveFreePoint('p', const Vec2(6, 0));
      expect(notifications, 1);
      final after = locus.samples!;
      for (var i = 0; i < after.length; i++) {
        expect(after[i]!.x, closeTo(before[i]!.x + 1, 1e-12));
        expect(after[i]!.y, closeTo(before[i]!.y, 1e-12));
      }
    });

    test('tangency-bounded run closes through the linkage continuation '
        'into the full circle', () {
      // Driver sweeps the x-axis over [-100, 100]; traced is the
      // perpendicular-through-driver ∩ circle(radius 10), defined only
      // while |x| <= 10 with both branches coalescing at x = ±10. The
      // Phase 39b walk flips the branch at each tangency, so the locus
      // is the whole circle — one closed component, no gaps.
      final locus = _perpendicularCircleLocus(
        center: 0,
        halfSpan: 100,
        sampleCount: 41,
      );
      final samples = locus.samples!;
      expect(
        samples,
        isNot(contains(null)),
        reason: 'a single run walks into a single component',
      );
      final points = samples.cast<Vec2>();
      expect(points.first, points.last, reason: 'closed loop');
      for (final p in points) {
        // 1e-6: the boundary samples sit in the intersection math's
        // epsilon-tangent zone, ~1e-8 outside the exact circle.
        expect(
          p.x * p.x + p.y * p.y,
          closeTo(100, 1e-6),
          reason: 'every sample lies on the circle',
        );
      }
      expect(
        points.any((p) => p.y > 5),
        isTrue,
        reason: 'the flipped branch covers the upper half',
      );
      expect(
        points.any((p) => p.y < -5),
        isTrue,
        reason: 'the original branch covers the lower half',
      );
      // Boundary refinement dives to the two-candidate edge — the
      // intersection epsilon puts it ~1e-4 from the exact tangency (the
      // old 1e-6 pin relied on the uniform window grid landing a sample
      // exactly on the tangency parameter; the tan grid does not).
      expect(
        points.any((p) => p.distanceTo(const Vec2(10, 0)) < 1e-3),
        isTrue,
        reason: 'right tangency sampled',
      );
      expect(
        points.any((p) => p.distanceTo(const Vec2(-10, 0)) < 1e-3),
        isTrue,
        reason: 'left tangency sampled',
      );
      // The sweep restored the flipped branch.
      expect(locus.traced, isA<IntersectionPoint>());
      expect((locus.traced as IntersectionPoint).branchIndex, 0);
      expect(locus.driver.parameter, 0);
    });

    test('a focus window that once cut the run no longer does: the '
        'projective sweep closes the full circle (Phase 39f)', () {
      // Before 39f the window [0, 100] cut the run at x = 0 and the walk,
      // flipping at the x = 30 tangency but never regaining the original
      // assignment, trimmed to one open branch (the Phase 39c pin). The
      // projective sweep covers the whole carrier, so both tangencies
      // are interior boundaries, both flip, and the walk closes — the
      // open-walk trim is now pinned by the doc-1-shaped fixture below,
      // whose walks end at the grid's infinity edges.
      final locus = _perpendicularCircleLocus(
        center: 50,
        halfSpan: 50,
        sampleCount: 21,
        radius: 30,
      );
      final samples = locus.samples!;
      expect(samples, isNot(contains(null)));
      final points = samples.cast<Vec2>();
      expect(points.first, points.last, reason: 'closed loop');
      for (final p in points) {
        expect(
          p.x * p.x + p.y * p.y,
          closeTo(900, 1e-4),
          reason: 'every sample lies on the circle',
        );
      }
      expect(
        points.any((p) => p.y > 15),
        isTrue,
        reason: 'the flipped branch covers the upper half',
      );
      expect(
        points.any((p) => p.y < -15),
        isTrue,
        reason: 'the original branch covers the lower half',
      );
    });

    test('doc-1 shape: open walks keep strokes and dives, no mirror '
        'sheets (Phase 39c)', () {
      // The tangent-and-bisector construction from the user document,
      // scaled down: driver D on line AB, F = circle(A,|AB|) ∩ Thales
      // circle over AD (exists while |AD| >= |AB|), G = the D-bisector
      // of ∠FDA re-crossing the Thales circle. At the tangency |AD| =
      // |AB| the bisector's limit direction is 45° to AB, so G converges
      // to (±r/2, ±r/2) — a genuine finite limit the refined dive must
      // reach. Inside the intersection math's tolerance zone, though,
      // the fabricated tangent F ≈ D collapses the bisector's vertex
      // rays and throws G to A — the Phase 39d phantom diagonal, which
      // must never be sampled. The flips at the tangencies lead to
      // sheets that dragging can never reach — they must be trimmed
      // (Phase 39c).
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(3, 0));
      final host = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 5);
      final mid = Midpoint(id: 'e', point1: driver, point2: a);
      final thales = CircleCenterPoint(id: 'f', center: mid, onCircle: driver);
      final circleA = CircleCenterPoint(id: 'c', center: a, onCircle: b);
      final f = IntersectionPoint(
        id: 'F',
        curve1: circleA,
        curve2: thales,
        branchIndex: 0,
      );
      final bisector = AngleBisectorLine(
        id: 'g',
        arm1: f,
        vertex: driver,
        arm2: a,
      );
      final g = IntersectionPoint(
        id: 'G',
        curve1: thales,
        curve2: bisector,
        branchIndex: 1,
      );
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: g,
        sampleCount: 40,
        center: 3,
        halfSpan: 10,
      );
      final samples = locus.samples!;
      final components = <List<Vec2>>[[]];
      for (final s in samples) {
        if (s == null) {
          components.add([]);
        } else {
          components.last.add(s);
        }
      }
      expect(
        components,
        hasLength(2),
        reason: 'one run each side of the |AD| < |AB| gap',
      );
      final componentSigns = <double>[];
      for (final component in components) {
        final signs = component
            .map((p) => p.y.sign)
            .where((s) => s != 0)
            .toSet();
        expect(
          signs,
          hasLength(1),
          reason:
              'each component stays on one sheet — no mirror '
              'strokes from a dangling flipped segment',
        );
        componentSigns.add(signs.single);
        expect(
          component.map((p) => p.norm).reduce(math.min),
          greaterThan(1.0),
          reason:
              'no sample near A — a sample there means the ladder '
              'entered the tolerance zone past the true tangency',
        );
      }
      for (final (i, component) in components.indexed) {
        final limit = Vec2(i == 0 ? -1.5 : 1.5, componentSigns[i] * 1.5);
        expect(
          component.map((p) => p.distanceTo(limit)).reduce(math.min),
          lessThan(0.01),
          reason: "the refined dive converges to G's true tangency limit",
        );
        // The other end of each stroke: as the driver runs off the host
        // line, the Thales circle over AD flattens onto the perpendicular
        // through A and G → (0, ±r/2) like 1/t — the infinity tail must
        // carry the stroke onto that limit instead of stopping at the
        // sweep window's cut (Phase 39e).
        final infinityLimit = Vec2(0, componentSigns[i] * 1.5);
        expect(
          component.map((p) => p.distanceTo(infinityLimit)).reduce(math.min),
          lessThan(1e-3),
          reason:
              'the window-edge end touches the driver-at-infinity '
              'limit on the perpendicular through A',
        );
      }
      expect(
        componentSigns.toSet(),
        hasLength(2),
        reason:
            'the fixed branch lands on opposite sides of AB for '
            'the two runs — identical signs mean run 2 was traced '
            "under run 1's leaked flip (the mirror sheet)",
      );
      expect(f.branchIndex, 0);
      expect(g.branchIndex, 1);
    });

    test('a circle-host run straddling the wrap closes the figure-eight '
        'in one component', () {
      // The three-bar linkage: driver B on circle(O, 100), circle(B, 170)
      // meets circle(C, 70) at D, traced E = midpoint(D, B). D exists
      // while |BC| <= 240 — an arc straddling θ = 0, so the run wraps the
      // sample array; the tangencies at both arc ends flip D's branch and
      // the walk closes the full figure-eight.
      final o = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(100, 0));
      final host = CircleCenterPoint(id: 'k', center: o, onCircle: rim);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final bar = FixedRadiusCircle(id: 'b', center: driver, radius: 170);
      final c = FreePoint(id: 'c', position: const Vec2(281, 0));
      final anchor = FixedRadiusCircle(id: 'ca', center: c, radius: 70);
      final d = IntersectionPoint(
        id: 'd',
        curve1: anchor,
        curve2: bar,
        branchIndex: 1,
      );
      // The pair is stored canonically, so the requested branch may be
      // renumbered onto that order (Phase 120c) — what this test is about
      // is that the sweep's flips are *restored*, not which label they
      // restore to.
      final seated = d.branchIndex;
      final traced = Midpoint(id: 'tr', point1: d, point2: driver);
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 64,
      );
      final samples = locus.samples!;
      expect(
        samples,
        isNot(contains(null)),
        reason: 'one wrapped run, one component — no seam at 0/2π',
      );
      final points = samples.cast<Vec2>();
      expect(points.first, points.last, reason: 'the eight closes');
      // The walk covers both branches: roughly twice the defined uniform
      // samples (plus ladders and the closing duplicate). Definedness is
      // |BC| <= 240 analytically.
      var uniformDefined = 0;
      for (var i = 0; i < 64; i++) {
        final b = host.circle!.pointAt(2 * math.pi * i / 64);
        if (b.distanceTo(c.position) <= 240) uniformDefined++;
      }
      expect(
        points.length,
        greaterThan((1.8 * uniformDefined).round()),
        reason: 'both halves of the eight are traced',
      );
      expect(d.branchIndex, seated, reason: 'flips restored after the sweep');
    });

    test('undefined host makes the locus undefined, and it recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: Vec2.zero); // coincident
      final host = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final traced = Midpoint(id: 'tr', point1: driver, point2: driver);
      construction
        ..add(a)
        ..add(b)
        ..add(host)
        ..add(driver)
        ..add(traced);
      final locus = Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: 4,
      );
      construction.add(locus);
      expect(locus.isDefined, isFalse);
      expect(locus.samples, isNull);
      construction.moveFreePoint('b', const Vec2(1, 0));
      expect(locus.isDefined, isTrue);
      expect(locus.samples!.whereType<Vec2>(), hasLength(4));
    });
  });

  group('Locus: transversal root crossings (Phase 117b)', () {
    // The apatitos-topos.rgl shape, reduced to its essential invariant.
    // C sits outside a circle centred at the origin; the driver D sweeps
    // that circle; E is the intersection of the circle with the
    // *segment* C→D. Because D is itself on the circle it is always one
    // of the two roots, so E's candidates pass through each other
    // **transversally** — separation vanishing linearly — twice a turn,
    // at the tangent points from C. The canonical order flips there.
    //
    // Traced is the chord's midpoint M = mid(D, E). Thales gives the
    // invariant that makes the two sheets tell each other apart: with E
    // the *second* intersection, OM ⊥ MC, so M rides the circle with
    // diameter OC. With E collapsed onto D — the canonical branch on the
    // arc facing C, and what the walk drew before Phase 117b — M is D
    // itself, which rides the *original* circle instead. The two circles
    // meet only at the two tangent points.
    const c = Vec2(-4, 0);
    const thalesCentre = Vec2(-2, 0);
    const thalesRadius = 2.0;

    /// [hideIncidence] hangs the chord off a bit-exact *copy* of the
    /// driver instead of the driver itself (Phase 135). The figure is
    /// identical to the last bit; what changes is that
    /// `sharedIncidentPoints` can no longer see that the driver is on
    /// both curves, so deflation stands down and the walk has to hold the
    /// crossing by detouring. That is the only way left to reach the
    /// detour path from a locus — see the tests below.
    Locus rig({int sampleCount = 64, bool hideIncidence = false}) {
      final centre = FreePoint(id: 'o', position: Vec2.zero);
      final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
      final host = CircleCenterPoint(id: 'k', center: centre, onCircle: rim);
      final outside = FreePoint(id: 'c', position: c);
      final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
      final chordEnd = hideIncidence
          ? HomotheticPoint(id: 'cp', point: driver, center: centre, ratio: 1)
          : driver;
      final chord = Segment(id: 'seg', point1: outside, point2: chordEnd);
      final e = IntersectionPoint(
        id: 'e',
        curve1: host,
        curve2: chord,
        branchIndex: 0,
      );
      final traced = Midpoint(id: 'm', point1: driver, point2: e);
      return Locus(
        id: 'loc',
        driver: driver,
        traced: traced,
        sampleCount: sampleCount,
      );
    }

    test('every traced sample rides the Thales circle over OC — the walk '
        'holds the second intersection through both crossings', () {
      final locus = rig();
      final samples = locus.samples!;
      expect(samples, isNot(contains(null)), reason: 'one closed component');
      for (final p in samples.cast<Vec2>()) {
        expect(
          p.distanceTo(thalesCentre),
          closeTo(thalesRadius, 1e-9),
          reason: 'sample $p left the chord-midpoint locus',
        );
      }
      expect(samples.first, samples.last, reason: 'the walk closes');
    });

    test('and so does the canonical scan now — the crossing is named, not '
        'navigated (Phase 135)', () {
      // This used to pin the *opposite*: a third of the canonical scan
      // sat on the driver's own circle, because the canonical order
      // flips at the tangent points from C and branch 0 stops meaning
      // "the second intersection" there. That flip is exactly what
      // deflation removes. D is on the host circle and on the chord by
      // construction, so E is the root left when D is divided out — the
      // same root at every parameter, with no order to flip and nothing
      // for a static scan to get wrong.
      //
      // The inverted assertion is the strong one: it fails if deflation
      // regresses, and `hideIncidence` below keeps the old behaviour
      // covered where it still applies.
      final locus = rig();
      final canonical = locus.coreSamples!;
      for (final p in canonical) {
        expect(
          p.distanceTo(thalesCentre),
          closeTo(thalesRadius, 1e-9),
          reason: 'canonical sample $p left the chord-midpoint locus',
        );
      }
    });

    test('with the incidence hidden the canonical scan is wrong again — a '
        'third of it on the driver\'s own circle (Phase 135)', () {
      // The pre-deflation behaviour, preserved: identical geometry, but
      // built so nothing can *prove* D is on both curves. This is what a
      // construction whose shared point comes from a theorem the
      // incidence detector does not model still looks like, and pinning
      // it here keeps the inverted test above honest — it fails if the
      // rig ever stops exercising a crossing at all.
      final locus = rig(hideIncidence: true);
      final canonical = locus.coreSamples!;
      final off = canonical
          .where(
            (p) => (p.distanceTo(thalesCentre) - thalesRadius).abs() > 1e-6,
          )
          .toList();
      expect(
        off.length,
        greaterThan(canonical.length ~/ 5),
        reason: 'the arc facing C is where the canonical order flips',
      );
      for (final p in off) {
        expect(
          p.norm,
          closeTo(2, 1e-9),
          reason: 'and there the canonical root is the driver itself',
        );
      }
    });

    test('a named crossing costs nothing to cross — no arc is planned at '
        'all (Phase 135)', () {
      // What deflation buys, stated as work not done. Phase 121 planned
      // one detour arc per tangent point here; there is now nothing to
      // detour around, because the root E tracks cannot be confused with
      // the root it meets.
      final counts = _countersFor(rig);
      expect(counts[TraceCounter.locusDetours] ?? 0, 0);
      expect(counts[TraceCounter.locusFolds] ?? 0, 0);
    });

    test('and with the incidence hidden the arcs come back — two '
        'crossings, two arcs (Phase 121)', () {
      // Detour coverage, and where it now lives. Phase 121 unified the
      // locus half-plane with the drag's constant, and this rig used to
      // share the corpus's whole detour coverage with
      // `apatitos-topos.rgl` — but both documents' crossings were
      // structural, so deflation took both to zero arcs (measured:
      // 4 → 0 on each). Hiding the incidence is what is left, and it is
      // not a contrivance: it is what a shared point arrived at by a
      // theorem the detector does not model looks like from here.
      //
      // **Known limitation, and this rig is its reproducer.** The walk
      // plans both arcs and still lands on the wrong sheet for a large
      // stretch — 406 of 723 samples off the Thales circle, identically
      // on the code before Phase 135, so it is neither caused nor
      // worsened by deflation. See `docs/TODO.md` Phase 136b. The
      // assertion here is deliberately only about the arcs: it keeps the
      // detour path from going uncovered while the sheet question is
      // open, and it must not be strengthened into a sheet claim without
      // fixing that first.
      final counts = _countersFor(() => rig(hideIncidence: true));
      expect(
        counts[TraceCounter.locusDetours],
        2,
        reason: 'one arc per tangent point from C',
      );
      expect(
        counts[TraceCounter.locusFolds] ?? 0,
        0,
        reason: 'the crossings are transversal — the curve never turns',
      );
    });

    test('the sweep resolution does not decide the answer', () {
      // A collision hiding inside one accepted step is a step-size bug,
      // so the invariant must hold at every scan density — including
      // coarse ones, where a whole crossing falls inside a single cell.
      for (final n in [8, 16, 64, 128]) {
        final locus = rig(sampleCount: n);
        for (final p in locus.samples!.cast<Vec2>()) {
          expect(
            p.distanceTo(thalesCentre),
            closeTo(thalesRadius, 1e-9),
            reason: 'sampleCount $n',
          );
        }
      }
    });
  });

  group('Locus: the seed is the driver\'s own parameter (Phase 133)', () {
    // The `no-locus.rgl` shape, reduced. F is glued to the x-axis; d is
    // the circle centred at the origin through F, so F is itself one of
    // the two crossings of d with the line c through B and F, and the
    // pair crosses transversally where AF ⟂ FB — at the feet of the
    // Thales circle over AB, here t = 0 and t = −8. The canonical index
    // therefore names a different root on each side of those, and out
    // at the sweep's driver-at-infinity end it names the driver.
    //
    // Which root the locus draws is settled by the document: it is
    // whichever one its traced point holds *where the driver actually
    // stands*. Seeding anywhere else is free to pick the other one, and
    // did — the reported document drew the x-axis, invisible under the
    // line the driver is glued to.
    const b = Vec2(-8, -1);

    ({Locus locus, IntersectionPoint g}) rig({required int branchIndex}) {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final unit = FreePoint(id: 'c', position: const Vec2(1, 0));
      final axis = LineThroughTwoPoints(id: 'axis', point1: a, point2: unit);
      final driver = PointOnObject(id: 'drv', curve: axis, parameter: -6.25);
      final circle = CircleCenterPoint(id: 'd', center: a, onCircle: driver);
      final off = FreePoint(id: 'b', position: b);
      final chord = LineThroughTwoPoints(id: 'c', point1: off, point2: driver);
      final g = IntersectionPoint(
        id: 'g',
        curve1: circle,
        curve2: chord,
        branchIndex: branchIndex,
      );
      return (
        locus: Locus(id: 'loc', driver: driver, traced: g, sampleCount: 128),
        g: g,
      );
    }

    for (final branchIndex in [0, 1]) {
      test('branch $branchIndex: the trace passes through the traced '
          'point, and rides that root the whole way', () {
        final (:locus, :g) = rig(branchIndex: branchIndex);
        final samples = locus.samples!;
        expect(samples, isNot(contains(null)), reason: 'one component');
        final points = samples.cast<Vec2>();
        expect(
          points.map((p) => p.distanceTo(g.position!)).reduce(math.min),
          lessThan(1e-9),
          reason: 'a locus passes through the point it is the locus of',
        );
        for (final p in points) {
          // P on line B–F(t) fixes t; |P| = |t| then says P is on the
          // circle of radius |AF(t)| — so P really is a crossing.
          final t = (p.x - b.x) / (p.y - b.y) * -b.y + b.x;
          expect(
            (p.norm - t.abs()).abs() / (1 + p.norm),
            lessThan(1e-6),
            reason: 'sample $p is not a crossing of d and c',
          );
        }
      });
    }

    test('a detour that cannot be walked gives up instead of spending the '
        "run's whole budget on it", () {
      // The sweep's own ends are driver-at-infinity limits, and the
      // starvation there classifies as a *crossing* — so the walk plans
      // an arc across a singularity that is really the edge of the
      // domain. That arc can never be walked: every trial is refused and
      // the step halves until no representable step advances it. Before
      // the floor it halved on and on, and the doomed detour spent the
      // whole run budget, leaving nothing for the leg that had not been
      // walked yet — which is how the curved branch above lost its
      // entire upper half even once it was seeded correctly.
      TraceDiagnostics.reset();
      TraceDiagnostics.enabled = true;
      try {
        TraceDiagnostics.frameBegin('test');
        rig(branchIndex: 1);
        TraceDiagnostics.frameEnd();
      } finally {
        TraceDiagnostics.enabled = false;
      }
      final counts = TraceDiagnostics.history.single.counts;
      // The claim is "did not spend the run's whole budget", and that is
      // exactly what a budget end reports — a bound on raw trials was a
      // proxy for it, and stopped being one when Phase 134's density
      // rule started refining for drawing and spending honest trials of
      // its own. Both counters are asserted so the proxy still catches a
      // grind that stays just inside the budget.
      expect(
        counts[TraceCounter.locusBudgetEnds],
        anyOf(isNull, 0),
        reason: 'the walk is not grinding a doomed arc to the budget',
      );
      expect(
        (counts[TraceCounter.locusTrials] ?? 0) -
            (counts[TraceCounter.locusDensityTrials] ?? 0),
        lessThan(8000),
        reason: 'and the walk proper is not grinding either',
      );
      expect(
        counts[TraceCounter.locusBudgetEnds] ?? 0,
        0,
        reason: 'and no leg ends by exhausting it',
      );
    });

    test('and the two branches are genuinely different curves — one of '
        'them is the driver line itself', () {
      final off = rig(branchIndex: 1).locus.samples!.cast<Vec2>();
      final on = rig(branchIndex: 0).locus.samples!.cast<Vec2>();
      // Whichever way the solver orders them at the stored parameter,
      // exactly one of the two roots is the driver, and its trace is the
      // x-axis. Pinning that keeps the test honest: it fails if the two
      // branches ever collapse onto one answer.
      final flat = [off, on].where((c) => c.every((p) => p.y.abs() < 1e-9));
      expect(flat, hasLength(1), reason: 'one branch is the driver itself');
      final curved = [off, on].firstWhere((c) => !flat.contains(c));
      expect(
        curved.where((p) => p.y.abs() > 1).length,
        greaterThan(curved.length ~/ 2),
        reason: 'and the other is a genuine curve',
      );
    });
  });

  group('Locus as a parent', () {
    test('is rejected as a PointOnObject host', () {
      final locus = _circleLocus(sampleCount: 4);
      expect(
        () => PointOnObject(id: 'bad', curve: locus, parameter: 0),
        throwsArgumentError,
      );
    });

    test('is rejected as an IntersectionPoint curve', () {
      final locus = _circleLocus(sampleCount: 4);
      final a = FreePoint(id: 'a2', position: Vec2.zero);
      final b = FreePoint(id: 'b2', position: const Vec2(1, 0));
      final line = LineThroughTwoPoints(id: 'l2', point1: a, point2: b);
      expect(
        () => IntersectionPoint(
          id: 'bad',
          curve1: locus,
          curve2: line,
          branchIndex: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

/// Line-host tangency fixture: driver sweeps the x-axis, traced is the
/// perpendicular-through-driver ∩ circle(center origin, [radius]) at
/// branch 0 — defined while |x| <= radius, branches coalescing at ±radius.
Locus _perpendicularCircleLocus({
  required double center,
  required double halfSpan,
  required int sampleCount,
  double radius = 10,
}) {
  final a = FreePoint(id: 'a', position: Vec2.zero);
  final b = FreePoint(id: 'b', position: const Vec2(1, 0));
  final host = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
  final driver = PointOnObject(id: 'drv', curve: host, parameter: 0);
  final perpendicular = PerpendicularLine(
    id: 'perp',
    through: driver,
    reference: host,
  );
  final rim = FreePoint(id: 'r', position: Vec2(radius, 0));
  final circle = CircleCenterPoint(id: 'k', center: a, onCircle: rim);
  final traced = IntersectionPoint(
    id: 'tr',
    curve1: perpendicular,
    curve2: circle,
    branchIndex: 0,
  );
  return Locus(
    id: 'loc',
    driver: driver,
    traced: traced,
    sampleCount: sampleCount,
    center: center,
    halfSpan: halfSpan,
  );
}

/// Circle-host fixture: host circle center (0,0) radius 2, driver on it,
/// traced = midpoint(driver, P) with P at (4, 0) — the half-scale circle
/// around (2, 0). Optionally adds everything to [into], ids as literals
/// ('o', 'r', 'k', 'drv', 'p', 'tr', 'loc').
Locus _circleLocus({
  required int sampleCount,
  double driverParameter = 0,
  Construction? into,
}) {
  final center = FreePoint(id: 'o', position: Vec2.zero);
  final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
  final host = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
  final driver = PointOnObject(
    id: 'drv',
    curve: host,
    parameter: driverParameter,
  );
  final p = FreePoint(id: 'p', position: const Vec2(4, 0));
  final traced = Midpoint(id: 'tr', point1: driver, point2: p);
  final locus = Locus(
    id: 'loc',
    driver: driver,
    traced: traced,
    sampleCount: sampleCount,
  );
  into
    ?..add(center)
    ..add(rim)
    ..add(host)
    ..add(driver)
    ..add(p)
    ..add(traced)
    ..add(locus);
  return locus;
}

/// Runs [body] inside one diagnostics frame and returns its counters.
Map<TraceCounter, int> _countersFor(void Function() body) {
  TraceDiagnostics.reset();
  TraceDiagnostics.enabled = true;
  try {
    TraceDiagnostics.frameBegin('test');
    body();
    TraceDiagnostics.frameEnd();
  } finally {
    TraceDiagnostics.enabled = false;
  }
  return TraceDiagnostics.history.single.counts;
}
