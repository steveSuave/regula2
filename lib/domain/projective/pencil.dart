// Phase 102 SPIKE 2: conic∩conic via degenerate pencil members. PROTOTYPE.
//
// This file establishes the numerical recipe that Phase 105 productionizes
// against the Phase 103/104 types (`ProjPoint`, `ConicMatrix`). Until then it
// works on raw representations: length-3 `List<Complex>` homogeneous vectors
// and row-major 3×3 `List<List<Complex>>` matrices (symmetric for conics).
// Allocation style is deliberately naive — clarity over speed; the SoA hot
// loop only matters for tracing (Phase 113+), not static solves.
//
// The algorithm (Richter-Gebert, *Perspectives on Projective Geometry* ch. 11):
// the pencil λ ↦ A + λB of two conics contains (generically) three degenerate
// members, at the roots of the cubic det(A + λB) = 0. A degenerate conic is a
// line pair C = ghᵀ + hgᵀ; each line meets a conic in exactly two points, so
// splitting one degenerate member and intersecting its lines with either input
// conic yields the four intersection points.
//
// Stability recipe (recorded in STATUS session 100, validated by
// `benchmark/pencil_stress.dart` and the glados suite):
// 1. Balance coordinates with S = diag(σ, σ, 1), σ estimated from the entry
//    magnitudes of both matrices, so the quadratic / linear / constant blocks
//    are commensurate (Frobenius normalization alone cannot fix that
//    inhomogeneity — 10⁶-scale circles collapse without it). Then normalize
//    both matrices to unit Frobenius norm.
// 2. Solve the cubic by Cardano on the depressed form, choosing the larger
//    resolvent root; polish every root with one Newton step on the original
//    cubic; degree drop (degenerate B) falls back to the quadratic/linear.
// 3. Root *clusters* are where naive root choice dies (near-identical conics
//    → near-triple root, error ~∛machine-eps contaminates the member). So the
//    candidate list is the three Cardano roots PLUS the cluster centers that
//    are well-conditioned exactly where clusters form: the triple-root center
//    −c2/(3c3) and the two roots of the derivative 3c3λ² + 2c2λ + c1
//    (≈ double roots). Among candidates whose member is genuinely degenerate
//    (|det| ≤ 1e-8 at unit Frobenius), pick the strongest rank-2 signature:
//    the largest |diag(adjugate)| entry. (adj(ghᵀ+hgᵀ) = −(g×h)(g×h)ᵀ, so
//    this measures distance from rank ≤ 1, where the split is ill-posed.)
// 4. Split via the adjugate: p = the lines' common point from the largest
//    adjugate diagonal, then C + M_p has rank 1 and factors as 2hgᵀ.
// 5. Intersect the two lines with whichever *input* conic has the larger
//    |det| (better conditioned than the degenerate member).
// 6. Polish each intersection point with one joint Newton step onto both
//    conics (minimal-norm correction along the two gradients), skipped near
//    tangency where the gradients are dependent. Un-balance the points last.
//
// Known limitation (Phase 105 must address): balancing is a pure scaling; a
// *translation* component is still missing, so small circles very far from
// the origin lose the digits the coordinate offset eats. See the stress
// corpus's far-offset family.

import 'dart:math' as math;

import 'complex.dart';

/// A homogeneous coordinate vector (point or line), length 3.
typedef CVec3 = List<Complex>;

/// A 3×3 complex matrix, row-major; symmetric when it represents a conic.
typedef CMat3 = List<List<Complex>>;

// ---------------------------------------------------------------------------
// Small linear algebra over ℂ³. All products are bilinear (no conjugation):
// incidence and quadratic forms in projective geometry are bilinear, and
// keeping every map holomorphic is what makes analytic continuation work.
// ---------------------------------------------------------------------------

CVec3 crossVec(CVec3 u, CVec3 v) => [
      u[1] * v[2] - u[2] * v[1],
      u[2] * v[0] - u[0] * v[2],
      u[0] * v[1] - u[1] * v[0],
    ];

Complex dotVec(CVec3 u, CVec3 v) => u[0] * v[0] + u[1] * v[1] + u[2] * v[2];

CVec3 matVec(CMat3 m, CVec3 v) =>
    [dotVec(m[0], v), dotVec(m[1], v), dotVec(m[2], v)];

/// The quadratic form `vᵀ M v`.
Complex quadForm(CMat3 m, CVec3 v) => dotVec(v, matVec(m, v));

