import 'dart:math' as math;

import '../math/circle_eq.dart';
import '../math/vec2.dart';
import 'complex.dart';
import 'proj_line.dart';
import 'proj_point.dart';
import 'tolerances.dart';

/// The circular point `I = [1 : i : 0]`.
///
/// Every real circle passes through [circularPointI] and [circularPointJ];
/// conversely a real conic through both has a circle's coefficient shape
/// (`xx = yy`, `xy = 0`). They are exchanged by complex conjugation and lie
/// on the line at infinity.
const ProjPoint circularPointI = ProjPoint(
  Complex.one,
  Complex.i,
  Complex.zero,
);

/// The circular point `J = [1 : −i : 0]`, conjugate of [circularPointI].
const ProjPoint circularPointJ = ProjPoint(
  Complex.one,
  Complex(0, -1),
  Complex.zero,
);

/// Whether [p] is one of the circular points I, J, within [eps].
///
/// Consumers use this to filter I and J out of *solver output* — two real
/// circles always meet in them ([intersectConicConic] returns them as two
/// of the four points), and they carry no branch information. The default
/// tolerance is [doubleRootEpsilon], not [projectiveEpsilon]: near-
/// concentric circles deliver I and J as doubled roots carrying ~1e-8
/// tilt, which a predicate-tight comparison would fail to recognize.
bool isCircularPoint(ProjPoint p, [double eps = doubleRootEpsilon]) =>
    p.closeTo(circularPointI, eps) || p.closeTo(circularPointJ, eps);

/// A conic of the complex projective plane, as the symmetric 3×3 matrix
///
/// ```
/// ⎡ xx  xy  xw ⎤
/// ⎢ xy  yy  yw ⎥
/// ⎣ xw  yw  ww ⎦
/// ```
///
/// whose zero set is `pᵀAp = 0`; in affine coefficients that is
/// `xx·x² + 2xy·xy + yy·y² + 2xw·x + 2yw·y + ww = 0`.
///
/// Conventions follow [ProjPoint]/[ProjLine]:
/// - Matrices differing by a nonzero complex scalar are the same conic —
///   compare with [closeTo]; `==` is exact component equality.
/// - The zero matrix is no conic. Predicates return false for it, [rank]
///   returns 0, and operations stay total, letting degenerate values
///   propagate rather than throwing.
/// - Every operation is bilinear/holomorphic in the entries — no
///   conjugation anywhere (analytic continuation needs holomorphy).
class ConicMatrix {
  const ConicMatrix(this.xx, this.xy, this.yy, this.xw, this.yw, this.ww);

  /// The conic with the classical real affine coefficients of
  /// `a·x² + b·xy + c·y² + d·x + e·y + f = 0`.
  ConicMatrix.coefficients(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
  ) : this(
        Complex(a),
        Complex(b / 2),
        Complex(c),
        Complex(d / 2),
        Complex(e / 2),
        Complex(f),
      );

  /// Lifts the circle `(x−cx)² + (y−cy)² = r²` to its conic matrix
  /// (unit quadratic part: `xx = yy = 1`).
  ConicMatrix.lift(CircleEq circle)
    : this(
        Complex.one,
        Complex.zero,
        Complex.one,
        Complex(-circle.center.x),
        Complex(-circle.center.y),
        Complex(
          circle.center.x * circle.center.x +
              circle.center.y * circle.center.y -
              circle.radius * circle.radius,
        ),
      );

  /// The degenerate conic `ghᵀ + hgᵀ` whose zero set is the two lines [g]
  /// and [h] — rank 2 when they are distinct, rank 1 when `g = h` (a double
  /// line).
  ConicMatrix.linePair(ProjLine g, ProjLine h)
    : this(
        (g.a * h.a).scale(2),
        g.a * h.b + g.b * h.a,
        (g.b * h.b).scale(2),
        g.a * h.c + g.c * h.a,
        g.b * h.c + g.c * h.b,
        (g.c * h.c).scale(2),
      );

