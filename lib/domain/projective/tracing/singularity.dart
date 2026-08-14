import 'dart:math' as math;

import '../../math/vec2.dart';
import '../complex.dart';

/// Singularity detection and complex-detour planning (Phase 115).
///
/// When the adaptive step controller starves — accepted steps Zeno toward
/// a parameter where the tracked roots collide — the singular parameter
/// `t*` is estimated from the collapse law of the candidate separation and
/// the pass detours around it through complex `t` (a `DragPath.evaluate`
/// is holomorphic, so the construction continues analytically off the real
/// axis). Away from the real singularity the roots stay well separated, so
/// the same acceptance rule that starved on the axis walks the detour in a
/// bounded number of trials and lands on the far side with branch identity
/// decided by continuity, not by a matching tie.
///
/// **Detour orientation is fixed and recorded here**: which half-plane of
/// the path parameter an arc walks is [detourOrientation] of the drag's
/// direction — a deterministic, *odd* rule (reversing the drag flips it).
/// Oddness is what makes reversal compose correctly: a return pass
/// parameterizes the reverse path, so keeping one absolute half-plane
/// would put its detour on the *other physical side* of the singularity —
/// the round trip would wind once around it and swap the branches (the
/// monodromy of the root split; the toy probe caught exactly this).
/// Flipping the half-plane with the direction retraces the same physical
/// side, winds zero net turns, and a there-and-back drag restores every
/// branch (identity monodromy — "no jump, no swap").

/// Trial-step size below which the controller is considered starving and
/// a detour is attempted (a fraction of the unit path parameter). Steps
/// this small in ordinary refinement re-double immediately; only a
/// collapsing separation pins them down.
const double detourTriggerStep = 1e-5;

/// Chordal candidate separation below which starvation is credited to a
/// root collision (rather than, say, the absolute motion cap refining a
/// legitimate through-infinity sweep, where the separation stays large).
/// Both trigger conditions must hold before a detour is attempted.
///
/// This is also the phase's ambiguity floor: a near-miss whose closest
/// approach stays *above* this separation is traced through on the real
/// axis and never detours; only far tighter misses can be mistaken for
/// tangencies (see `estimateSingularParameter`'s undershoot note).
const double detourTriggerSeparation = 1e-3;

/// Radius margin applied to the estimated singularity distance when
/// planning an arc ([DetourArc.plan]): the singular parameter should sit
/// strictly inside the detour, not on its rim, so the estimate is
/// overshot by this factor. The arc's clearance from the singularity is
/// governed by the *entry* distance (the arc's nearest points to a
/// parameter near its center are its real endpoints), so a generous
/// factor costs nothing in clearance.
const double detourSafety = 1.5;

/// Estimates the parameter `t*` where the candidate separation collapses
/// to zero, from its values [s1] at [t1] and [s2] at [t2] (two
/// consecutive accepted steps, `t1 < t2`) — or null when the samples do
/// not point at a singularity ahead.
///
/// Near a transverse tangency the two roots split as `±C·√(t* − t)`, so
/// the *squared* separation is linear in `t` and extrapolating it to zero
/// recovers `t*` exactly (up to sample noise):
///
///     t* = t2 + s2²·(t2 − t1) / (s1² − s2²)
///
/// On a *near-miss* — `s² = C²·((t − a)² + b²)`, no real zero — the same
/// linear extrapolation systematically *undershoots* the closest approach
/// `a` while the samples are farther from `a` than `b` (the fit's zero
/// crossing lands where the quadratic still has `s² > 0`). That bias is
/// load-bearing: an undershot estimate plans an arc that exits before
/// `a`, so the complex zeros at `a ± ib` stay outside the detour and the
/// continuation stays homotopic to the real path.
///
/// Null when the separation is not strictly decreasing, a sample is
/// non-finite, the samples are not ordered, or the extrapolated `t*` is
/// not strictly ahead of [t2] (in particular `s2 == 0`: the pass is
/// already *on* the singularity, and no arc anchored there can avoid it).
double? estimateSingularParameter({
  required double t1,
  required double s1,
  required double t2,
  required double s2,
}) {
  if (!(t2 > t1) || !(s2 < s1) || !(s2 >= 0) || !s1.isFinite) {
    return null;
  }
  final tStar = t2 + s2 * s2 * (t2 - t1) / (s1 * s1 - s2 * s2);
  return tStar.isFinite && tStar > t2 ? tStar : null;
}

