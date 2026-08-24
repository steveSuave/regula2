import '../construction/geo_object.dart';
import 'fact.dart';
import 'predicate.dart';

/// What a carrier *is* — and, equivalently, how many points it takes to
/// name one. Two distinct points determine a line; three determine a
/// circle. [arity] is that number, and it is the whole of the generic
/// machinery below: a carrier's names are the arity-subsets of its point
/// set, and two carriers sharing one name are one carrier.
enum CarrierKind {
  line(2),
  circle(3);

  const CarrierKind(this.arity);

  /// How many points name this kind of carrier.
  final int arity;
}

/// A line or a circle as an *object*, carrying the points known to lie
/// on it (PLAN §"Two closures the rule table is standing in for").
///
/// The prover's vocabulary is point-tuples, so a line is named by a pair
/// of points on it and one line has many names: `para(A,B,C,D)` and
/// `para(A,X,C,D)` are different facts even with `A`, `B`, `X`
/// collinear. A `Carrier` is the identity behind those names. It is
/// deliberately **not** a `Fact` and does not enter the database: the
/// vocabulary and the save format do not move, and a proof still reads
/// in point tuples. What changes is that "which points name this line"
/// becomes a lookup instead of a derivation.
///
/// Compares by kind and point *set* — two carriers naming the same
/// points are the same carrier — which is what makes
/// [CarrierIndex.sameLine] an equality rather than a search.
class Carrier {
  /// [points] is taken as the carrier's full known point set; it is
  /// sorted by id here, so the ordering is deterministic and
  /// construction-order independent for the same reason `Fact`'s is.
  Carrier(this.kind, Iterable<GeoPoint> known)
    : points = List.unmodifiable(
        List<GeoPoint>.of(known)..sort((a, b) => a.id.compareTo(b.id)),
      );

  final CarrierKind kind;

  /// Every point known to lie on this carrier, ordered by id. At least
  /// [CarrierKind.arity] of them: a carrier with fewer points than it
  /// takes to name one does not exist.
  final List<GeoPoint> points;

  bool contains(GeoPoint point) =>
      points.any((p) => identical(p, point) || p.id == point.id);

  /// Whether the closure knows more about this carrier than the pair (or
  /// triple) naming it does — the case where it has something to say.
  bool get isNamed => points.length > kind.arity;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Carrier ||
        other.kind != kind ||
        other.points.length != points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (points[i].id != other.points[i].id) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([kind, ...points.map((p) => p.id)]);

  @override
  String toString() => '${kind.name}{${points.map((p) => p.id).join(', ')}}';
}

/// The argument pairs of [kind] that name a **line** — the slots a
/// matcher may resolve through the line closure, replacing the witness
/// pair with any other pair on the same carrier.
///
/// This table is a soundness claim per entry, and it is the one place
/// where the closure can go wrong: reading a slot as a line when it
/// names a *segment* would let `cong(A,B,C,D)` match a premise spelled
/// `cong(A,X,C,D)` with `A`, `B`, `X` collinear, which is false the
/// moment `|AX| ≠ |AB|` — and it would be false invisibly, since the
/// numeric screen only ever sees the conclusion. So the entries are
/// pinned against the *evaluators* (`carriers_test.dart`), exactly the
/// way `Fact`'s symmetry group is: the claim "this substitution
/// preserves truth" is one only `Predicate.holdsOn` can adjudicate.
///
/// **The two directions of error are not symmetric, and only one of them
/// fails a test.** A slot listed that should not be makes the matcher
/// unsound, and the sweep catches it on a numeric counterexample. A slot
/// *missing* that belongs costs completeness only — the matcher resolves
/// less than it could — so nothing here fails; what would show it is the
/// fact-count measurement, not a test.
///
/// The claims, in the order of the switch:
///
/// - **`para`, `perp`** — both pairs name lines. `ab ∥ cd` is a
///   statement about two directions, and every pair on line `ab` has
///   that direction.
/// - **`eqangle`** — all four pairs name lines. The predicate is
///   `∠(ab, cd) = ∠(ef, gh)` read **mod π**, which is the angle between
///   *lines*; that is the same reading `Fact`'s column swap already
///   relies on.
/// - **`cong`, `eqratio`** — no slot is a line. A pair names a segment,
///   and a segment has a length its carrier does not: `|AB|` and `|AX|`
///   differ for `X` on line `AB`. This is the entry that would be
///   unsound if it were guessed by shape.
/// - **`midp`, `simtri`, `contri`** — the arguments are points in
///   distinguished roles, not pairs. `midp(m,a,b)` does put `m` on line
///   `ab`, but that is incidence the closure *absorbs* (as the `coll`
///   `midp_coll` derives), never a slot to resolve.
/// - **`coll`, `cyclic`** — empty for a different reason, and worth
///   saying so: these predicates *are* the incidence. Their content is
///   what builds the closure, so resolving them through it would be
///   circular rather than merely wrong.
List<List<int>> lineSlots(PredicateKind kind) => switch (kind) {
  PredicateKind.para || PredicateKind.perp => const [
    [0, 1],
    [2, 3],
  ],
  PredicateKind.eqangle => const [
    [0, 1],
    [2, 3],
    [4, 5],
    [6, 7],
  ],
  PredicateKind.coll ||
  PredicateKind.cyclic ||
  PredicateKind.cong ||
  PredicateKind.eqratio ||
  PredicateKind.midp ||
  PredicateKind.simtri ||
  PredicateKind.contri => const [],
};

