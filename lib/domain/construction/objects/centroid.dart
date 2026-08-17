import '../../projective/absolute.dart';
import '../../projective/metric.dart';
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
  ProjPoint computeCenter(
    ProjPoint a,
    ProjPoint b,
    ProjPoint c,
    Absolute absolute,
  ) => absolute.isEuclidean
      ? centroidOf(a, b, c)
      // The medians' common point. Under the Euclidean absolute that is
      // what `centroidOf`'s affine average computes; under a proper one
      // the medians run to the *CK* midpoints, and the construction is
      // otherwise the same — so this generalizes rather than refuses.
      : a
            .join(midpointOf(b, c, absolute))
            .meet(b.join(midpointOf(a, c, absolute)));
}
