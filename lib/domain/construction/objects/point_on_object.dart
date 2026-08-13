import '../../math/vec2.dart';
import '../geo_object.dart';

/// A point constrained to a curve (a [GeoLine] or [GeoCircle]).
///
/// The point keeps a fixed [parameter] in the curve's analytic
/// parameterization — signed arc-length along `LineEq.direction` from
/// `LineEq.pointOnLine`, or the polar angle for a circle — and recomputes
/// its position from the curve's current geometry, so it rides along when
/// the curve moves. Undefined exactly while the curve is.
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
  /// angle (radians) on a circle. See the class doc for stability caveats.
  ///
  /// Mutated only by `Construction.setPointOnObjectParameter` (via
  /// commands) so every change goes through dependent recomputation.
  double parameter;

  Vec2? _position;

  @override
  Vec2? get position => _position;

  @override
  List<GeoObject> get parents => [curve];

  @override
  void recompute() {
    _position = switch (curve) {
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
  }
}
