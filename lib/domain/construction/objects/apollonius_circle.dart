import '../../math/circle_eq.dart';
import '../../projective/circles.dart';
import '../../projective/conic_matrix.dart';
import '../geo_object.dart';

/// The Apollonius circle over [point1] (A) and [point2] (B) with the
/// distance ratio supplied by [point3] (C): the locus of points P with
/// `|PA| / |PB| = |CA| / |CB|` — which passes through C itself.
///
/// Undefined while any two of the points coincide (within
/// `projectiveEpsilon`, guarded before the kernel call) or a parent is
/// undefined; recovers when a drag breaks the degeneracy.
///
/// Migrated (Phase 109): stores [apolloniusCircleOf] of the parents'
/// projective views; [circle] is its projection. C equidistant from A and
/// B now yields the degenerate line pair of the perpendicular bisector
/// with the line at infinity instead of no value at all ([conic]
/// non-null, [circle] null — [isDefined] still reads false), and the
/// exactly-equidistant cutoff replaces V1's `1 − ratio²` epsilon band, so
/// near-bisector configurations stay defined as very large circles.
class ApolloniusCircle extends GeoCircle {
  ApolloniusCircle({
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
  void recompute() {
    final a = point1.projPoint;
    final b = point2.projPoint;
    final c = point3.projPoint;
    // C on A makes the ratio zero, C on B makes it infinite, A on B makes
    // it meaningless — all three collapse the locus to a point or nothing.
    if (a == null ||
        b == null ||
        c == null ||
        a.closeTo(b) ||
        c.closeTo(a) ||
        c.closeTo(b)) {
      _conic = null;
      _circle = null;
      return;
    }
    final k = apolloniusCircleOf(a, b, c);
    _conic = k.isZero ? null : k;
    _circle = _conic?.toCircleEq();
  }
}