/// The incidence closure: lines and circles merged by union-find over
/// the tuples that name them, so that a pair of points resolves to *the*
/// line it lies on rather than to one spelling of it.
///
/// This is M-P2d, and it exists to delete rules rather than to add them.
/// `coll_transitive` (`coll(a,b,c) & coll(a,b,d) => coll(a,c,d)`) is
/// this structure written as a match pattern, one derivation at a time
/// and at the engine's per-application cost; `cyclic_fifth_point` is the
/// same for circles; `perp_coll` is a consumer re-deriving the lookup
/// inline. Here the same content is a union: [absorb] a `coll` and every
/// pair of its points names one line, permanently and for free.
///
/// **The soundness argument is the arity, and it is the classical one.**
/// Two classes are merged exactly when they share a *name* — a pair of
/// points for a line, a triple for a circle — and two distinct points
/// determine a line while three determine a circle. So a merge is the
/// statement "these are the same line", and it inherits precisely the
/// assumption `coll_transitive` already makes: that the shared points
/// are genuinely distinct. Points distinct as objects but coincident in
/// position would break both equally, which is to say this adds no
/// soundness surface the rule table did not already have.
///
/// **It is incremental because the engine is.** Forward chaining adds
/// one fact at a time, and [absorb] absorbs one fact at a time, with the
/// same result as rebuilding from the whole database (pinned by test).
///
/// What it deliberately does not do: derive facts. Nothing here writes
/// to a `FactDatabase`, and a carrier is not a proof step. The consumer
/// that resolves a pair to its carrier *before* joining is the matcher,
/// and that is the next phase; this one is the structure and its
/// measurement.
class CarrierIndex {
  CarrierIndex();

  /// The closure of [facts], absorbed in iteration order.
  factory CarrierIndex.over(Iterable<Fact> facts) =>
      CarrierIndex()..absorbAll(facts);

  final Map<CarrierKind, _Closure> _closures = {
    for (final kind in CarrierKind.values) kind: _Closure(kind),
  };

  /// Absorbs [fact], answering whether the closure grew.
  ///
  /// Only `coll` and `cyclic` say anything about incidence, and every
  /// other kind is ignored with a false answer — including `midp`, whose
  /// incidence content reaches here as the `coll` that `midp_coll`
  /// derives. A fact with a repeated point is ignored too: it names no
  /// carrier, and refusing it is data handling rather than a programmer
  /// error, since the database is free to hold one.
  bool absorb(Fact fact) {
    final kind = switch (fact.kind) {
      PredicateKind.coll => CarrierKind.line,
      PredicateKind.cyclic => CarrierKind.circle,
      _ => null,
    };
    if (kind == null) return false;
    final ids = <String>{for (final point in fact.points) point.id};
    if (ids.length != fact.points.length) return false;
    return _closures[kind]!.absorb(fact.points);
  }

