// Phase 105: production conic∩conic on the proper projective types,
// implementing the stability recipe established by the Phase 102 pencil
// spike (docs/STATUS.md session 101) plus the translation balancing the
// spike identified as its known gap.
//
// The algorithm (Richter-Gebert, *Perspectives on Projective Geometry*
// ch. 11): the pencil λ ↦ A + λB of two conics contains (generically) three
// degenerate members, at the roots of the cubic det(A + λB) = 0. A
// degenerate conic is a line pair C = ghᵀ + hgᵀ; each line meets a conic in
// exactly two points, so splitting one degenerate member and intersecting
// its lines with either input conic yields the four intersection points.
//
// Stability recipe (validated by `benchmark/pencil_stress.dart` and the
// glados suite; kernel cutoffs live in `tolerances.dart`):
// 1. Balance coordinates: conjugate by the translation taking the
//    configuration centroid (the mean of the conics' finite real centers,
//    i.e. their poles of the line at infinity) to the origin — without it,
//    small configurations far from the origin lose digits quadratically in
//    the offset. Then conjugate by S = diag(σ, σ, 1), σ estimated from the
//    entry magnitudes of both matrices, so the quadratic / linear / constant
//    blocks are commensurate (Frobenius normalization alone cannot fix that
//    inhomogeneity — 10⁶-scale circles collapse without it). Then normalize
//    both matrices to unit Frobenius norm.
// 2. Solve the cubic per `cubic.dart` (Cardano, larger resolvent root, one
//    Newton polish per root, degree drops).
// 3. Root *clusters* are where naive root choice dies (near-identical
//    conics → near-triple root, error ~∛machine-eps contaminates the
//    member). So the candidate list is the three Cardano roots PLUS the
//    cluster centers that are well-conditioned exactly where clusters form:
//    the triple-root center −c2/(3c3) and the two roots of the derivative
//    (≈ double roots). Among candidates whose member is genuinely
//    degenerate (|det| ≤ degenerateMemberEpsilon at unit Frobenius), pick
//    the best score = rank2Signature / (sqrt|det| + 1e-16): a member is
//    only as good as its degeneracy is *accurate*, and |det| at the
//    computed root measures exactly that, while the signature factor keeps
//    rank-1 members (ill-posed split) from winning on their exact-zero det.
//    A degenerate *input* is itself a pencil member (λ = 0 / λ = ∞).
// 4. Split via the adjugate: adj(ghᵀ+hgᵀ) = −(g×h)(g×h)ᵀ, so p = the lines'
//    common point comes from the largest adjugate diagonal, then C + M_p
//    has rank 1 and factors as 2hgᵀ; rank ≤ 1 members are a double line
//    (the largest matrix row).
// 5. Intersect the two lines with whichever *input* conic has the larger
//    |det| (better conditioned than the degenerate member), via
//    `intersectLineConic`.
// 6. Polish each point with one joint Newton step onto both conics (the
//    minimal-norm correction along the two gradients), skipped near
//    tangency where the gradients are dependent. Un-balance the points
//    last, and put them in canonical order.

import 'dart:math' as math;

import '../math/vec2.dart';
import 'complex.dart';
import 'conic_matrix.dart';
import 'cubic.dart';
import 'proj_line.dart';
import 'proj_point.dart';
import 'tolerances.dart';

