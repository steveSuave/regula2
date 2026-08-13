import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/euclidean.dart';
import '../../projective/proj_point.dart';
import 'triangle_circle.dart';

/// The nine-point (Euler) circle of a triangle: through the three side
/// midpoints, the three feet of the altitudes, and the midpoints between
/// each vertex and the orthocenter.
///
/// Migrated (Phase 109): the circumcircle of the three side midpoints,
/// natively projective. Collinear (distinct) vertices yield the
/// degenerate line pair of the midpoint line with the line at infinity —
/// `conic` non-null, `circle` null — instead of no value at all;
/// coincident vertices stay fully undefined (base-class guard).
class NinePointCircle extends TriangleCircle {
  NinePointCircle({
    required super.id,
    required super.vertex1,
    required super.vertex2,
    required super.vertex3,
    super.attributes,
  });

  @override
  ConicMatrix? computeConic(ProjPoint a, ProjPoint b, ProjPoint c) =>
      circumcircleOf(midpointOf(a, b), midpointOf(b, c), midpointOf(c, a));
}
