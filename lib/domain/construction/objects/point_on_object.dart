import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/conic_shape.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// A point constrained to a curve (a [GeoLine] or [GeoCircle]).
///
/// The point keeps a fixed [parameter] in the curve's analytic
/// parameterization — signed arc-length along `LineEq.direction` from
/// `LineEq.pointOnLine`, or the polar angle for a circle — and recomputes
/// its position from the curve's current geometry, so it rides along when
/// the curve moves. Undefined exactly while the curve's *chart projection*
/// is: per PLAN §Parameterization the parameter is a real number of the
/// affine chart, so a carrier that is complex or wholly at infinity has no
/// chart to evaluate in and takes the point down with it.
///
/// Migrated (Phase 111): stores the homogeneous lift of the chart
/// evaluation. The `line`/`circle` reads in [recompute] are the sanctioned
/// chart reads of the pinned parameterization decision (parameters are
/// chart quantities; the migrated carriers' projections carry the
/// `orientedAlong` anchor this parameterization depends on) — not bridge
/// leftovers. Until tracing (Phase 113+) continues the point's homogeneous
/// value, the stored lift always has `w` exactly one, so [position] reads
/// the chart coordinates back exactly at any magnitude — no at-infinity
/// cutoff, which locus sweeps along diverging line arms rely on.
///
/// Because the parameter is tied to the *analytic* form, the point tracks
/// the curve but does not stick to the points that defined it (e.g.
/// translating a line along itself leaves the constrained point where it
/// was). Deterministic, same spirit as the intersection-branch ordering
/// wart in PLAN. Dragging the point *along* its curve re-sets [parameter]
/// via `Construction.setPointOnObjectParameter`, the same way free points
/// move through `moveFreePoint`.
///
/// **A general conic is a host too** (Phase 132). A conic with no
/// `CircleEq` — a five-point conic, a Cayley-Klein circle, any ellipse
/// that is not a circle — used to fall off the end of both
/// parameterizations: [recompute] left the point undefined and [near]
/// *threw*. Since the hit tester has reported general conics since Phase
/// 119 and `resolvePoint` glue-probes every hit curve, that throw was
/// reachable from the toolbar in six taps. Such a host is swept by
/// `ConicShape`'s **pencil angle** instead: π-periodic, a bijection from
/// `[0, π)` onto the whole curve, and polynomial in homogeneous
/// coordinates rather than a chart evaluation. A circle keeps its polar
/// angle, so no stored parameter changes meaning, no document needs a
/// migration, and the save format does not move.
///
/// Two things follow from the parameter being a pencil angle. [near]
/// glues to the **nearest point of the ink** (`ConicShape.parameterNear`,
/// the search the hit tester already runs) rather than to
/// `ConicShape.parameterOf`, which answers the arc of the join and is a
/// different point for a tap that missed the curve. And the pencil angle
/// names a point only through `ConicShape`'s canonical frame, whose
/// discrete choices switch as the host moves — so the angle is an
/// **address**, held stable the way `branchIndex` is (Phase 132d):
/// statically it resolves canonically ([recompute] stays a pure function
/// of parents and params — no history here), while *during a drag* the
/// session carries it across each frame switch
/// (`ConicShape.carryParameterFrom`) and the gesture's command replays
/// the net re-expressions, so commit, undo and redo restore glue
/// identity exactly. A single static step across a switch (one command
/// moving a parent far) may still re-address, exactly as a static step
/// may relabel an intersection branch.
///
/// Bounded hosts confine the point to their drawn extent: the effective
/// parameter is clamped into the host's `angularExtent` (arcs, sectors)
/// or `parameterExtent` (segments, rays) on every recompute, so the point
/// never leaves the visible curve — `IntersectionPoint`'s deferred
/// clipping does not apply here. Because [parameter] itself is kept as
/// stored, a host that shrinks past the point carries it along on its
/// nearer end and gives it back when it grows again.
class PointOnObject extends GeoPoint {
  PointOnObject({
    required super.id,
    required this.curve,
    required this.parameter,
    super.attributes,
  }) {
    if (curve is! GeoLine && curve is! GeoCircle) {
      throw ArgumentError('PointOnObject requires a line or circle parent');
    }
    recompute();
  }

