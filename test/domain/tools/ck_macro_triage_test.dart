import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/tools/isosceles_trapezium_macro_tool.dart';
import 'package:regula/domain/tools/isosceles_triangle_macro_tool.dart';
import 'package:regula/domain/tools/kite_macro_tool.dart';
import 'package:regula/domain/tools/multi_point_tool.dart';
import 'package:regula/domain/tools/right_triangle_macro_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// The nine macro tools that survived Phase 128, sorted by what happens
/// to their *figure* under a proper absolute (Phase 129, PLAN §"The macro
/// triage").
///
/// Unlike the two Phase 128 fixed, these specify their shapes with metric
/// primitives — perpendicular, compass circle, midpoint, reflection,
/// parallel — every one of which Phase 125 already substituted. So the
/// question each group answers is whether the *figure* survives, not
/// whether the primitive does.

/// Ids for the throwaway tools below; nothing here reads them back.
int _id = 0;

void main() {
  /// Feeds [taps] to [tool] in a document of [absolute]'s geometry until
  /// it commits, and applies the command.
  Construction stamped(
    MultiPointTool tool,
    Absolute absolute,
    List<Vec2> taps,
  ) {
    final construction = Construction(
      kernel: DocumentKernel(metric: absolute.metric),
    );
    for (final tap in taps) {
      final result = tool.onInput(ToolInput(tap, absolute: absolute));
      if (result is ToolCommitted) {
        result.command.apply(construction);
        return construction;
      }
    }
    fail('${tool.runtimeType} never committed under ${absolute.metric}');
  }

  /// The figure's visible points, in build order.
  List<GeoPoint> corners(Construction c) => [
    for (final o in c.objects)
      if (o is GeoPoint && o.attributes.visible) o,
  ];

  /// The distance [absolute] measures — the chart under Euclidean, whose
  /// distance is not a cross-ratio at all.
  double span(Absolute absolute, GeoPoint p, GeoPoint q) => absolute.isEuclidean
      ? p.position!.distanceTo(q.position!)
      : distanceBetween(absolute, p.projPoint!, q.projPoint!)!;

  double angleAt(Absolute absolute, GeoPoint v, GeoPoint p, GeoPoint q) =>
      angleBetweenLines(
        absolute,
        v.projPoint!.join(p.projPoint!),
        v.projPoint!.join(q.projPoint!),
      )!;

  /// Every corner defined and drawable — the thing three of these tools
  /// silently failed at before this phase.
  void expectWholeFigure(Construction c, {required int corners_}) {
    expect(corners(c), hasLength(corners_));
    for (final object in c.objects) {
      final undefined = switch (object) {
        final GeoPoint p => p.position == null,
        final GeoLine l => l.line == null,
        final GeoCircle circle => circle.conic == null,
        _ => false,
      };
      expect(
        undefined,
        isFalse,
        reason: '${object.id} (${object.runtimeType}) has no value',
      );
    }
  }

  group('already right: every primitive in them generalizes', () {
    test('the isosceles triangle has equal legs under every absolute', () {
      for (final metric in FundamentalConic.values) {
        final absolute = Absolute.of(metric);
        final c = stamped(
          IsoscelesTriangleMacroTool(newId: () => 'n${_id++}'),
          absolute,
          const [Vec2(0, 0), Vec2(0.4, 0), Vec2(0.25, 0.45)],
        );
        expectWholeFigure(c, corners_: 3);
        final v = corners(c);
        expect(
          span(absolute, v[2], v[0]),
          closeTo(span(absolute, v[2], v[1]), 1e-9),
          reason:
              '$metric: the apex is glued to the perpendicular bisector of '
              'the base, and both midpoint and perpendicular are metric',
        );
      }
    });

    test('the right triangle has a right angle under every absolute', () {
      for (final metric in FundamentalConic.values) {
        final absolute = Absolute.of(metric);
        final c = stamped(
          RightTriangleMacroTool(newId: () => 'n${_id++}'),
          absolute,
          const [Vec2(0, 0), Vec2(0.4, 0), Vec2(0.35, 0.3)],
        );
        expectWholeFigure(c, corners_: 3);
        final v = corners(c);
        expect(
          angleAt(absolute, v[1], v[0], v[2]),
          closeTo(math.pi / 2, 1e-12),
          reason: '$metric: π/2 is π/2 in every geometry',
        );
      }
    });

    test('but the angle sum is not π, which is the point', () {
      double sum(FundamentalConic metric) {
        final absolute = Absolute.of(metric);
        final v = corners(
          stamped(
            RightTriangleMacroTool(newId: () => 'n${_id++}'),
            absolute,
            const [Vec2(0, 0), Vec2(0.4, 0), Vec2(0.35, 0.3)],
          ),
        );
        return angleAt(absolute, v[0], v[1], v[2]) +
            angleAt(absolute, v[1], v[0], v[2]) +
            angleAt(absolute, v[2], v[0], v[1]);
      }

      expect(sum(FundamentalConic.euclidean), closeTo(math.pi, 1e-12));
      expect(sum(FundamentalConic.hyperbolic), lessThan(math.pi - 0.05));
      expect(sum(FundamentalConic.elliptic), greaterThan(math.pi + 0.04));
    });
  });

  group('right once the reflection stopped being affine', () {
    test('the kite is a kite under every absolute', () {
      for (final metric in FundamentalConic.values) {
        final absolute = Absolute.of(metric);
        // An axis well off the world origin: the polar of a line *through*
        // the origin is the same point for all three absolutes, so a kite
        // centred there would pass whatever the reflection did.
        final c = stamped(
          KiteMacroTool(newId: () => 'n${_id++}'),
          absolute,
          const [Vec2(0.1, 0.1), Vec2(0.5, 0.15), Vec2(0.35, 0.55)],
        );
        expectWholeFigure(c, corners_: 4);
        final v = corners(c);
        final (a, b, apex, d) = (v[0], v[1], v[2], v[3]);
        expect(
          span(absolute, a, d),
          closeTo(span(absolute, a, b), 1e-9),
          reason: '$metric: |AD| = |AB|',
        );
        expect(
          span(absolute, apex, d),
          closeTo(span(absolute, apex, b), 1e-9),
          reason: '$metric: |CD| = |CB|',
        );
      }
    });

    test('the isosceles trapezium keeps its equal legs', () {
      for (final metric in FundamentalConic.values) {
        final absolute = Absolute.of(metric);
        final c = stamped(
          IsoscelesTrapeziumMacroTool(newId: () => 'n${_id++}'),
          absolute,
          const [Vec2(-0.05, 0.1), Vec2(0.45, 0.15), Vec2(0.4, 0.5)],
        );
        expectWholeFigure(c, corners_: 4);
        final v = corners(c);
        expect(
          span(absolute, v[0], v[3]),
          closeTo(span(absolute, v[1], v[2]), 1e-9),
          reason: '$metric: |AD| = |BC|, which the reflection guarantees',
        );
      }
    });

    test('and loses the word trapezium: the base sides are not parallel', () {
      // Two lines perpendicular to a common axis. In the hyperbolic plane
      // they never meet and are not parallel either — ultraparallel, and
      // the figure is a Saccheri quadrilateral. In the elliptic plane they
      // meet at the axis's pole. Only the Euclidean pair is parallel, and
      // the tool's name says so for all three.
      double base(FundamentalConic metric) {
        final absolute = Absolute.of(metric);
        final v = corners(
          stamped(
            IsoscelesTrapeziumMacroTool(newId: () => 'n${_id++}'),
            absolute,
            const [Vec2(-0.05, 0.1), Vec2(0.45, 0.15), Vec2(0.4, 0.5)],
          ),
        );
        return angleAt(absolute, v[0], v[1], v[3]);
      }

      // The base angle is what a pair of parallels would fix: equal to
      // the top angle's supplement in the Euclidean plane and to nothing
      // in the other two, where it moves with the figure's size.
      expect(
        base(FundamentalConic.hyperbolic),
        isNot(closeTo(base(FundamentalConic.euclidean), 1e-6)),
      );
      expect(
        base(FundamentalConic.elliptic),
        isNot(closeTo(base(FundamentalConic.euclidean), 1e-6)),
      );
    });

    test('the CK route carries no scaffolding at all', () {
      final euclidean = stamped(
        KiteMacroTool(newId: () => 'n${_id++}'),
        Absolute.euclidean,
        const [Vec2(0.1, 0.1), Vec2(0.5, 0.15), Vec2(0.35, 0.55)],
      );
      expect(euclidean.objects.whereType<SegmentRatioPoint>(), hasLength(1));
      expect(euclidean.objects.whereType<ReflectedPoint>(), isEmpty);

      final hyperbolic = stamped(
        KiteMacroTool(newId: () => 'n${_id++}'),
        Absolute.hyperbolic,
        const [Vec2(0.1, 0.1), Vec2(0.5, 0.15), Vec2(0.35, 0.55)],
      );
      expect(
        hyperbolic.objects.whereType<SegmentRatioPoint>(),
        isEmpty,
        reason: 'a ratio along a segment is affine (Phase 125)',
      );
      expect(hyperbolic.objects.whereType<ReflectedPoint>(), hasLength(1));
      expect(
        hyperbolic.length,
        lessThan(euclidean.length),
        reason:
            'the harmonic homology needs no perpendicular and no foot, so '
            'the metric route is the shorter one',
      );
    });
  });
}