double vecNorm2(CVec3 v) => v[0].abs2 + v[1].abs2 + v[2].abs2;

/// Scales [v] so its largest component has magnitude 1 (identity on zero).
CVec3 normalizeVec(CVec3 v) {
  var best = 0;
  for (var i = 1; i < 3; i++) {
    if (v[i].abs2 > v[best].abs2) best = i;
  }
  if (v[best].abs2 == 0) return v;
  final s = 1 / v[best].abs;
  return [v[0].scale(s), v[1].scale(s), v[2].scale(s)];
}

Complex det3(CMat3 m) =>
    m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
    m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
    m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

CMat3 adjugate3(CMat3 m) => [
      [
        m[1][1] * m[2][2] - m[1][2] * m[2][1],
        -(m[0][1] * m[2][2] - m[0][2] * m[2][1]),
        m[0][1] * m[1][2] - m[0][2] * m[1][1],
      ],
      [
        -(m[1][0] * m[2][2] - m[1][2] * m[2][0]),
        m[0][0] * m[2][2] - m[0][2] * m[2][0],
        -(m[0][0] * m[1][2] - m[0][2] * m[1][0]),
      ],
      [
        m[1][0] * m[2][1] - m[1][1] * m[2][0],
        -(m[0][0] * m[2][1] - m[0][1] * m[2][0]),
        m[0][0] * m[1][1] - m[0][1] * m[1][0],
      ],
    ];

/// The pencil member `a + λ·b`.
CMat3 pencilMember(CMat3 a, Complex lambda, CMat3 b) => [
      for (var i = 0; i < 3; i++)
        [for (var j = 0; j < 3; j++) a[i][j] + lambda * b[i][j]],
    ];

/// Squared Frobenius norm.
double frobenius2(CMat3 m) {
  var sum = 0.0;
  for (final row in m) {
    for (final e in row) {
      sum += e.abs2;
    }
  }
  return sum;
}

/// [m] scaled to unit Frobenius norm (identity on the zero matrix).
CMat3 normalizeConic(CMat3 m) {
  final f = math.sqrt(frobenius2(m));
  if (f == 0) return m;
  final s = 1 / f;
  return [
    for (final row in m) [for (final e in row) e.scale(s)],
  ];
}

// ---------------------------------------------------------------------------
// Cubic solver.
// ---------------------------------------------------------------------------

/// All complex roots of `c3·λ³ + c2·λ² + c1·λ + c0 = 0`.
///
/// Degree drops (leading coefficients relatively ≈ 0) fall through to the
/// quadratic / linear cases, so the list has 3, 2, 1, or 0 entries. Cardano on
/// the depressed cubic, taking the larger-magnitude resolvent root to avoid
/// cancellation; every root gets one Newton polish step on the original
/// polynomial. Multiple roots are returned with multiplicity (at reduced
/// accuracy — a double root is only good to ~sqrt(machine eps)).
List<Complex> solveCubic(Complex c3, Complex c2, Complex c1, Complex c0) {
  final scale = math.max(
    math.max(c3.abs, c2.abs),
    math.max(c1.abs, c0.abs),
  );
  if (scale == 0) return const [];
  const dropEps = 1e-13;
  if (c3.abs <= dropEps * scale) {
    return _solveQuadratic(c2, c1, c0, scale);
  }

  final a2 = c2 / c3;
  final a1 = c1 / c3;
  final a0 = c0 / c3;
  // Depress: λ = t − a2/3 ⇒ t³ + pt + q.
  final p = a1 - (a2 * a2).scale(1 / 3);
  final q = (a2 * a2 * a2).scale(2 / 27) - (a2 * a1).scale(1 / 3) + a0;
  final hq = q.scale(0.5);
  final p3 = p.scale(1 / 3);
  final s = (hq * hq + p3 * p3 * p3).sqrt;
  final plus = -hq + s;
  final minus = -hq - s;
  final u3 = plus.abs2 >= minus.abs2 ? plus : minus;
  final shift = a2.scale(1 / 3);
  if (u3.abs2 == 0) {
    // p = q = 0: triple root at −a2/3.
    final r = -shift;
    return [r, r, r];
  }
  final u = _cbrt(u3);
  final roots = <Complex>[];
  var w = u;
  const omega = Complex(-0.5, 0.8660254037844386);
  for (var k = 0; k < 3; k++) {
    final root = w - p3 / w - shift;
    roots.add(_polishPolyRoot(root, c3, c2, c1, c0));
    w = w * omega;
  }
  return roots;
}

