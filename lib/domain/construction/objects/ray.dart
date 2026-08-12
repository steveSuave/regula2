import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';
import 'line_through_two_points.dart';

/// The ray from [origin] through [through].
///
/// A [GeoLine] via its carrier [line], so rays participate in
/// intersections like infinite lines do (clipping intersection points to
/// the ray's extent is deferred, matching `Segment`; constrained points
/// do clamp, via [parameterExtent]). Undefined while the points coincide
/// or a parent is undefined.
///
/// The carrier's `direction` is normalized independently of the parents'
/// order, so painter and hit tester must use [start] and
/// [throughPosition] — not the carrier — to know which half-line exists.
///
/// Migrated (Phase 107): the carrier is the projective join
/// ([carrierThrough]), but like `Segment` a ray needs its endpoint and
/// direction anchor drawable, so both parents must stay real and finite —
/// a parent at infinity leaves the whole object undefined, carrier
/// included, exactly as in V1.
class Ray extends GeoLine {
  Ray({
    required super.id,
    required this.origin,
    required this.through,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint origin;
  final GeoPoint through;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  /// The ray's endpoint; null while [origin] is undefined.
  Vec2? get start => origin.position;

  /// A point the ray passes through, fixing its direction from [start];
  /// null while [through] is undefined.
  Vec2? get throughPosition => through.position;

  /// Bounded at [origin]'s carrier parameter, unbounded past [through] —
  /// on whichever side of the carrier's parameterization that is.
  @override
  (double?, double?)? get parameterExtent {
    final line = _line;
    if (line == null) {
      return null;
    }
    final t0 = line.parameterAt(origin.position!);
    final tThrough = line.parameterAt(through.position!);
    return tThrough >= t0 ? (t0, null) : (null, t0);
  }

  @override
  List<GeoObject> get parents => [origin, through];

  @override
  void recompute() {
    final p1 = origin.position;
    final p2 = through.position;
    if (p1 == null || p2 == null) {
      _carrier = null;
      _line = null;
      return;
    }
    _carrier = carrierThrough(origin, through);
    _line = orientedAlong(_carrier?.toLineEq(), p2 - p1);
  }
}
