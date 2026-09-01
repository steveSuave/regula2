import 'dart:math' as math;

import '../../math/rational.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import 'relative_line.dart';

/// The line through [through] making a *stated* angle with [reference]:
/// the direction turned from the reference's by [turn], a rational in
/// units of π reduced mod 1 — the constants stack's fixed-angle carrier
/// (PLAN §"The constants stack"). A pair of points on it satisfies
/// `aconst(ref…, self…; turn)` by construction, which is what
/// `hypotheses()` emits and no combination of the angle-free kinds can
/// state.
///
/// The turn is a statement about *lines*, read mod π like the whole
/// angle vocabulary, so `[0, 1)` in units of π covers every distinct
/// carrier; `RotatedPoint.angle` stays the float world-space radian it
/// is because a rotated point is not mod π and not a hypothesis.
///
/// Euclidean-only, like the prover vocabulary it exists to feed: a
/// rational turn of π is a chart statement, so a proper absolute leaves
/// the line undefined (the `SegmentRatioPoint` arrangement). Undefined
/// too while a parent is, or the reference has no real finite direction.
class FixedAngleLine extends RelativeLine {
  /// Throws [ArgumentError] when [turn] is not already the canonical
  /// residue in `[0, 1)` — the residue is the identity, so an unreduced
  /// spelling would be two names for one carrier.
  FixedAngleLine({
    required super.id,
    required super.through,
    required super.reference,
    required this.turn,
    super.attributes,
  }) {
    if (turn != turn.modOne()) {
      throw ArgumentError.value(
        turn,
        'turn',
        'a stated angle is a residue mod 1, in [0, 1)',
      );
    }
  }

  /// The stated angle from [reference] to this line, in units of π,
  /// canonical in `[0, 1)`. Exact and fixed for the object's lifetime.
  final Rational turn;

  @override
  ProjLine carrierFrom(
    ProjPoint through,
    ProjLine reference,
    Absolute absolute,
  ) {
    // Euclidean only (Phase 125's rule): a rational multiple of π is a
    // statement in the chart's angle measure, and the CK measure is a
    // logarithm — reinterpreting the parameter would change what the
    // hypothesis asserts.
    if (!absolute.isEuclidean) {
      return const ProjLine(Complex.zero, Complex.zero, Complex.zero);
    }
    final projected = reference.toOrientedLineEq();
    if (projected == null) {
      return const ProjLine(Complex.zero, Complex.zero, Complex.zero);
    }
    final d = projected.direction;
    final t = turn.toDouble() * math.pi;
    final cos = math.cos(t);
    final sin = math.sin(t);
    return through.join(
      ProjPoint(
        Complex(d.x * cos - d.y * sin),
        Complex(d.x * sin + d.y * cos),
        Complex.zero,
      ),
    );
  }
}