  /// The unique conic through five points, or null when they do not
  /// determine one (linear system rank < 5: repeated points, four or more
  /// collinear points, …).
  ///
  /// Each point contributes the row `[x², xy, y², xw, yw, w²]` of a 5×6
  /// homogeneous linear system in the affine coefficients; the conic is its
  /// one-dimensional null space. Points are chart-normalized first so the
  /// pivot tolerance is meaningful, and elimination pivots by magnitude.
  static ConicMatrix? throughFivePoints(List<ProjPoint> points) {
    assert(points.length == 5, 'a conic is determined by five points');
    final m = <List<Complex>>[];
    for (final p in points) {
      if (p.isZero) return null;
      final n = p.normalized;
      m.add([n.x * n.x, n.x * n.y, n.y * n.y, n.x * n.w, n.y * n.w, n.w * n.w]);
    }
    // Gauss–Jordan with partial pivoting. Rows have max magnitude 1 (the
    // chart-normalized coordinate squared), so the pivot cutoff is relative.
    const pivotEps2 = 1e-20;
    final pivotCols = <int>[];
    var row = 0;
    for (var col = 0; col < 6 && row < 5; col++) {
      var best = row;
      for (var r = row + 1; r < 5; r++) {
        if (m[r][col].abs2 > m[best][col].abs2) best = r;
      }
      if (m[best][col].abs2 <= pivotEps2) continue;
      final tmp = m[row];
      m[row] = m[best];
      m[best] = tmp;
      for (var r = 0; r < 5; r++) {
        if (r == row) continue;
        final factor = m[r][col] / m[row][col];
        for (var c = col; c < 6; c++) {
          m[r][c] = m[r][c] - factor * m[row][c];
        }
      }
      pivotCols.add(col);
      row++;
    }
    if (row < 5) return null;
    final free = ({0, 1, 2, 3, 4, 5}..removeAll(pivotCols)).single;
    final sol = List<Complex>.filled(6, Complex.zero);
    sol[free] = Complex.one;
    for (var r = 0; r < 5; r++) {
      final pc = pivotCols[r];
      sol[pc] = -m[r][free] / m[r][pc];
    }
    return ConicMatrix(
      sol[0],
      sol[1].scale(0.5),
      sol[2],
      sol[3].scale(0.5),
      sol[4].scale(0.5),
      sol[5],
    );
  }

  final Complex xx;
  final Complex xy;
  final Complex yy;
  final Complex xw;
  final Complex yw;
  final Complex ww;

  /// Squared Frobenius norm of the full 3×3 matrix (off-diagonal entries
  /// counted twice). Representation-level, not projective — use it to build
  /// relative tolerances.
  double get norm2 =>
      xx.abs2 + yy.abs2 + ww.abs2 + 2 * (xy.abs2 + xw.abs2 + yw.abs2);

  /// Whether this is the zero matrix (no conic at all).
  bool get isZero => norm2 == 0;

  /// The same conic with every entry multiplied by [k] — the projective
  /// identity when `k ≠ 0`.
  ConicMatrix scaledBy(Complex k) =>
      ConicMatrix(xx * k, xy * k, yy * k, xw * k, yw * k, ww * k);

  /// Chart normalization: divides by the largest-magnitude entry, so that
  /// entry becomes exactly 1 and the others have magnitude ≤ 1. Removes
  /// both scale and phase (which is what makes [isReal] scale-invariant);
  /// identity on the zero matrix.
  ConicMatrix get normalized {
    var d = xx;
    for (final e in [xy, yy, xw, yw, ww]) {
      if (e.abs2 > d.abs2) d = e;
    }
    if (d.abs2 == 0) return this;
    return ConicMatrix(xx / d, xy / d, yy / d, xw / d, yw / d, ww / d);
  }

  /// The quadratic form `pᵀAp` — bilinear, zero exactly when [p] lies on
  /// the conic.
  Complex evaluate(ProjPoint p) =>
      xx * p.x * p.x +
      yy * p.y * p.y +
      ww * p.w * p.w +
      (xy * p.x * p.y + xw * p.x * p.w + yw * p.y * p.w).scale(2);

  /// The polar line `Ap` of [p] — for `p` on the conic, its tangent line
  /// there; for the center of a circle, the line at infinity.
  ProjLine polarLine(ProjPoint p) => ProjLine(
    xx * p.x + xy * p.y + xw * p.w,
    xy * p.x + yy * p.y + yw * p.w,
    xw * p.x + yw * p.y + ww * p.w,
  );

