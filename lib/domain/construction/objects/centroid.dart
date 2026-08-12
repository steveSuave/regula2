import '../../projective/euclidean.dart';
import '../../projective/proj_point.dart';
import 'triangle_center_point.dart';

/// The centroid (intersection of the medians) of three points.
///
/// Defined whenever all parents are — unlike the other triangle centers,
/// collinear or coincident vertices are not degenerate for the centroid.
class Centroid extends TriangleCenterPoint {
  Centroid({
    required super.id,
    required super.vertex1,
    required super.vertex2,
    required super.vertex3,
    super.attributes,
  });

  @override
  ProjPoint computeCenter(ProjPoint a, ProjPoint b, ProjPoint c) =>
      centroidOf(a, b, c);
}