/// The four intersection points of conics [a0] and [b0] — always four, with
/// multiplicity (a tangency doubles its point; two circles always include
/// the circular points I and J); complex points appear when the real
/// picture misses. Total: zero inputs and conics projectively equal within
/// [coincidentConicEpsilon] (no discrete intersection) return the empty
/// list, and pencils degenerate beyond repair propagate zero triples rather
/// than throwing.
///
/// Canonical order (old-ordering compatibility, see PLAN §Migration; [eps]
/// is the classification tolerance):
/// - Real finite points first. When both conics have real finite distinct
///   centers (poles of the line at infinity), points order like V1
///   `intersectCircleCircle`: the point to the left of the directed center
///   line a→b first — swapping the arguments reverses the pair. Without a
///   usable center direction, ascending affine (x, y).
/// - Then real points at infinity, by their normalized coordinates.
/// - Then non-real points, by ascending sign-canonical imaginary measure
///   (the largest pairwise Hermitian form Im(x̄y) / Im(x̄w) / Im(ȳw), scaled
///   by the norm — invariant under complex rescaling), so conjugate mates
///   land negative-first: for two circles the trailing pair is
///   J = [1 : −i : 0] then I = [1 : i : 0]. Ties fall back to lexicographic
///   comparison of the normalized coordinates, then to solver order (which
///   keeps a doubled point's copies adjacent).
List<ProjPoint> intersectConicConic(
  ConicMatrix a0,
  ConicMatrix b0, [
  double eps = projectiveEpsilon,
]) {
  if (a0.isZero || b0.isZero) return const [];
  if (a0.closeTo(b0, coincidentConicEpsilon)) return const [];

  // 1. Balance: centroid → origin, diag(σ, σ, 1), unit Frobenius.
  final t = _translationEstimate(a0, b0, eps);
  final at = _translated(a0, t.x, t.y);
  final bt = _translated(b0, t.x, t.y);
  final sigma = _balanceScale(at, bt);
  final a = _frobNormalized(_scaled(at, sigma));
  final b = _frobNormalized(_scaled(bt, sigma));

  // 2. det(a + λb) is cubic in λ; its coefficients interpolate from the
  // determinants at λ ∈ {0, 1, −1, ∞}, all O(1) at unit Frobenius.
  final c0 = a.det;
  final c3 = b.det;
  final dPlus = _member(a, Complex.one, b).det;
  final dMinus = _member(a, const Complex(-1), b).det;
  final c1 = (dPlus - dMinus).scale(0.5) - c3;
  final c2 = (dPlus + dMinus).scale(0.5) - c0;
  final coeffScale = math.max(
    math.max(c3.abs, c2.abs),
    math.max(c1.abs, c0.abs),
  );

  // 3. Candidate roots and member choice.
  final lambdas = [
    ...solveCubic(c3, c2, c1, c0),
    if (c3.abs > polynomialDegreeDropEpsilon * coeffScale)
      (-c2 / c3).scale(1 / 3),
    ...solveQuadratic(c3.scale(3), c2.scale(2), c1, coeffScale),
  ];
  ConicMatrix? best;
  var bestScore = -1.0;
  ConicMatrix? bestUnfiltered;
  var bestUnfilteredSig = -1.0;
  void consider(ConicMatrix m) {
    final n = _frobNormalized(m);
    final sig = _rank2Signature(n);
    final det = n.det.abs;
    if (det <= degenerateMemberEpsilon) {
      final score = sig / (math.sqrt(det) + 1e-16);
      if (score > bestScore) {
        bestScore = score;
        best = n;
      }
    }
    if (sig > bestUnfilteredSig) {
      bestUnfilteredSig = sig;
      bestUnfiltered = n;
    }
  }

  for (final lambda in lambdas) {
    consider(_member(a, lambda, b));
  }
  if (c0.abs <= degenerateInputEpsilon) consider(a);
  if (c3.abs <= degenerateInputEpsilon) consider(b);
  final member = best ?? bestUnfiltered;
  if (member == null) return const [];

  // 4–6. Split, intersect with the better-conditioned input, polish,
  // un-balance, order.
  final (g, h) = _splitDegenerateConic(member);
  final carrier = c0.abs >= c3.abs ? a : b;
  final points = [
    for (final x in intersectLineConic(g, carrier, eps)) _polish(x, a, b),
    for (final x in intersectLineConic(h, carrier, eps)) _polish(x, a, b),
  ];
  return _canonicalOrder(
    [for (final p in points) _unbalance(p, sigma, t)],
    a0,
    b0,
    eps,
  );
}

// ---------------------------------------------------------------------------
// Matrix helpers. The adjugate of a symmetric matrix is symmetric, so it is
// itself representable as a ConicMatrix.
// ---------------------------------------------------------------------------