  /// The pole of [l] — the adjugate applied to the line, `adj(A)·l` —
  /// the point whose [polarLine] is [l] (up to scale) when the conic is
  /// nondegenerate. Division-free, so total: for a rank-2 conic the
  /// adjugate collapses to `p·pᵀ` on the singular point and the pole is a
  /// multiple of it (possibly the zero triple, e.g. ℓ∞ against a line
  /// pair whose singular point is at infinity); rank ≤ 1 gives the zero
  /// triple always.
  ///
  /// The pole of the line at infinity is the *center* of the conic —
  /// for a lifted circle, exactly its center.
  ProjPoint poleOf(ProjLine l) {
    final a11 = yy * ww - yw * yw;
    final a12 = yw * xw - xy * ww;
    final a13 = xy * yw - yy * xw;
    final a22 = xx * ww - xw * xw;
    final a23 = xy * xw - xx * yw;
    final a33 = xx * yy - xy * xy;
    return ProjPoint(
      a11 * l.a + a12 * l.b + a13 * l.c,
      a12 * l.a + a22 * l.b + a23 * l.c,
      a13 * l.a + a23 * l.b + a33 * l.c,
    );
  }

  /// Whether [p] lies on the conic, relatively:
  /// `|pᵀAp| ≤ eps·‖A‖_F·|p|²`. False when either side is zero.
  bool containsPoint(ProjPoint p, [double eps = projectiveEpsilon]) {
    final scale2 = norm2 * p.norm2 * p.norm2;
    if (scale2 == 0) return false;
    return evaluate(p).abs2 <= eps * eps * scale2;
  }

  /// Projective equality: whether the matrices are proportional up to
  /// [eps], measured relatively — every 2×2 minor of the two coefficient
  /// 6-vectors is small against `‖A‖·‖B‖` (by Lagrange's identity this is a
  /// sine-like measure, like [ProjPoint.closeTo]'s cross product). False
  /// when either matrix is zero.
  bool closeTo(ConicMatrix other, [double eps = projectiveEpsilon]) {
    final u = [xx, xy, yy, xw, yw, ww];
    final v = [other.xx, other.xy, other.yy, other.xw, other.yw, other.ww];
    var u2 = 0.0, v2 = 0.0;
    for (var i = 0; i < 6; i++) {
      u2 += u[i].abs2;
      v2 += v[i].abs2;
    }
    if (u2 == 0 || v2 == 0) return false;
    var r2 = 0.0;
    for (var i = 0; i < 6; i++) {
      for (var j = i + 1; j < 6; j++) {
        r2 += (u[i] * v[j] - u[j] * v[i]).abs2;
      }
    }
    return r2 <= eps * eps * u2 * v2;
  }

  /// Whether this conic is real up to a complex scalar: after [normalized]
  /// (which removes phase), every entry is real within [eps]. False for the
  /// zero matrix.
  bool isReal([double eps = projectiveEpsilon]) {
    if (isZero) return false;
    final n = normalized;
    return n.xx.isRealWithin(eps) &&
        n.xy.isRealWithin(eps) &&
        n.yy.isRealWithin(eps) &&
        n.xw.isRealWithin(eps) &&
        n.yw.isRealWithin(eps) &&
        n.ww.isRealWithin(eps);
  }

  /// The determinant of the matrix — zero exactly for degenerate conics
  /// (line pairs and double lines).
  Complex get det =>
      xx * (yy * ww - yw * yw) -
      xy * (xy * ww - yw * xw) +
      xw * (xy * yw - yy * xw);

  /// Numerical rank at a relative tolerance: 3 for a nondegenerate conic,
  /// 2 for a line pair, 1 for a double line, 0 for the zero matrix (and for
  /// non-finite entries).
  ///
  /// Both cutoffs are relative to the Frobenius norm: `|det| > eps·‖A‖³`
  /// reads rank 3, else `max|adj| > eps·‖A‖²` reads rank 2.
  int rank([double eps = projectiveEpsilon]) {
    if (!xx.isFinite ||
        !xy.isFinite ||
        !yy.isFinite ||
        !xw.isFinite ||
        !yw.isFinite ||
        !ww.isFinite) {
      return 0;
    }
    final f2 = norm2;
    if (f2 == 0) return 0;
    final f = math.sqrt(f2);
    if (det.abs > eps * f * f * f) return 3;
    final adjMax2 = [
      yy * ww - yw * yw,
      xw * yw - xy * ww,
      xy * yw - yy * xw,
      xx * ww - xw * xw,
      xy * xw - xx * yw,
      xx * yy - xy * xy,
    ].map((e) => e.abs2).reduce(math.max);
    if (adjMax2 > eps * eps * f2 * f2) return 2;
    return 1;
  }