  /// Absorbs each of [facts], answering how many grew the closure.
  int absorbAll(Iterable<Fact> facts) {
    var grew = 0;
    for (final fact in facts) {
      if (absorb(fact)) grew++;
    }
    return grew;
  }

  /// The line through [a] and [b] — total, because two distinct points
  /// always name a line. A pair no `coll` has ever mentioned answers the
  /// carrier that names exactly those two points, which is the truth
  /// about it: the closure knows of no third point on it.
  ///
  /// Throws [ArgumentError] on a repeated point, the same
  /// programmer-error contract `LineEq` keeps for a degenerate line.
  Carrier lineThrough(GeoPoint a, GeoPoint b) =>
      _closures[CarrierKind.line]!.lookUp([a, b]);

  /// The circle through [a], [b] and [c] — total, for the same reason,
  /// three distinct points naming a circle. Throws [ArgumentError] on a
  /// repeated point.
  Carrier circleThrough(GeoPoint a, GeoPoint b, GeoPoint c) =>
      _closures[CarrierKind.circle]!.lookUp([a, b, c]);

  /// Whether `ab` and `cd` name the same line — the matcher's question,
  /// and an equality rather than a search.
  bool sameLine(GeoPoint a, GeoPoint b, GeoPoint c, GeoPoint d) =>
      lineThrough(a, b) == lineThrough(c, d);

  /// Whether [fact] relates a line to itself — true, and content-free.
  ///
  /// `para`/`perp` whose two lines are one line; `eqangle` whose both
  /// sides are a zero angle (each pair one line), or whose two sides are
  /// one angle under two spellings. Every other kind is never trivial:
  /// `cong` over collinear segments is a real fact, and `coll` names a
  /// line rather than relating one.
  ///
  /// These exist because the DD table's implicit non-degeneracy
  /// conditions ride on the numeric screen, and the screen cannot
  /// refuse a degenerate instance whose conclusion is *true* — `0 = 0`,
  /// `AB ∥ AB` (PLAN §"Nondegeneracy the numeric screen cannot carry").
  /// They are load-bearing in the closure, so this is a reading of the
  /// database, not a filter on it: the panel folds them away.
  bool isTrivial(Fact fact) {
    final p = fact.points;
    bool same(int a, int b, int c, int d) => sameLine(p[a], p[b], p[c], p[d]);
    return switch (fact.kind) {
      PredicateKind.para || PredicateKind.perp => same(0, 1, 2, 3),
      PredicateKind.eqangle =>
        (same(0, 1, 2, 3) && same(4, 5, 6, 7)) ||
            (same(0, 1, 4, 5) && same(2, 3, 6, 7)),
      _ => false,
    };
  }

  /// Every line the closure has materialized — those a `coll` created,
  /// never the singletons [lineThrough] answers for an unmentioned pair.
  Iterable<Carrier> get lines => _closures[CarrierKind.line]!.carriers;

  /// Every circle the closure has materialized.
  Iterable<Carrier> get circles => _closures[CarrierKind.circle]!.carriers;
}

/// One kind's union-find, over the arity-subsets that name a carrier.
///
/// The invariant the expansion maintains is what makes lookup a map
/// read: **every arity-subset of a class's point set maps to that
/// class.** So resolving a pair never has to search, and a merge that
/// makes two previously unrelated names equal is discovered when the
/// subsets are re-keyed, not later by a rule.
class _Closure {
  _Closure(this.kind);

  final CarrierKind kind;

  final List<int> _parent = [];
  final List<int> _size = [];

  /// Point sets, meaningful at roots only, keyed by id within a class so
  /// that membership does not depend on `GeoPoint` equality.
  final List<Map<String, GeoPoint>> _points = [];

  /// Name → node. Read through [_find] to reach the class.
  final Map<String, int> _node = {};

  Iterable<Carrier> get carriers sync* {
    for (var i = 0; i < _parent.length; i++) {
      if (_find(i) == i) yield Carrier(kind, _points[i].values);
    }
  }

  Carrier lookUp(List<GeoPoint> name) {
    _requireDistinct(name);
    final node = _node[_key(name)];
    if (node == null) return Carrier(kind, name);
    return Carrier(kind, _points[_find(node)].values);
  }

