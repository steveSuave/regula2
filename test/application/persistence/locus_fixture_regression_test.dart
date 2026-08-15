import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/math/vec2.dart';

/// Regression tests over the two user documents that drove Phases 39b–39d,
/// kept verbatim in `test/fixtures/`. They load through the real codec so
/// the whole path — decode, chain construction, sweep, walk, boundary
/// refinement — is exercised on real-world geometry, not scaled fixtures.
void main() {
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
      final residual =
          (p - c).normSquared - (p - g).normSquared - k;
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
