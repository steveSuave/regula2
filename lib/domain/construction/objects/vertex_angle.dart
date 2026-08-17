import '../../math/angle_geometry.dart';
import '../../projective/absolute.dart';
import '../../projective/ck_measure.dart';
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
  double? _measure;

  @override
  AngleGeometry? get angle => _angle;

  @override
  double? get measure => _measure ?? _angle?.measure;

  @override
  List<GeoObject> get parents => [arm1, vertex, arm2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final a = arm1.projPoint?.toVec2();
    final v = vertex.projPoint?.toVec2();
    final b = arm2.projPoint?.toVec2();
    _angle = (a == null || v == null || b == null)
        ? null
        : AngleGeometry.fromRays(a, v, b);
    _measure = _ckMeasure(absolute);
  }

  /// The Cayley-Klein measure of the marked wedge, or null to fall back to
  /// the marker's own sweep.
  ///
  /// Euclidean angle measure is elliptic and the chart formula is already
  /// exactly it (agreement pinned to 7.4e-13 in `ck_measure_test.dart`),
  /// so Euclidean keeps the chart answer: exact, cheaper, and it keeps a
  /// right angle reading exactly pi/2. This is the Phase 122 circle
  /// fast-path rule -- the general formula is the definition, the
  /// specialization is what runs where it is exact.
  double? _ckMeasure(Absolute absolute) {
    if (absolute.isEuclidean) {
      return null;
    }
    final v = vertex.projPoint;
    final a = arm1.projPoint;
    final b = arm2.projPoint;
    if (v == null || a == null || b == null) {
      return null;
    }
    return angleBetweenLines(absolute, v.join(a), v.join(b));
  }
}
