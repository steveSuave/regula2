import '../../math/angle_geometry.dart';
import '../../math/circle_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The circular sector (pie wedge) around [center]: [start] fixes the
/// radius and the start angle, [end] fixes only the end angle — its
/// distance from the center is irrelevant. The wedge opens
/// counter-clockwise from start to end.
///
/// A [GeoCircle] via its carrier [circle], like `Arc`. Undefined while
/// [start] or [end] coincides with [center] (no direction → no angle;
/// now within `projectiveEpsilon` rather than V1's exact equality) or a
/// parent is undefined or not real and finite (the angles need real
/// positions); recovers when the degeneracy passes.
///
/// Migrated (Phase 109): the carrier is [circleThrough] on the projective
/// views of [center] and [start]; [circle] is its projection and the
/// angular extent stays affine metadata read off that projection.
///
/// **The carrier is total; only the wedge is a chart reading** (Phase
/// 136c), the same split `Segment` and `Ray` took in Phase 136b and the
/// one `Arc` has had since Phase 109. [circle], [startAngle], [sweep],
/// [startRim], [endRim], [angularExtent], [containsAngle] and therefore
/// [isDefined] all still require three real finite positions and an
/// [end] off the [center], exactly as before — but [conic] does not,
/// because it is the projective value and the one degeneracy convention
/// says a projective value is null only when a parent's is or the
/// computed value is the zero triple (see `GeoObject`). The old guard
/// bundled the positions and `end.closeTo(center)` into the same early
/// return that nulled the carrier, and neither is in it: [end] fixes
/// only the end angle, and [circleThrough] reads no chart at all. A
/// chart-gated carrier is an object that **cannot be continued
/// through** — a complex detour drives a parent off the real axis, the
/// carrier vanishes, and every intersection riding it coasts the whole
/// arc on a stale root — and no static test can tell one from a correct
/// one, which is why this was found by reading rather than by running.
///
/// Painter and hit tester must use [startAngle]/[sweep] and the two rim
/// points — the carrier alone is the full circle.
class Sector extends GeoCircle {
  Sector({
    required super.id,
    required this.center,
    required this.start,
    required this.end,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint center;
  final GeoPoint start;
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

  /// Counter-clockwise sweep from [startAngle] to [end]'s carrier angle,
  /// in [0, 2π). Null while undefined.
  double? get sweep => _sweep;

  /// Where the wedge's first straight edge meets the carrier — [start]'s
  /// position. Null while undefined.
  Vec2? get startRim => isDefined ? start.position : null;

  /// Where the wedge's second straight edge meets the carrier — [end]
  /// projected radially onto the circle. Null while undefined.
  Vec2? get endRim {
    final circle = _circle;
    final startAngle = _startAngle;
    final sweep = _sweep;
    if (circle == null || startAngle == null || sweep == null) {
      return null;
    }
    return circle.pointAt(startAngle + sweep);
  }

  /// The wedge's arc as a counter-clockwise span from [startAngle].
  @override
  (double, double)? get angularExtent {
    final startAngle = _startAngle;
    final sweep = _sweep;
    return (startAngle == null || sweep == null) ? null : (startAngle, sweep);
  }

  /// Whether the carrier point at [angle] lies on the wedge's arc
  /// (endpoints included). False while undefined.
  bool containsAngle(double angle) {
    final startAngle = _startAngle;
    final sweep = _sweep;
    if (startAngle == null || sweep == null) {
      return false;
    }
    return ccwSweep(startAngle, angle) <= sweep;
  }

  /// The wedge draws, which is a stronger question than the base class's
  /// "does the carrier project to a circle?".
  ///
  /// Overridden in Phase 136c because the carrier stopped being a chart
  /// reading and the base class reads `conic` when `circle` is null: a
  /// sector with a parent off the chart now has a perfectly good
  /// parameterized carrier, and would have read *defined* with no extent
  /// at all. The painter dereferences [circle], [startAngle] and [sweep]
  /// unconditionally on a defined sector, so that is not a cosmetic
  /// difference. This is exactly the old behaviour restated: before the
  /// split the four fields were nulled together, so `circle != null` and
  /// `sweep != null` named the same states.
  @override
  bool get isDefined => _sweep != null;

  @override
  List<GeoObject> get parents => [center, start, end];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Euclidean only (Phase 125). As Arc: the carrier generalizes, the angular extent does not.
    if (!absolute.isEuclidean) {
      _conic = null;
      _circle = null;
      _startAngle = null;
      _sweep = null;
      return;
    }
    final c = center.projPoint;
    final s = start.projPoint;
    final e = end.projPoint;
    // The carrier's own gate: a parent with no projective value, and the
    // one coincidence that collapses the circle itself. [end] is not in
    // it — it fixes only the end angle.
    if (c == null || s == null || e == null || s.closeTo(c)) {
      _conic = null;
      _circle = null;
      _startAngle = null;
      _sweep = null;
      return;
    }
    final k = circleThrough(c, s);
    _conic = k.isZero ? null : k;
    // The projection stays gated on the chart: the wedge's angles need
    // real finite positions with directions from the center, so a sector
    // with a parent off the chart keeps its carrier but has no drawable
    // extent and stays undefined ([isDefined] reads [circle]).
    final cp = center.position;
    final sp = start.position;
    final ep = end.position;
    if (cp == null || sp == null || ep == null || e.closeTo(c)) {
      _circle = null;
      _startAngle = null;
      _sweep = null;
      return;
    }
    final circle = _circle = _conic?.toCircleEq();
    if (circle == null) {
      _startAngle = null;
      _sweep = null;
      return;
    }
    final startAngle = circle.angleAt(sp);
    _startAngle = startAngle;
    _sweep = ccwSweep(startAngle, circle.angleAt(ep));
  }
}
