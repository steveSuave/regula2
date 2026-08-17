import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';

/// The radical axis of two circles: the line of points with equal power
/// to both — through their intersections when they cross, always
/// perpendicular to the line of centers.
///
/// Migrated (Phase 110): the carrier is [radicalAxisOf] on the parents'
/// conics — the pencil member whose quadratic block cancels, which is
/// the line pair (axis, ℓ∞). Concentric circles now carry ℓ∞
/// ([projLine] real, [line] null, so the object still reads undefined
/// there), and V1's absolute epsilon guard around concentricity is gone:
/// merely near-concentric circles have a genuine faraway axis. Exactly
/// coincident carriers cancel to the zero triple (undefined); a
/// degenerate line-conic parent degenerates the axis onto its own line —
/// the continuous limit of a circle flattening.
class RadicalAxisLine extends GeoLine {
  RadicalAxisLine({
    required super.id,
    required this.circle1,
    required this.circle2,
    super.attributes,
  }) {
    if (identical(circle1, circle2)) {
      throw ArgumentError('RadicalAxisLine requires two distinct circles');
    }
    recompute();
  }

  final GeoCircle circle1;
  final GeoCircle circle2;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [circle1, circle2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    // Euclidean only (Phase 125). The radical axis is the locus of equal *power*, built on the
    // Euclidean circle coefficient shape and on squared distance. Neither
    // survives a change of absolute.
    if (!absolute.isEuclidean) {
      _carrier = null;
      _line = null;
      return;
    }
    final c1 = circle1.conic;
    final c2 = circle2.conic;
    if (c1 == null || c2 == null) {
      _carrier = null;
      _line = null;
      return;
    }
    final axis = radicalAxisOf(c1, c2);
    _carrier = axis.isZero ? null : axis;
    _line = orientedAlong(_carrier?.toLineEq(), _v1Direction());
  }

  /// The V1 orientation: `radicalAxis`'s normal is the center₁→center₂
  /// offset, so its direction is that offset rotated clockwise. Null
  /// without an affine view of both parents (no V1 precedent).
  Vec2? _v1Direction() {
    final a = circle1.circle;
    final b = circle2.circle;
    if (a == null || b == null) {
      return null;
    }
    final d = b.center - a.center;
    return d == Vec2.zero ? null : Vec2(d.y, -d.x);
  }
}
