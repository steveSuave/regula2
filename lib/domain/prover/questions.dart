import '../construction/geo_object.dart';
import '../construction/incidence.dart';
import '../construction/objects/ray.dart';
import '../construction/objects/segment.dart';
import 'fact_naming.dart';
import 'hypotheses.dart';
import 'predicate.dart';

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

/// A pair of points, and whether it bounds a length.
///
/// The distinction is what keeps `cong` from being offered about two
/// *lines*: "are these the same length?" is a question about segments and
/// about points the user picked, never about a line, which has no length
/// to compare. Direction and perpendicularity are fine either way.
class _Pair {
  _Pair(this.a, this.b, {required this.boundsLength});

  final GeoPoint a;
  final GeoPoint b;
  final bool boundsLength;
}

/// A group of equivalent pairs — every way the selection can name one
/// line — carrying whether the *group* stands for something with a
/// length.
class _Group {
  _Group(this.pairs, {required this.boundsLength});

  final List<_Pair> pairs;
  final bool boundsLength;
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
/// would ask a different question from the user's. `eqangle` is offered
/// from exactly one shape, four carriers (Phase 159): four lines *are*
/// `∠(s1,s2) = ∠(s3,s4)`, and what is left is which lines pair off —
/// the same ambiguity four points already carry, answered the same way,
/// by offering every reading. Phase 148's exclusion was written for
/// point selections, where it still holds.
///
/// Order is the order the questions should be offered in: the relation
/// most selections mean first.
List<ProverQuestion> askableQuestions(
  Iterable<GeoObject> objects, {
  required Set<String> selectedIds,
}) {
  final all = List.of(objects);
  final points = [
    for (final object in all)
      if (object is GeoPoint) object,
  ];
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

  List<GeoPoint> onCarrier(GeoObject carrier) => [
    for (final point in points)
      if (structurallyIncident(carrier, point)) point,
  ];

  // A segment or a ray bounds a length between its own two defining
  // points; any other pair on it merely witnesses the direction. A
  // general line bounds nothing.
  _Group? groupFor(GeoLine carrier) {
    final on = onCarrier(carrier);
    final pairs = <_Pair>[];
    final defining = switch (carrier) {
      Segment(:final point1, :final point2) => (point1, point2),
      Ray(:final origin, :final through) => (origin, through),
      _ => null,
    };
    if (defining != null) {
      pairs.add(_Pair(defining.$1, defining.$2, boundsLength: true));
    }
    for (var i = 0; i < on.length; i++) {
      for (var j = i + 1; j < on.length; j++) {
        if (defining != null &&
            ((identical(on[i], defining.$1) && identical(on[j], defining.$2)) ||
                (identical(on[i], defining.$2) &&
                    identical(on[j], defining.$1)))) {
          continue;
        }
        pairs.add(_Pair(on[i], on[j], boundsLength: false));
      }
    }
    if (pairs.isEmpty) return null;
    return _Group(pairs, boundsLength: defining != null);
  }

  // Every selected object must be *consumed* by the question, or there
  // is no question. A selection with something left over — two segments
  // and a stray point, a circle alongside — would have to be read by
  // ignoring part of what the user picked, and silently ignoring half a
  // selection is how a tool answers a question nobody asked.
  if (selected.length !=
      selectedPoints.length + carriers.length + circles.length) {
    return const [];
  }

  // How a carrier is named in a reading: its defining pair when it has
  // one, else the first pair the selection knows on it — with the
  // separator rule `readFact` uses.
  String nameOf(_Group group) {
    final pair = group.pairs.first;
    final names = [pair.a, pair.b].map(describePoint).toList();
    final separator = names.every((name) => name.length == 1) ? '' : ',';
    return names.join(separator);
  }

  // A line and a circle: is the line tangent? Sugar (Phase 159): the
  // tangent at `T` is perpendicular to the radius `O→T`, so the question
  // is `perp(O, T, T, P)` for every other named `P` on the line — which
  // needs a named centre and a named touch point, exactly as Phase 155's
  // hypothesis does. A point the construction puts on both the line and
  // the circle is the touch point; without one, or without a centre,
  // there is no statement to ask and the chip is not offered (naming the
  // point is Phase 153's job, not a special case here). A secant with
  // two named crossings phrases the same question about each, and the
  // filter refutes it.
  if (circles.length == 1 && carriers.length == 1 && selectedPoints.isEmpty) {
    final circle = circles.single;
    final line = carriers.single;
    if (!isCircleByConstruction(circle)) return const [];
    final centre = circleCentre(circle, all);
    if (centre == null) return const [];
    final group = groupFor(line);
    if (group == null) return const [];
    final onLine = onCarrier(line);
    final touches = [
      for (final point in onLine)
        if (structurallyIncident(circle, point)) point,
    ];
    final spellings = [
      for (final touch in touches)
        for (final other in onLine)
          if (!identical(other, touch) && !identical(other, centre))
            Predicate(PredicateKind.perp, [centre, touch, touch, other]),
    ];
    if (spellings.isEmpty) return const [];
    final at = touches.length == 1
        ? ' at ${describePoint(touches.single)}'
        : '';
    return [
      ProverQuestion(
        PredicateKind.perp,
        spellings,
        reading: '${nameOf(group)} is tangent to the circle$at',
      ),
    ];
  }
  if (circles.isNotEmpty) return const [];

  final out = <ProverQuestion>[];
  void relate(_Group first, _Group second) {
    for (final kind in [
      PredicateKind.perp,
      PredicateKind.para,
      if (first.boundsLength && second.boundsLength) PredicateKind.cong,
    ]) {
      final spellings = [
        for (final p in first.pairs)
          for (final q in second.pairs)
            if (!_degenerate(p, q)) Predicate(kind, [p.a, p.b, q.a, q.b]),
      ];
      if (spellings.isEmpty) continue;
      out.add(ProverQuestion(kind, spellings));
    }
  }

  _Group? groupOfSelectedPoints() => selectedPoints.length == 2
      ? _Group([
          _Pair(selectedPoints[0], selectedPoints[1], boundsLength: true),
        ], boundsLength: true)
      : null;

  // Two line-shaped things, however the selection named them.
  if (carriers.length == 2 && selectedPoints.isEmpty) {
    final first = groupFor(carriers[0]);
    final second = groupFor(carriers[1]);
    if (first == null || second == null) return const [];
    relate(first, second);
    return out;
  }
  if (carriers.length == 1 && selectedPoints.length == 2) {
    final first = groupFor(carriers.single);
    if (first == null) return const [];
    relate(first, groupOfSelectedPoints()!);
    return out;
  }
  // Three line-shaped things: are they concurrent? Sugar (Phase 159,
  // PLAN §"JGEX's question list, compared"): in a point-tuple vocabulary
  // concurrency is `coll(P, X, Y)` where `P` is the meeting point of two
  // of the lines and `X`, `Y` name the third — every pair of carriers
  // with a named meeting point, every witness pair on the third. With no
  // named meeting point there is nothing to say, and the honest answer
  // is a chip that is not offered rather than a point invented here. A
  // `concurrent` predicate proper — refutation with no named point at
  // all — is a vocabulary addition and its own phase.
  if (carriers.length == 3 && selectedPoints.isEmpty) {
    final groups = <_Group>[];
    for (final carrier in carriers) {
      final group = groupFor(carrier);
      if (group == null) return const [];
      groups.add(group);
    }
    final spellings = <Predicate>[];
    for (var i = 0; i < 3; i++) {
      for (var j = i + 1; j < 3; j++) {
        final k = 3 - i - j;
        final meeting = [
          for (final point in onCarrier(carriers[i]))
            if (structurallyIncident(carriers[j], point)) point,
        ];
        for (final p in meeting) {
          for (final pair in groups[k].pairs) {
            if (identical(p, pair.a) || identical(p, pair.b)) continue;
            spellings.add(Predicate(PredicateKind.coll, [p, pair.a, pair.b]));
          }
        }
      }
    }
    if (spellings.isEmpty) return const [];
    final names = groups.map(nameOf).toList();
    return [
      ProverQuestion(
        PredicateKind.coll,
        spellings,
        reading: '${names[0]}, ${names[1]} and ${names[2]} are concurrent',
      ),
    ];
  }

  // Four line-shaped things: an equality of angles. Three statements,
  // not six and not two, and *which* three is the finding: `eqangle`'s
  // transpose symmetry (M-P2a) makes `∠(c0,c1) = ∠(c2,c3)` the same fact
  // as `∠(c0,c2) = ∠(c1,c3)`, so pairing the sides the way four points
  // pair off for `para` duplicates one reading and misses another. Read
  // each as a linear equation over line angles, `θ1 − θ0 = θ3 − θ2`,
  // i.e. `θ1 + θ2 = θ0 + θ3`: a statement is a partition of the four
  // lines into two pairs with equal angle *sums*, and there are three of
  // those. Below, one oriented spelling of each; the test checks all six
  // orientations canonicalize onto exactly these.
  if (carriers.length == 4 && selectedPoints.isEmpty) {
    final groups = <_Group>[];
    for (final carrier in carriers) {
      final group = groupFor(carrier);
      if (group == null) return const [];
      groups.add(group);
    }
    const pairings = [
      [0, 1, 2, 3], // θ1 + θ2 = θ0 + θ3
      [0, 1, 3, 2], // θ1 + θ3 = θ0 + θ2
      [0, 2, 3, 1], // θ2 + θ3 = θ0 + θ1
    ];
    for (final [i, j, k, l] in pairings) {
      final spellings = [
        for (final p in groups[i].pairs)
          for (final q in groups[j].pairs)
            for (final r in groups[k].pairs)
              for (final s in groups[l].pairs)
                if (!_degenerate(p, q) &&
                    !_degenerate(r, s) &&
                    !_sameLines(p, q, r, s))
                  Predicate(PredicateKind.eqangle, [
                    p.a,
                    p.b,
                    q.a,
                    q.b,
                    r.a,
                    r.b,
                    s.a,
                    s.b,
                  ]),
      ];
      if (spellings.isEmpty) continue;
      out.add(ProverQuestion(PredicateKind.eqangle, spellings));
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

/// Whether relating [first] to [second] is structurally degenerate: a
/// pair with both endpoints the same point names no line at all, and two
/// pairs naming the *same* two points relate a line to itself.
///
/// Refused here rather than left to the filter: it is a property of the
/// tuple, not of any configuration, which is the same line the rule
/// engine draws at binding time.
bool _degenerate(_Pair first, _Pair second) {
  if (identical(first.a, first.b) || identical(second.a, second.b)) return true;
  return (identical(first.a, second.a) && identical(first.b, second.b)) ||
      (identical(first.a, second.b) && identical(first.b, second.a));
}

/// Whether the angle from [p] to [q] is the angle from [r] to [s] by
/// spelling alone — the same two lines on both sides, in either order —
/// which is `0 = 0` or `θ = θ` and not a question.
bool _sameLines(_Pair p, _Pair q, _Pair r, _Pair s) {
  bool same(_Pair x, _Pair y) =>
      (identical(x.a, y.a) && identical(x.b, y.b)) ||
      (identical(x.a, y.b) && identical(x.b, y.a));
  return (same(p, r) && same(q, s)) || (same(p, s) && same(q, r));
}
