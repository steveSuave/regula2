import '../construction/geo_object.dart';
import '../math/vec2.dart';
import 'numeric_checks.dart' as checks;

/// The prover's predicate vocabulary (PLAN §M-P1) — the ten relations DD
/// forward chaining ranges over, each with its fixed arity in points.
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
  contri(6);

  const PredicateKind(this.arity);

  /// How many points the predicate takes.
  final int arity;
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
  /// Throws [ArgumentError] when [points] does not match [kind.arity] —
  /// a malformed predicate is a programmer error, like a degenerate
  /// `LineEq`, never a value to evaluate conservatively.
  Predicate(this.kind, List<GeoPoint> points)
    : points = List.unmodifiable(points) {
    if (points.length != kind.arity) {
      throw ArgumentError.value(
        points,
        'points',
        '${kind.name} takes ${kind.arity} points, got ${points.length}',
      );
    }
  }

  final PredicateKind kind;

  /// The arguments, in the kind's documented order. Fixed for the
  /// predicate's lifetime.
  final List<GeoPoint> points;

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
    };
  }

  /// Numeric truth at the points' current positions — one configuration,
  /// no perturbation. The filter's screen over sampled configurations is
  /// `DiagramFilter.holds`.
  bool get holdsNow => holdsOn([for (final point in points) point.position]);

  @override
  String toString() => '${kind.name}(${points.map((p) => p.id).join(', ')})';
}
