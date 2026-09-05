import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/tracing_flags.dart';
import 'package:regula/domain/tools/drag_session.dart';

/// Phase 134: what a drag frame does when the crossing it must carry a
/// branch through lands on the frame's own boundary.
///
/// The rig is `no-locus.rgl`'s shape with the locus taken off, and that
/// is the point of it: a locus-chain intersection is held out of tracing
/// altogether (see `Construction._traceAlong`), so the reported document
/// cannot show what the *walk* does with this geometry. Without the
/// locus, `G` is an ordinary traced slot and every mechanism is live.
///
/// F is glued to the x-axis; d is the circle centred at the origin
/// through F, so F is itself one of the two crossings of d with the line
/// c through B and F, and G is the other. The pair crosses transversally
/// where AF ⟂ FB — at t = 0 and t = −8, the feet of the Thales circle
/// over AB — so the canonical index names a *different* root on each
/// side of those. A frame that fails to carry identity across therefore
/// does not merely wobble: G lands on the driver's own root and stays
/// there, which is what the user reported as the locus disappearing.
///
/// **Why the circle is built through a copy of F rather than F itself**
/// (Phase 135). F on both curves is a *structural* incidence, and
/// deflation now resolves exactly that case with no tracing at all — so
/// the rig as written would stop exercising a single line of what this
/// file is named after. `HomotheticPoint(F, centre: A, ratio: 1)` is F,
/// bit for bit, at every parameter (A is the origin, so the arithmetic
/// is exact); what it is not is F *by construction*, so
/// `sharedIncidentPoints` cannot see the incidence and the walk has to
/// earn the crossing the hard way. The geometry, the crossings, the
/// bail, the budget B needs — all unchanged and re-measured. Deflation's
/// own coverage of this shape, with the incidence left visible, is
/// `test/domain/construction/deflation_test.dart`.
///
/// The two crossings are not the same difficulty. At t = −8 the two
/// roots simply meet; at t = 0 the *carrier* collapses with them — the
/// circle centred A through F has radius zero — so the walk has no
/// candidates at all there and used to re-acquire on a coin flip.
void main() {
  const b = Vec2(-8, -1);

  /// The crossing of d and c that is *not* the driver, in closed form.
  /// Substituting P = F + s·(B − F) into |P| = |t| gives s = 0 (which is
  /// F) or the root below.
  Vec2 otherCrossing(double t) {
    final s = 2 * t * (8 + t) / ((8 + t) * (8 + t) + 1);
    return Vec2(t + s * (b.x - t), -s);
  }

  ({Construction construction, PointOnObject f, IntersectionPoint g}) rig() {
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final unit = FreePoint(id: 'u', position: const Vec2(1, 0));
    final axis = LineThroughTwoPoints(id: 'axis', point1: a, point2: unit);
    final driver = PointOnObject(id: 'drv', curve: axis, parameter: -6.25);
    // F, exactly — but not F as far as structural incidence is
    // concerned. See the file doc.
    final copy = HomotheticPoint(id: 'cp', point: driver, center: a, ratio: 1);
    final circle = CircleCenterPoint(id: 'd', center: a, onCircle: copy);
    final off = FreePoint(id: 'b', position: b);
    final chord = LineThroughTwoPoints(id: 'c', point1: off, point2: driver);
    // Whichever index names the non-driver root where the document
    // stands — the branch the user's G would hold.
    var index = 0;
    for (final candidate in [0, 1]) {
      final probe = IntersectionPoint(
        id: 'g',
        curve1: circle,
        curve2: chord,
        branchIndex: candidate,
      );
      if (probe.position!.distanceTo(otherCrossing(-6.25)) < 1e-9) {
        index = candidate;
      }
    }
    final g = IntersectionPoint(
      id: 'g',
      curve1: circle,
      curve2: chord,
      branchIndex: index,
    );
    return (
      construction: Construction()
        ..add(a)
        ..add(unit)
        ..add(axis)
        ..add(driver)
        ..add(copy)
        ..add(circle)
        ..add(off)
        ..add(chord)
        ..add(g),
      f: driver,
      g: g,
    );
  }

  /// Slides the driver from [from] to [to] in frames of [step], with the
  /// pointer quantized to that step — so a step dividing the degenerate
  /// parameter puts a frame boundary exactly on it, which is what grid
  /// snapping does in the reported document.
  void slide(
    Construction construction,
    PointOnObject f, {
    required double from,
    required double to,
    required double step,
  }) {
    final session = DragSession.start(construction, f, f.position!)!;
    final dir = to > from ? 1.0 : -1.0;
    var at = from;
    while (dir * (to - at) > 1e-9) {
      at += dir * step;
      if (dir * (at - to) > 0) at = to;
      session.update(Vec2((at / step).roundToDouble() * step, 0));
    }
    session.end()?.apply(construction);
  }

  tearDown(() {
    TracingFlags.dragTracing = true;
    TracingFlags.dragStepBudget = null;
  });

  group('a frame boundary on the degeneracy (Phase 134)', () {
    // Every one of these fails without the fix, on every step size and
    // every budget: the frame ending on t = 0 leaves the construction on
    // a state no pass can seed from, so the next frame resolves
    // canonically, the order has flipped, and G takes the driver's root
    // for the rest of the gesture.
    for (final step in [0.02, 0.1, 0.25, 1.0]) {
      test('step $step: the carrier collapse at A is crossed, not coasted', () {
        final (:construction, :f, :g) = rig();
        slide(construction, f, from: -6, to: 4, step: step);
        expect(
          g.position!.distanceTo(otherCrossing(4)),
          lessThan(1e-9),
          reason: 'G left its own branch and took the driver\'s',
        );
      });
    }

    test('and it holds for the whole sweep, not just its end', () {
      final (:construction, :f, :g) = rig();
      final session = DragSession.start(construction, f, f.position!)!;
      for (var k = -6; k <= 6; k++) {
        final at = k * 0.1;
        session.update(Vec2(at, 0));
        // The frame that lands exactly on the collapse is the one frame
        // where the two roots really are the same point, so G is allowed
        // to be there; every other frame must be on its own branch.
        expect(
          g.position!.distanceTo(otherCrossing(at)),
          lessThan(1e-9),
          reason: 'left its branch at t = ${at.toStringAsFixed(2)}',
        );
      }
      session.end();
    });

    test('the crossing at B is carried at the budget this rig derives', () {
      // The transversal at t = −8 is not a carrier collapse and needs no
      // coasting — what it needs is budget: the creep in, the detour arc
      // and the exit together outrun the 128 trials that shipped as a
      // constant, on a coarse frame. This is Phase 139's payoff, so the
      // budget is deliberately *not* set here: four objects hang off the
      // driver, so the derivation hands the gesture its ceiling, and the
      // crossing is carried with nothing hand-tuned.
      expect(TracingFlags.dragStepBudget, isNull, reason: 'derived, not set');
      final (:construction, :f, :g) = rig();
      slide(construction, f, from: -6, to: -12, step: 0.25);
      expect(g.position!.distanceTo(otherCrossing(-12)), lessThan(1e-9));
    });

    test('and at the constant this rig used to get, the crossing is kept '
        'across two frames (Phase 189)', () {
      // This was the control: pinned back to 128, the same sweep lost G
      // to the driver's own root, because the frame straddling t = −8
      // ran out of trials in the detour's *exit* — past the crossing —
      // and bailed to a static solve that relabelled it. A pass now
      // keeps a crossing it can vouch for: it stops where the budget ran
      // out, the driver lags the pointer by the rest of the path, and
      // the next frame finishes the climb from there.
      TracingFlags.dragStepBudget = 128;
      final (:construction, :f, :g) = rig();
      final session = DragSession.start(construction, f, f.position!)!;
      var kept = 0;
      var lagged = 0;
      var bailed = 0;
      for (var at = -6.25; at > -12 - 1e-9; at -= 0.25) {
        session.update(Vec2(at, 0));
        final stats = session.traceStats!;
        if (stats.bailed) bailed++;
        if (!stats.bailed && stats.reached < 1) {
          kept++;
          if ((f.parameter - at).abs() > 1e-9) lagged++;
        }
      }
      // The frame whose pointer lands *exactly* on t = −8 (the grid step
      // divides it) still bails: its singularity is an endpoint no arc
      // can enclose, the Phase 134 case, and the anchor holds. The frame
      // after it spans the crossing, keeps it, and stops just past it.
      expect(bailed, 1);
      expect(kept, 1, reason: 'the crossing frame stops short');
      expect(lagged, kept, reason: 'and the driver lags the pointer there');
      session.end()?.apply(construction);
      expect(g.position!.distanceTo(otherCrossing(-12)), lessThan(1e-9));
    });

    test('the walk itself: at 128 the transversal pass stops past the '
        'crossing with G on its own root, and a pass from there finishes', () {
      TracingFlags.dragStepBudget = 128;
      final (:construction, :f, :g) = rig();
      final first = construction.recomputeAlongParameterPath(
        'drv',
        -6.25,
        -9,
        stepBudget: 128,
      );
      expect(first.detours, 1);
      expect(first.reached, greaterThan(0));
      expect(first.reached, lessThan(1));
      // The driver sits at the lerp of the stop — bitwise what the slide
      // session anchors to — and it is past the crossing at t = −8.
      final stop = -6.25 * (1 - first.reached) + -9 * first.reached;
      expect(f.parameter, stop);
      expect(stop, lessThan(-8));
      // Identity carried: G is the *other* crossing there, not the
      // driver's root the static relabel used to hand it.
      expect(g.position!.distanceTo(otherCrossing(stop)), lessThan(1e-9));
      final second = construction.recomputeAlongParameterPath(
        'drv',
        stop,
        -9,
        stepBudget: 128,
      );
      expect(second.reached, 1);
      expect(second.detours, 0);
      expect(g.position!.distanceTo(otherCrossing(-9)), lessThan(1e-9));
    });
  });

  group('the pass seeds at its own path start (Phase 134)', () {
    test('a bailed frame does not hand its static solve to the next one', () {
      // A frame straddling the collapse starves at the shipped budget,
      // so the gesture falls back to the static solve for that frame —
      // and the anchor may not walk forward onto it, or the next frame
      // would continue from a state identity was never carried through.
      // The proof is the recovery: the following frames put G back on
      // its own branch, which they can only do from the held anchor.
      //
      // The budget is pinned back to the constant this rig used to get
      // because Phase 139's derivation *crosses* this frame rather than
      // bailing on it — a real improvement, and it would leave the bail
      // path with no coverage. Forcing the starvation is what the pin is
      // for. The improvement itself is pinned just below.
      TracingFlags.dragStepBudget = 128;
      final (:construction, :f, :g) = rig();
      final session = DragSession.start(construction, f, f.position!)!;
      session.update(const Vec2(-0.1, 0));
      session.update(Vec2.zero);
      expect(session.traceStats!.bailed, isTrue, reason: 'the rig must bail');
      // The static solve is still what the user sees: the driver follows
      // the pointer while the frame is being given up on.
      expect(f.parameter, closeTo(0, 1e-12));
      session.update(const Vec2(0.1, 0));
      expect(g.position!.distanceTo(otherCrossing(0.1)), lessThan(1e-9));
      session.end();
    });

    test('and at the derived budget it is crossed instead of bailed on '
        '(Phase 139)', () {
      // The same two frames, with nothing pinned: this rig recomputes
      // four objects per trial, so the derivation hands it the ceiling
      // and the walk gets across the carrier collapse at t = 0 inside
      // the frame. The user-visible difference is one fewer frame
      // resolved statically mid-gesture.
      expect(TracingFlags.dragStepBudget, isNull, reason: 'derived, not set');
      final (:construction, :f, :g) = rig();
      final session = DragSession.start(construction, f, f.position!)!;
      session.update(const Vec2(-0.1, 0));
      session.update(Vec2.zero);
      expect(session.traceStats!.bailed, isFalse);
      session.update(const Vec2(0.1, 0));
      expect(g.position!.distanceTo(otherCrossing(0.1)), lessThan(1e-9));
      session.end();
    });

    test('a pass whose start is behind the construction still seeds there', () {
      // The precondition that used to be assumed: `recomputeAlongPath`
      // is handed a path starting where the caller says, not where the
      // point happens to sit. Drive the driver away first, then trace a
      // path that starts back at the parameter G's branch was picked at.
      final (:construction, :f, :g) = rig();
      construction.setPointOnObjectParameter('drv', 3.0);
      final result = construction.recomputeAlongParameterPath('drv', -6, -5);
      expect(result.acceptedSteps, greaterThan(0));
      expect(f.parameter, closeTo(-5, 1e-12));
      expect(g.position!.distanceTo(otherCrossing(-5)), lessThan(1e-9));
    });
  });

  group('a pass reports how far its roots closed (Phase 134)', () {
    test('a quiet stretch reports no closing at all', () {
      final (:construction, :f, :g) = rig();
      final result = construction.recomputeAlongParameterPath('drv', -6, -5.9);
      expect(result.closing, closeTo(1, 0.05));
      expect(g.position!.distanceTo(otherCrossing(-5.9)), lessThan(1e-9));
    });

    test('a run into the collapse reports zero — the state no pass can '
        'seed from', () {
      // Budgeted so the pass *finishes* on the collapse rather than
      // starving short of it: it is the finished pass whose report the
      // caller acts on, and the report has to say "do not anchor here".
      final (:construction, :f, :g) = rig();
      final result = construction.recomputeAlongParameterPath(
        'drv',
        -0.1,
        0,
        stepBudget: 512,
      );
      expect(
        result.closing,
        0,
        reason: 'the roots met, so this end is not an anchor',
      );
    });

    test('and a run that merely approaches it reports the fraction', () {
      final (:construction, :f, :g) = rig();
      final result = construction.recomputeAlongParameterPath('drv', -1, -0.1);
      expect(result.closing, greaterThan(0));
      expect(result.closing, lessThan(0.5), reason: 'the roots closed ~10x');
    });
  });
}
