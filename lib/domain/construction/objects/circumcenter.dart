import '../../projective/absolute.dart';
import '../../projective/metric.dart';
import '../../projective/proj_point.dart';
import 'triangle_center_point.dart';

/// The circumcenter (center of the circle through all three vertices) of
/// three points — projectively, the meet of two perpendicular bisectors.
///
/// Undefined while any two vertices coincide (a bisector degenerates to
/// the zero triple); collinear vertices put it at infinity perpendicular
/// to the common line (V1: undefined), so [position] still goes null
/// there.
class Circumcenter extends TriangleCenterPoint {
  Circumcenter({
    required super.id,
    required super.vertex1,
    required super.vertex2,
    required super.vertex3,
    super.attributes,
  });

  @override
  ProjPoint computeCenter(
    ProjPoint a,
    ProjPoint b,
    ProjPoint c,
    Absolute absolute,
  ) => perpendicularBisectorOf(
    a,
    b,
    absolute,
  ).meet(perpendicularBisectorOf(a, c, absolute));
}
