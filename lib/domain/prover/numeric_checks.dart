import 'dart:math' as math;

import '../math/vec2.dart';

/// Numeric truth of the prover's predicates, measured in the Euclidean
/// chart.
///
/// These are the evaluators behind the model filter (PLAN §M-P1): a
/// deduction is only attempted when its conclusion is already numerically
/// true in the diagram, so each function here answers "does this
/// predicate hold in this configuration, up to floating-point error?" —
/// never "is it a theorem", which is what the perturbation probe on top
/// of them settles probabilistically and forward chaining (M-P2) settles
/// deductively.
///
/// **All comparisons are dimensionless or scale-relative** against
/// [predicateTolerance]: a sine or cosine of an angle between directions,
/// a length difference relative to the lengths compared, a position
/// difference relative to the position's magnitude (the
/// `point_coincidence.dart` convention). A predicate that holds
/// identically computes to float noise (~1e-12 relative, a few orders
/// worse through a long construction); an accidental truth broken by a
/// probe separates by ~`probeScale` (3e-2, conditioned down an order or
/// two at worst). 1e-6 sits between the two with margin on both sides,
/// and is deliberately the same magnitude the coincidence probe screens
/// positions with.
///
/// **Degenerate arguments answer conservatively — false — wherever the
/// predicate presupposes structure the configuration lacks**: a zero
/// direction has no parallel, no perpendicular and no angle; four
/// collinear points lie on no circle; a flattened triangle is similar and
/// congruent to nothing. The one deliberate exception is [collinear],
/// which answers true on coincident points (they impose no constraint a
/// line could fail), matching the zero-epsilon incidence relation's
/// reading. An undefined point never reaches these functions — the
/// `Predicate` layer answers false before evaluating.
const double predicateTolerance = 1e-6;

/// Position comparisons: [predicateTolerance] relative to the magnitude
/// of what is compared, floored at 1 world unit — positions carry float
/// error proportional to their size.
double _positionTolerance(double magnitude) =>
    predicateTolerance * math.max(1.0, magnitude);

/// coll(a, b, c) — the three points are collinear.
///
/// `|u × v| ≤ tol·|u|·|v|` with `u = b − a`, `v = c − a`: the sine of
/// the angle at `a`, dimensionless. Total without a branch — coincident
/// points zero the left side and the right, and 0 ≤ 0 reads true, which
/// is the deliberate exception above.
bool collinear(Vec2 a, Vec2 b, Vec2 c) {
  final u = b - a;
  final v = c - a;
  return u.cross(v).abs() <= predicateTolerance * u.norm * v.norm;
}

/// para(a, b, c, d) — line ab is parallel to line cd.
///
/// The sine between the two directions. A zero direction (a == b or
/// c == d) is no line and parallels nothing.
bool parallel(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  final u = b - a;
  final v = d - c;
  if (u.normSquared == 0 || v.normSquared == 0) {
    return false;
  }
  return u.cross(v).abs() <= predicateTolerance * u.norm * v.norm;
}

/// perp(a, b, c, d) — line ab is perpendicular to line cd.
///
/// The cosine between the two directions; same degeneracy rule as
/// [parallel].
bool perpendicular(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  final u = b - a;
  final v = d - c;
  if (u.normSquared == 0 || v.normSquared == 0) {
    return false;
  }
  return u.dot(v).abs() <= predicateTolerance * u.norm * v.norm;
}

/// cong(a, b, c, d) — segment ab and segment cd have equal length.
///
/// Length difference relative to the larger length, floored at 1 world
/// unit. Two zero-length segments are congruent — the distances are
/// equal, and nothing about congruence presupposes extent.
bool congruent(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  final ab = a.distanceTo(b);
  final cd = c.distanceTo(d);
  return (ab - cd).abs() <= _positionTolerance(math.max(ab, cd));
}

/// midp(m, a, b) — m is the midpoint of segment ab.
///
/// A position comparison, relative to the magnitudes involved.
bool midpointOf(Vec2 m, Vec2 a, Vec2 b) {
  final mid = (a + b) / 2;
  final magnitude = math.max(m.norm, math.max(a.norm, b.norm));
  return m.distanceTo(mid) <= _positionTolerance(magnitude);
}

/// The directed angle from direction [u] to direction [v], reduced mod π
/// into [0, π) — the angle between the *lines* they span, which is what
/// every angle predicate compares (a line has no preferred direction, so
/// angles between lines are only defined mod π).
double _lineAngle(Vec2 u, Vec2 v) {
  final angle = math.atan2(u.cross(v), u.dot(v)) % math.pi;
  // Dart's % is never negative, so this is already in [0, π] — with the
  // closed end reachable only as a rounding artifact, when an angle
  // epsilon-below zero wraps to exactly π. Fold it back onto 0.
  return angle == math.pi ? 0.0 : angle;
}

/// Whether two line angles agree mod π, honouring the wrap: 1e-7 and
/// π − 1e-7 are the same line angle.
bool _lineAnglesAgree(double first, double second) {
  final difference = (first - second).abs();
  return math.min(difference, math.pi - difference) <= predicateTolerance;
}

/// cyclic(a, b, c, d) — the four points lie on one circle.
///
/// The inscribed angle theorem as directed angles mod π: ∠(ca, cb) =
/// ∠(da, db) exactly when a, b, c, d are concyclic *or all collinear* —
/// so the collinear case, which is a line and not a circle, is excluded
/// first. A point coinciding with another answers false: it either
/// leaves an angle undefined, or — for the pair c, d — compares one
/// angle with its own copy, which is the vacuous "some circle through
/// three points" and not the predicate.
bool concyclic(Vec2 a, Vec2 b, Vec2 c, Vec2 d) {
  if (collinear(a, b, c) && collinear(a, b, d)) {
    return false;
  }
  final ca = a - c;
  final cb = b - c;
  final da = a - d;
  final db = b - d;
  if (ca.normSquared == 0 ||
      cb.normSquared == 0 ||
      da.normSquared == 0 ||
      db.normSquared == 0 ||
      (c - d).normSquared == 0) {
    return false;
  }
  return _lineAnglesAgree(_lineAngle(ca, cb), _lineAngle(da, db));
}

