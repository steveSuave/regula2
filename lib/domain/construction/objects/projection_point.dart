import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/metric.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The orthogonal projection of [point] onto [line] — the foot of the
/// perpendicular.
///
/// Undefined while either parent is (e.g. the line's defining points
/// coincide); a point already on the line projects to itself, which is
/// not degenerate. Segments and rays project onto their infinite
/// carrier, matching `ReflectedPoint`'s mirror semantics.
///
/// Migrated (Phase 108): the meet of the carrier with
/// [perpendicularThrough] the point, on the parents' projective views. A
/// parent at infinity projects to the carrier's point at infinity (the
/// affine limit of ever-farther feet), marked as such: [projPoint] real,
/// [position] null. The exception is the carrier's own normal direction,
/// whose perpendicular is not unique — the zero triple, undefined.
class ProjectionPoint extends GeoPoint {
  ProjectionPoint({
    required super.id,
    required this.point,
    required this.line,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point;
  final GeoLine line;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point, line];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p = point.projPoint;
    final carrier = line.projLine;
    if (p == null || carrier == null) {
      _point = null;
      return;
    }
    final foot = perpendicularThrough(p, carrier, absolute).meet(carrier);
    _point = foot.isZero ? null : foot;
  }
}
