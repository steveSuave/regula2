/// **V1's affine circle relations, frozen as a test oracle.**
///
/// Superseded in Phase 110 by `lib/domain/projective/circles.dart`
/// (`radicalAxisOf`), `ConicMatrix`'s polar (`A·p`) and
/// `apolloniusCircleOf`, and left with no `lib/` consumer; moved here in
/// Phase 121.
///
/// Kept for the same reason as `intersections.dart` in this directory —
/// see its header for the argument in full: the projective kernels are
/// specified as *agreeing with V1* on real transverse cases, and that
/// agreement is a permanent contract (v1 documents are permanent), so
/// the build being agreed with has to stay around to be compared against.
/// Nothing under `lib/` may import this, which living in `test/` enforces
/// structurally. Do not extend it and do not "fix" it toward the new
/// kernel: its whole value is being unchanged.
library;

import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

/// The radical axis of [c1] and [c2] — the line of points with equal
/// *power* (`|P − center|² − radius²`) with respect to both circles — or
/// `null` when the circles are concentric (within [epsilon]), where no
/// such line exists.
///
/// Equating the two powers cancels the quadratic terms, leaving the line
/// `2(c₂ − c₁)·P + (|c₁|² − |c₂|² − r₁² + r₂²) = 0`. Its normal is the
/// center offset, so the axis is always perpendicular to the line of
/// centers; when the circles intersect it carries their common chord, and
/// for equal radii it is the perpendicular bisector of the centers.
LineEq? radicalAxis(
  CircleEq c1,
  CircleEq c2, [
  double epsilon = defaultEpsilon,
]) {
  if (c1.center.closeTo(c2.center, epsilon)) {
    return null;
  }
  final d = c2.center - c1.center;
  return LineEq(
    2 * d.x,
    2 * d.y,
    c1.center.normSquared -
        c2.center.normSquared -
        c1.radius * c1.radius +
        c2.radius * c2.radius,
  );
}

/// The polar line of [pole] with respect to [circle] — the line
/// `(pole − c)·(X − c) = r²` — or `null` when [pole] sits on the center
/// (within [epsilon]), where every direction is equally perpendicular
/// and no polar exists.
///
/// The normal is the center→pole offset, so the polar is always
/// perpendicular to that join, crossing it at the *inverse point* of the
/// pole (distance `r² / |pole − c|` from the center). A pole outside the
/// circle sends the polar through its two tangent points; a pole on the
/// circle is its own inverse, collapsing the polar onto the tangent
/// there; a pole inside sends it outside the circle entirely. Poles and
/// polars are reciprocal (La Hire): Q lies on the polar of P exactly
/// when P lies on the polar of Q.
LineEq? polarLine(
  Vec2 pole,
  CircleEq circle, [
  double epsilon = defaultEpsilon,
]) {
  if (pole.closeTo(circle.center, epsilon)) {
    return null;
  }
  final n = pole - circle.center;
  return LineEq(
    n.x,
    n.y,
    -n.dot(circle.center) - circle.radius * circle.radius,
  );
}

/// The Apollonius circle over [a] and [b] with distance ratio [ratio] —
/// the locus of points P with `|PA| / |PB| = ratio` — or `null` when the
/// configuration degenerates: [a] and [b] coincide (within [epsilon]),
/// [ratio] is not a finite positive number, or [ratio] is 1 (within
/// [epsilon] on `1 − ratio²`), where the locus is the perpendicular
/// bisector of AB rather than a circle.
///
/// The center lies on line AB at `(A − k²·B) / (1 − k²)` with radius
/// `k·|AB| / |1 − k²|`; the circle cuts AB at the two points dividing it
/// internally and externally in the ratio k.
CircleEq? apolloniusCircle(
  Vec2 a,
  Vec2 b,
  double ratio, [
  double epsilon = defaultEpsilon,
]) {
  if (!ratio.isFinite || ratio <= 0 || a.closeTo(b, epsilon)) {
    return null;
  }
  final k2 = ratio * ratio;
  final denominator = 1 - k2;
  if (denominator.abs() <= epsilon) {
    return null;
  }
  final center = (a - b * k2) * (1 / denominator);
  final radius = ratio * a.distanceTo(b) / denominator.abs();
  return CircleEq(center, radius);
}
