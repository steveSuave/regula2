import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';
import 'line_through_two_points.dart';

/// The segment between two points.
///
/// A [GeoLine] via its carrier [line], so segments participate in
/// intersections like infinite lines do (clipping intersection points to
/// the segment's extent is deferred — see `IntersectionPoint`; constrained
/// points do clamp, via [parameterExtent]). Undefined while the endpoints
/// coincide or a parent is undefined.
///
/// Migrated (Phase 107): the carrier is the projective join
/// ([carrierThrough]), but unlike `LineThroughTwoPoints` a segment *is*
/// its drawn extent, so it additionally requires both endpoints real and
/// finite — an endpoint at infinity leaves the whole object undefined,
/// carrier included, exactly as in V1.
class Segment extends GeoLine {
  Segment({
    required super.id,
    required this.point1,
    required this.point2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  /// Current endpoints; null while the respective parent is undefined.
  /// The painter draws from these, [line] exists for intersection math.
  Vec2? get start => point1.position;
  Vec2? get end => point2.position;

  /// Both endpoints' carrier parameters, ordered.
  @override
  (double?, double?)? get parameterExtent {
    final line = _line;
    if (line == null) {
      return null;
    }
    final t1 = line.parameterAt(point1.position!);
    final t2 = line.parameterAt(point2.position!);
    return t1 <= t2 ? (t1, t2) : (t2, t1);
  }

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p1 = point1.position;
    final p2 = point2.position;
    if (p1 == null || p2 == null) {
      _carrier = null;
      _line = null;
      return;
    }
    _carrier = carrierThrough(point1, point2);
    _line = orientedAlong(_carrier?.toLineEq(), p2 - p1);
  }
}
