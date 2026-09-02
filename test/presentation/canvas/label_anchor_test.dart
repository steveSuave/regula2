import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/presentation/canvas/label_anchor.dart';

import '../../projective_stubs.dart';

void main() {
  final origin = FreePoint(id: 'o', position: Vec2.zero);
  final east = FreePoint(id: 'e', position: const Vec2(4, 0));
  final north = FreePoint(id: 'n', position: const Vec2(0, 4));

  void expectAnchor(Vec2 actual, Vec2 expected) {
    expect(
      actual.closeTo(expected),
      isTrue,
      reason: 'expected $expected, got $actual',
    );
  }

  group('labelAnchor', () {
    test('point: the point itself', () {
      expectAnchor(labelAnchor(east), const Vec2(4, 0));
    });

    test('segment: the midpoint', () {
      final segment = Segment(id: 's', point1: east, point2: north);
      expectAnchor(labelAnchor(segment), const Vec2(2, 2));
    });

    test('ray: the origin', () {
      final ray = Ray(id: 'r', origin: east, through: north);
      expectAnchor(labelAnchor(ray), const Vec2(4, 0));
    });

    test('infinite line: the anchor closest to the world origin', () {
      final a = FreePoint(id: 'a', position: const Vec2(0, 2));
      final b = FreePoint(id: 'b', position: const Vec2(4, 2));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      expectAnchor(labelAnchor(line), const Vec2(0, 2));
    });

    test('circle: the top of the rim', () {
      final circle = CircleCenterPoint(id: 'k', center: origin, onCircle: east);
      expectAnchor(labelAnchor(circle), const Vec2(0, 4));
    });

    test('arc: the middle of the drawn branch', () {
      // Unit-scaled half circle from (4,0) through (0,4) to (-4,0):
      // CCW sweep of pi, so the branch midpoint is the top.
      final west = FreePoint(id: 'w', position: const Vec2(-4, 0));
      final arc = Arc(id: 'arc', start: east, via: north, end: west);
      expectAnchor(labelAnchor(arc), const Vec2(0, 4));
    });

    test('sector: the middle of the rim branch', () {
      // Quarter wedge from (4,0) CCW to (0,4): the rim midpoint is at 45°.
      final sector = Sector(id: 'w', center: origin, start: east, end: north);
      final diagonal = 4 / math.sqrt2;
      expectAnchor(labelAnchor(sector), Vec2(diagonal, diagonal));
    });

    test('angle: the vertex', () {
      final angle = VertexAngle(
        id: 'g',
        arm1: east,
        vertex: origin,
        arm2: north,
      );
      expectAnchor(labelAnchor(angle), Vec2.zero);
    });

    test('locus: the first core sample, never a diverging arm '
        '(Phase 39f)', () {
      final locus = _StubLocus(
        samples: const [Vec2(-1e6, 1e5), Vec2(2, 1), Vec2(1e6, 1e5)],
        coreSamples: const [Vec2(2, 1)],
      );
      expectAnchor(labelAnchor(locus), const Vec2(2, 1));
    });

    test('locus with an all-gap core anchors at the world origin', () {
      final locus = _StubLocus(
        samples: const [Vec2(-1e6, 1e5), null, Vec2(1e6, 1e5)],
        coreSamples: const [],
      );
      expectAnchor(labelAnchor(locus), Vec2.zero);
    });
  });
  group('conic anchors (Phase 119)', () {
    test('a circle-shaped conic still hangs from the top of the rim', () {
      // r = 5 about (2, 1): the arm must not change for circles.
      final anchor = labelAnchor(
        StubProjectiveConic(ConicMatrix.coefficients(1, 0, 1, -4, -2, -20)),
      );
      expect(anchor.x, closeTo(2, 1e-9));
      expect(anchor.y, closeTo(6, 1e-9));
    });

    test('a conic with no rim hangs from a point of its curve', () {
      // x²/4 + y²/9 = 1.
      final conic = ConicMatrix.coefficients(1 / 4, 0, 1 / 9, 0, 0, -1);
      final anchor = labelAnchor(StubProjectiveConic(conic));
      expect(conic.containsPoint(ProjPoint.lift(anchor)), isTrue);
    });

    test('a line pair hangs from the lines\' crossing', () {
      // (y − x)(y + x) = 0, crossing at the origin.
      final anchor = labelAnchor(
        StubProjectiveConic(ConicMatrix.coefficients(1, 0, -1, 0, 0, 0)),
      );
      expect(anchor.closeTo(Vec2.zero, 1e-9), isTrue);
    });

    test('parallel lines hang from a point of one of them', () {
      // x = ±1: the crossing is at infinity, so the meet cannot serve.
      final anchor = labelAnchor(
        StubProjectiveConic(ConicMatrix.coefficients(1, 0, 0, 0, 0, -1)),
      );
      expect(anchor.x.abs(), closeTo(1, 1e-9));
    });
  });
}

/// A [GeoLocus] with hand-picked samples and core samples: the anchor
/// consumes the kind accessors only.
class _StubLocus extends GeoLocus {
  _StubLocus({required List<Vec2?>? samples, required List<Vec2> coreSamples})
    : _samples = samples,
      _coreSamples = coreSamples,
      super(id: 'loc');

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
