import 'dart:math' as math;

import '../../math/vec2.dart';
import '../complex.dart';
import '../tolerances.dart';

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

/// The widest angular step a detour arc may take (Phase 117b). The arc's
/// two endpoints are its *real* entry and exit, so a walk that accepts
/// the whole semicircle in one trial has continued from one real
/// parameter straight to the other — precisely the step across the
/// collision the detour exists to avoid, and the acceptance rule cannot
/// tell the difference (near a collision both roots move little). Four
/// steps minimum keep the continuation genuinely off the real axis.
const double maxDetourArcStep = math.pi / 4;

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

/// The fraction of the extrapolated distance-to-collision one accepted
/// step may cover (see [collisionStepLimit]). Below 1 by enough margin
/// to absorb sample noise; the estimator itself never overshoots on
/// either collapse law, so the true collision always stays outside.
const double collisionStepFraction = 0.75;

/// The widest span an accepted step may cover without risking that an
/// approaching root collision hides *strictly inside* it, given the
/// separation samples [s1] at [t1] and [s2] at [t2] (the last two
/// accepted steps). Infinite when the samples do not point at a
/// collision ahead — there is then nothing to bound.
///
/// **Why the acceptance rules alone are not enough** (Phase 117b): the
/// Cinderella bound compares a root's motion against the separation at
/// the *previous* accepted step, so it only sees the step's endpoints.
/// Where two roots pass through each other transversally — the second
/// intersection of a circle with a line drawn *through a point of that
/// circle*, the commonest such configuration — the separation dips to
/// zero and recovers within one scan cell while both endpoints keep a
/// comfortable separation and every root moves only a little. Nearest
/// matching then keeps the *canonical index* rather than the analytic
/// branch, and the trace silently changes sheets with no starvation,
/// no fold and no detour to catch it. Capping the step by the
/// extrapolated collision distance forces the collision to the *end*
/// of a step, where refinement localizes it and the existing
/// fold/crossing machinery takes over.
///
/// The cap is self-scaling: a separation that is large, or shrinking
/// slowly, extrapolates its collision far ahead and does not throttle
/// anything. It is also conservative by construction —
/// [estimateSingularParameter] is exact on the `√` law of a transverse
/// tangency and *undershoots* on the linear law of a transversal
/// crossing (and on a near-miss), so the returned limit never lets a
/// step reach the true collision.
double collisionStepLimit({
  required double t1,
  required double s1,
  required double t2,
  required double s2,
}) {
  final tStar = estimateSingularParameter(t1: t1, s1: s1, t2: t2, s2: s2);
  if (tStar == null) {
    return double.infinity;
  }
  final limit = collisionStepFraction * (tStar - t2);
  return limit > 0 ? limit : double.infinity;
}

/// A located minimum of the candidate-separation profile along a leg:
/// where it sits ([t]) and how deep it goes ([separation]).
class SeparationMinimum {
  const SeparationMinimum(this.t, this.separation);

  /// The leg parameter of the minimum.
  final double t;

  /// The separation there.
  final double separation;

  /// Whether the minimum is a genuine root collision rather than a
  /// near-miss.
  ///
  /// The search drives the bracket to the floating-point floor, so a
  /// real zero reads at solver noise whatever the collapse law — the
  /// linear law of a transversal crossing and the `√` law of a tangency
  /// both bottom out inside the kernel's snapped-double-root zone. A
  /// miss instead flattens at its closest approach and reads that.
  /// `doubleRootEpsilon` is therefore the right threshold and the
  /// consistent one: it is already what the kernel means by "these two
  /// roots coincide", so a miss tighter than it is a double root
  /// everywhere else in the engine too.
  ///
  /// Misclassifying a miss as a collision is the expensive direction —
  /// it plans an arc around complex branch points that the real path
  /// passes *between*, which winds and swaps the branches — so a
  /// minimum that fails this leaves the caller with
  /// [estimateSingularParameter] and its undershoot guarantee.
  bool get isCollision => separation <= doubleRootEpsilon;
}