/// The detour orientation for a drag from [start] to [end]: `+1` walks
/// arcs through the upper half-plane of the path parameter (`Im t > 0`),
/// `−1` through the lower. The rule — descending or leftward drags
/// detour upper — is arbitrary; what is load-bearing is that it is
/// deterministic and *odd* (reversing the drag flips it), which is what
/// makes a there-and-back drag an identity (see the library doc). A
/// degenerate zero-direction path cannot starve the controller, so its
/// value never matters.
double detourOrientation(Vec2 start, Vec2 end) {
  final dy = end.y - start.y;
  if (dy != 0) {
    return dy < 0 ? 1 : -1;
  }
  return end.x - start.x < 0 ? 1 : -1;
}

/// [detourOrientation] for a scalar drive (Phase 116b: a constrained
/// point's parameter drag): decreasing drives detour upper. The same
/// oddness requirement applies — reversing the drive must flip the
/// half-plane, or a there-and-back slide would wind once around the
/// singularity and swap the branches. Matches [detourOrientation] on a
/// horizontal path, deliberately: both are "leftward → upper".
double detourOrientation1D(double from, double to) => to - from < 0 ? 1 : -1;

/// A semicircular detour in complex path parameter: the arc
/// `t(θ) = center + radius·(cos θ + i·orientation·sin θ)`, walked from
/// `θ = π` (the real [entry], where the starving pass sits) down to
/// `θ = 0` (the real [exit], past the singularity), keeping
/// `orientation·Im t ≥ 0` throughout — one half-plane per arc, chosen by
/// [detourOrientation] (see the library doc for why the choice must be
/// odd in the drag direction).
class DetourArc {
  const DetourArc._(this.entry, this.radius, this.orientation);

  /// The real parameter where the arc leaves the axis — the pass's last
  /// accepted `t`, so the traced state is already there.
  final double entry;

  /// Half the real span the arc detours across.
  final double radius;

  /// `+1` for the upper half-plane, `−1` for the lower (see
  /// [detourOrientation]).
  final double orientation;

  /// The arc's center on the real axis, at or past the estimated
  /// singularity.
  double get center => entry + radius;

  /// The real parameter where the arc rejoins the axis. Computed as
  /// `center + radius` so it is bitwise the value [tAt] produces at
  /// `θ = 0` (where `cos θ` is exactly 1 and `sin θ` exactly 0 — the
  /// exit is exactly real, like the entry).
  double get exit => center + radius;

  /// The complex path parameter at arc angle [theta] ∈ [0, π].
  Complex tAt(double theta) => Complex(
        center + radius * math.cos(theta),
        orientation * radius * math.sin(theta),
      );

  /// Plans the arc from [entry] around the estimated singularity [tStar],
  /// or null when no valid arc exists.
  ///
  /// The radius is [detourSafety] times the estimated distance, shrunk to
  /// keep the whole arc strictly inside the path (`exit < end`, with
  /// margin for the shrink's rounding). Null when [tStar] is not strictly
  /// between [entry] and [end] — a singular *endpoint* cannot be detoured
  /// around, the pass would have to finish at a complex parameter — or
  /// when the shrunken arc no longer strictly encloses [tStar]; the
  /// caller starves and bails exactly as it would without a detour.
  static DetourArc? plan({
    required double entry,
    required double tStar,
    required double orientation,
    double end = 1,
  }) {
    if (!tStar.isFinite || !(tStar > entry) || !(tStar < end)) {
      return null;
    }
    final radius = math.min(
      detourSafety * (tStar - entry),
      0.499 * (end - entry),
    );
    final arc = DetourArc._(entry, radius, orientation);
    return arc.exit > tStar && arc.exit < end ? arc : null;
  }

  @override
  String toString() => 'DetourArc(entry: $entry, exit: $exit, '
      'radius: $radius, orientation: $orientation)';
}
