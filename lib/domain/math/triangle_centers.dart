/// Closed-form triangle centers.
///
/// All functions take the three vertices in any order. [centroid] is defined
/// for any three points; the other centers return `null` when the triangle
/// is degenerate (vertices collinear or coincident within [isCollinear]'s
/// tolerance), so a construction can mark the dependent object undefined
/// while the user drags through the degeneracy instead of blowing up.
library;

import 'line_eq.dart';
import 'vec2.dart';

/// Intersection of the medians: `(a + b + c) / 3`.
Vec2 centroid(Vec2 a, Vec2 b, Vec2 c) => (a + b + c) / 3;

/// Center of the circle through all three vertices, or `null` when they
/// are collinear.
Vec2? circumcenter(Vec2 a, Vec2 b, Vec2 c, [double epsilon = defaultEpsilon]) {
  if (isCollinear(a, b, c, epsilon)) {
    return null;
  }
  // Standard closed form; the denominator is 4× the signed triangle area.
  final d = 2 * (b - a).cross(c - a);
  final a2 = a.normSquared;
  final b2 = b.normSquared;
  final c2 = c.normSquared;
  return Vec2(
    (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
    (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d,
  );
}

/// Intersection of the altitudes, or `null` when the vertices are collinear.
///
/// Uses the Euler-line identity `H = A + B + C − 2O` (with `O` the
/// circumcenter), which also puts the centroid exactly a third of the way
/// from `O` to `H`.
Vec2? orthocenter(Vec2 a, Vec2 b, Vec2 c, [double epsilon = defaultEpsilon]) {
  final o = circumcenter(a, b, c, epsilon);
  if (o == null) {
    return null;
  }
  return a + b + c - o * 2;
}

/// Center of the inscribed circle, or `null` when the vertices are
/// collinear: the average of the vertices weighted by their opposite side
/// lengths.
Vec2? incenter(Vec2 a, Vec2 b, Vec2 c, [double epsilon = defaultEpsilon]) {
  if (isCollinear(a, b, c, epsilon)) {
    return null;
  }
  final la = b.distanceTo(c);
  final lb = c.distanceTo(a);
  final lc = a.distanceTo(b);
  return (a * la + b * lb + c * lc) / (la + lb + lc);
}

/// Radius of the circle through all three vertices, or `null` when they
/// are collinear.
///
/// The nine-point (Euler) circle is then centered at the midpoint of
/// [circumcenter] and [orthocenter] with radius `circumradius / 2`.
double? circumradius(
  Vec2 a,
  Vec2 b,
  Vec2 c, [
  double epsilon = defaultEpsilon,
]) {
  final o = circumcenter(a, b, c, epsilon);
  return o?.distanceTo(a);
}

/// Radius of the inscribed circle — the distance from the [incenter] to any
/// side — or `null` when the vertices are collinear.
///
/// Closed form `area / semiperimeter`, which for vertices is
/// `|(b−a) × (c−a)| / (|bc| + |ca| + |ab|)`.
double? inradius(Vec2 a, Vec2 b, Vec2 c, [double epsilon = defaultEpsilon]) {
  if (isCollinear(a, b, c, epsilon)) {
    return null;
  }
  final la = b.distanceTo(c);
  final lb = c.distanceTo(a);
  final lc = a.distanceTo(b);
  return (b - a).cross(c - a).abs() / (la + lb + lc);
}