List<Complex> _solveQuadratic(Complex a, Complex b, Complex c, double scale) {
  const dropEps = 1e-13;
  if (a.abs <= dropEps * scale) {
    if (b.abs <= dropEps * scale) return const [];
    return [-c / b];
  }
  final s0 = (b * b - (a * c).scale(4)).sqrt;
  // Choose the sign that grows |b + s| (avoids catastrophic cancellation).
  final s = (b.re * s0.re + b.im * s0.im) >= 0 ? s0 : -s0;
  final q = (b + s).scale(-0.5);
  if (q.abs2 == 0) return [Complex.zero, Complex.zero];
  return [q / a, c / q];
}

Complex _cbrt(Complex z) {
  final m = z.abs;
  if (m == 0) return Complex.zero;
  return Complex.polar(math.exp(math.log(m) / 3), z.arg / 3);
}

Complex _polishPolyRoot(Complex x, Complex c3, Complex c2, Complex c1, Complex c0) {
  final f = ((c3 * x + c2) * x + c1) * x + c0;
  final fp = (c3.scale(3) * x + c2.scale(2)) * x + c1;
  if (fp.abs2 < 1e-30) return x;
  return x - f / fp;
}

// ---------------------------------------------------------------------------
// Degenerate conic split.
// ---------------------------------------------------------------------------

/// How strongly [c] (assumed unit Frobenius) reads as rank 2 rather than
/// rank ≤ 1: the largest |diag(adjugate)| entry. Zero for rank ≤ 1, where the
/// line-pair split through the adjugate is ill-posed.
double rank2Signature(CMat3 c) {
  final adj = adjugate3(c);
  var best = 0.0;
  for (var i = 0; i < 3; i++) {
    best = math.max(best, adj[i][i].abs);
  }
  return best;
}

