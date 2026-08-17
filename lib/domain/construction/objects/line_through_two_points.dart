import '../../math/line_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';

/// The infinite line through two points.
///
/// Migrated (Phase 107): the carrier is the projective join of the
/// parents' homogeneous points. A parent at infinity now yields the real
/// line through the finite parent in that direction (V1: undefined).
/// Undefined while the parents projectively coincide (within
/// `projectiveEpsilon`, the [carrierThrough] convention) or a parent is
/// undefined; comes back when they separate.
class LineThroughTwoPoints extends GeoLine {
  LineThroughTwoPoints({
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

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    _carrier = carrierThrough(point1, point2);
    final p1 = point1.position;
    final p2 = point2.position;
    _line = orientedAlong(
      _carrier?.toLineEq(),
      (p1 == null || p2 == null) ? null : p2 - p1,
    );
  }
}

/// Projective carrier through two point objects — the join of their
/// homogeneous points — or null when either parent is undefined or the
/// points projectively coincide (within `projectiveEpsilon`).
///
/// Shared by [LineThroughTwoPoints], `Segment` and `Ray` so all three
/// agree on what "degenerate" means.
ProjLine? carrierThrough(GeoPoint point1, GeoPoint point2) {
  final p1 = point1.projPoint;
  final p2 = point2.projPoint;
  if (p1 == null || p2 == null || p1.closeTo(p2)) {
    return null;
  }
  return p1.join(p2);
}
