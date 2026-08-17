import 'intersections.dart';
import 'line_eq.dart';
import 'vec2.dart';

/// The internal bisector of the angle at [vertex] between the rays toward
/// [arm1] and [arm2], or null when either arm point (nearly) coincides
/// with the vertex — no ray, no angle.
///
/// Degenerate-but-defined cases: arms on the same ray bisect to that ray;
/// arms on opposite rays (a straight angle) bisect to the perpendicular
/// at the vertex.
LineEq? angleBisector(Vec2 arm1, Vec2 vertex, Vec2 arm2) {
  if (arm1.closeTo(vertex) || arm2.closeTo(vertex)) {
    return null;
  }
  final u = (arm1 - vertex).normalized();
  final v = (arm2 - vertex).normalized();
  final sum = u + v;
  final diff = u - v;
  // For unit vectors, u+v and u−v are orthogonal and can't both be small:
  // the sum bisects ordinary angles but vanishes toward opposite rays,
  // where the difference (norm → 2) takes over via its perpendicular.
  final direction = sum.normSquared >= diff.normSquared
      ? sum
      : diff.perpendicular;
  return LineEq.pointDirection(vertex, direction);
}

/// One of the two bisectors of the angle between [line1] and [line2] —
/// they form a perpendicular pair through the intersection. [branch] 0
/// bisects along `d̂1 + d̂2` (the lines' unit directions), 1 along
/// `d̂1 − d̂2`.
///
/// Null when the lines are parallel — no unique intersection, no wedge.
/// That gate also keeps both direction sums well away from zero: `d̂1 ±
/// d̂2` only vanishes when the directions (anti-)align, which *is*
/// parallelism.
LineEq? twoLineBisector(LineEq line1, LineEq line2, int branch) {
  final crossing = intersectLineLine(line1, line2);
  if (crossing.isEmpty) {
    return null;
  }
  final d1 = line1.direction;
  final d2 = line2.direction;
  return LineEq.pointDirection(
    crossing.single,
    branch == 0 ? d1 + d2 : d1 - d2,
  );
}
