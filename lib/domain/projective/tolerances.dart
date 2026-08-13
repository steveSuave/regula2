/// Tolerance policy for the projective layer (consolidated in Phase 105).
///
/// One policy, two kinds of constants — do not mix them up:
///
/// **The predicate tolerance** — [projectiveEpsilon], the default `eps` of
/// every user-facing predicate in this layer (`isReal`, `isFinite`,
/// `closeTo`, incidence, containment, `rank`) and of the classification
/// steps built on them (projection to the affine chart, canonical ordering
/// of intersection points). All of these predicates are *relative*:
/// residuals are measured against the operands' homogeneous norms, so the
/// value bounds a dimensionless sine-like measure, never a world-space
/// distance. Callers with unusual needs pass a different `eps` per call;
/// nothing in the layer may bake in an absolute (world-unit) cutoff.
///
/// **Kernel cutoffs** — every other constant here. These are internal knobs
/// of the numerical algorithms (degree-drop detection, degenerate-member
/// filtering, split guards), all defined on *balanced, unit-Frobenius
/// normalized* data, where they are properties of double-precision
/// arithmetic rather than geometry tolerances. They are not parameters of
/// any public signature and are collected here only so the layer's numeric
/// policy is auditable in one place. Their values were established
/// empirically by the Phase 102 stress corpus (see docs/STATUS.md session
/// 101 and `benchmark/pencil_stress.dart`); don't tune them without
/// re-running it.
library;

/// Default relative tolerance for projective predicates (realness,
/// finiteness, incidence, projective equality). Matches the affine layer's
/// `defaultEpsilon` order of magnitude.
const double projectiveEpsilon = 1e-9;

/// Kernel cutoff: a polynomial's leading coefficient is treated as vanished
/// — dropping the degree — when it is below this fraction of the largest
/// coefficient (`cubic.dart`).
const double polynomialDegreeDropEpsilon = 1e-13;

/// Kernel cutoff: a pencil member (unit Frobenius) counts as genuinely
/// degenerate when `|det| ≤` this. Members above it carry too much root
/// error to split (`conic_intersection.dart`).
const double degenerateMemberEpsilon = 1e-8;

/// Kernel cutoff: an *input* conic counts as itself a degenerate member of
/// the pencil (λ = 0 / λ = ∞) when its unit-Frobenius `|det| ≤` this
/// (`conic_intersection.dart`).
const double degenerateInputEpsilon = 1e-10;

/// Kernel cutoff: the degenerate-conic split falls back to the double-line
/// (rank-1) path when the largest adjugate diagonal of the unit-Frobenius
/// member is `≤` this (`conic_intersection.dart`).
const double rank1SplitEpsilon = 1e-10;

/// Kernel cutoff: two conics projectively equal within this have no
/// discrete intersection — `intersectConicConic` reports none rather than
/// returning the noise the pencil would produce. Deliberately far below
/// [projectiveEpsilon]: near-identical-but-distinct conics down to ~1e-12
/// separation still solve accurately (stress corpus) and must not be
/// swallowed.
const double coincidentConicEpsilon = 1e-13;

/// Kernel cutoff: the joint-Newton polish of an intersection point is
/// skipped when the 2×2 normal-equation determinant falls below this
/// fraction of its scale — the gradients are nearly dependent (tangency)
/// and the system is singular (`conic_intersection.dart`).
const double tangentPolishEpsilon = 1e-12;

/// Classification tolerance for *solver root coincidence*: two roots of an
/// intersection count as the same point (a tangency's double root, the
/// doubled circular points of concentric circles) when `closeTo` within
/// this. A double root is inherently only ~√(machine eps) ≈ 1e-8 accurate —
/// its polish is rightly skipped on singular normal equations — so root
/// coincidence must be judged well above 1e-8, yet far below any genuine
/// root separation. Deliberately looser than [projectiveEpsilon]: this
/// never enters a computed value, only how solver output is counted and
/// filtered (`IntersectionPoint.candidateCount`, the I/J filter).
const double doubleRootEpsilon = 1e-6;
