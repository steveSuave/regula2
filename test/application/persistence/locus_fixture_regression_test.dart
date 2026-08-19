import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/drag_session.dart';

/// Regression tests over the two user documents that drove Phases 39b–39d,
/// kept verbatim in `test/fixtures/`. They load through the real codec so
/// the whole path — decode, chain construction, sweep, walk, boundary
/// refinement — is exercised on real-world geometry, not scaled fixtures.
void main() {
  Construction construction(String fixture) {
    final json =
        jsonDecode(File('test/fixtures/$fixture').readAsStringSync())
            as Map<String, dynamic>;
    return decodeDocument(json).construction;
  }

  Locus loadLocus(String fixture, {required List<FreePoint> freeOut}) {
    final json =
        jsonDecode(File('test/fixtures/$fixture').readAsStringSync())
            as Map<String, dynamic>;
    final construction = decodeDocument(json).construction;
    freeOut.addAll(construction.objects.whereType<FreePoint>());
    return construction.objects.whereType<Locus>().single;
  }

  List<List<Vec2>> components(Locus locus) {
    final out = <List<Vec2>>[[]];
    for (final s in locus.samples!) {
      if (s == null) {
        out.add([]);
      } else {
        out.last.add(s);
      }
    }
    return out;
  }

  test('locus-miss.json (tangent-and-bisector): two single-sided strokes, '
      'dives converge to the true tangency limits, never to A or B', () {
    // G = bisector of ∠FDA re-crossing the Thales circle over AD, F the
    // tangency point of the tangent from D to circle(A, |AB|). Failure
    // history: 39b/39c drew mirror sheets from leaked branch flips; 39c
    // still sampled the intersection tolerance zone past the true
    // tangency, where the fabricated tangent F ≈ D collapses the
    // bisector and throws G onto A (one run) and B (the other) — long
    // phantom diagonals from each stroke's end down to the line AB;
    // 39d still cut each stroke at the sweep window's edge, ≈ 11 world
    // units short of its driver-at-infinity limit on line b (39e).
    final free = <FreePoint>[];
    final locus = loadLocus('locus-miss.json', freeOut: free);
    final a = free.singleWhere((p) => p.attributes.name == 'A').position;
    final b = free.singleWhere((p) => p.attributes.name == 'B').position;

    final comps = components(locus);
    expect(
      comps,
      hasLength(2),
      reason: 'one run each side of the |AD| < |AB| gap',
    );

    // Analytic limit of G at the tangency |AD| = |AB|: the bisector's
    // limit direction is 45° to AB, so G → A + (AD̂ ± perp) · |AB| / 2,
    // with D at the tangency parameter on each side of A.
    final r = (b - a).norm;
    final dir = (b - a) / r;
    final perp = Vec2(-dir.y, dir.x);
    Vec2 limit(double side, double sheet) =>
        a + (dir * side + perp * sheet) * (r / 2);

    for (final (i, comp) in comps.indexed) {
      // Sweep ascends from below A: component 0 meets the tangency on
      // the far side of A from B, component 1 on the B side.
      final side = i == 0 ? -1.0 : 1.0;
      final sides = comp
          .map((p) => (p - a).cross(dir).sign)
          .where((s) => s != 0)
          .toSet();
      expect(
        sides,
        hasLength(1),
        reason:
            'each stroke stays on one side of line AB — no mirror '
            'sheet from a leaked or dangling branch flip',
      );
      final sheet = -sides.single;
      expect(
        comp.map((p) => p.distanceTo(limit(side, sheet))).reduce(math.min),
        lessThan(0.5),
        reason: "the refined dive converges to G's true tangency limit",
      );
      // The stroke's far end (Phase 39e): as D runs off line AB the
      // Thales circle over AD flattens onto the perpendicular through A
      // (the document's line b, through A and C) and G → A + perp·|AB|/2
      // like 1/t. The sweep window used to cut the stroke ≈ 11 world
      // units short of it — the reported visible gap; the infinity tail
      // must carry the stroke onto the limit.
      expect(
        comp
            .map((p) => p.distanceTo(a + perp * (sheet * r / 2)))
            .reduce(math.min),
        lessThan(0.01),
        reason:
            'the window-edge end touches the driver-at-infinity '
            'limit on line b',
      );
      for (final anchor in [a, b]) {
        expect(
          comp.map((p) => p.distanceTo(anchor)).reduce(math.min),
          greaterThan(30),
          reason:
              'no sample near A or B — a sample there is the '
              'tolerance-zone phantom (the Phase 39d diagonal)',
        );
      }
    }
  });

  test('locus3.json (parabola): a segment-hosted driver sweeps exactly the '
      'segment — the parabola piece between the endpoint images', () {
    // E on square side BC, F = the perpendicular to AE at E crossing the
    // carrier of the far side CD, G = midpoint(F, E) — analytically on
    // the parabola x = y²/4 (vertex at the world origin). History:
    // before Phase 39f the baked window `[center ± halfSpan]` cut the
    // arms ~1 view-width out; 39f swept the whole carrier projectively
    // (E's host segment was still unclamped then, so E really roamed
    // the infinite line and the full parabola appeared). Since bounded
    // hosts confine constrained points to their drawn extent, E cannot
    // leave BC and the sweep covers exactly the segment: G runs from
    // the image of B, (1, −2), to the image of C, (1, 2), endpoints
    // included. Hosting E on the *line* through B and C is the way to
    // draw the full parabola.
    final locus = loadLocus('locus3.json', freeOut: <FreePoint>[]);
    final samples = locus.samples!;
    expect(
      samples,
      isNot(contains(null)),
      reason: 'one gapless component — F exists for every E on BC',
    );
    final points = samples.cast<Vec2>();
    for (final p in points) {
      expect(
        (p.x - p.y * p.y / 4).abs(),
        lessThan(1e-6 * (1 + p.x.abs())),
        reason: 'every sample lies on the parabola x = y²/4',
      );
      expect(
        p.y,
        inInclusiveRange(-2 - 1e-9, 2 + 1e-9),
        reason: 'nothing beyond the endpoint images',
      );
    }
    expect(
      points.first.distanceTo(const Vec2(1, -2)),
      lessThan(1e-6),
      reason: 'the sweep starts exactly on the image of B',
    );
    expect(
      points.last.distanceTo(const Vec2(1, 2)),
      lessThan(1e-6),
      reason: 'and ends exactly on the image of C',
    );
    // Since Phase 117 the walked samples are adaptive while coreSamples
    // is the (canonical) scan slice — on a gapless bounded sweep that is
    // every scan sample, and each lies on the same parabola piece.
    expect(
      locus.coreSamples,
      hasLength(locus.sampleCount),
      reason: 'a bounded sweep has no far-out samples — all scan is core',
    );
    for (final p in locus.coreSamples!) {
      expect((p.x - p.y * p.y / 4).abs(), lessThan(1e-6 * (1 + p.x.abs())));
      expect(p.y, inInclusiveRange(-2 - 1e-9, 2 + 1e-9));
    }
  });

  test('apatitos-topos.rgl (transversal crossings): the traced circumcentre '
      'rides one straight line, both crossings included', () {
    // The Phase 117b document. D sweeps circle a; E is the intersection
    // of a with segment CD, so D itself is always one of E's two roots
    // and the pair crosses *transversally* at each tangent point from C
    // — the collapse law is linear, not the √ law Phase 115 fits. The
    // traced point H is the circumcentre of D, G (the tangency point of
    // the tangent from C) and F = mid(C, E).
    //
    // The analytic answer: |CF|·|CD| = ½|CE|·|CD| = ½·pow(C) = ½|CG|², so
    // C has *constant* power about circle DFG. |CH|² − |HG|² is then
    // constant, which is a line perpendicular to CG. Before 117b the walk
    // glided across each crossing inside one accepted step and came out
    // holding the canonical index: a third of the sweep drew the sheet
    // where E has collapsed onto D, a curve merely asymptotic to that
    // line.
    final free = <FreePoint>[];
    final locus = loadLocus('apatitos-topos.rgl', freeOut: free);
    final c = free.singleWhere((p) => p.attributes.name == 'C').position;
    // G is fixed (it does not depend on the driver), so read it off the
    // construction rather than re-deriving it.
    final samples = locus.samples!;
    expect(samples, isNot(contains(null)), reason: 'one closed component');
    final points = samples.cast<Vec2>();
    expect(points.length, greaterThan(64));

    // 2(G − C)·H + |C|² − |G|² = ½|CG|², written as a residual scaled by
    // the sample's own magnitude so the far-out arm is judged fairly.
    const g = Vec2(-1, 1.7320508075688774);
    final k = (c - g).normSquared / 2;
    for (final p in points) {
      final residual = (p - c).normSquared - (p - g).normSquared - k;
      expect(
        residual.abs() / (1 + p.norm),
        lessThan(1e-6),
        reason: 'sample $p left the constant-power line',
      );
    }
    expect(points.first, points.last, reason: 'the sweep closes');
    // The line runs to infinity where D, F, G go collinear, so the trace
    // must actually get out there — a run that stopped short would pass
    // the residual test trivially.
    expect(points.map((p) => p.norm).reduce(math.max), greaterThan(50));
  });

  test('no-locus.rgl (the driver is one of the two roots): the walk holds '
      "the *other* one — the branch the document's own point names", () {
    // A user document whose locus drew nothing. F is glued to line a
    // (the x-axis through A); d is the circle centred A through F, so F
    // itself is always one of the two crossings of d with line c = BF,
    // and G is the other one. The two roots cross transversally where
    // AF ⟂ FB — at t = 0 and t = −8, the feet of the Thales circle over
    // AB — so which of them the *canonical* index names flips with the
    // sweep parameter.
    //
    // The walk used to seed its branch identity at the run's low end,
    // where the driver is a hundred million units out and the canonical
    // index there names F. It then held that branch honestly all the
    // way back: every sample was the driver's own position, so the
    // locus was the x-axis — painted exactly under line a, in the same
    // default colour, and reported as "the locus does not show". The
    // seed is now the driver's *own* parameter, where the document's G
    // pins the branch.
    final locus = loadLocus('no-locus.rgl', freeOut: <FreePoint>[]);
    final samples = locus.samples!;
    expect(samples, isNot(contains(null)), reason: 'one component');
    final points = samples.cast<Vec2>();

    // Every sample is on the curve: P is on line B–F(t) fixes t, and
    // then |P| = |t| says P is on the circle of radius |AF(t)|.
    for (final p in points) {
      final t = (p.x + 8) / (p.y + 1) - 8;
      expect(
        (p.norm - t.abs()).abs() / (1 + p.norm),
        lessThan(1e-6),
        reason: 'sample $p is not a crossing of d and c',
      );
    }
    // …and it is the crossing that is *not* the driver, which is the
    // whole point: the abandoned branch is the x-axis.
    expect(
      points.where((p) => p.y.abs() > 1).length,
      greaterThan(points.length ~/ 2),
      reason: 'the trace is not the driver line',
    );
    // The invariant the seed exists for: a locus passes through the
    // position its traced point actually has.
    final g =
        construction(
              'no-locus.rgl',
            ).objects.singleWhere((o) => o.attributes.name == 'G')
            as GeoPoint;
    expect(
      points.map((p) => p.distanceTo(g.position!)).reduce(math.min),
      lessThan(1e-9),
    );
  });

  test('no-locus.rgl: a branch flip the walk cannot cross is *self-healing* '
      '— sliding F back between A and B brings the locus back', () {
    // The document's two roots cross where AF ⟂ FB, at F = A and F = B,
    // and the drag walk cannot presently carry G across either (Phase
    // 134): at B the frame budget runs out just after the detour, and
    // at A the circle itself has radius zero, so the walk coasts and
    // re-acquires on a coin flip. G therefore lands on the driver's own
    // root and the locus draws the x-axis, invisibly under line a.
    //
    // That is a defect, and this test does not pin it. What it pins is
    // that it stays *recoverable*: `branchIndex` is not written by the
    // pass, so the canonical flip is symmetric and sliding back undoes
    // it. Tracing the chain member instead — which Phase 134 wants, and
    // which its stated Phase 113 reason no longer forbids — adopts the
    // index at the end of every pass, so one uncrossable return leaves
    // the wrong root stored for good: measured at 12 of 12 randomized
    // gesture sequences ending stuck, against 0 of 12 here.
    const steps = [0.02, 0.05, 0.1, 0.25, 0.5, 1.0];
    final rng = math.Random(7);
    for (var trial = 0; trial < 4; trial++) {
      // A fresh document per trial: the point of the test is that no
      // *sequence* of gestures can strand the locus, so each one starts
      // from the state the user opens.
      final json =
          jsonDecode(File('test/fixtures/no-locus.rgl').readAsStringSync())
              as Map<String, dynamic>;
      final construction = decodeDocument(json).construction;
      final f = construction.objects.whereType<PointOnObject>().single;
      final locus = construction.objects.whereType<Locus>().single;

      void slideTo(double target, double step) {
        final session = DragSession.start(construction, f, f.position!)!;
        var at = f.parameter;
        final dir = target > at ? 1.0 : -1.0;
        while (dir * (target - at) > 1e-9) {
          at += dir * step;
          if (dir * (at - target) > 0) at = target;
          session.update(Vec2(at, 0));
        }
        session.end()?.apply(construction);
      }

      for (var gesture = 0; gesture < 6; gesture++) {
        slideTo(-14 + rng.nextDouble() * 20, steps[rng.nextInt(steps.length)]);
      }
      slideTo(-4, 0.25);
      expect(
        locus.samples!.any((p) => p != null && p.y.abs() > 1e-9),
        isTrue,
        reason: 'trial $trial left the locus stuck on the driver root',
      );
    }
  });

  test('locus-miss-2.json (twin tangent points): one closed figure-eight, '
      'no gap and no dropped half', () {
    // Traced is itself the coalescing intersection; the walk must flip
    // through both tangencies and close. Failure history: pre-39b the
    // sweep drew only the reachable half of the eight, with a hole at
    // the wrap of the circle-host parameter.
    final locus = loadLocus('locus-miss-2.json', freeOut: <FreePoint>[]);
    expect(
      locus.samples,
      isNot(contains(null)),
      reason: 'a single closed component — no hole',
    );
    final points = locus.samples!.cast<Vec2>();
    expect(points.first, points.last, reason: 'the walk closes the eight');
    expect(points.length, greaterThan(50));
  });
}
