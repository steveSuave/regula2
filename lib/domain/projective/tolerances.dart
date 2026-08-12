/// Tolerances for the projective layer.
///
/// Provisional home: Phase 105 consolidates the layer's epsilon policy into a
/// single documented scheme; until then this file holds the one shared
/// default. The predicates in `proj_point.dart` / `proj_line.dart` are
/// *relative* — residuals are measured against the homogeneous triples'
/// norms — so this value bounds a dimensionless sine-like measure, not a
/// world-space distance.
library;

/// Default relative tolerance for projective predicates (realness,
/// finiteness, incidence, projective equality). Matches the affine layer's
/// `defaultEpsilon` order of magnitude.
const double projectiveEpsilon = 1e-9;
