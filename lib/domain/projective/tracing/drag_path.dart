import '../../math/vec2.dart';
import '../complex.dart';
import '../proj_point.dart';

/// One free point's drag from [start] to [end], parameterized by
/// `t ∈ [0, 1]`.
///
/// The path is the *domain of continuation*: tracing resolves a drag by
/// walking `t` and recomputing dependents at each substep, so branch
/// identity follows the roots' motion instead of being re-picked per
/// frame ([evaluate] is deliberately holomorphic in `t` so Phase 115 can
/// detour `t` through complex values around a degeneracy — a real
/// interpolation of endpoints could not be continued off the real axis).
///
/// A drag session builds one path per preview update, anchored at the
/// *previous* preview position — matching continuity across paths rides
/// on `start` being where the construction currently sits.
class DragPath {
  const DragPath(this.start, this.end);

  final Vec2 start;
  final Vec2 end;

  /// The dragged point's chart position at real parameter [t] — the
  /// affine interpolation `start·(1−t) + end·t`, exact at both endpoints
  /// (`at(0) == start`, `at(1) == end`, bitwise).
  Vec2 at(double t) =>
      Vec2(start.x * (1 - t) + end.x * t, start.y * (1 - t) + end.y * t);

  /// The dragged point's homogeneous position at complex parameter [t] —
  /// the same interpolation continued holomorphically, `w` exactly one.
  /// Agrees with the lift of [at] for real [t]; a complex [t] moves the
  /// point off the real plane (the Phase 115 detour).
  ProjPoint evaluate(Complex t) {
    final s = Complex.one - t;
    return ProjPoint(
      s.scale(start.x) + t.scale(end.x),
      s.scale(start.y) + t.scale(end.y),
      Complex.one,
    );
  }

  @override
  String toString() => 'DragPath($start → $end)';
}
