/// **V1's affine tangent points, frozen as a test oracle.**
///
/// Superseded in Phase 110 by `TangentLine`'s polar construction and left
/// with no `lib/` consumer; moved here in Phase 121.
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
import 'package:regula/domain/math/vec2.dart';

import 'intersections.dart';

/// The points where the tangent lines from [external] touch [circle].
///
/// Built as the Thales circle over the segment center–[external]
/// intersected with [circle] (a tangent point sees that segment under a
/// right angle). Reusing [intersectCircleCircle] buys branch stability
/// for free: the first point lies to the *left* of the directed line
/// from the center to [external], which is continuous under any drag of
/// the external point — none of the line∩circle direction-reversal wart.
///
/// Returns two points from a point strictly outside, the point itself
/// when it lies on the circle (within [epsilon] — both tangents collapse
/// to the tangent at the point), and none from strictly inside or for a
/// degenerate (≤ [epsilon]) radius.
List<Vec2> tangentPointsToCircle(
  Vec2 external,
  CircleEq circle, [
  double epsilon = defaultEpsilon,
]) {
  if (circle.radius <= epsilon) {
    return const [];
  }
  if (circle.contains(external, epsilon)) {
    return [external];
  }
  final thales = CircleEq.centerAndPoint(
    circle.center.lerp(external, 0.5),
    external,
  );
  // Strictly inside, the Thales circle lies wholly inside [circle] (every
  // point of it is within |center − external| < radius of the center), so
  // the intersection is naturally empty — no explicit inside test needed.
  return intersectCircleCircle(circle, thales, epsilon);
}
