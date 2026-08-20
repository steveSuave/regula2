import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The polar line of [point] (the pole) with respect to [circle]:
/// perpendicular to the center→pole join at the pole's inverse point —
/// through the tangent points when the pole is outside, the tangent at
/// the pole when it lies on the circle, and still defined inside.
///
/// Unlike [point]'s two tangent lines the polar is single-valued, so
/// there is no branch.
///
/// Migrated (Phase 110): the carrier is `A·p` on the parents' projective
/// views — the kernel's polar operation, verbatim. The pole at the
/// circle's center now carries ℓ∞ ([projLine] real, [line] null, so the
/// object still reads undefined there), and V1's absolute epsilon guard
/// around the center is gone: a pole merely *near* the center has a
/// genuine faraway polar. A degenerate line-pair carrier polarizes too
/// (every polar passes through its singular point); only the singular
/// point itself has no polar (zero triple → undefined).
class PolarLine extends GeoLine {
  PolarLine({
    required super.id,
    required this.point,
    required this.circle,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point;
  final GeoCircle circle;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [point, circle];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p = point.projPoint;
    final a = circle.conic;
    if (p == null || a == null) {
      _carrier = null;
      _line = null;
      return;
    }
    final polar = a.polarLine(p);
    _carrier = polar.isZero ? null : _oriented(polar, a, p);
    _line = orientedAlong(_carrier?.toLineEq(), _v1Direction());
  }

  /// [polar] with its representative sign carrying the V1 orientation
  /// (Phase 137, PLAN §"Orientation is the representative's sign"). For a
  /// circle-shaped conic the quadratic block is `s·I`, so the raw
  /// `A·p` has normal `s·w_p·(pole − center)` — V1's "normal points
  /// centre→pole" is the raw representative times `sign(tr Q · w_p)`.
  /// The sign's discontinuity loci are `w_p = 0` (the pole at infinity)
  /// and `tr Q = 0` (a balanced-hyperbola conic) — both states V1's
  /// chart rule never classified either; at either the raw sign stands.
  static ProjLine _oriented(ProjLine polar, ConicMatrix a, ProjPoint p) {
    final sign = (a.xx.re + a.yy.re) * p.w.re;
    return sign < 0 ? polar.scaledBy(const Complex(-1)) : polar;
  }

  /// The V1 orientation: `polarLine`'s normal is the center→pole offset,
  /// so its direction is that offset rotated clockwise. Null without an
  /// affine view of both parents (no V1 precedent).
  Vec2? _v1Direction() {
    final pole = point.position;
    final c = circle.circle;
    if (pole == null || c == null) {
      return null;
    }
    final n = pole - c.center;
    return n == Vec2.zero ? null : Vec2(n.y, -n.x);
  }
}
