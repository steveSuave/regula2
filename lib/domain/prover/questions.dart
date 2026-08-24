import 'dart:math' as math;

import '../construction/geo_object.dart';
import 'predicate.dart';
import 'question_spellings.dart';

/// A question about the figure, and every point-tuple spelling of it
/// (PLAN §M-P4).
///
/// **A question is a statement, not a spelling, and that distinction is
/// load-bearing.** `para(A,B,C,D)` and `para(A,X,C,D)` are *different*
/// facts even when `A`, `B` and `X` are collinear, because the DD core
/// has no coll-propagation rules to re-spell a derived fact — the same
/// gap that makes `test/fixtures/perp-true-unproved.rgl` unreachable. A
/// question asked with one witness pair would therefore miss a proof the
/// run found under another. So a question carries all of them and is
/// answered *proved* when any one is in the database: which points name
/// a line is the prover's business, not the user's.
///
/// Every spelling is the same statement numerically, so refuting one
/// refutes all — which is why [canonical] is enough to ask the
/// `DiagramFilter`.
class ProverQuestion {
  ProverQuestion(this.kind, List<Predicate> spellings, {this.reading})
    : spellings = List.unmodifiable(spellings) {
    if (spellings.isEmpty) {
      throw ArgumentError.value(spellings, 'spellings', 'must be non-empty');
    }
  }

  final PredicateKind kind;

  /// The sentence this question is asked *as*, when the spellings are
  /// sugar for something the vocabulary has no word for — "these three
  /// lines are concurrent" is `coll` about their meeting point, "this
  /// line is tangent to the circle" is `perp` about the radius (Phase
  /// 159). Null for a question that *is* its fact, which reads through
  /// `readFact`. The spelling stays visible either way: it is what the
  /// prover is actually asked, and what the tooltip shows.
  final String? reading;

  /// Every equivalent phrasing, first-listed first. Non-empty.
  final List<Predicate> spellings;

  /// The spelling to show the user and to ask the numeric filter.
  Predicate get canonical => spellings.first;

  @override
  String toString() =>
      'ProverQuestion(${kind.name}, ${spellings.length} spellings)';
}