ConicMatrix _adjugate(ConicMatrix m) => ConicMatrix(
      m.yy * m.ww - m.yw * m.yw,
      m.xw * m.yw - m.xy * m.ww,
      m.xx * m.ww - m.xw * m.xw,
      m.xy * m.yw - m.yy * m.xw,
      m.xy * m.xw - m.xx * m.yw,
      m.xx * m.yy - m.xy * m.xy,
    );

/// The pencil member `a + λ·b`.
ConicMatrix _member(ConicMatrix a, Complex lambda, ConicMatrix b) =>
    ConicMatrix(
      a.xx + lambda * b.xx,
      a.xy + lambda * b.xy,
      a.yy + lambda * b.yy,
      a.xw + lambda * b.xw,
      a.yw + lambda * b.yw,
      a.ww + lambda * b.ww,
    );

/// [m] scaled to unit Frobenius norm (identity on zero / non-finite input).
ConicMatrix _frobNormalized(ConicMatrix m) {
  final f = math.sqrt(m.norm2);
  if (f == 0 || !f.isFinite) return m;
  return m.scaledBy(Complex(1 / f));
}

/// How strongly [m] (assumed unit Frobenius) reads as rank 2 rather than
/// rank ≤ 1: the largest |diag(adjugate)| entry. Zero for rank ≤ 1, where
/// the line-pair split through the adjugate is ill-posed.
double _rank2Signature(ConicMatrix m) {
  final adj = _adjugate(m);
  return math.max(adj.xx.abs, math.max(adj.yy.abs, adj.ww.abs));
}

// ---------------------------------------------------------------------------
// Coordinate balancing.
// ---------------------------------------------------------------------------

/// The mean of the two conics' finite real centers (pole of the line at
/// infinity, read from the adjugate) — zero when neither conic has one.
/// Purely a conditioning choice: any real translation is exact geometry.
Vec2 _translationEstimate(ConicMatrix a, ConicMatrix b, double eps) {
  final centers = [
    _realCenter(a, eps),
    _realCenter(b, eps),
  ].whereType<Vec2>().toList();
  if (centers.isEmpty) return Vec2.zero;
  var sx = 0.0, sy = 0.0;
  for (final c in centers) {
    sx += c.x;
    sy += c.y;
  }
  final t = Vec2(sx / centers.length, sy / centers.length);
  // A bogus far pole must not fling the configuration away instead.
  if (!t.x.isFinite || !t.y.isFinite || t.norm > 1e12) return Vec2.zero;
  return t;
}

/// The conic's center — its pole of the line at infinity, the third column
/// of the adjugate — projected to the real affine chart; null for parabolas
/// (pole at infinity), non-real conics, and degenerate values.
Vec2? _realCenter(ConicMatrix m, double eps) {
  final adj = _adjugate(_frobNormalized(m));
  return ProjPoint(adj.xw, adj.yw, adj.ww).toVec2(eps);
}

/// `TᵀMT` for the translation `T` taking the origin to `(tx, ty)` — the
/// conic in coordinates whose origin sits at `(tx, ty)`.
ConicMatrix _translated(ConicMatrix m, double tx, double ty) {
  final xw = m.xx.scale(tx) + m.xy.scale(ty) + m.xw;
  final yw = m.xy.scale(tx) + m.yy.scale(ty) + m.yw;
  final ww = (xw + m.xw).scale(tx) + (yw + m.yw).scale(ty) + m.ww;
  return ConicMatrix(m.xx, m.xy, m.yy, xw, yw, ww);
}

/// Estimates σ so that conjugating by `S = diag(σ, σ, 1)` makes the
/// quadratic, linear, and constant blocks of both conics commensurate:
/// σ ≈ max(linear/quadratic, sqrt(constant/quadratic)) over both matrices,
/// clamped to [1e-12, 1e12] (degenerate estimates fall back to 1).
double _balanceScale(ConicMatrix a, ConicMatrix b) {
  var q = 0.0, l = 0.0, c = 0.0;
  for (final m in [a, b]) {
    q = math.max(q, math.max(m.xx.abs, math.max(m.xy.abs, m.yy.abs)));
    l = math.max(l, math.max(m.xw.abs, m.yw.abs));
    c = math.max(c, m.ww.abs);
  }
  if (q == 0) return 1;
  final sigma = math.max(l / q, math.sqrt(c / q));
  if (!sigma.isFinite || sigma < 1e-12) return 1;
  return math.min(sigma, 1e12);
}

