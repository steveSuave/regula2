import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The center point of a circle-valued object.
///
/// The parent may be any [GeoCircle] — for an arc or sector this is the
/// carrier circle's center. Defined whenever the parent projects to a
/// real circle. Not to be confused with `CircleCenterPoint`, the *circle*
/// built from a center and a rim point.
///
/// Migrated (Phase 109): the center is the pole of the line at infinity
/// with respect to the parent's conic (`ConicMatrix.poleOf`) — exact for
/// lifted circles. A degenerate line-pair parent (e.g. a collinear
/// `ThreePointCircle`) collapses the pole to the zero triple: undefined,
/// as before.
class CircleCenter extends GeoPoint {
  CircleCenter({required super.id, required this.circle, super.attributes}) {
    recompute();
  }

  final GeoCircle circle;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [circle];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final pole = circle.conic?.poleOf(ProjLine.infinity);
    _point = (pole == null || pole.isZero) ? null : pole;
  }
}
