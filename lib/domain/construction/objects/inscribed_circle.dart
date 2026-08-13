import '../../math/circle_eq.dart';
import '../../math/triangle_centers.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_point.dart';
import 'triangle_circle.dart';

/// The inscribed circle (incircle) of a triangle: centered at the
/// incenter, tangent to all three sides from the inside.
///
/// Undefined while the vertices are collinear, coincident, or not real
/// and finite. Rides along on the migrated `TriangleCircle` base
/// (Phase 109) via project→compute→lift rather than being migrated
/// itself: the incenter's closed form takes square roots of side lengths,
/// which is neither holomorphic nor single-valued, so — like `Incenter`
/// in Phase 107 — the affine formula stays authoritative.
class InscribedCircle extends TriangleCircle {
  InscribedCircle({
    required super.id,
    required super.vertex1,
    required super.vertex2,
    required super.vertex3,
    super.attributes,
  });

  @override
  ConicMatrix? computeConic(ProjPoint a, ProjPoint b, ProjPoint c) {
    final va = a.toVec2();
    final vb = b.toVec2();
    final vc = c.toVec2();
    if (va == null || vb == null || vc == null) {
      return null;
    }
    final center = incenter(va, vb, vc);
    if (center == null) {
      return null;
    }
    return ConicMatrix.lift(CircleEq(center, inradius(va, vb, vc)!));
  }
}