/// What [selectedIds] lets the user ask, over the points of [objects].
///
/// Empty when the selection phrases nothing, which is the usual answer
/// and deliberately so: a lone point, a circle, five objects at once and
/// a carrier with fewer than two named points on it are all selections
/// with no statement in the DD vocabulary behind them. Offering a
/// question the prover cannot even be handed would be worse than
/// offering none.
///
/// **`eqratio` / `simtri` / `contri` are absent on purpose.** They take
/// eight points, or a triangle *correspondence* — neither is something a
/// set of selected objects expresses, and guessing the correspondence
/// would ask a different question from the user's. The question builder
/// (`QuestionTemplate`, Phase 160) is where those are asked: a slot
/// carries the order a set cannot. `eqangle` is offered from exactly one
/// shape, four carriers (Phase 159): four lines *are*
/// `∠(s1,s2) = ∠(s3,s4)`, and what is left is which lines pair off —
/// the same ambiguity four points already carry, answered the same way,
/// by offering every reading. Phase 148's exclusion was written for
/// point selections, where it still holds.
///
/// The spellings themselves — which pairs name a line, which name a
/// length, what is degenerate — are `question_spellings.dart`'s, shared
/// with the builder so a statement is spelled the same whichever surface
/// asked it. What is decided *here* is only what a bare set of objects
/// can mean.
///
/// Order is the order the questions should be offered in: the relation
/// most selections mean first.
List<ProverQuestion> askableQuestions(
  Iterable<GeoObject> objects, {
  required Set<String> selectedIds,
}) {
  final all = List.of(objects);
  final selected = [
    for (final object in all)
      if (selectedIds.contains(object.id)) object,
  ];
  final selectedPoints = [
    for (final object in selected)
      if (object is GeoPoint) object,
  ];
  final carriers = [
    for (final object in selected)
      if (object is GeoLine) object,
  ];
  final circles = [
    for (final object in selected)
      if (object is GeoCircle) object,
  ];

  // Every selected object must be *consumed* by the question, or there
  // is no question. A selection with something left over — two segments
  // and a stray point, a circle alongside — would have to be read by
  // ignoring part of what the user picked, and silently ignoring half a
  // selection is how a tool answers a question nobody asked.
  if (selected.length !=
      selectedPoints.length + carriers.length + circles.length) {
    return const [];
  }

  // Each selected carrier as the pairs naming it, or null for the whole
  // selection when any carrier has no name.
  List<CarrierGroup>? groupsOf(List<GeoLine> lines) {
    final groups = <CarrierGroup>[];
    for (final carrier in lines) {
      final group = CarrierGroup.ofCarrier(all, carrier);
      if (group == null) return null;
      groups.add(group);
    }
    return groups;
  }

  // A line and a circle: is the line tangent?
  if (circles.length == 1 && carriers.length == 1 && selectedPoints.isEmpty) {
    final groups = groupsOf(carriers);
    if (groups == null) return const [];
    final question = tangencyQuestion(all, groups.single, circles.single);
    return question == null ? const [] : [question];
  }
  if (circles.isNotEmpty) return const [];

  List<ProverQuestion> relate(CarrierGroup first, CarrierGroup second) => [
    for (final kind in [
      PredicateKind.perp,
      PredicateKind.para,
      PredicateKind.cong,
    ])
      ?relationQuestion(kind, first, second),
  ];

  // Two line-shaped things, however the selection named them.
  if (carriers.length == 2 && selectedPoints.isEmpty) {
    final groups = groupsOf(carriers);
    if (groups == null) return const [];
    return relate(groups[0], groups[1]);
  }
  if (carriers.length == 1 && selectedPoints.length == 2) {
    final groups = groupsOf(carriers);
    if (groups == null) return const [];
    return relate(
      groups.single,
      CarrierGroup.ofPoints(selectedPoints[0], selectedPoints[1]),
    );
  }
  // Three line-shaped things: are they concurrent?
  if (carriers.length == 3 && selectedPoints.isEmpty) {
    final groups = groupsOf(carriers);
    if (groups == null) return const [];
    final question = concurrencyQuestion(groups);
    return question == null ? const [] : [question];
  }

  // Four line-shaped things: an equality of angles. Three statements,
  // not six and not two, and *which* three is the finding: `eqangle`'s
  // transpose symmetry (M-P2a) makes `∠(c0,c1) = ∠(c2,c3)` the same fact
  // as `∠(c0,c2) = ∠(c1,c3)`, so pairing the sides the way four points
  // pair off for `para` duplicates one reading and misses another. Read
  // each as a linear equation over line angles, `θ1 − θ0 = θ3 − θ2`,
  // i.e. `θ1 + θ2 = θ0 + θ3`: a statement is a partition of the four
  // lines into two pairs with equal angle *sums*, and there are three of
  // those. The test checks all orientations canonicalize onto exactly
  // these.
  //
  // Which of a statement's eight spellings is *offered* matters, because
  // the chip reads as spelled (Phase 162): `∠(BC,CE) = ∠(BD,DC)` and its
  // transpose are one directed fact and two different sentences —
  // "angles BCE and BDC are equal" is the tangent–chord theorem, "angles
  // ECD and CBD are equal" is false as magnitudes. So the spelling is
  // chosen, not inherited from construction order: one that reads
  // three-point on both sides, and among those one whose magnitude
  // reading is true in the figure; deterministic on ties.
  if (carriers.length == 4 && selectedPoints.isEmpty) {
    final groups = groupsOf(carriers);
    if (groups == null) return const [];
    // The three partitions into equal-sum pairs, as (a, b | c, d) with
    // θa + θb ≡ θc + θd.
    const partitions = [
      [1, 2, 0, 3],
      [1, 3, 0, 2],
      [2, 3, 0, 1],
    ];
    final out = <ProverQuestion>[];
    for (final [a, b, c, d] in partitions) {
      // Every spelling ∠(x,y) = ∠(z,w) of θy − θx ≡ θw − θz with
      // {y, z} = {a, b} and {x, w} = {c, d}, or the roles swapped.
      final orientations = <List<int>>[
        for (final (y, z) in [(a, b), (b, a)])
          for (final (x, w) in [(c, d), (d, c)]) ...[
            [x, y, z, w],
            [z, w, x, y],
          ],
      ];
      final chosen = _bestOrientation(orientations, groups);
      final question = eqangleQuestion([for (final i in chosen) groups[i]]);
      if (question != null) out.add(question);
    }
    return out;
  }
  if (carriers.isNotEmpty) return const [];

  // Point-only selections.
  if (selectedPoints.length == 3) {
    final [a, b, c] = selectedPoints;
    return [
      ProverQuestion(PredicateKind.coll, [
        Predicate(PredicateKind.coll, [a, b, c]),
      ]),
      ProverQuestion(PredicateKind.midp, [
        Predicate(PredicateKind.midp, [a, b, c]),
      ]),
      ProverQuestion(PredicateKind.midp, [
        Predicate(PredicateKind.midp, [b, a, c]),
      ]),
      ProverQuestion(PredicateKind.midp, [
        Predicate(PredicateKind.midp, [c, a, b]),
      ]),
    ];
  }
  if (selectedPoints.length == 4) {
    final [a, b, c, d] = selectedPoints;
    // The three ways four points pair off into two lines. Which pairing
    // the user means is genuinely ambiguous, so all three are offered
    // and each names its own points.
    const pairings = [
      [0, 1, 2, 3],
      [0, 2, 1, 3],
      [0, 3, 1, 2],
    ];
    final quad = [a, b, c, d];
    return [
      ProverQuestion(PredicateKind.cyclic, [
        Predicate(PredicateKind.cyclic, quad),
      ]),
      for (final kind in [
        PredicateKind.perp,
        PredicateKind.para,
        PredicateKind.cong,
      ])
        for (final pairing in pairings)
          ProverQuestion(kind, [
            Predicate(kind, [for (final i in pairing) quad[i]]),
          ]),
    ];
  }
  return const [];
}

