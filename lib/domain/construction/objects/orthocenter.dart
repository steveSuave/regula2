import '../../projective/absolute.dart';
import '../../projective/metric.dart';
import '../../projective/proj_point.dart';
import 'triangle_center_point.dart';

/// The orthocenter (intersection of the altitudes) of three points —
/// projectively, the meet of two altitudes (perpendiculars through a
/// vertex to the opposite side, via the circular points I, J).
///
/// Undefined while any two vertices coincide (the altitudes merge — zero
/// meet); collinear vertices put it at infinity in the common line's
/// normal direction (V1: undefined), so [position] still goes null there.
class Orthocenter extends TriangleCenterPoint {
  Orthocenter({
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
  ) => perpendicularThrough(
    a,
    b.join(c),
    absolute,
  ).meet(perpendicularThrough(b, a.join(c), absolute));
}
