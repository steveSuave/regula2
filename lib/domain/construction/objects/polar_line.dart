import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_line.dart';
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
    _carrier = polar.isZero ? null : polar;
    _line = orientedAlong(_carrier?.toLineEq(), _v1Direction());
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
