import 'dart:math' as math;

import 'vec2.dart';

/// An infinite line in normalized implicit form `a·x + b·y + c = 0`,
/// where `(a, b)` is a unit normal.
///
/// Because the normal is unit length, `a·x + b·y + c` is the *signed
/// distance* of `(x, y)` from the line — that makes distance queries and
/// projections one-liners. Note that `(a, b, c)` and `(-a, -b, -c)` describe
/// the same line with opposite orientation; use [closeTo] for geometric
/// (orientation-blind) equality.
class LineEq {
  const LineEq._(this.a, this.b, this.c);

  /// Creates a line from raw implicit coefficients, normalizing so the
  /// normal `(a, b)` has unit length.
  ///
  /// Throws an [ArgumentError] when [a] and [b] are both zero (no line).
  factory LineEq(double a, double b, double c) {
    final n = math.sqrt(a * a + b * b);
    if (n == 0) {
      throw ArgumentError('LineEq requires a non-zero normal (a, b)');
    }
    return LineEq._(a / n, b / n, c / n);
  }

  /// The line through [p] and [q].
  ///
  /// Throws an [ArgumentError] when the points coincide.
  factory LineEq.throughPoints(Vec2 p, Vec2 q) {
    final delta = q - p;
    if (delta.normSquared == 0) {
      throw ArgumentError(
        'Cannot construct a line through two coincident points',
      );
    }
    return LineEq.pointDirection(p, delta);
  }

  /// The line through [p] with direction [direction].
  ///
  /// Throws an [ArgumentError] for a zero direction.
  factory LineEq.pointDirection(Vec2 p, Vec2 direction) {
    final normal = direction.perpendicular;
    return LineEq(normal.x, normal.y, -normal.dot(p));
  }

  final double a;
  final double b;
  final double c;

  /// Unit normal of the line.
  Vec2 get normal => Vec2(a, b);

  /// Unit direction along the line (the normal rotated 90° clockwise).
  Vec2 get direction => Vec2(b, -a);

  /// An arbitrary point on the line (the one closest to the origin).
  Vec2 get pointOnLine => normal * -c;

  /// Signed distance from [p] to the line; the sign tells which side of the
  /// line [p] is on.
  double signedDistanceTo(Vec2 p) => a * p.x + b * p.y + c;

  double distanceTo(Vec2 p) => signedDistanceTo(p).abs();

  bool contains(Vec2 p, [double epsilon = defaultEpsilon]) =>
      distanceTo(p) <= epsilon;

  /// Orthogonal projection of [p] onto the line (the closest point).
  Vec2 project(Vec2 p) => p - normal * signedDistanceTo(p);

  /// The mirror image of [p] across the line.
  Vec2 reflect(Vec2 p) => p - normal * (2 * signedDistanceTo(p));

  /// The point at signed arc-length [t] along [direction] from
  /// [pointOnLine] — the inverse of [parameterAt].
  ///
  /// This parameterization is tied to the line's *analytic* form: as the
  /// line moves, [pointOnLine] and [direction] move with it, so a fixed
  /// [t] tracks the line but does not stick to whatever points defined it.
  Vec2 pointAt(double t) => pointOnLine + direction * t;

  /// The [pointAt] parameter of [p]'s projection onto the line, i.e.
  /// `pointAt(parameterAt(p)) == project(p)`.
  double parameterAt(Vec2 p) => direction.dot(p - pointOnLine);

  /// Whether the two lines have the same (or opposite) direction.
  ///
  /// Both normals are unit length, so the cross product is the sine of the
  /// angle between the lines and [epsilon] bounds that angle directly.
  bool isParallelTo(LineEq other, [double epsilon = defaultEpsilon]) =>
      normal.cross(other.normal).abs() <= epsilon;

  /// Geometric equality: same line regardless of orientation.
  bool closeTo(LineEq other, [double epsilon = defaultEpsilon]) =>
      isParallelTo(other, epsilon) && other.distanceTo(pointOnLine) <= epsilon;

  @override
  bool operator ==(Object other) =>
      other is LineEq && other.a == a && other.b == b && other.c == c;

  @override
  int get hashCode => Object.hash(a, b, c);

  @override
  String toString() => 'LineEq($a, $b, $c)';
}

/// Whether [a], [b] and [c] lie on a single line, within [epsilon].
///
/// The cross product `(b - a) × (c - a)` is twice the triangle's area, so the
/// tolerance scales with the product of the side lengths to stay
/// magnitude-independent (`sin` of the deviation angle ≤ [epsilon] for
/// non-tiny triangles).
bool isCollinear(Vec2 a, Vec2 b, Vec2 c, [double epsilon = defaultEpsilon]) {
  final ab = b - a;
  final ac = c - a;
  final scale = math.max(1.0, ab.norm * ac.norm);
  return ab.cross(ac).abs() <= epsilon * scale;
}
