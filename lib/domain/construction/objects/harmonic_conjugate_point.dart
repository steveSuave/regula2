import '../../math/vec2.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The fourth harmonic point: the conjugate of [point3] with respect to
/// [point1] and [point2], with cross-ratio (A,B;C,D) = −1.
///
/// Undefined while any parent is, while the three points are not
/// collinear (within the projective incidence tolerance), or while the
/// base pair coincides; recovers when the degeneracy passes.
///
/// Migrated (Phase 108): [harmonicConjugateOf] on the parents' projective
/// views — the cross-ratio computed natively, division-free. [point3] at
/// the midpoint of the base pair now conjugates to the join's point at
/// infinity instead of going undefined, marked as such: [projPoint] real,
/// [position] null. The coincidence and collinearity gates keep V1's
/// semantics (relative tolerance, like every migrated guard).
class HarmonicConjugatePoint extends GeoPoint {
  HarmonicConjugatePoint({
    required super.id,
    required this.point1,
    required this.point2,
    required this.point3,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;
  final GeoPoint point3;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point1, point2, point3];

  @override
  void recompute() {
    final a = point1.projPoint;
    final b = point2.projPoint;
    final c = point3.projPoint;
    if (a == null || b == null || c == null || a.closeTo(b)) {
      _point = null;
      return;
    }
    if (!c.isIncidentTo(a.join(b))) {
      _point = null;
      return;
    }
    final d = harmonicConjugateOf(a, b, c);
    _point = d.isZero ? null : d;
  }
}