/// Splits a degenerate (rank ≤ 2) conic into its two lines `(g, h)`, with
/// `C ∝ ghᵀ + hgᵀ`. A rank-1 conic is a double line: `g = h`.
///
/// Rank 2: `adj(C) = −ppᵀ` up to scale, where `p = g×h` is the lines' common
/// point. Recover `p` from the largest adjugate diagonal (β = sqrt(−adj_ii),
/// p = adj column i / β), then `C + M_p = 2hgᵀ` (rank 1; `M_p` is the
/// cross-product matrix), whose rows/columns are the lines.
(CVec3, CVec3) splitDegenerateConic(CMat3 c0) {
  final c = normalizeConic(c0);
  final adj = adjugate3(c);
  var i = 0;
  for (var k = 1; k < 3; k++) {
    if (adj[k][k].abs2 > adj[i][i].abs2) i = k;
  }
  const rank1Eps = 1e-10;
  if (adj[i][i].abs <= rank1Eps) {
    // Rank ≤ 1: double line — every nonzero row is proportional to it.
    var r = 0;
    for (var k = 1; k < 3; k++) {
      if (vecNorm2(c[k]) > vecNorm2(c[r])) r = k;
    }
    final g = normalizeVec(c[r]);
    return (g, g);
  }
  final beta = (-adj[i][i]).sqrt;
  final p = [adj[0][i] / beta, adj[1][i] / beta, adj[2][i] / beta];
  final d = [
    [c[0][0], c[0][1] - p[2], c[0][2] + p[1]],
    [c[1][0] + p[2], c[1][1], c[1][2] - p[0]],
    [c[2][0] - p[1], c[2][1] + p[0], c[2][2]],
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
  final g = normalizeVec(d[br]); // row ∝ gᵀ
  final h = normalizeVec([d[0][bs], d[1][bs], d[2][bs]]); // column ∝ h
  return (g, h);
}

// ---------------------------------------------------------------------------
// Line ∩ conic.
// ---------------------------------------------------------------------------

/// The two intersection points of line [l] with conic [a] (always two, with
/// multiplicity at tangency; complex when the real picture misses).
///
/// Spans [l] by two points `p1 = l×e_i`, `p2 = l×e_j` (i, j the axes other
/// than l's largest component, which keeps them independent), then solves the
/// homogeneous quadratic in (α:β) for `x = α·p1 + β·p2`, roots extracted
/// cancellation-free as (q : qa) and (qc : q).
List<CVec3> intersectLineConic(CVec3 l, CMat3 a) {
  var k = 0;
  for (var t = 1; t < 3; t++) {
    if (l[t].abs2 > l[k].abs2) k = t;
  }
  final i = (k + 1) % 3;
  final j = (k + 2) % 3;
  final ei = [Complex.zero, Complex.zero, Complex.zero]..[i] = Complex.one;
  final ej = [Complex.zero, Complex.zero, Complex.zero]..[j] = Complex.one;
  final p1 = crossVec(l, ei);
  final p2 = crossVec(l, ej);

  final ap2 = matVec(a, p2);
  final qa = quadForm(a, p1);
  final qb = dotVec(p1, ap2).scale(2);
  final qc = dotVec(p2, ap2);

  final coeffScale = math.max(qa.abs, math.max(qb.abs, qc.abs));
  if (coeffScale == 0) {
    // The whole line lies on the (degenerate) conic; any two points span it.
    return [normalizeVec(p1), normalizeVec(p2)];
  }
  final s0 = (qb * qb - (qa * qc).scale(4)).sqrt;
  final s = (qb.re * s0.re + qb.im * s0.im) >= 0 ? s0 : -s0;
  final q = (qb + s).scale(-0.5);
  // Roots (α:β) = (q : qa) and (qc : q); x = α p1 + β p2.
  var x1 = [
    for (var t = 0; t < 3; t++) p1[t] * q + p2[t] * qa,
  ];
  var x2 = [
    for (var t = 0; t < 3; t++) p1[t] * qc + p2[t] * q,
  ];
  // q = qa = 0 (or q = qc = 0) collapses a root vector to ~0: the root is a
  // double root at p1 (resp. p2) — fall back to the span point itself.
  final spanScale = math.max(vecNorm2(p1), vecNorm2(p2)) * coeffScale * coeffScale;
  if (vecNorm2(x1) <= 1e-24 * spanScale) x1 = p1;
  if (vecNorm2(x2) <= 1e-24 * spanScale) x2 = p2;
  return [normalizeVec(x1), normalizeVec(x2)];
}

// ---------------------------------------------------------------------------
// Joint Newton polish.
// ---------------------------------------------------------------------------

/// One Newton step moving [x] onto both conics simultaneously: the
/// minimal-norm correction δ with `∇f_A·δ = −f_A`, `∇f_B·δ = −f_B` (bilinear
/// 2×2 normal equations along the two gradients). Skipped when the gradients
/// are nearly dependent (tangency) — the system is singular there and the
/// unpolished point is already the best available.
CVec3 polishIntersectionPoint(CVec3 x0, CMat3 a, CMat3 b) {
  final x = normalizeVec(x0);
  final fa = quadForm(a, x);
  final fb = quadForm(b, x);
  final ga = matVec(a, x).map((e) => e.scale(2)).toList();
  final gb = matVec(b, x).map((e) => e.scale(2)).toList();
  final m11 = dotVec(ga, ga);
  final m12 = dotVec(ga, gb);
  final m22 = dotVec(gb, gb);
  final det = m11 * m22 - m12 * m12;
  final gradScale = (m11.abs + m22.abs) / 2;
  if (det.abs <= 1e-12 * gradScale * gradScale || gradScale == 0) return x;
  final y1 = (-fa * m22 + fb * m12) / det;
  final y2 = (-fb * m11 + fa * m12) / det;
  return normalizeVec([
    for (var t = 0; t < 3; t++) x[t] + ga[t] * y1 + gb[t] * y2,
  ]);
}

// ---------------------------------------------------------------------------
// Coordinate balancing.
// ---------------------------------------------------------------------------

/// Estimates σ so that conjugating by `S = diag(σ, σ, 1)` makes the quadratic,
/// linear, and constant blocks of both conics commensurate: σ ≈
/// max(linear/quadratic, sqrt(constant/quadratic)) over both matrices.
double _balanceScale(CMat3 a, CMat3 b) {
  var q = 0.0, l = 0.0, c = 0.0;
  for (final m in [a, b]) {
    q = math.max(q, math.max(m[0][0].abs, math.max(m[0][1].abs, m[1][1].abs)));
    l = math.max(l, math.max(m[0][2].abs, m[1][2].abs));
    c = math.max(c, m[2][2].abs);
  }
  if (q == 0) return 1;
  final sigma = math.max(l / q, math.sqrt(c / q));
  if (!sigma.isFinite || sigma < 1e-12) return 1;
  return math.min(sigma, 1e12);
}

/// `SᵀMS` for `S = diag(σ, σ, 1)`.
CMat3 _conjugateByScale(CMat3 m, double sigma) {
  final s2 = sigma * sigma;
  return [
    [m[0][0].scale(s2), m[0][1].scale(s2), m[0][2].scale(sigma)],
    [m[1][0].scale(s2), m[1][1].scale(s2), m[1][2].scale(sigma)],
    [m[2][0].scale(sigma), m[2][1].scale(sigma), m[2][2]],
  ];
}

// ---------------------------------------------------------------------------
// The headline: conic ∩ conic.
// ---------------------------------------------------------------------------

/// The four intersection points of conics [a0] and [b0] (with multiplicity;
/// complex points appear as members of conjugate pairs when the inputs are
/// real). Returns fewer than four only when the pencil is entirely degenerate
/// (e.g. identical conics).
List<CVec3> intersectConicsPencil(CMat3 a0, CMat3 b0) {
  final sigma = _balanceScale(a0, b0);
  final a = normalizeConic(_conjugateByScale(a0, sigma));
  final b = normalizeConic(_conjugateByScale(b0, sigma));

  // det(a + λb) expanded by columns: c1 sums single-column substitutions,
  // c2 double substitutions.
  CVec3 col(CMat3 m, int j) => [m[0][j], m[1][j], m[2][j]];
  Complex detCols(CVec3 u, CVec3 v, CVec3 w) => det3([
        [u[0], v[0], w[0]],
        [u[1], v[1], w[1]],
        [u[2], v[2], w[2]],
      ]);
  final a0c = col(a, 0), a1c = col(a, 1), a2c = col(a, 2);
  final b0c = col(b, 0), b1c = col(b, 1), b2c = col(b, 2);
  final c0 = det3(a);
  final c3 = det3(b);
  final c1 = detCols(b0c, a1c, a2c) +
      detCols(a0c, b1c, a2c) +
      detCols(a0c, a1c, b2c);
  final c2 = detCols(b0c, b1c, a2c) +
      detCols(b0c, a1c, b2c) +
      detCols(a0c, b1c, b2c);

  final coeffScale = math.max(
    math.max(c3.abs, c2.abs),
    math.max(c1.abs, c0.abs),
  );
  final lambdas = [
    ...solveCubic(c3, c2, c1, c0),
    // Cluster-robust candidates (see the recipe header): the triple-root
    // center and the derivative's roots (≈ double roots). Cheap, and the
    // |det| filter below discards them whenever they are not actually
    // pencil roots.
    if (c3.abs > 1e-13 * coeffScale) (-c2 / c3).scale(1 / 3),
    ..._solveQuadratic(
      c3.scale(3),
      c2.scale(2),
      c1,
      coeffScale,
    ),
  ];

  // Pick the degenerate member by score = signature / sqrt(|det|): a member
  // is only as good as its degeneracy is *accurate*, and |det| at the
  // computed root measures exactly that (a simple well-separated root lands
  // at det ~ machine eps; a root from a cluster carries the cluster's error).
  // The signature factor keeps rank-1 members (ill-posed split) from winning
  // on their exact-zero det. A degenerate *input* is itself a pencil member
  // (λ = 0 / λ = ∞).
  const detEps = 1e-8;
  CMat3? best;
  var bestScore = -1.0;
  CMat3? bestUnfiltered;
  var bestUnfilteredSig = -1.0;
  void consider(CMat3 m) {
    final n = normalizeConic(m);
    final sig = rank2Signature(n);
    final det = det3(n).abs;
    if (det <= detEps) {
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
    consider(pencilMember(a, lambda, b));
  }
  const degenerateEps = 1e-10;
  if (c0.abs <= degenerateEps) consider(a);
  if (c3.abs <= degenerateEps) consider(b);
  final member = best ?? bestUnfiltered;
  if (member == null) return const [];

  final (g, h) = splitDegenerateConic(member);
  // Intersect with the better-conditioned input conic.
  final carrier = c0.abs >= c3.abs ? a : b;
  final balanced = [
    for (final x in intersectLineConic(g, carrier))
      polishIntersectionPoint(x, a, b),
    for (final x in intersectLineConic(h, carrier))
      polishIntersectionPoint(x, a, b),
  ];
  // Un-balance: x = S·x̂ for S = diag(σ, σ, 1).
  return [
    for (final p in balanced)
      normalizeVec([p[0].scale(sigma), p[1].scale(sigma), p[2]]),
  ];
}