  /// Whether the conic is degenerate (a line pair or double line) at [eps]:
  /// `rank < 3`. True for the zero matrix.
  bool isDegenerate([double eps = projectiveEpsilon]) => rank(eps) < 3;

  /// Projection to a center-and-radius circle — the rendering question.
  /// Returns the circle when this conic is real, has a circle's shape
  /// (`xx ≈ yy`, `xy ≈ 0`, relative at [eps] *to the quadratic block's
  /// own scale*) and a real non-negative squared radius; else null
  /// (non-circles, imaginary circles, degenerate line-conics).
  ///
  /// Judging the shape against the quadratic block — not the full matrix
  /// norm — matters: a circle far from the origin (or huge) has
  /// `xx ≪ xw` and would read "degenerate" under a whole-matrix relative
  /// check, yet it is exactly circle-shaped and V1's affine kernel held
  /// it as center + radius with no cutoff at all. Locus infinity tails
  /// drive constructions there deliberately. Degenerate line-conics are
  /// no risk: the Phase 109 circle constructors produce their vanishing
  /// quadratic entries *exactly*, so they fail the `quadScale == 0` test,
  /// not a tolerance.
  ///
  /// The center/radius arithmetic uses ratios of the raw entries (scale-
  /// and phase-free once the shape checks pass) rather than chart
  /// normalization, which costs an ulp: the circle constructors put `xx`
  /// at a product of unit `w`s, and raw ratios keep integer centers and
  /// radii bit-exact for them.
  CircleEq? toCircleEq([double eps = projectiveEpsilon]) {
    if (!isReal(eps)) return null;
    final quadScale = math.sqrt(math.max(xx.abs2, math.max(xy.abs2, yy.abs2)));
    if (quadScale == 0 ||
        (xx - yy).abs > eps * quadScale ||
        xy.abs > eps * quadScale) {
      return null;
    }
    // The checks leave |xx| within eps of quadScale, so dividing by xx is
    // safe; the ratios can still overflow for extreme entry spreads —
    // reject non-finite results rather than throwing in CircleEq.
    final cx = -(xw / xx).re;
    final cy = -(yw / xx).re;
    final f = (ww / xx).re;
    final r2 = cx * cx + cy * cy - f;
    if (!cx.isFinite || !cy.isFinite || !r2.isFinite) return null;
    final r2Scale = math.max(1.0, cx * cx + cy * cy + f.abs());
    if (r2 < -eps * r2Scale) return null;
    return CircleEq(Vec2(cx, cy), math.sqrt(math.max(0, r2)));
  }

  @override
  bool operator ==(Object other) =>
      other is ConicMatrix &&
      other.xx == xx &&
      other.xy == xy &&
      other.yy == yy &&
      other.xw == xw &&
      other.yw == yw &&
      other.ww == ww;

  @override
  int get hashCode => Object.hash(xx, xy, yy, xw, yw, ww);

  @override
  String toString() =>
      'ConicMatrix(xx: $xx, xy: $xy, yy: $yy, xw: $xw, yw: $yw, ww: $ww)';
}

