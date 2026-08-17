import '../../math/angle_geometry.dart';
import '../../math/circle_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The circular arc from [start] to [end] passing through [via].
///
/// A [GeoCircle] via its carrier [circle] (the three points' circumcircle),
/// so arcs participate in intersections like full circles do — clipping
/// intersection points to the arc's extent is deferred, matching `Segment`
/// and `Ray`.
///
/// The drawn extent is [startAngle] plus the signed [sweep]: whichever
/// branch of the carrier contains [via]. Painter and hit tester must use
/// those — the carrier alone is the full circle.
///
/// Migrated (Phase 109): the carrier is [circumcircleOf] on the parents'
/// projective views; [circle] is its projection and the angular extent
/// stays affine metadata read off that projection. Collinear (distinct)
/// points now yield the degenerate line-pair carrier ([conic] non-null,
/// [circle] and the angles null — [isDefined] still reads false);
/// coincident points (within `projectiveEpsilon`, guarded before the
/// kernel call) stay fully undefined. Recovery on drag is unchanged.
class Arc extends GeoCircle {
  Arc({
    required super.id,
    required this.start,
    required this.via,
    required this.end,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint start;
  final GeoPoint via;
  final GeoPoint end;

  ConicMatrix? _conic;
  CircleEq? _circle;
  double? _startAngle;
  double? _sweep;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  /// Carrier angle of [start]; null while undefined.
  double? get startAngle => _startAngle;

  /// Signed sweep from [startAngle] to [end]'s carrier angle, positive
  /// counter-clockwise — the branch containing [via]. Null while undefined.
  double? get sweep => _sweep;

  /// The arc's endpoints; null while the parent point is undefined.
  Vec2? get startPosition => start.position;
  Vec2? get endPosition => end.position;

  /// The drawn branch as a counter-clockwise span: a negative [sweep]
  /// walks back from [startAngle], so the span starts at the far endpoint.
  @override
  (double, double)? get angularExtent {
    final startAngle = _startAngle;
    final sweep = _sweep;
    if (startAngle == null || sweep == null) {
      return null;
    }
    return sweep >= 0 ? (startAngle, sweep) : (startAngle + sweep, -sweep);
  }

  /// Whether the carrier point at [angle] lies on the arc (endpoints
  /// included). False while undefined.
  bool containsAngle(double angle) {
    final startAngle = _startAngle;
    final sweep = _sweep;
    if (startAngle == null || sweep == null) {
      return false;
    }
    return sweep >= 0
        ? ccwSweep(startAngle, angle) <= sweep
        : ccwSweep(angle, startAngle) <= -sweep;
  }

  @override
  List<GeoObject> get parents => [start, via, end];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Euclidean only (Phase 125). The carrier circle generalizes, but the angular extent that makes
    // it an arc is a chart parameterization (PLAN, Parameterization), and
    // a CK circle is not a Euclidean circle in the chart. The extent would
    // have to be re-founded on the CK angle first.
    if (!absolute.isEuclidean) {
      _conic = null;
      _circle = null;
      _startAngle = null;
      _sweep = null;
      return;
    }
    final s = start.projPoint;
    final v = via.projPoint;
    final e = end.projPoint;
    if (s == null ||
        v == null ||
        e == null ||
        s.closeTo(v) ||
        v.closeTo(e) ||
        s.closeTo(e)) {
      _conic = null;
      _circle = null;
      _startAngle = null;
      _sweep = null;
      return;
    }
    final k = circumcircleOf(s, v, e);
    _conic = k.isZero ? null : k;
    final circle = _circle = _conic?.toCircleEq();
    final sp = start.position;
    final vp = via.position;
    final ep = end.position;
    if (circle == null || sp == null || vp == null || ep == null) {
      _startAngle = null;
      _sweep = null;
      return;
    }
    final startAngle = circle.angleAt(sp);
    _startAngle = startAngle;
    _sweep = sweepThrough(startAngle, circle.angleAt(vp), circle.angleAt(ep));
  }
}