/// The orientation of an `eqangle` statement to offer, out of the
/// [orientations] that spell it (Phase 162).
///
/// Scored on the groups' first pairs — the ones the offered spelling
/// uses: two for each side that shares exactly one point (it reads
/// three-point, "angle BCE", instead of "the angle from BC to CE"), and
/// one more when both do and the two angles are equal *as magnitudes*
/// in the figure, so that the plain reading is true in the sense a
/// reader takes it and not only mod π. Ties go to the first listed,
/// which is what makes the choice deterministic.
List<int> _bestOrientation(
  List<List<int>> orientations,
  List<CarrierGroup> groups,
) {
  var best = orientations.first;
  var bestScore = -1;
  for (final orientation in orientations) {
    final [i, j, k, l] = orientation;
    final first = _vertex(groups[i].pairs.first, groups[j].pairs.first);
    final second = _vertex(groups[k].pairs.first, groups[l].pairs.first);
    var score = (first == null ? 0 : 2) + (second == null ? 0 : 2);
    if (first != null && second != null && _sameMagnitude(first, second)) {
      score += 1;
    }
    if (score > bestScore) {
      best = orientation;
      bestScore = score;
    }
  }
  return best;
}

/// The angle two pairs name three-point — vertex and arms — when they
/// share exactly one point, else null.
({GeoPoint vertex, GeoPoint arm1, GeoPoint arm2})? _vertex(
  WitnessPair p,
  WitnessPair q,
) {
  final shared = [
    for (final x in [p.a, p.b])
      for (final y in [q.a, q.b])
        if (identical(x, y)) x,
  ];
  if (shared.length != 1) return null;
  final vertex = shared.single;
  return (
    vertex: vertex,
    arm1: identical(p.a, vertex) ? p.b : p.a,
    arm2: identical(q.a, vertex) ? q.b : q.a,
  );
}

/// Whether two three-point angles are equal as undirected magnitudes in
/// the current figure — the sense a reader takes "angles BCE and BDC
/// are equal" in. Positions are read as the filter reads them; any
/// missing or degenerate one answers false, which is "no preference".
bool _sameMagnitude(
  ({GeoPoint vertex, GeoPoint arm1, GeoPoint arm2}) first,
  ({GeoPoint vertex, GeoPoint arm1, GeoPoint arm2}) second,
) {
  double? magnitude(({GeoPoint vertex, GeoPoint arm1, GeoPoint arm2}) angle) {
    final v = angle.vertex.position;
    final a = angle.arm1.position;
    final b = angle.arm2.position;
    if (v == null || a == null || b == null) return null;
    final u = a - v;
    final w = b - v;
    if (u.normSquared == 0 || w.normSquared == 0) return null;
    return math.acos(
      ((u.x * w.x + u.y * w.y) / (u.norm * w.norm)).clamp(-1.0, 1.0),
    );
  }

  final m1 = magnitude(first);
  final m2 = magnitude(second);
  if (m1 == null || m2 == null) return false;
  return (m1 - m2).abs() < 1e-6;
}