/// eqangle(a, b, c, d, e, f, g, h) — the angle from line ab to line cd
/// equals the angle from line ef to line gh, as directed angles mod π.
bool equalAngles(
  Vec2 a,
  Vec2 b,
  Vec2 c,
  Vec2 d,
  Vec2 e,
  Vec2 f,
  Vec2 g,
  Vec2 h,
) {
  final u1 = b - a;
  final v1 = d - c;
  final u2 = f - e;
  final v2 = h - g;
  if (u1.normSquared == 0 ||
      v1.normSquared == 0 ||
      u2.normSquared == 0 ||
      v2.normSquared == 0) {
    return false;
  }
  return _lineAnglesAgree(_lineAngle(u1, v1), _lineAngle(u2, v2));
}

/// eqratio(a, b, c, d, e, f, g, h) — |ab| / |cd| = |ef| / |gh|.
///
/// Compared cross-multiplied, `|ab|·|gh| = |cd|·|ef|`, which is total:
/// a zero numerator pair agrees (0/x = 0/y), and a zero *denominator*
/// only agrees when its mate's product also vanishes — the honest
/// reading of an infinite ratio. Tolerance is relative to the products,
/// floored at 1.
bool equalRatios(
  Vec2 a,
  Vec2 b,
  Vec2 c,
  Vec2 d,
  Vec2 e,
  Vec2 f,
  Vec2 g,
  Vec2 h,
) {
  final left = a.distanceTo(b) * g.distanceTo(h);
  final right = c.distanceTo(d) * e.distanceTo(f);
  return (left - right).abs() <=
      predicateTolerance * math.max(1.0, math.max(left, right));
}

/// aconst(a, b, c, d; r) — the angle from line ab to line cd is r·π,
/// for a stated r in units of π reduced into [0, 1).
///
/// The same directed-mod-π reading as [equalAngles], compared against
/// the stated value instead of a second pair; same degeneracy rule — a
/// zero direction is no line and makes no angle.
bool angleIs(Vec2 a, Vec2 b, Vec2 c, Vec2 d, double r) {
  final u = b - a;
  final v = d - c;
  if (u.normSquared == 0 || v.normSquared == 0) {
    return false;
  }
  return _lineAnglesAgree(_lineAngle(u, v), r * math.pi);
}

/// rconst(a, b, c, d; q) — |ab| / |cd| = q, for a stated q.
///
/// Compared cross-multiplied like [equalRatios] and by the same
/// totality argument: `|ab| = q·|cd|` holds for a zero pair only when
/// both sides vanish. Tolerance relative to the lengths, floored at 1.
bool ratioIs(Vec2 a, Vec2 b, Vec2 c, Vec2 d, double q) {
  final left = a.distanceTo(b);
  final right = q * c.distanceTo(d);
  return (left - right).abs() <=
      predicateTolerance * math.max(1.0, math.max(left.abs(), right.abs()));
}

/// lconst(a, b; q) — |ab| = q, in the document's own units.
///
/// The one comparison here that is not scale-relative between figure
/// quantities, because the statement itself is not: a stated length
/// names a number in the figure's coordinates, and rescaling the figure
/// genuinely changes its truth.
bool lengthIs(Vec2 a, Vec2 b, double q) {
  final length = a.distanceTo(b);
  return (length - q).abs() <=
      predicateTolerance * math.max(1.0, math.max(length, q.abs()));
}

/// simtri(a, b, c, d, e, f) — triangles abc and def are similar.
///
/// Side-ratio equality, `|ab|/|de| = |bc|/|ef| = |ca|/|fd|`, compared
/// cross-multiplied — **orientation-free**, so a reflected similar
/// triangle satisfies it too. If M-P2's rule set needs the direct /
/// reflected split (Newclid's simtri vs simtrir), it splits here, by
/// adding the sign of the two triangles' orientations to the check —
/// the ratios are the shared part. Degenerate (collinear) triangles are
/// similar to nothing.
bool similarTriangles(Vec2 a, Vec2 b, Vec2 c, Vec2 d, Vec2 e, Vec2 f) {
  if (!_genuineTriangle(a, b, c) || !_genuineTriangle(d, e, f)) {
    return false;
  }
  return equalRatios(a, b, d, e, b, c, e, f) &&
      equalRatios(b, c, e, f, c, a, f, d);
}

/// contri(a, b, c, d, e, f) — triangles abc and def are congruent.
///
/// Three side congruences (SSS); orientation-free like
/// [similarTriangles], and degenerate triangles are congruent to
/// nothing.
bool congruentTriangles(Vec2 a, Vec2 b, Vec2 c, Vec2 d, Vec2 e, Vec2 f) {
  if (!_genuineTriangle(a, b, c) || !_genuineTriangle(d, e, f)) {
    return false;
  }
  return congruent(a, b, d, e) &&
      congruent(b, c, e, f) &&
      congruent(c, a, f, d);
}

/// A triangle with three non-collinear corners — what the triangle
/// predicates presuppose. [collinear]'s sine bound already reads
/// coincident corners as collinear, so this single check refuses every
/// flattening, within tolerance of the exactly-flat limit.
bool _genuineTriangle(Vec2 a, Vec2 b, Vec2 c) => !collinear(a, b, c);