/// `SᵀMS` for `S = diag(σ, σ, 1)`.
ConicMatrix _scaled(ConicMatrix m, double sigma) {
  final s2 = sigma * sigma;
  return ConicMatrix(
    m.xx.scale(s2),
    m.xy.scale(s2),
    m.yy.scale(s2),
    m.xw.scale(sigma),
    m.yw.scale(sigma),
    m.ww,
  );
}

/// Maps a point from balanced coordinates back: `x = T·S·x̂`.
ProjPoint _unbalance(ProjPoint p, double sigma, Vec2 t) {
  final w = p.w;
  return ProjPoint(
    p.x.scale(sigma) + w.scale(t.x),
    p.y.scale(sigma) + w.scale(t.y),
    w,
  ).normalized;
}

// ---------------------------------------------------------------------------
// Degenerate conic split.
// ---------------------------------------------------------------------------

/// Splits a degenerate (rank ≤ 2) conic into its two lines `(g, h)`, with
/// `C ∝ ghᵀ + hgᵀ`. A rank-1 conic is a double line: `g = h`.
///
/// Rank 2: `adj(C) = −ppᵀ` up to scale, where `p = g×h` is the lines'
/// common point. Recover `p` from the largest adjugate diagonal
/// (β = sqrt(−adj_ii), p = adj column i / β), then `C + M_p = 2hgᵀ`
/// (rank 1; `M_p` is the cross-product matrix), whose rows/columns are the
/// lines.
(ProjLine, ProjLine) _splitDegenerateConic(ConicMatrix c0) {
  final c = _frobNormalized(c0);
  final adj = _adjugate(c);
  final diag = [adj.xx, adj.yy, adj.ww];
  var i = 0;
  for (var k = 1; k < 3; k++) {
    if (diag[k].abs2 > diag[i].abs2) i = k;
  }
  if (diag[i].abs <= rank1SplitEpsilon) {
    // Rank ≤ 1: double line — every nonzero row is proportional to it.
    final rows = [
      ProjLine(c.xx, c.xy, c.xw),
      ProjLine(c.xy, c.yy, c.yw),
      ProjLine(c.xw, c.yw, c.ww),
    ];
    var r = 0;
    for (var k = 1; k < 3; k++) {
      if (rows[k].norm2 > rows[r].norm2) r = k;
    }
    final g = rows[r].normalized;
    return (g, g);
  }
  final beta = (-diag[i]).sqrt;
  final columns = [
    [adj.xx, adj.xy, adj.xw],
    [adj.xy, adj.yy, adj.yw],
    [adj.xw, adj.yw, adj.ww],
  ];
  final p = [for (final e in columns[i]) e / beta];
  final d = [
    [c.xx, c.xy - p[2], c.xw + p[1]],
    [c.xy + p[2], c.yy, c.yw - p[0]],
    [c.xw - p[1], c.yw + p[0], c.ww],
  ];
  var br = 0, bs = 0;
  var bestAbs2 = -1.0;
  for (var r = 0; r < 3; r++) {
    for (var s = 0; s < 3; s++) {
      if (d[r][s].abs2 > bestAbs2) {
        bestAbs2 = d[r][s].abs2;
        br = r;
        bs = s;
      }
    }
  }
  final g = ProjLine(d[br][0], d[br][1], d[br][2]).normalized; // row ∝ gᵀ
  final h = ProjLine(d[0][bs], d[1][bs], d[2][bs]).normalized; // column ∝ h
  return (g, h);
}

// ---------------------------------------------------------------------------
// Joint Newton polish.
// ---------------------------------------------------------------------------

