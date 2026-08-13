import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// One of the two tangent lines from [point] to [circle].
///
/// [branch] picks the tangent whose touch point lies to the left (0) or
/// right (1) of the directed line from the circle's center to [point] —
/// V1 `tangentPointsToCircle`'s order, continuous under any drag of the
/// external point. With [point] on the circle both branches collapse to
/// the tangent at the point.
///
/// Migrated (Phase 110), polar-based: the touch points are the two
/// intersections of the pole's polar with the conic — always two, with
/// multiplicity — and the carrier is the *polar of the touch point*
/// (well-conditioned everywhere the join `point × touch` degenerates,
/// and through [point] automatically, by La Hire). A pole strictly
/// inside the circle has complex touch points: the carrier is a complex
/// line ([projLine] non-null, [line] null), undefined for rendering —
/// where V1 had no value at all. The center itself polarizes to ℓ∞,
/// whose meets with the circle are I and J: both tangents are isotropic
/// lines, likewise undefined. Undefined with a null carrier only while a
/// parent is, or at the singular point of a degenerate carrier (zero
/// polar).
class TangentLine extends GeoLine {
  TangentLine({
    required super.id,
    required this.point,
    required this.circle,
    required this.branch,
    super.attributes,
  }) {
    if (branch != 0 && branch != 1) {
      throw ArgumentError.value(branch, 'branch', 'must be 0 or 1');
    }
    recompute();
  }

  final GeoPoint point;
  final GeoCircle circle;
  final int branch;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [point, circle];

  @override
  void recompute() {
    final p = point.projPoint;
    final a = circle.conic;
    if (p == null || a == null) {
      _carrier = null;
      _line = null;
      return;
    }
    final polar = a.polarLine(p);
    if (polar.isZero) {
      _carrier = null;
      _line = null;
      return;
    }
    final touches = intersectLineConic(polar, a);
    if (touches.length < 2 || touches[0].isZero || touches[1].isZero) {
      _carrier = null;
      _line = null;
      return;
    }
    final touch = _v1Ordered(touches)[branch];
    final tangent = a.polarLine(touch);
    _carrier = tangent.isZero ? null : tangent;
    _line = orientedAlong(_carrier?.toLineEq(), _v1Direction(touch));
  }

  /// Reorders the two touch points into V1's branch order — the point to
  /// the left of the directed center→pole line first. Solver order stands
  /// when the V1 rule cannot classify (no affine views, complex or
  /// infinite touches, collapsed tangency — where the order is moot).
  List<ProjPoint> _v1Ordered(List<ProjPoint> touches) {
    final pole = point.position;
    final c = circle.circle;
    final t0 = touches[0].toVec2();
    final t1 = touches[1].toVec2();
    if (pole == null || c == null || t0 == null || t1 == null) {
      return touches;
    }
    final d = pole - c.center;
    // Left of the directed line = positive cross product.
    if (d.cross(t1 - c.center) > d.cross(t0 - c.center)) {
      return [touches[1], touches[0]];
    }
    return touches;
  }

  /// The V1 orientation: the tangent runs along the touch-point radius
  /// rotated counter-clockwise (`LineEq.pointDirection` of V1). Null
  /// without an affine picture (no V1 precedent).
  Vec2? _v1Direction(ProjPoint touch) {
    final t = touch.toVec2();
    final c = circle.circle;
    if (t == null || c == null) {
      return null;
    }
    final r = t - c.center;
    return r == Vec2.zero ? null : r.perpendicular;
  }
}
