import '../../math/circle_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// Base for circle objects derived from the three vertices of a triangle
/// (`NinePointCircle`, `InscribedCircle`) — the circle sibling of
/// `TriangleCenterPoint`.
///
/// Migrated (Phase 109): the base stores a [ConicMatrix]; [circle] is its
/// projection. Subclasses supply [computeConic] on the vertices'
/// projective views — either natively projective (`NinePointCircle`) or
/// project-compute-lift for closed forms that need real distances
/// (`InscribedCircle`), returning null (or the zero matrix) for input
/// their formula cannot handle. Coincident vertices (within
/// `projectiveEpsilon`) are guarded here, before [computeConic]; that
/// makes the object undefined until the degeneracy passes.
abstract class TriangleCircle extends GeoCircle {
  TriangleCircle({
    required super.id,
    required this.vertex1,
    required this.vertex2,
    required this.vertex3,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint vertex1;
  final GeoPoint vertex2;
  final GeoPoint vertex3;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [vertex1, vertex2, vertex3];

  /// The conic derived from triangle `abc` (pairwise-distinct projective
  /// points), or null when the subclass's formula degenerates.
  ConicMatrix? computeConic(
    ProjPoint a,
    ProjPoint b,
    ProjPoint c,
    Absolute absolute,
  );

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final a = vertex1.projPoint;
    final b = vertex2.projPoint;
    final c = vertex3.projPoint;
    if (a == null ||
        b == null ||
        c == null ||
        a.closeTo(b) ||
        b.closeTo(c) ||
        a.closeTo(c)) {
      _conic = null;
      _circle = null;
      return;
    }
    final k = computeConic(a, b, c, absolute);
    _conic = (k == null || k.isZero) ? null : k;
    _circle = _conic?.toCircleEq();
  }
}