  /// Absorbs an incidence over [points] — all of them on one carrier —
  /// answering whether the closure grew.
  bool absorb(List<GeoPoint> points) {
    var grew = false;
    var root = -1;
    for (final name in _subsets(points)) {
      final key = _key(name);
      final existing = _node[key];
      if (existing == null) {
        _node[key] = _fresh(name);
        grew = true;
      }
      final node = _find(_node[key]!);
      if (root == -1) {
        root = node;
      } else if (node != root) {
        root = _union(root, node);
        grew = true;
      }
    }
    if (root == -1) return false;
    for (final point in points) {
      if (_points[root].containsKey(point.id)) continue;
      _points[root][point.id] = point;
      grew = true;
    }
    if (_expand(root)) grew = true;
    return grew;
  }

  /// Re-keys every arity-subset of [root]'s point set onto [root],
  /// merging whatever it collides with — a collision is two carriers
  /// found to share a name, which is the closure's whole content.
  ///
  /// A merge grows the point set, which yields new subsets, so this
  /// restarts rather than iterating a snapshot. The sets are small (the
  /// subsets of one line's points, not of the diagram's) and each
  /// restart consumes a class, so the loop is bounded by their number.
  bool _expand(int root) {
    var grew = false;
    var current = root;
    var settled = false;
    while (!settled) {
      settled = true;
      final points = _points[_find(current)].values.toList();
      for (final name in _subsets(points)) {
        final key = _key(name);
        final existing = _node[key];
        if (existing == null) {
          _node[key] = _find(current);
          grew = true;
          continue;
        }
        final other = _find(existing);
        if (other == _find(current)) continue;
        current = _union(_find(current), other);
        grew = true;
        settled = false;
        break;
      }
    }
    return grew;
  }

  int _fresh(List<GeoPoint> name) {
    final index = _parent.length;
    _parent.add(index);
    _size.add(1);
    _points.add({for (final point in name) point.id: point});
    return index;
  }

  int _find(int node) {
    var root = node;
    while (_parent[root] != root) {
      root = _parent[root];
    }
    var walk = node;
    while (_parent[walk] != root) {
      final next = _parent[walk];
      _parent[walk] = root;
      walk = next;
    }
    return root;
  }

  /// Union by size, answering the surviving root. The loser's points
  /// move to the winner: a class's point set is the union of everything
  /// merged into it.
  int _union(int a, int b) {
    var winner = _find(a);
    var loser = _find(b);
    if (winner == loser) return winner;
    if (_size[winner] < _size[loser]) {
      final swap = winner;
      winner = loser;
      loser = swap;
    }
    _parent[loser] = winner;
    _size[winner] += _size[loser];
    _points[winner].addAll(_points[loser]);
    _points[loser] = {};
    return winner;
  }

  /// The arity-subsets of [points], each sorted by id — the names this
  /// kind of carrier can be called by.
  Iterable<List<GeoPoint>> _subsets(List<GeoPoint> points) sync* {
    final ordered = List.of(points)..sort((a, b) => a.id.compareTo(b.id));
    if (ordered.length < kind.arity) return;
    final indices = [for (var i = 0; i < kind.arity; i++) i];
    while (true) {
      yield [for (final i in indices) ordered[i]];
      var cursor = kind.arity - 1;
      while (cursor >= 0 &&
          indices[cursor] == ordered.length - kind.arity + cursor) {
        cursor--;
      }
      if (cursor < 0) return;
      indices[cursor]++;
      for (var i = cursor + 1; i < kind.arity; i++) {
        indices[i] = indices[i - 1] + 1;
      }
    }
  }

  void _requireDistinct(List<GeoPoint> name) {
    if (name.length != kind.arity) {
      throw ArgumentError.value(
        name,
        'name',
        'a ${kind.name} is named by ${kind.arity} points, '
            'got ${name.length}',
      );
    }
    final ids = <String>{for (final point in name) point.id};
    if (ids.length != name.length) {
      throw ArgumentError.value(
        name,
        'name',
        'a ${kind.name} needs ${kind.arity} distinct points',
      );
    }
  }

  /// Ids are unique per `Construction`, and sorting them makes the key
  /// independent of the order the name was written in.
  String _key(List<GeoPoint> name) {
    final ids = [for (final point in name) point.id]..sort();
    return ids.join(' ');
  }
}
