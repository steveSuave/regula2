import '../../math/vec2.dart';
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

  /// The complex-detour mutation (Phase 116b), mirroring `FreePoint`'s:
  /// stores a generally complex homogeneous position while a tracing
  /// pass walks a *parameter* drag off the real axis. Only
  /// `Construction.recomputeAlongParameterPath` may call this, with the
  /// carrier's chart form evaluated at a complex parameter (`w` exactly
  /// one), and the pass must leave the point real — its real steps
  /// re-enter [recompute], which rebuilds [_point] from the stored real
  /// [parameter] — before returning or throwing. The stored [parameter]
  /// itself stays real throughout (PLAN §Parameterization).
  set tracedPosition(ProjPoint value) => _point = value;

  @override
  Vec2? get position => switch (_point) {
    null => null,
    // `w` is exactly one (the lift of a chart evaluation) — read the chart
    // coordinates back directly; `toVec2` would impose a relative
    // at-infinity cutoff V1 never had.
    final p => Vec2(p.x.re, p.y.re),
  };

  @override
  List<GeoObject> get parents => [curve];

  @override
  void recompute() {
    final chartPoint = switch (curve) {
      GeoLine(:final line) && final GeoLine host => line?.pointAt(
        host.clampParameter(parameter),
      ),
      GeoCircle(:final circle) && final GeoCircle host => circle?.pointAt(
        host.clampAngle(parameter),
      ),
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
