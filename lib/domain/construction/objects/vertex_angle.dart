import '../../math/angle_geometry.dart';
import '../geo_object.dart';

/// The angle at [vertex] swept counter-clockwise from the ray towards
/// [arm1] to the ray towards [arm2].
///
/// The sweep is directed, so the two arm orders mark the two
/// complementary angles (their measures total 2π). Undefined while an arm
/// coincides with the vertex or a parent is undefined.
///
/// Migrated (Phase 112): reads the parents' projective views and projects
/// them into the chart itself — angles are chart quantities (the metric
/// boundary; M-CK re-founds them on cross-ratios later). A parent that is
/// complex or at infinity leaves the angle undefined: a point at infinity
/// is a direction *without a sign*, so the wedge between signed rays has
/// no rescaling-invariant meaning there — don't "improve" this to read
/// the representative's direction.
class VertexAngle extends GeoAngle {
  VertexAngle({
    required super.id,
    required this.arm1,
    required this.vertex,
    required this.arm2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint arm1;
  final GeoPoint vertex;
  final GeoPoint arm2;

  AngleGeometry? _angle;

  @override
  AngleGeometry? get angle => _angle;

  @override
  List<GeoObject> get parents => [arm1, vertex, arm2];

  @override
  void recompute() {
    final a = arm1.projPoint?.toVec2();
    final v = vertex.projPoint?.toVec2();
    final b = arm2.projPoint?.toVec2();
    _angle = (a == null || v == null || b == null)
        ? null
        : AngleGeometry.fromRays(a, v, b);
  }
}
