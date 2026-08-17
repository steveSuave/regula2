/// Intersection routines for the analytic primitives.
///
/// Every function returns 0, 1 or 2 points. When two points are returned
/// their order is *deterministic* for a given argument order — Phase 2's
/// `IntersectionPoint` relies on this so the branch a user picked stays
/// stable while dragging:
///
/// - [intersectLineCircle]: ordered by increasing parameter along the
///   line's [LineEq.direction].
/// - [intersectCircleCircle]: the first point lies to the left of the
///   directed line from `c1.center` to `c2.center` (swapping the arguments
///   swaps the order).
///
/// Coincident lines and coincident circles overlap in infinitely many
/// points; both cases return the empty list, as does any parallel /
/// concentric / non-touching configuration.
library;

import 'dart:math' as math;

import 'circle_eq.dart';
import 'line_eq.dart';
import 'vec2.dart';

/// Intersection of two lines.
///
/// Returns the empty list when the lines are parallel within [epsilon].
/// Both normals are unit length, so [epsilon] bounds the sine of the angle
/// between the lines.
List<Vec2> intersectLineLine(
  LineEq l1,
  LineEq l2, [
  double epsilon = defaultEpsilon,
]) {
  final det = l1.normal.cross(l2.normal);
  if (det.abs() <= epsilon) {
    return const [];
  }
  return [
    Vec2((l1.b * l2.c - l2.b * l1.c) / det, (l2.a * l1.c - l1.a * l2.c) / det),
  ];
}

/// Intersection of a line and a circle.
///
/// Returns two points ordered along the line's direction, one point at
/// tangency (the line's closest approach to the center, so it sits on the
/// line and within [epsilon] of the circle), or none. [epsilon] is a
/// distance tolerance in world units.
List<Vec2> intersectLineCircle(
  LineEq l,
  CircleEq c, [
  double epsilon = defaultEpsilon,
]) {
  final foot = l.project(c.center);
  final d = l.distanceTo(c.center);
  if ((d - c.radius).abs() <= epsilon) {
    return [foot];
  }
  if (d > c.radius) {
    return const [];
  }
  final half = math.sqrt(c.radius * c.radius - d * d);
  final offset = l.direction * half;
  return [foot - offset, foot + offset];
}

/// Intersection of two circles.
///
/// Returns two points (the first to the left of the directed center line
/// `c1.center → c2.center`), one point at external or internal tangency,
/// or none (separate, one inside the other, or concentric — which includes
/// coincident circles). [epsilon] is a distance tolerance in world units.
List<Vec2> intersectCircleCircle(
  CircleEq c1,
  CircleEq c2, [
  double epsilon = defaultEpsilon,
]) {
  final delta = c2.center - c1.center;
  final d = delta.norm;
  if (d <= epsilon) {
    return const [];
  }
  final r1 = c1.radius;
  final r2 = c2.radius;
  // Distance from c1.center to the chord midpoint, along the center line.
  final a = (d * d + r1 * r1 - r2 * r2) / (2 * d);
  final u = delta / d;
  final mid = c1.center + u * a;
  final externallyTangent = (d - (r1 + r2)).abs() <= epsilon;
  final internallyTangent = (d - (r1 - r2).abs()).abs() <= epsilon;
  if (externallyTangent || internallyTangent) {
    return [mid];
  }
  if (d > r1 + r2 || d < (r1 - r2).abs()) {
    return const [];
  }
  final h = math.sqrt(math.max(0.0, r1 * r1 - a * a));
  final offset = u.perpendicular * h;
  return [mid + offset, mid - offset];
}