/// The two intersection points of line [l] with conic [a] — always exactly
/// two, with multiplicity at tangency; complex (conjugate pair, null
/// projections) when the real picture misses. Total: zero/degenerate inputs
/// propagate zero triples rather than throwing, and a line lying entirely on
/// a degenerate conic returns two (arbitrary) spanning points of the line.
///
/// Canonical order (old-ordering compatibility, see PLAN §Migration):
/// - Both points real and finite: increasing parameter along the
///   representative's direction `(b, −a)` — exactly [ProjLine.lift] of a
///   V1 `LineEq` orders like V1 `intersectLineCircle`. Like V1, flipping
///   the representative's sign flips the order.
/// - Conjugate pair (real miss): the point whose chart parameter has
///   negative imaginary part comes first.
/// - Anything else keeps the solver's (deterministic) order.
///
/// The algorithm spans [l] by two points `p1 = l×e_i`, `p2 = l×e_j` (i, j
/// the axes other than l's largest coefficient, which keeps them
/// independent), then solves the homogeneous quadratic in `(α:β)` for
/// `x = α·p1 + β·p2`, roots extracted cancellation-free as `(q : qa)` and
/// `(qc : q)`.
List<ProjPoint> intersectLineConic(
  ProjLine l,
  ConicMatrix a, [
  double eps = projectiveEpsilon,
]) {
  final coeffs = [l.a, l.b, l.c];
  var k = 0;
  for (var t = 1; t < 3; t++) {
    if (coeffs[t].abs2 > coeffs[k].abs2) k = t;
  }
  // l × e_i for the two basis vectors other than axis k.
  ProjPoint spanPoint(int i) => switch (i) {
    0 => ProjPoint(Complex.zero, l.c, -l.b),
    1 => ProjPoint(-l.c, Complex.zero, l.a),
    _ => ProjPoint(l.b, -l.a, Complex.zero),
  };
  final p1 = spanPoint((k + 1) % 3);
  final p2 = spanPoint((k + 2) % 3);

  final ap2 = a.polarLine(p2);
  final qa = a.evaluate(p1);
  final qb = p1.incidence(ap2).scale(2);
  final qc = p2.incidence(ap2);

  final coeffScale = math.max(qa.abs, math.max(qb.abs, qc.abs));
  if (coeffScale == 0) {
    // The whole line lies on the (degenerate) conic; any two points span it.
    return _canonicallyOrdered(l, p1.normalized, p2.normalized, eps);
  }
  final s0 = (qb * qb - (qa * qc).scale(4)).sqrt;
  // Choose the sign that grows |qb + s| (avoids catastrophic cancellation).
  final s = (qb.re * s0.re + qb.im * s0.im) >= 0 ? s0 : -s0;
  final q = (qb + s).scale(-0.5);
  // Roots (α:β) = (q : qa) and (qc : q); x = α·p1 + β·p2.
  ProjPoint combine(Complex alpha, Complex beta) => ProjPoint(
    p1.x * alpha + p2.x * beta,
    p1.y * alpha + p2.y * beta,
    p1.w * alpha + p2.w * beta,
  );
  var x1 = combine(q, qa);
  var x2 = combine(qc, q);
  // q = qa = 0 (or q = qc = 0) collapses a root vector to ~0: the root is a
  // double root at p1 (resp. p2) — fall back to the span point itself.
  final spanScale = math.max(p1.norm2, p2.norm2) * coeffScale * coeffScale;
  if (x1.norm2 <= 1e-24 * spanScale) x1 = p1;
  if (x2.norm2 <= 1e-24 * spanScale) x2 = p2;
  return _canonicallyOrdered(l, x1.normalized, x2.normalized, eps);
}

List<ProjPoint> _canonicallyOrdered(
  ProjLine l,
  ProjPoint p1,
  ProjPoint p2,
  double eps,
) {
  // Direction of the given representative: (b, −a), matching V1
  // `LineEq.direction` for real coefficients; representatives with a
  // negligible real part fall back to the imaginary parts.
  final reNorm = l.a.re * l.a.re + l.b.re * l.b.re;
  final imNorm = l.a.im * l.a.im + l.b.im * l.b.im;
  final double dx, dy;
  if (reNorm >= imNorm) {
    dx = l.b.re;
    dy = -l.a.re;
  } else {
    dx = l.b.im;
    dy = -l.a.im;
  }
  if (dx == 0 && dy == 0) return [p1, p2];
  final v1 = p1.toVec2(eps);
  final v2 = p2.toVec2(eps);
  if (v1 != null && v2 != null) {
    if (v2.x * dx + v2.y * dy < v1.x * dx + v1.y * dy) return [p2, p1];
    return [p1, p2];
  }
  final s1 = _chartParameter(p1, dx, dy);
  final s2 = _chartParameter(p2, dx, dy);
  if (s1 != null && s2 != null && s2.im < s1.im) return [p2, p1];
  return [p1, p2];
}

/// The (complex) parameter of [p] along the affine direction `(dx, dy)`, or
/// null when the point is at infinity or non-finite.
Complex? _chartParameter(ProjPoint p, double dx, double dy) {
  if (p.w.abs2 == 0) return null;
  final s = (p.x.scale(dx) + p.y.scale(dy)) / p.w;
  return s.isFinite ? s : null;
}