/// Locates the next minimum of [separationAt] ahead of [from] by direct
/// measurement — a geometric forward bracket followed by a ternary
/// search — searching no further than [end]. Null when the separation
/// does not turn around inside the window: there is no minimum to aim
/// at, and the caller keeps its extrapolated estimate.
///
/// The forward bracket doubles its stride, so a dip far narrower than
/// its distance from [from] can be stepped over and read as "no
/// minimum". That is the safe direction — the caller falls back to
/// [estimateSingularParameter] — and it does not arise in the walks,
/// which only ask once their own step has already collapsed to
/// [detourTriggerStep] near the collision.
///
/// **Why measure rather than extrapolate** (Phase 117b):
/// [estimateSingularParameter] fits the `s ∝ √(t* − t)` law of a
/// transverse tangency, where it is exact. At a *transversal* crossing
/// — two roots passing through each other, separation vanishing
/// linearly — the same fit undershoots by a factor that does not
/// improve as the walk closes in (each refinement re-undershoots), so
/// the planned arc hugs the collision instead of clearing it: the
/// detour exits nearer the singularity than it entered and matching
/// picks the wrong sheet on the way out. Measuring the minimum is
/// law-agnostic — it costs a bounded handful of evaluations, once per
/// singularity — and its depth is exactly the crossing/near-miss
/// discriminator the extrapolation cannot provide.
///
/// [separationAt] must leave no state behind: it is called at
/// parameters all over the window, in no particular order.
SeparationMinimum? locateSeparationMinimum({
  required double from,
  required double end,
  required double firstStep,
  required double Function(double t) separationAt,
}) {
  if (!(end > from) || !(firstStep > 0)) {
    return null;
  }
  // Bracket: probe forward, doubling the stride, until the separation
  // turns up. The window's end is a legitimate probe (a leg may starve
  // right at its own edge), but a profile still falling there has no
  // minimum inside the window to aim at.
  var lo = from;
  var sLo = separationAt(from);
  var mid = from + firstStep;
  if (!(mid < end)) {
    return null;
  }
  var sMid = separationAt(mid);
  if (!(sMid < sLo)) {
    // Already rising at the first probe: whatever minimum there may be
    // sits inside the first step, too close to resolve from here.
    return null;
  }
  var stride = firstStep;
  double? hi;
  var sHi = double.nan;
  for (var probe = 0; probe < _maxBracketProbes; probe++) {
    stride *= 2;
    var next = mid + stride;
    if (next >= end) {
      next = end;
    }
    if (!(next > mid)) {
      return null;
    }
    final sNext = separationAt(next);
    if (sNext > sMid) {
      hi = next;
      sHi = sNext;
      break;
    }
    lo = mid;
    sLo = sMid;
    mid = next;
    sMid = sNext;
  }
  if (hi == null || !(sMid < sLo) || !(sMid < sHi)) {
    return null;
  }
  // Ternary search on the unimodal bracket.
  var a = lo;
  var b = hi;
  final resolution = _minimumResolution * (hi - lo);
  for (var i = 0; i < _maxTernaryIterations && b - a > resolution; i++) {
    final m1 = a + (b - a) / 3;
    final m2 = b - (b - a) / 3;
    if (separationAt(m1) <= separationAt(m2)) {
      b = m2;
    } else {
      a = m1;
    }
  }
  final t = (a + b) / 2;
  return SeparationMinimum(t, separationAt(t));
}

/// Forward doublings allowed while bracketing a separation minimum.
const int _maxBracketProbes = 24;

/// Ternary-search iterations on a bracketed minimum — each shrinks the
/// bracket by 1/3, so 100 drive any bracket down to the floating-point
/// floor. Resolving that far is what makes the near-miss test sharp: a
/// miss is only told from a collision *below* its own closest approach,
/// so a shallow search would read a tight miss as a collision.
const int _maxTernaryIterations = 100;

/// Bracket width, relative to the *initial* bracket, below which further
/// ternary iterations buy nothing.
const double _minimumResolution = 1e-15;

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
