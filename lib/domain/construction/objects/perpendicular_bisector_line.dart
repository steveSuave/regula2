import '../../math/line_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/euclidean.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';

/// The perpendicular bisector of the segment between [point1] and
/// [point2]: the line through their midpoint, perpendicular to the join.
///
/// A dedicated kind on the [AngleBisectorLine] precedent rather than a
/// hidden Midpoint + PerpendicularLine macro — single-valued and
/// continuous. Undefined while either parent is, or while the points
/// projectively coincide (within `projectiveEpsilon`, the
/// `carrierThrough` convention); recovers when they separate.
///
/// Migrated (Phase 107): [perpendicularBisectorOf] on the parents'
/// projective views — the perpendicular direction is the join's conjugate
/// w.r.t. the circular points I, J.
class PerpendicularBisectorLine extends GeoLine {
  PerpendicularBisectorLine({
    required super.id,
    required this.point1,
    required this.point2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p1 = point1.projPoint;
    final p2 = point2.projPoint;
    if (p1 == null || p2 == null || p1.closeTo(p2)) {
      _carrier = null;
      _line = null;
      return;
    }
    final carrier = perpendicularBisectorOf(p1, p2);
    _carrier = carrier.isZero ? null : carrier;
    final a1 = point1.position;
    final a2 = point2.position;
    _line = orientedAlong(
      _carrier?.toLineEq(),
      (a1 == null || a2 == null) ? null : (a2 - a1).perpendicular,
    );
  }
}
