import 'dart:math' as math;

import 'vec2.dart';

/// A circle as center + radius.
///
/// **A view struct, not a kernel type (Phase 121)** — the circle twin of
/// [LineEq], and the same rules apply. Circles are computed as
/// `ConicMatrix`; this is what one *projects to*, through
/// `ConicMatrix.toCircleEq`, which answers null for anything that is not
/// a real circle (a general conic included — a conic-valued kind
/// overrides `isDefined` rather than pretending). Nothing constructs it
/// outside `lib/domain/`, and inside it only behind a guard.
///
/// A zero radius is allowed (degenerate point-circle) so constructions
/// don't blow up mid-drag when defining points coincide; a negative or
/// non-finite radius is rejected.
class CircleEq {
  CircleEq(this.center, this.radius) {
    if (radius.isNaN || radius.isInfinite || radius < 0) {
      throw ArgumentError.value(
        radius,
        'radius',
        'must be a finite non-negative number',
      );
    }
  }

  /// The circle centered at [center] passing through [onCircle].
  factory CircleEq.centerAndPoint(Vec2 center, Vec2 onCircle) =>
      CircleEq(center, center.distanceTo(onCircle));

  final Vec2 center;
  final double radius;

  /// Signed distance from [p] to the circle's boundary:
  /// negative inside, zero on the circle, positive outside.
  double signedDistanceTo(Vec2 p) => center.distanceTo(p) - radius;

  double distanceTo(Vec2 p) => signedDistanceTo(p).abs();

  /// Whether [p] lies *on* the circle (not inside it), within [epsilon].
  bool contains(Vec2 p, [double epsilon = defaultEpsilon]) =>
      distanceTo(p) <= epsilon;

  /// The point on the circle at [angle] radians from the positive x-axis.
  Vec2 pointAt(double angle) =>
      center + Vec2(math.cos(angle), math.sin(angle)) * radius;

  /// The [pointAt] angle of [p]'s radial projection onto the circle, in
  /// `(-π, π]`. [p] coincident with [center] has no direction; that (and
  /// only that) returns 0.
  double angleAt(Vec2 p) {
    final offset = p - center;
    return offset.normSquared == 0 ? 0 : math.atan2(offset.y, offset.x);
  }

  bool closeTo(CircleEq other, [double epsilon = defaultEpsilon]) =>
      center.closeTo(other.center, epsilon) &&
      (radius - other.radius).abs() <= epsilon;

  @override
  bool operator ==(Object other) =>
      other is CircleEq && other.center == center && other.radius == radius;

  @override
  int get hashCode => Object.hash(center, radius);

  @override
  String toString() => 'CircleEq(center: $center, radius: $radius)';
}
