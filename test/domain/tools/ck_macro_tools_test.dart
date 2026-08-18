import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/tools/equilateral_triangle_macro_tool.dart';
import 'package:regula/domain/tools/multi_point_tool.dart';
import 'package:regula/domain/tools/regular_polygon_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// The two macro tools that name a *shape* — "equilateral triangle",
/// "regular polygon" — under a proper absolute (Phase 128, PLAN §"A shape
/// is not an angle").
///
/// Both used to realise their shape with a rotation through a constant
/// angle baked in at build time. That is exactly right in the Euclidean
/// plane and wrong in the other two, and the first group here pins *why*
/// as a fact about the geometry rather than about the tools, since it is
/// the whole reason they dispatch.

/// Ids for the throwaway tools below; nothing here reads them back.
int _id = 0;

void main() {
  const proper = [FundamentalConic.hyperbolic, FundamentalConic.elliptic];

  /// Drives a two-tap macro tool at [a] then [b] in a document whose
  /// geometry is [absolute], and applies the committed command.
  Construction stamped(MultiPointTool tool, Absolute absolute, Vec2 a, Vec2 b) {
    final construction = Construction(
      kernel: DocumentKernel(metric: absolute.metric),
    );
    expect(tool.onInput(ToolInput(a, absolute: absolute)), isA<ToolAccepted>());
    final result =
        tool.onInput(ToolInput(b, absolute: absolute)) as ToolCommitted;
    result.command.apply(construction);
    return construction;
  }

  /// The figure's visible points, in build order.
  List<GeoPoint> corners(Construction c) => [
    for (final o in c.objects)
      if (o is GeoPoint && o.attributes.visible) o,
  ];

  double side(Absolute absolute, GeoPoint p, GeoPoint q) =>
      distanceBetween(absolute, p.projPoint!, q.projPoint!)!;

  /// Asserts every side of the closed ring [ring] is the same length, in
  /// whichever measure [absolute] has — the chart under Euclidean, whose
  /// distance is not a cross-ratio at all.
  void expectRegular(Absolute absolute, List<GeoPoint> ring, {String? why}) {
    double measure(GeoPoint p, GeoPoint q) => absolute.isEuclidean
        ? p.position!.distanceTo(q.position!)
        : side(absolute, p, q);
    final first = measure(ring[0], ring[1]);
    expect(first, greaterThan(0));
    for (var k = 1; k < ring.length; k++) {
      expect(
        measure(ring[k], ring[(k + 1) % ring.length]),
        closeTo(first, 1e-9),
        reason:
            '${absolute.metric}: side $k of ${ring.length}${why == null ? '' : ' — $why'}',
      );
    }
  }

  group('a constant angle does not name a shape', () {
    /// The turn that closes a regular [n]-gon of Cayley–Klein side [s],
    /// from `cos(π/n) = σ(s/2)·sin(θ/2)` with `σ = cosh` hyperbolic and
    /// `cos` elliptic. Euclidean is `σ ≡ 1`, which is the whole of why a
    /// constant works there and nowhere else.
    double closingTurn(int n, double s, Absolute absolute) {
      final sigma = absolute.metric == FundamentalConic.hyperbolic
          ? (math.exp(s / 2) + math.exp(-s / 2)) / 2
          : math.cos(s / 2);
      return 2 * math.asin(math.cos(math.pi / n) / sigma);
    }

    /// A, B and B turned about A by [apexAngle], in the plain kernel —
    /// the construction both tools used to make, with no tool in the way.
    List<GeoPoint> turned(FundamentalConic metric, double bx, double angle) {
      final construction = Construction(kernel: DocumentKernel(metric: metric));
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: Vec2(bx, 0));
      construction
        ..add(a)
        ..add(b);
      final c = RotatedPoint(id: 'C', point: b, center: a, angle: angle);
      construction.add(c);
      return [a, b, c];
    }

    test('the rotation delivers 60° exactly — that is the defect', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        final v = turned(metric, 0.6, math.pi / 3);
        expect(
          angleBetweenLines(
            absolute,
            v[0].projPoint!.join(v[1].projPoint!),
            v[0].projPoint!.join(v[2].projPoint!),
          ),
          closeTo(math.pi / 3, 1e-12),
          reason:
              '$metric: ckRotation is an isometry and turns by what it is '
              'asked to. A 60° apex is equilateral only where the angles '
              'of a triangle sum to π, so exactness here is the problem',
        );
        final leg = side(absolute, v[0], v[1]);
        expect(
          side(absolute, v[0], v[2]),
          closeTo(leg, 1e-12),
          reason: '$metric: the apex is an isometric image of B about A',
        );
        expect(
          side(absolute, v[1], v[2]),
          isNot(closeTo(leg, 1e-6)),
          reason: '$metric: so the figure is isoceles, not equilateral',
        );
      }
    });

    test('and the base errs long in hyperbolic, short in elliptic', () {
      double ratio(FundamentalConic metric, double bx) {
        final absolute = Absolute.of(metric);
        final v = turned(metric, bx, math.pi / 3);
        return side(absolute, v[1], v[2]) / side(absolute, v[0], v[1]);
      }

      // Sign: a hyperbolic triangle's angles sum to less than π, so a 60°
      // apex over-opens the figure; an elliptic one's sum to more, so it
      // under-opens. Magnitude: the error is a function of the side and
      // is not small. `bx` is a chart coordinate, so 0.9 is well inside
      // the unit absolute and still a long way across the plane.
      expect(ratio(FundamentalConic.hyperbolic, 0.1), closeTo(1.0013, 1e-4));
      expect(ratio(FundamentalConic.hyperbolic, 0.6), closeTo(1.0581, 1e-4));
      expect(ratio(FundamentalConic.hyperbolic, 0.9), closeTo(1.2282, 1e-4));
      expect(ratio(FundamentalConic.elliptic, 0.1), closeTo(0.9988, 1e-4));
      expect(ratio(FundamentalConic.elliptic, 0.6), closeTo(0.9629, 1e-4));
      expect(ratio(FundamentalConic.elliptic, 0.9), closeTo(0.9308, 1e-4));
    });

    test('a chain of constant turns leaves the ring open', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        for (final n in [3, 6, 8]) {
          final construction = Construction(
            kernel: DocumentKernel(metric: metric),
          );
          final a = FreePoint(id: 'A', position: const Vec2(0, 0));
          final b = FreePoint(id: 'B', position: const Vec2(0.3, 0));
          construction
            ..add(a)
            ..add(b);
          final chain = <GeoPoint>[a, b];
          for (var k = 2; k < n; k++) {
            final vertex = RotatedPoint(
              id: 'v$k',
              point: chain[k - 2],
              center: chain[k - 1],
              angle: 2 * math.pi / n - math.pi,
            );
            construction.add(vertex);
            chain.add(vertex);
          }
          final first = side(absolute, chain[0], chain[1]);
          for (var k = 1; k < n - 1; k++) {
            expect(
              side(absolute, chain[k], chain[k + 1]),
              closeTo(first, 1e-9),
              reason:
                  '$metric n=$n: every vertex is an isometric image of the '
                  'previous-but-one, so the chain is equilateral as far as '
                  'it goes',
            );
          }
          expect(
            side(absolute, chain[n - 1], chain[0]),
            isNot(closeTo(first, 1e-6)),
            reason:
                '$metric n=$n: but the last vertex does not land adjacent '
                'to the first, and a closing segment would draw a side '
                'that is not one',
          );
        }
      }
    });

    test('a side-dependent turn does close it, for every n', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        for (final n in [3, 5, 6, 8]) {
          for (final bx in [0.1, 0.3, 0.6]) {
            final construction = Construction(
              kernel: DocumentKernel(metric: metric),
            );
            final a = FreePoint(id: 'A', position: const Vec2(0, 0));
            final b = FreePoint(id: 'B', position: Vec2(bx, 0));
            construction
              ..add(a)
              ..add(b);
            final s = side(absolute, a, b);
            final chain = <GeoPoint>[a, b];
            for (var k = 2; k < n; k++) {
              final vertex = RotatedPoint(
                id: 'v$k',
                point: chain[k - 2],
                center: chain[k - 1],
                angle: -closingTurn(n, s, absolute),
              );
              construction.add(vertex);
              chain.add(vertex);
            }
            expectRegular(absolute, chain, why: 'bx=$bx');
          }
        }
      }
    });

    test('but no constant serves, because that turn moves with the side', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        final small = closingTurn(6, 0.1, absolute);
        final large = closingTurn(6, 1.0, absolute);
        expect(
          (small - large).abs(),
          greaterThan(0.01),
          reason:
              '$metric: the turn a regular hexagon needs is a function of '
              'its side length. `RotatedPoint.angle` is fixed for the '
              "object's lifetime, so a figure built correct on the stamp "
              'stops being regular at the first drag — which is why the '
              'fix is not "bake a better constant"',
        );
        expect(
          small,
          closeTo(2 * math.pi / 3, 0.01),
          reason:
              '$metric: and it tends to the Euclidean interior angle as '
              'the figure shrinks, which is why nothing showed up in a '
              'small test figure',
        );
      }
    });
  });

  group('EquilateralTriangleMacroTool', () {
    EquilateralTriangleMacroTool tool() =>
        EquilateralTriangleMacroTool(newId: () => 'n${_id++}');

    test('is equilateral under every absolute', () {
      for (final metric in FundamentalConic.values) {
        final absolute = Absolute.of(metric);
        for (final bx in [0.1, 0.6, 0.9]) {
          final c = stamped(tool(), absolute, const Vec2(0, 0), Vec2(bx, 0));
          expectRegular(absolute, corners(c), why: 'bx=$bx');
        }
      }
    });

    test('the apex stays left of A→B, and tap order still picks the side', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        for (final pair in [
          (const Vec2(0, 0), const Vec2(0.6, 0)),
          (const Vec2(-0.4, 0.2), const Vec2(0.3, -0.5)),
        ]) {
          for (final swapped in [false, true]) {
            final a = swapped ? pair.$2 : pair.$1;
            final b = swapped ? pair.$1 : pair.$2;
            final v = corners(stamped(tool(), absolute, a, b));
            final d = b - a;
            final toApex = v[2].position! - a;
            expect(
              d.x * toApex.y - d.y * toApex.x,
              greaterThan(0),
              reason:
                  '$metric A=$a B=$b: the branch is picked by side, not '
                  'taken as index 0 — the candidate order follows the '
                  'conic solver and reverses with the tap order',
            );
          }
        }
      }
    });

    test('the Euclidean route keeps its scaffolding-free apex', () {
      final c = stamped(
        tool(),
        Absolute.euclidean,
        const Vec2(0, 0),
        const Vec2(2, 0),
      );
      expect(c.length, 6, reason: '2 corners + apex + 3 sides');
      expect(c.objects.whereType<RotatedPoint>(), hasLength(1));
      expect(c.objects.whereType<IntersectionPoint>(), isEmpty);
      expect(
        c.objects.whereType<GeoCircle>(),
        isEmpty,
        reason: 'no hidden circles where the constant angle is exact',
      );
      expect(
        c.objects.whereType<RotatedPoint>().single.position!.closeTo(
          Vec2(1, math.sqrt(3)),
          1e-12,
        ),
        isTrue,
      );
    });

    test('a proper absolute builds Euclid I.1, circles hidden', () {
      final c = stamped(
        tool(),
        Absolute.hyperbolic,
        const Vec2(0, 0),
        const Vec2(0.6, 0),
      );
      expect(c.length, 8, reason: '2 corners + 2 circles + apex + 3 sides');
      final circles = c.objects.whereType<GeoCircle>().toList();
      expect(circles, hasLength(2));
      expect(
        circles.every((circle) => !circle.attributes.visible),
        isTrue,
        reason: 'the circles are the construction, not the figure',
      );
      expect(c.objects.whereType<IntersectionPoint>(), hasLength(1));
      expect(c.objects.whereType<RotatedPoint>(), isEmpty);
      expect(c.objects.whereType<Segment>(), hasLength(3));
    });

    test('dragging a corner keeps it equilateral in a hyperbolic plane', () {
      const absolute = Absolute.hyperbolic;
      final c = stamped(tool(), absolute, const Vec2(0, 0), const Vec2(0.3, 0));
      final a = c.objects.whereType<FreePoint>().first;

      for (final to in [const Vec2(-0.2, 0.5), const Vec2(0.55, -0.35)]) {
        c.moveFreePoint(a.id, to);
        expectRegular(absolute, corners(c), why: 'after dragging A to $to');
      }
    });

    test('re-stamping over the same corners reuses the apex and drops the '
        'circles', () {
      const absolute = Absolute.hyperbolic;
      final construction = Construction(
        kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
      );
      final a = FreePoint(id: 'A', position: const Vec2(0, 0));
      final b = FreePoint(id: 'B', position: const Vec2(0.3, 0));
      construction
        ..add(a)
        ..add(b);
      final macro = tool();
      ToolResult tap(FreePoint at) => macro.onInput(
        ToolInput(
          at.position,
          hit: at,
          objects: construction.objects,
          absolute: absolute,
        ),
      );

      tap(a);
      (tap(b) as ToolCommitted).command.apply(construction);
      final apex = construction.objects.whereType<IntersectionPoint>().single;
      final before = construction.length;

      tap(a);
      (tap(b) as ToolCommitted).command.apply(construction);

      expect(
        construction.objects.whereType<IntersectionPoint>().single,
        same(apex),
        reason: 'the apex is reused, not stacked',
      );
      expect(
        construction.length,
        before + 3,
        reason:
            'only the three side segments are re-added — with nothing left '
            'for the circles to carry, they are dropped with the apex',
      );
    });
  });

  group('RegularPolygonMacroTool', () {
    RegularPolygonMacroTool tool(int n) =>
        RegularPolygonMacroTool(newId: () => 'n${_id++}', sideCount: n);

    test('the Euclidean route still chains two adjacent vertices', () {
      for (final n in [3, 6, 8]) {
        final c = stamped(
          tool(n),
          Absolute.euclidean,
          const Vec2(0, 0),
          const Vec2(2, 0),
        );
        final ring = corners(c);
        expect(ring, hasLength(n));
        expect(
          ring[0].position,
          const Vec2(0, 0),
          reason: 'the first tap is a vertex, not a centre',
        );
        expectRegular(Absolute.euclidean, ring);
        expect(
          ring[0].position!.distanceTo(ring[1].position!),
          closeTo(2, 1e-12),
          reason: 'and the tapped side is the polygon side',
        );
      }
    });

    test('a proper absolute reads the taps as centre and vertex, and the '
        'ring closes', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        for (final n in [3, 5, 6, 8]) {
          for (final bx in [0.1, 0.3, 0.6]) {
            final c = stamped(tool(n), absolute, const Vec2(0, 0), Vec2(bx, 0));
            final ring = corners(c);
            expect(
              ring,
              hasLength(n + 1),
              reason: 'the centre is a visible point but not a vertex',
            );
            expectRegular(absolute, ring.sublist(1), why: 'n=$n bx=$bx');
          }
        }
      }
    });

    test('every vertex is the same distance from the centre', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        final c = stamped(
          tool(7),
          absolute,
          const Vec2(0, 0),
          const Vec2(0, 0.5),
        );
        final ring = corners(c);
        final radius = side(absolute, ring[0], ring[1]);
        for (var k = 2; k < ring.length; k++) {
          expect(
            side(absolute, ring[0], ring[k]),
            closeTo(radius, 1e-9),
            reason: '$metric: vertex $k is on the orbit, so on the circle',
          );
        }
      }
    });

    test('dragging the centre or the vertex keeps it regular', () {
      const absolute = Absolute.hyperbolic;
      final c = stamped(
        tool(6),
        absolute,
        const Vec2(0, 0),
        const Vec2(0.3, 0),
      );
      final free = c.objects.whereType<FreePoint>().toList();

      c.moveFreePoint(free[0].id, const Vec2(-0.2, 0.1));
      expectRegular(absolute, corners(c).sublist(1), why: 'centre moved');

      c.moveFreePoint(free[1].id, const Vec2(0.4, 0.45));
      expectRegular(absolute, corners(c).sublist(1), why: 'vertex moved');
    });
  });
}