/// One Newton step moving [x0] onto both conics simultaneously: the
/// minimal-norm correction δ with `∇f_A·δ = −f_A`, `∇f_B·δ = −f_B`
/// (bilinear 2×2 normal equations along the two gradients). Skipped when
/// the gradients are nearly dependent (tangency) — the system is singular
/// there and the unpolished point is already the best available.
ProjPoint _polish(ProjPoint x0, ConicMatrix a, ConicMatrix b) {
  final x = x0.normalized;
  final fa = a.evaluate(x);
  final fb = b.evaluate(x);
  final ga = a.polarLine(x).scaledBy(const Complex(2)); // gradient of pᵀAp
  final gb = b.polarLine(x).scaledBy(const Complex(2));
  final m11 = _dotLines(ga, ga);
  final m12 = _dotLines(ga, gb);
  final m22 = _dotLines(gb, gb);
  final det = m11 * m22 - m12 * m12;
  final gradScale = (m11.abs + m22.abs) / 2;
  if (gradScale == 0 ||
      det.abs <= tangentPolishEpsilon * gradScale * gradScale) {
    return x;
  }
  final y1 = (-fa * m22 + fb * m12) / det;
  final y2 = (-fb * m11 + fa * m12) / det;
  return ProjPoint(
    x.x + ga.a * y1 + gb.a * y2,
    x.y + ga.b * y1 + gb.b * y2,
    x.w + ga.c * y1 + gb.c * y2,
  ).normalized;
}

/// Bilinear dot product of two coefficient triples (no conjugation —
/// holomorphy, as everywhere in this layer).
Complex _dotLines(ProjLine u, ProjLine v) => u.a * v.a + u.b * v.b + u.c * v.c;

// ---------------------------------------------------------------------------
// Canonical ordering.
// ---------------------------------------------------------------------------

List<ProjPoint> _canonicalOrder(
  List<ProjPoint> pts,
  ConicMatrix a,
  ConicMatrix b,
  double eps,
) {
  Vec2? direction;
  final ca = _realCenter(a, eps);
  final cb = _realCenter(b, eps);
  if (ca != null && cb != null) {
    final d = cb - ca;
    if (d.norm > 1e-12 * (1 + ca.norm + cb.norm)) direction = d;
  }
  final keys = [for (final p in pts) _OrderKey(p, direction, eps)];
  final order = List<int>.generate(pts.length, (i) => i);
  order.sort((i, j) {
    final c = keys[i].compareTo(keys[j]);
    return c != 0 ? c : i.compareTo(j);
  });
  return [for (final i in order) pts[i]];
}

class _OrderKey {
  factory _OrderKey(ProjPoint p, Vec2? direction, double eps) {
    final v = p.toVec2(eps);
    if (v != null) {
      // Real finite: V1 circle∩circle order — left of the directed center
      // line first, i.e. descending cross product against it.
      final primary = direction == null ? 0.0 : -direction.cross(v);
      return _OrderKey._(0, primary, [v.x, v.y]);
    }
    final n = p.normalized;
    final lex = [n.x.re, n.x.im, n.y.re, n.y.im, n.w.re, n.w.im];
    if (p.isReal(eps)) return _OrderKey._(1, 0, lex);
    // Non-real: the largest of the three pairwise Hermitian forms Im(x̄y),
    // Im(x̄w), Im(ȳw), scaled by the triple's norm. All three vanish exactly
    // when the triple is real up to a complex scalar, so a non-real point
    // has a significant one; the value is invariant under complex rescaling
    // and flips sign under conjugation, so conjugate mates order
    // negative-first by geometry, never by representation noise. (Hermitian
    // is fine here — this is classification, not kernel math.)
    final f1 = (p.x.conj * p.y).im;
    final f2 = (p.x.conj * p.w).im;
    final f3 = (p.y.conj * p.w).im;
    var f = f1;
    if (f2.abs() > f.abs()) f = f2;
    if (f3.abs() > f.abs()) f = f3;
    return _OrderKey._(2, f / p.norm2, lex);
  }

  const _OrderKey._(this.tier, this.primary, this.lex);

  final int tier;
  final double primary;
  final List<double> lex;

  int compareTo(_OrderKey other) {
    if (tier != other.tier) return tier.compareTo(other.tier);
    final c = primary.compareTo(other.primary);
    if (c != 0) return c;
    for (var i = 0; i < lex.length && i < other.lex.length; i++) {
      final d = lex[i].compareTo(other.lex[i]);
      if (d != 0) return d;
    }
    return 0;
  }
}
