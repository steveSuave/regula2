import '../../math/line_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/circles.dart';
import '../../projective/complex.dart';
import '../../projective/conic_matrix.dart';
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
    _carrier = axis.isZero ? null : _oriented(axis, c1, c2);
    _line = _carrier?.toOrientedLineEq();
  }

  /// [axis] with its representative sign carrying the V1 orientation
  /// (Phase 137, PLAN §"Orientation is the representative's sign").
  /// `radicalAxisOf`'s linear part is `s₁·s₂·(center₂ − center₁)` for
  /// circle-shaped conics with quadratic scales `s₁`, `s₂` — V1's
  /// "normal points centre₁→centre₂" is the raw representative times
  /// `sign(tr Q₁ · tr Q₂)`, and a circle-shaped block's trace never
  /// vanishes, so the sign is total here. A degenerate line-conic parent
  /// (the flattening limit) can zero a trace; the raw sign stands there,
  /// where V1's chart rule never classified either.
  static ProjLine _oriented(ProjLine axis, ConicMatrix c1, ConicMatrix c2) {
    final sign = (c1.xx.re + c1.yy.re) * (c2.xx.re + c2.yy.re);
    return sign < 0 ? axis.scaledBy(const Complex(-1)) : axis;
  }
}
