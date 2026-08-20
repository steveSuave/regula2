import '../../math/line_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
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
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p = point.projPoint;
    final a = circle.conic;
    // Non-real parents yield nothing: tangency from a complex pole is an
    // intersection-shaped operation and would fabricate real touch
    // points V1 left undefined (see `intersectionCandidates`).
    if (p == null || a == null || !p.isReal() || !a.isReal()) {
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
    final touch = _v1Ordered(touches, a, p)[branch];
    final tangent = a.polarLine(touch);
    _carrier = tangent.isZero ? null : _oriented(tangent, a, touch);
    _line = _carrier?.toOrientedLineEq();
  }

  /// [tangent] with its representative sign carrying the V1 orientation
  /// (Phase 137, PLAN §"Orientation is the representative's sign"). For a
  /// circle-shaped conic the raw `A·t` has normal `s·w_t·(touch − center)`
  /// while V1 runs the tangent along the touch radius rotated
  /// counter-clockwise — normal along `−(touch − center)` — so the V1
  /// representative is the raw one times `−sign(tr Q · w_t)`. The sign's
  /// discontinuity loci (`w_t = 0`, `tr Q = 0`) are states V1's chart
  /// rule never classified either; at either the raw sign stands.
  static ProjLine _oriented(ProjLine tangent, ConicMatrix a, ProjPoint t) {
    final sign = (a.xx.re + a.yy.re) * t.w.re;
    return sign > 0 ? tangent.scaledBy(const Complex(-1)) : tangent;
  }

  /// Reorders the two touch points into V1's branch order — the point to
  /// the left of the directed center→pole line first — decided
  /// projectively (Phase 137): leftness is the sign of
  /// `det[centre, pole, touch]` with each row's sign normalized by its
  /// `w`, which for chart-normalized rows is exactly the chart cross
  /// product `cross(pole − c, touch − c)` the V1 rule compared. The
  /// centre row is `adj(A)·ℓ∞`, whose own `w` is `det Q` — positive for
  /// every circle-shaped conic, and independent of the representative's
  /// sign either way, since the adjugate is even. Solver order stands
  /// when a row is complex or at infinity (collapsed tangency, isotropic
  /// touches — where the order is moot, and where V1's chart rule could
  /// not classify either). Unlike the chart rule, this one also orders
  /// the tangents to a chartless carrier — a conic with no `CircleEq` —
  /// where solver order previously stood.
  List<ProjPoint> _v1Ordered(
    List<ProjPoint> touches,
    ConicMatrix a,
    ProjPoint pole,
  ) {
    final c = a.poleOf(ProjLine.infinity);
    final d0 = _leftness(c, pole, touches[0]);
    final d1 = _leftness(c, pole, touches[1]);
    if (d0 == null || d1 == null) {
      return touches;
    }
    if (d1 > d0) {
      return [touches[1], touches[0]];
    }
    return touches;
  }

  /// `det[c, p, t] / (w_c·w_p·w_t)` on the real parts — the projective
  /// leftness of [t] against the directed line [c]→[p], equal to the
  /// chart cross product `cross(p − c, t − c)` exactly, so comparing two
  /// touches' values is V1's comparison and not merely V1's sign. Null
  /// when a row is not real within the projective tolerance or has
  /// `w.re == 0` (no finite chart point to speak of).
  static double? _leftness(ProjPoint c, ProjPoint p, ProjPoint t) {
    if (!c.isReal() || !p.isReal() || !t.isReal()) {
      return null;
    }
    if (c.w.re == 0 || p.w.re == 0 || t.w.re == 0) {
      return null;
    }
    final det =
        c.x.re * (p.y.re * t.w.re - p.w.re * t.y.re) -
        c.y.re * (p.x.re * t.w.re - p.w.re * t.x.re) +
        c.w.re * (p.x.re * t.y.re - p.y.re * t.x.re);
    return det / (c.w.re * p.w.re * t.w.re);
  }
}