  /// The constrained point closest to [position] on [curve]'s *current*
  /// geometry — how tools turn a tap into a parameter.
  ///
  /// Throws [ArgumentError] while the curve is undefined (no geometry to
  /// project onto); hit-tested taps never see undefined curves.
  factory PointOnObject.near({
    required String id,
    required GeoObject curve,
    required Vec2 position,
  }) {
    final parameter = switch (curve) {
      GeoLine(:final line?) && final GeoLine host => host.clampParameter(
        line.parameterAt(position),
      ),
      GeoCircle(:final circle?) && final GeoCircle host => host.clampAngle(
        circle.angleAt(position),
      ),
      // A tap on a general conic glues to the point it selected, which
      // is the nearest point of the ink — the same search the hit tester
      // runs, not the arc of the join `parameterOf` would answer.
      GeoCircle(:final conic?) =>
        ConicShape.of(conic).parameterNear(position) ??
            (throw ArgumentError(
              'Cannot project onto a conic with no real curve',
            )),
      GeoLine() || GeoCircle() => throw ArgumentError(
        'Cannot project onto an undefined curve',
      ),
      GeoPoint() ||
      GeoAngle() ||
      GeoPolygon() ||
      GeoMeasurement() ||
      GeoLocus() ||
      GeoText() => throw ArgumentError(
        'PointOnObject requires a line or circle parent',
      ),
    };
    return PointOnObject(id: id, curve: curve, parameter: parameter);
  }

  /// A [GeoLine] or [GeoCircle] (enforced in the constructor).
  final GeoObject curve;

  /// Position on the curve: arc-length along a line's direction, polar
  /// angle (radians) on a circle. Always real, read in the affine chart
  /// (PLAN §Parameterization). See the class doc for stability caveats.
  ///
  /// Mutated only by `Construction.setPointOnObjectParameter` (via
  /// commands) so every change goes through dependent recomputation.
  double parameter;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  /// The sweep/detour mutation, mirroring `FreePoint`'s: stores a
  /// homogeneous position directly, bypassing the stored [parameter].
  /// Two callers are sanctioned: `Construction.recomputeAlongParameterPath`
  /// (Phase 116b — a *parameter* drag's complex detour, the carrier's
  /// chart form at a complex parameter, `w` exactly one) and the locus
  /// sweep (Phase 117 — driving this point over its host's sweep domain,
  /// `w` exactly one on interior chart evaluations and exactly zero at a
  /// ray host's driver-at-infinity edge). Either pass must leave the
  /// point real — real steps and the sweep's restore re-enter
  /// [recompute], which rebuilds [_point] from the stored real
  /// [parameter] — before returning or throwing. The stored [parameter]
  /// itself stays real throughout (PLAN §Parameterization).
  set tracedPosition(ProjPoint value) => _point = value;

  @override
  Vec2? get position => switch (_point) {
    null => null,
    // The sanctioned mutations keep `w` exactly one or exactly zero
    // (the locus sweep's driver-at-infinity edge — no chart position).
    final p when p.w.re == 0 && p.w.im == 0 => null,
    // `w` is exactly one (the lift of a chart evaluation) — read the chart
    // coordinates back directly; `toVec2` would impose a relative
    // at-infinity cutoff V1 never had.
    final p => Vec2(p.x.re, p.y.re),
  };

  @override
  List<GeoObject> get parents => [curve];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final chartPoint = switch (curve) {
      GeoLine(:final line) && final GeoLine host => line?.pointAt(
        host.clampParameter(parameter),
      ),
      // A circle keeps its polar angle: the parameter a document stores
      // means what it has always meant (see [parameter]).
      GeoCircle(:final circle?) && final GeoCircle host => circle.pointAt(
        host.clampAngle(parameter),
      ),
      // Any other conic — a five-point conic, a Cayley-Klein circle —
      // is swept by the pencil angle instead (Phase 132).
      GeoCircle(:final conic?) => ConicShape.of(conic).chartPointAt(parameter),
      GeoCircle() => null,
      GeoPoint() ||
      GeoAngle() ||
      GeoPolygon() ||
      GeoMeasurement() ||
      GeoLocus() ||
      GeoText() => throw StateError('PointOnObject parent must be a curve'),
    };
    _point = switch (chartPoint) {
      null => null,
      final p => ProjPoint.lift(p),
    };
  }
}
