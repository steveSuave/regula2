import '../../math/triangle_centers.dart' as tc;
import '../../projective/absolute.dart';
import '../../projective/metric.dart';
import '../../projective/proj_point.dart';
import 'triangle_center_point.dart';

/// The incenter (center of the inscribed circle) of three points.
/// Undefined while the vertices are collinear or coincident.
///
/// Distance-weighted, so not a projective construction (Phase 107 note):
/// it is computed in the affine chart and lifted back, and stays undefined
/// whenever a vertex leaves the chart (complex or at infinity).
class Incenter extends TriangleCenterPoint {
  Incenter({
    required super.id,
    required super.vertex1,
    required super.vertex2,
    required super.vertex3,
    super.attributes,
  });

  @override
  ProjPoint? computeCenter(
    ProjPoint a,
    ProjPoint b,
    ProjPoint c,
    Absolute absolute,
  ) {
    if (!absolute.isEuclidean) {
      // The internal bisectors' common point — the definition, and one
      // that generalizes because `angleBisectorOf` does. The chart route
      // below is the Euclidean specialization, kept because it is exact.
      final meet = angleBisectorOf(
        b,
        a,
        c,
        absolute,
      ).meet(angleBisectorOf(a, b, c, absolute));
      return meet.isZero ? null : meet;
    }
    final pa = a.toVec2();
    final pb = b.toVec2();
    final pc = c.toVec2();
    if (pa == null || pb == null || pc == null) {
      return null;
    }
    final center = tc.incenter(pa, pb, pc);
    return center == null ? null : ProjPoint.lift(center);
  }
}
