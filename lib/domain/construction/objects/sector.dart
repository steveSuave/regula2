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
    final cp = center.position;
    final sp = start.position;
    final ep = end.position;
    // The wedge's angles need real finite positions with directions from
    // the center — a sector, unlike an arc, has no meaning without them.
    if (c == null ||
        s == null ||
        e == null ||
        cp == null ||
        sp == null ||
        ep == null ||
        s.closeTo(c) ||
        e.closeTo(c)) {
      _conic = null;
      _circle = null;
      _startAngle = null;
      _sweep = null;
      return;
    }
    final k = circleThrough(c, s);
    _conic = k.isZero ? null : k;
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
