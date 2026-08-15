/// How often a locus re-sweeps while a drag gesture is previewing
/// (Phase 117d).
///
/// A locus is the only leaf in the graph whose recompute has no bounded
/// cost: it is a whole traced sweep, hundreds of chain solves, and the
/// count is a property of the curve (its folds, its crossings) rather
/// than of any tunable. Everything else in a preview frame is a handful
/// of solves. So on any construction carrying a locus, the frame budget
/// is the sweep's budget, and a sweep that outgrows the budget takes the
/// whole gesture down with it — the app stops responding to the pointer
/// because it is busy drawing a curve nobody can see move.
///
/// The fix is not to make the sweep cheaper (measured: dropping
/// `sampleCount` from 128 to 16 saves only a third, because the walk's
/// step size answers to the geometry) but to stop tying it to the
/// pointer. A locus is a DAG leaf — nothing may take one as a parent —
/// so *no* decision anywhere depends on its samples being current. It is
/// pixels, and pixels may lag.
///
/// While [previewing], a locus therefore re-sweeps only once it has been
/// idle at least as long as its own last sweep took ([maxShare] = 0.5,
/// a 50% duty cycle). The rule is self-tuning and has no wall-clock
/// constant in it: a sweep well inside the frame budget waits less than
/// one frame and so runs every frame, exactly as before, while a sweep
/// that costs 40× the budget simply updates 40× less often and the drag
/// stays live. What it guarantees is the thing that was missing — the
/// gesture's responsiveness no longer depends on the sweep's cost.
///
/// The last frame of a gesture is *not* a preview: it arrives through
/// the command, with [previewing] false, so the committed state always
/// carries a fully current locus. Staleness lives and dies inside the
/// gesture.
///
/// Deliberately mutable process-global state, like `TracingFlags` next
/// door: a gesture is a global thing, and threading a preview flag
/// through every recompute path would put drag bookkeeping into every
/// object's signature.
abstract final class LocusRefresh {
  /// Whether a drag gesture is currently previewing frames.
  ///
  /// Set only by the drag sessions, and only around one preview frame at
  /// a time — always in a `finally`, since a stuck `true` would freeze
  /// every locus in the document until the next commit.
  static bool previewing = false;

  /// The share of gesture wall time a locus may spend sweeping, in
  /// `(0, 1]`. At 1 a locus sweeps on every frame however long it takes
  /// (the pre-117d behaviour); at 0.5 it waits out one sweep's duration
  /// between sweeps.
  static double maxShare = 0.5;

  /// Whether a locus whose last sweep took [lastSweepMs] and which has
  /// been idle [idleMs] may sweep now.
  ///
  /// Always true outside a preview, and always true for a locus that has
  /// never swept — a first frame must draw something.
  static bool due({required double lastSweepMs, required double idleMs}) {
    if (!previewing || !(lastSweepMs > 0)) {
      return true;
    }
    final share = maxShare.clamp(1e-3, 1.0);
    return idleMs >= lastSweepMs * (1 - share) / share;
  }

  /// Runs [frame] as a drag preview, restoring the previous scope after.
  ///
  /// Nests safely, so a session need not know whether it is the
  /// outermost thing running.
  static T preview<T>(T Function() frame) {
    final outer = previewing;
    previewing = true;
    try {
      return frame();
    } finally {
      previewing = outer;
    }
  }
}
