import '../../math/circle_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The circle through three points (their circumcircle).
///
/// Migrated (Phase 109): stores [circumcircleOf] of the parents'
/// projective views; [circle] is its projection. Collinear (distinct)
/// points now yield the degenerate line pair of their line with the line
/// at infinity instead of no value at all — [conic] non-null, [circle]
/// null, so [isDefined] still reads false and rendering skips it until
/// Phase 119 draws degenerate conics. Coincident points (within
/// `projectiveEpsilon`, guarded before the kernel call per the
/// `carrierThrough` convention) stay fully undefined; recovery on drag is
/// unchanged.
class ThreePointCircle extends GeoCircle {
  ThreePointCircle({
    required super.id,
    required this.point1,
    required this.point2,
    required this.point3,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;
  final GeoPoint point3;

  ConicMatrix? _conic;
  CircleEq? _circle;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  List<GeoObject> get parents => [point1, point2, point3];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p1 = point1.projPoint;
    final p2 = point2.projPoint;
    final p3 = point3.projPoint;
    if (p1 == null ||
        p2 == null ||
        p3 == null ||
        p1.closeTo(p2) ||
        p2.closeTo(p3) ||
        p1.closeTo(p3)) {
      _conic = null;
      _circle = null;
      return;
    }
    final k = circumcircleOf(p1, p2, p3);
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
  }
}
