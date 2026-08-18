import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';

/// Phase 126: the theorem the mini-tutorial promises the user.
///
/// Phase 125's coverage gate shows every kind *responds* to the absolute;
/// it deliberately does not show the response is right, and said so. This
/// is one of the places that debt gets paid, and it is the right one to
/// pay first because it is what the geometry menu's guide tells a user to
/// go and build: a triangle's angles sum to less than a straight angle in
/// hyperbolic geometry, more in elliptic, and exactly π in Euclidean.
///
/// It is also a strong test of the angle measure for a reason unrelated to
/// the tutorial: the sum is a *global* fact about three independent
/// measurements, so an angle formula that is wrong by a scale, a sign, a
/// supplement or a chart artefact cannot survive it at three separate
/// triangles.
void main() {
  /// The angle sum of the triangle on [a], [b], [c] under [metric].
  double sumOf(FundamentalConic metric, Vec2 a, Vec2 b, Vec2 c) {
    final construction = Construction(kernel: DocumentKernel(metric: metric));
    final points = {
      'a': FreePoint(id: 'a', position: a),
      'b': FreePoint(id: 'b', position: b),
      'c': FreePoint(id: 'c', position: c),
    };
    for (final p in points.values) {
      construction.add(p);
    }
    // Each corner: the wedge between the two sides meeting there.
    const corners = [('a', 'b', 'c'), ('b', 'c', 'a'), ('c', 'a', 'b')];
    var sum = 0.0;
    for (final (vertex, arm1, arm2) in corners) {
      final angle = VertexAngle(
        id: 'angle-$vertex',
        arm1: points[arm1]!,
        vertex: points[vertex]!,
        arm2: points[arm2]!,
      );
      construction.add(angle);
      final measure = angle.measure;
      expect(measure, isNotNull, reason: '$metric at $vertex');
      sum += measure!;
    }
    return sum;
  }

  // Well inside the unit disc, so the hyperbolic figure is entirely in
  // the plane and the elliptic one is nowhere near the point at infinity
  // of the chart. Three shapes rather than one: a defect that came from
  // a formula error rather than from the geometry would not track the
  // area across all of them.
  const triangles = [
    (Vec2(-0.5, -0.3), Vec2(0.5, -0.3), Vec2(0.0, 0.55)),
    (Vec2(-0.2, -0.1), Vec2(0.15, -0.12), Vec2(0.0, 0.18)),
    (Vec2(-0.7, -0.6), Vec2(0.72, -0.55), Vec2(0.05, 0.75)),
  ];

  test('Euclidean: exactly a straight angle, at every shape', () {
    for (final (a, b, c) in triangles) {
      expect(
        sumOf(FundamentalConic.euclidean, a, b, c),
        closeTo(math.pi, 1e-12),
        reason: '$a $b $c',
      );
    }
  });

  test('hyperbolic: less than a straight angle — a defect', () {
    for (final (a, b, c) in triangles) {
      final sum = sumOf(FundamentalConic.hyperbolic, a, b, c);
      expect(sum, lessThan(math.pi - 1e-6), reason: '$a $b $c');
      expect(sum, greaterThan(0), reason: '$a $b $c');
    }
  });

  test('elliptic: more than a straight angle — an excess', () {
    for (final (a, b, c) in triangles) {
      final sum = sumOf(FundamentalConic.elliptic, a, b, c);
      expect(sum, greaterThan(math.pi + 1e-6), reason: '$a $b $c');
    }
  });

  test('the defect grows with the triangle, which is the theorem', () {
    // The defect *is* the area (Gauss–Bonnet), so a bigger triangle has a
    // bigger one. This is what the guide tells the user they will see
    // when they drag a corner outwards, so it is worth pinning: a
    // constant offset, or a defect that shrank, would tell the same
    // "less than 180°" story while being a different geometry.
    double defect(double scale) {
      final sum = sumOf(
        FundamentalConic.hyperbolic,
        Vec2(-0.5 * scale, -0.3 * scale),
        Vec2(0.5 * scale, -0.3 * scale),
        Vec2(0, 0.55 * scale),
      );
      return math.pi - sum;
    }

    final defects = [
      for (final s in [0.2, 0.5, 0.8, 1.0]) defect(s),
    ];
    for (var i = 1; i < defects.length; i++) {
      expect(defects[i], greaterThan(defects[i - 1]), reason: 'step $i');
    }
    // And it vanishes in the small-triangle limit: hyperbolic geometry is
    // locally Euclidean, which is why a figure near the disc centre looks
    // ordinary.
    expect(defect(0.01), lessThan(1e-3));
  });
}
