import '../../math/circle_eq.dart';
import '../../math/triangle_centers.dart';
import '../../projective/absolute.dart';
import '../../projective/ck_circles.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/metric.dart';
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
  ConicMatrix? computeConic(
    ProjPoint a,
    ProjPoint b,
    ProjPoint c,
    Absolute absolute,
  ) {
    if (!absolute.isEuclidean) {
      // Centred on the incentre, through the foot of the perpendicular to
      // a side — which is what "tangent to the sides" means, and which
      // generalizes because every piece of it now does.
      final centre = angleBisectorOf(
        b,
        a,
        c,
        absolute,
      ).meet(angleBisectorOf(a, b, c, absolute));
      if (centre.isZero) {
        return null;
      }
      final side = a.join(b);
      final foot = perpendicularThrough(centre, side, absolute).meet(side);
      return foot.isZero ? null : ckCircleThrough(absolute, centre, foot);
    }
    final va = a.toVec2();
    final vb = b.toVec2();
    final vc = c.toVec2();
    if (va == null || vb == null || vc == null) {
      return null;
    }
    final center = incenter(va, vb, vc);
    final radius = inradius(va, vb, vc);
    if (center == null || radius == null) {
      return null;
    }
    // `CircleEq` still throws on a bad radius, so the check is the
    // guard, not a formality: the two helpers share a collinearity test
    // and so agree today, but a recompute path may not depend on two
    // separate functions staying in step (Phase 121 — no throwing
    // construction inside a domain flow).
    return ConicMatrix.lift(CircleEq(center, radius));
  }
}
