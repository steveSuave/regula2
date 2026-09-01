import '../construction/geo_object.dart';
import '../math/rational.dart';
import '../math/vec2.dart';
import 'numeric_checks.dart' as checks;

/// The prover's predicate vocabulary (PLAN §M-P1) — the relations DD
/// forward chaining ranges over, each with its fixed arity in points.
///
/// The three [carriesValue] kinds are the constants stack's vocabulary
/// (PLAN §"The constants stack", Phases 181–182): facts that state a
/// number as part of their identity. **No DD rule matches them** —
/// hypotheses state them, the AR translations absorb them, asks answer
/// them by entailment — so forward chaining still ranges over the ten
/// point-pure relations.
enum PredicateKind {
  /// coll(a, b, c) — collinear.
  coll(3),

  /// para(a, b, c, d) — line ab parallel to line cd.
  para(4),

  /// perp(a, b, c, d) — line ab perpendicular to line cd.
  perp(4),

  /// cong(a, b, c, d) — |ab| = |cd|.
  cong(4),

  /// cyclic(a, b, c, d) — concyclic on a genuine circle.
  cyclic(4),

  /// eqangle(a, b, c, d, e, f, g, h) — ∠(ab, cd) = ∠(ef, gh) mod π.
  eqangle(8),

  /// eqratio(a, b, c, d, e, f, g, h) — |ab|/|cd| = |ef|/|gh|.
  eqratio(8),

  /// midp(m, a, b) — m is the midpoint of ab.
  midp(3),

  /// simtri(a, b, c, d, e, f) — similar triangles (orientation-free).
  simtri(6),

  /// contri(a, b, c, d, e, f) — congruent triangles (orientation-free).
  contri(6),

  /// aconst(a, b, c, d; r) — the angle from line ab to line cd is r,
  /// stated in units of π and reduced mod 1 into `[0, 1)` (Newclid's
  /// convention: θ_cd − θ_ab ≡ r·π mod π).
  aconst(4, carriesValue: true),

  /// rconst(a, b, c, d; q) — |ab| / |cd| = q, for a stated q ∈ ℚ⁺.
  rconst(4, carriesValue: true),

  /// lconst(a, b; q) — |ab| = q, for a stated q ∈ ℚ⁺ in the document's
  /// own units.
  lconst(2, carriesValue: true);

  const PredicateKind(this.arity, {this.carriesValue = false});

  /// How many points the predicate takes.
  final int arity;

  /// Whether a statement of this kind carries a rational value as part
  /// of its identity — `rconst(a,b,c,d; 2)` and `rconst(a,b,c,d; 3)` are
  /// different statements about the same points.
  final bool carriesValue;
}

/// One predicate instance over the diagram's points: a [kind] applied to
/// [points], in the argument order the kind's doc names.
///
/// This is the *statement*, separated from its truth: [holdsOn] answers
/// numerically for any configuration's positions, so the `DiagramFilter`
/// can ask the same predicate about many sampled configurations without
/// touching the construction. What it deliberately is **not** is a fact:
/// canonical forms, argument-order normalization and equality keying (two
/// `eqangle`s naming one fact in different orders) are the fact
/// database's concern and arrive with M-P2 — a `Predicate` compares by
/// identity like any object.
class Predicate {
  /// Throws [ArgumentError] when [points] does not match [kind.arity],
  /// when [value]'s presence does not match [PredicateKind.carriesValue],
  /// or when a carried value is out of the kind's range — positive for a
  /// stated length or ratio, reduced into `[0, 1)` for a stated angle
  /// (the residue is the value, so an unreduced spelling is two names
  /// for one statement). A malformed predicate is a programmer error,
  /// like a degenerate `LineEq`, never a value to evaluate
  /// conservatively.
  Predicate(this.kind, List<GeoPoint> points, {this.value})
    : points = List.unmodifiable(points) {
    if (points.length != kind.arity) {
      throw ArgumentError.value(
        points,
        'points',
        '${kind.name} takes ${kind.arity} points, got ${points.length}',
      );
    }
    if ((value != null) != kind.carriesValue) {
      throw ArgumentError.value(
        value,
        'value',
        kind.carriesValue
            ? '${kind.name} states a value'
            : '${kind.name} carries no value',
      );
    }
    final v = value;
    if (v != null) {
      if (kind == PredicateKind.aconst) {
        if (v != v.modOne()) {
          throw ArgumentError.value(
            value,
            'value',
            'a stated angle is a residue mod 1, in [0, 1)',
          );
        }
      } else if (v.isZero || v.isNegative) {
        throw ArgumentError.value(
          value,
          'value',
          'a stated length or ratio is positive',
        );
      }
    }
  }

  final PredicateKind kind;

  /// The arguments, in the kind's documented order. Fixed for the
  /// predicate's lifetime.
  final List<GeoPoint> points;

  /// The stated value — non-null exactly for a [PredicateKind.carriesValue]
  /// kind, and always positive.
  final Rational? value;

  /// Numeric truth over explicit positions, parallel to [points]. A null
  /// position — an undefined point in that configuration — makes every
  /// predicate false: an undefined point is *nowhere*, and a deduction
  /// about it must not be attempted.
  bool holdsOn(List<Vec2?> positions) {
    if (positions.length != kind.arity) {
      throw ArgumentError.value(
        positions,
        'positions',
        '${kind.name} takes ${kind.arity} positions, '
            'got ${positions.length}',
      );
    }
    final p = <Vec2>[];
    for (final position in positions) {
      if (position == null) {
        return false;
      }
      p.add(position);
    }
    return switch (kind) {
      PredicateKind.coll => checks.collinear(p[0], p[1], p[2]),
      PredicateKind.para => checks.parallel(p[0], p[1], p[2], p[3]),
      PredicateKind.perp => checks.perpendicular(p[0], p[1], p[2], p[3]),
      PredicateKind.cong => checks.congruent(p[0], p[1], p[2], p[3]),
      PredicateKind.cyclic => checks.concyclic(p[0], p[1], p[2], p[3]),
      PredicateKind.eqangle => checks.equalAngles(
        p[0],
        p[1],
        p[2],
        p[3],
        p[4],
        p[5],
        p[6],
        p[7],
      ),
      PredicateKind.eqratio => checks.equalRatios(
        p[0],
        p[1],
        p[2],
        p[3],
        p[4],
        p[5],
        p[6],
        p[7],
      ),
      PredicateKind.midp => checks.midpointOf(p[0], p[1], p[2]),
      PredicateKind.simtri => checks.similarTriangles(
        p[0],
        p[1],
        p[2],
        p[3],
        p[4],
        p[5],
      ),
      PredicateKind.contri => checks.congruentTriangles(
        p[0],
        p[1],
        p[2],
        p[3],
        p[4],
        p[5],
      ),
      PredicateKind.aconst => checks.angleIs(
        p[0],
        p[1],
        p[2],
        p[3],
        value!.toDouble(),
      ),
      PredicateKind.rconst => checks.ratioIs(
        p[0],
        p[1],
        p[2],
        p[3],
        value!.toDouble(),
      ),
      PredicateKind.lconst => checks.lengthIs(p[0], p[1], value!.toDouble()),
    };
  }

  /// Numeric truth at the points' current positions — one configuration,
  /// no perturbation. The filter's screen over sampled configurations is
  /// `DiagramFilter.holds`.
  bool get holdsNow => holdsOn([for (final point in points) point.position]);

  @override
  String toString() =>
      '${kind.name}(${points.map((p) => p.id).join(', ')}'
      '${value == null ? '' : '; $value'})';
}
