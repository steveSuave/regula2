import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/tools/equilateral_triangle_macro_tool.dart';
import 'package:regula/domain/tools/multi_point_tool.dart';
import 'package:regula/domain/tools/regular_polygon_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// What the two macro tools built on `RotatedPoint` actually build once
/// the rotation under them is a Cayley–Klein one (Phase 127).
///
/// Both tools name a *shape* — "equilateral triangle", "regular polygon"
/// — and both realise it with a rotation through a **constant** angle
/// baked in at build time. That is exactly right in the Euclidean plane
/// and wrong in the other two, and this file is the measurement rather
/// than the fix: it pins what the tools currently produce, how far off it
/// is, and what closure would require.
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

  /// The figure's vertices in build order: the two tapped corners, then
  /// the derived ones in the order the tool chained them.
  List<GeoPoint> vertices(Construction c) =>
      c.objects.whereType<GeoPoint>().toList();

  double side(Absolute absolute, GeoPoint p, GeoPoint q) =>
      distanceBetween(absolute, p.projPoint!, q.projPoint!)!;

  /// The turn that *would* close a regular [n]-gon of Cayley–Klein side
  /// [s], from the standard relation `cos(π/n) = σ(s/2)·sin(θ/2)` between
  /// a regular polygon's half-central-angle and its interior angle θ,
  /// with `σ = cosh` in the hyperbolic plane and `cos` in the elliptic
  /// one. Euclidean is `σ ≡ 1`, which is the whole of why a constant
  /// works there and nowhere else.
  ///
  /// Computed here rather than in `lib/` on purpose: nothing ships this
  /// yet, and the tests below are what establishes that it is the right
  /// thing to ship.
  double closingTurn(int n, double s, Absolute absolute) {
    final sigma = absolute.metric == FundamentalConic.hyperbolic
        ? (math.exp(s / 2) + math.exp(-s / 2)) / 2
        : math.cos(s / 2);
    return 2 * math.asin(math.cos(math.pi / n) / sigma);
  }

  group('EquilateralTriangleMacroTool under a proper absolute', () {
    test('the apex angle is exactly 60° in every geometry', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        final tool = EquilateralTriangleMacroTool(newId: () => 'n${_id++}');
        final v = vertices(
          stamped(tool, absolute, const Vec2(0, 0), const Vec2(0.6, 0)),
        );
        final atA = angleBetweenLines(
          absolute,
          v[0].projPoint!.join(v[1].projPoint!),
          v[0].projPoint!.join(v[2].projPoint!),
        );
        expect(
          atA,
          closeTo(math.pi / 3, 1e-12),
          reason:
              '$metric: ckRotation is an isometry and turns by what it is '
              'asked to — 60° is delivered exactly. That is the defect, '
              'not a symptom of one: a 60° apex is equilateral only where '
              'the angles of a triangle sum to π',
        );
      }
    });

    test('the two legs are equal and the base is not', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        final tool = EquilateralTriangleMacroTool(newId: () => 'n${_id++}');
        final v = vertices(
          stamped(tool, absolute, const Vec2(0, 0), const Vec2(0.6, 0)),
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

    test('the base errs long in hyperbolic and short in elliptic', () {
      double ratio(FundamentalConic metric, double bx) {
        final absolute = Absolute.of(metric);
        final tool = EquilateralTriangleMacroTool(newId: () => 'n${_id++}');
        final v = vertices(
          stamped(tool, absolute, const Vec2(0, 0), Vec2(bx, 0)),
        );
        return side(absolute, v[1], v[2]) / side(absolute, v[0], v[1]);
      }

      // Sign: a hyperbolic triangle's angles sum to less than π, so a 60°
      // apex over-opens the figure; an elliptic one's sum to more, so it
      // under-opens. Magnitude: the error is a function of the side, and
      // it is not small — a triangle spanning most of the disc is a fifth
      // out. `bx` is a chart coordinate, so 0.9 is well inside the unit
      // absolute and still a long way across the plane.
      expect(ratio(FundamentalConic.hyperbolic, 0.1), closeTo(1.0013, 1e-4));
      expect(ratio(FundamentalConic.hyperbolic, 0.6), closeTo(1.0581, 1e-4));
      expect(ratio(FundamentalConic.hyperbolic, 0.9), closeTo(1.2282, 1e-4));
      expect(ratio(FundamentalConic.elliptic, 0.1), closeTo(0.9988, 1e-4));
      expect(ratio(FundamentalConic.elliptic, 0.6), closeTo(0.9629, 1e-4));
      expect(ratio(FundamentalConic.elliptic, 0.9), closeTo(0.9308, 1e-4));
    });
  });

  group('RegularPolygonMacroTool under a proper absolute', () {
    test('every chained side is equal — the ring simply does not close', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        for (final n in [3, 6, 8]) {
          final tool = RegularPolygonMacroTool(
            newId: () => 'n${_id++}',
            sideCount: n,
          );
          final v = vertices(
            stamped(tool, absolute, const Vec2(0, 0), const Vec2(0.3, 0)),
          );
          expect(v, hasLength(n));
          final first = side(absolute, v[0], v[1]);
          for (var k = 1; k < n - 1; k++) {
            expect(
              side(absolute, v[k], v[k + 1]),
              closeTo(first, 1e-9),
              reason:
                  '$metric n=$n: every vertex is an isometric image of the '
                  'previous-but-one, so the chain is equilateral as far as '
                  'it goes',
            );
          }
          expect(
            side(absolute, v[n - 1], v[0]),
            isNot(closeTo(first, 1e-6)),
            reason:
                '$metric n=$n: but the last vertex does not land adjacent '
                'to the first, and the closing segment draws a side that '
                'is not one',
          );
        }
      }
    });

    test('the closing side is off by enough to see', () {
      double error(FundamentalConic metric, int n, double bx) {
        final absolute = Absolute.of(metric);
        final tool = RegularPolygonMacroTool(
          newId: () => 'n${_id++}',
          sideCount: n,
        );
        final v = vertices(
          stamped(tool, absolute, const Vec2(0, 0), Vec2(bx, 0)),
        );
        return side(absolute, v[n - 1], v[0]) / side(absolute, v[0], v[1]);
      }

      // The chain accumulates the per-vertex angle error, so the gap grows
      // with the vertex count as well as with the side. A hyperbolic
      // octagon of modest side closes with a segment nearly four times the
      // length of its other sides; this is a visibly broken figure, not a
      // rounding complaint.
      expect(error(FundamentalConic.hyperbolic, 6, 0.3), closeTo(1.2201, 1e-4));
      expect(error(FundamentalConic.hyperbolic, 8, 0.6), closeTo(3.8242, 1e-4));
      expect(error(FundamentalConic.elliptic, 6, 0.3), closeTo(0.8132, 1e-4));
      expect(error(FundamentalConic.elliptic, 8, 0.6), closeTo(0.3615, 1e-4));
    });
  });

  group('what closure would require', () {
    test('a side-dependent turn closes the ring exactly, for every n', () {
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
            for (var k = 0; k < n; k++) {
              expect(
                side(absolute, chain[k], chain[(k + 1) % n]),
                closeTo(s, 1e-9),
                reason: '$metric n=$n bx=$bx: side $k',
              );
            }
          }
        }
      }
    });

    test('and no constant can serve, because that turn moves with the '
        'side', () {
      for (final metric in proper) {
        final absolute = Absolute.of(metric);
        final short = closingTurn(6, 0.1, absolute);
        final long = closingTurn(6, 1.0, absolute);
        expect(
          (short - long).abs(),
          greaterThan(0.01),
          reason:
              '$metric: the turn a regular hexagon needs is a function of '
              'its side length. `RotatedPoint.angle` is fixed for the '
              "object's lifetime, so a figure built correct on the stamp "
              'stops being regular the moment a corner is dragged — which '
              'is why the fix is not "bake a better constant"',
        );
        expect(
          short,
          closeTo(2 * math.pi / 3, 0.01),
          reason:
              '$metric: and it tends to the Euclidean interior angle '
              '(2π/3 for a hexagon) as the figure shrinks, which is why '
              'nothing showed up in a small test figure',
        );
      }
    });
  });

  group('the Euclidean answer is untouched', () {
    test('both tools still build exactly what they always did', () {
      final triangle = vertices(
        stamped(
          EquilateralTriangleMacroTool(newId: () => 'n${_id++}'),
          Absolute.euclidean,
          const Vec2(0, 0),
          const Vec2(2, 0),
        ),
      );
      final leg = triangle[0].position!.distanceTo(triangle[1].position!);
      expect(
        triangle[1].position!.distanceTo(triangle[2].position!),
        closeTo(leg, 1e-12),
      );
      expect(
        triangle[2].position!.distanceTo(triangle[0].position!),
        closeTo(leg, 1e-12),
      );

      final hexagon = vertices(
        stamped(
          RegularPolygonMacroTool(newId: () => 'n${_id++}', sideCount: 6),
          Absolute.euclidean,
          const Vec2(0, 0),
          const Vec2(2, 0),
        ),
      );
      for (var k = 0; k < 6; k++) {
        expect(
          hexagon[k].position!.distanceTo(hexagon[(k + 1) % 6].position!),
          closeTo(2, 1e-12),
          reason: 'the Euclidean ring closes: side $k',
        );
      }
    });
  });
}
