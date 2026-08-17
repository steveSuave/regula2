/// **V1's affine harmonic conjugate, frozen as a test oracle.**
///
/// Superseded by the projective cross-ratio on `ProjPoint` and left with
/// no `lib/` consumer; moved here in Phase 121.
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

import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

/// The harmonic conjugate of [c] with respect to [a] and [b] — the fourth
/// point D with cross-ratio (A,B;C,D) = −1 — or `null` when the
/// configuration degenerates: [a] and [b] coincide, [c] lies off the line
/// AB (within [isCollinear]'s tolerance), or [c] is the midpoint of AB
/// (D at infinity).
///
/// In the affine coordinate t along AB (A at 0, B at 1) with C at t, D
/// sits at `t / (2t − 1)`: C at either endpoint is its own conjugate, C
/// strictly between the endpoints maps outside the segment, and the map
/// is an involution — the conjugate of the conjugate is C again.
Vec2? harmonicConjugate(
  Vec2 a,
  Vec2 b,
  Vec2 c, [
  double epsilon = defaultEpsilon,
]) {
  if (a.closeTo(b, epsilon) || !isCollinear(a, b, c, epsilon)) {
    return null;
  }
  final ab = b - a;
  final t = (c - a).dot(ab) / ab.normSquared;
  final denominator = 2 * t - 1;
  if (denominator.abs() <= epsilon) {
    return null;
  }
  return a + ab * (t / denominator);
}
