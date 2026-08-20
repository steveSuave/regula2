import '../construction/geo_object.dart';
import 'predicate.dart';

/// A predicate reduced to the one form that stands for every way of
/// writing the same statement — the fact database's key (PLAN §M-P2).
///
/// `Predicate` deliberately compares by identity: it is a *statement*
/// applied to points in a documented argument order, and M-P1 had no
/// reason to ask when two statements are the same one. Forward chaining
/// does, on every derived conclusion: `para(a, b, c, d)` and
/// `para(d, c, b, a)` are one fact, and a database that stored them
/// separately would never reach a fixpoint — each rule would rediscover
/// the same conclusion in a new spelling forever.
///
/// **The canonical form is the least element of the statement's orbit
/// under its own symmetries**, ordered lexicographically by point [id].
/// "Its own symmetries" is the load-bearing phrase and the whole of this
/// class's difficulty: the group is different per kind, it is stated
/// per kind in [_canonicalArguments], and it is pinned against the
/// *evaluators* rather than against itself — a group element that is not
/// actually a symmetry of the predicate would merge two different
/// statements and make every proof downstream unsound, and only
/// `Predicate.holdsOn` can catch that.
///
/// Ordering by `id` makes the form deterministic and construction-order
/// independent, which is what keeps a proof reproducible; it presupposes
/// the ids being unique, which `Construction` guarantees.
class Fact {
  /// Canonicalizes [points] for [kind].
  ///
  /// Throws [ArgumentError] on the wrong number of points, the same
  /// programmer-error contract as [Predicate].
  Fact(this.kind, List<GeoPoint> points)
    : points = List.unmodifiable(_canonicalArguments(kind, points));

  /// The canonical form of [predicate]'s statement.
  Fact.of(Predicate predicate) : this(predicate.kind, predicate.points);

  final PredicateKind kind;

  /// The arguments in canonical order — a valid argument list for
  /// [kind], naming the same statement the fact was built from.
  final List<GeoPoint> points;

  /// The fact as an evaluable statement again. Numerically identical to
  /// any predicate that canonicalizes here, which is exactly what the
  /// symmetry table is tested against.
  Predicate get statement => Predicate(kind, points);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Fact || other.kind != kind) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (!identical(points[i], other.points[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([kind, ...points]);

  @override
  String toString() => '${kind.name}(${points.map((p) => p.id).join(', ')})';
}

/// The symmetry group of each kind, applied.
///
/// Every case below is a claim that the listed rewrites leave the
/// predicate's *meaning* unchanged. The claims, in the order of the
/// switch:
///
/// - **`coll`, `cyclic`** — fully symmetric. Lying on one line, or on
///   one circle, is a property of the set.
/// - **`para`, `perp`, `cong`** — a pair names an unordered segment (or
///   the line it spans), and the two pairs are interchangeable: `ab ∥ cd`
///   is `ba ∥ dc` is `cd ∥ ab`. Sorting within each pair and then
///   between them realizes exactly that group.
/// - **`midp`** — the midpoint is a distinguished role and does not move;
///   the two ends are interchangeable.
/// - **`simtri`, `contri`** — the statement is a *correspondence*
///   a↔d, b↔e, c↔f, so a permutation is a symmetry only when applied to
///   both triples at once; the two triangles are then interchangeable.
///   Both kinds are orientation-free (side ratios / SSS), so no further
///   restriction applies — if M-P2b's rules need Newclid's
///   direct/reflected split, the *predicate* splits first and this table
///   follows it.
/// - **`eqangle`, `eqratio`** — see [_matrixForms].
List<GeoPoint> _canonicalArguments(PredicateKind kind, List<GeoPoint> points) {
  if (points.length != kind.arity) {
    throw ArgumentError.value(
      points,
      'points',
      '${kind.name} takes ${kind.arity} points, got ${points.length}',
    );
  }
  return switch (kind) {
    PredicateKind.coll || PredicateKind.cyclic => _sorted(points),
    PredicateKind.para ||
    PredicateKind.perp ||
    PredicateKind.cong => _leastOf(_pairForms(points)),
    PredicateKind.midp => [points[0], ..._sorted(points.sublist(1))],
    PredicateKind.eqangle ||
    PredicateKind.eqratio => _leastOf(_matrixForms(points)),
    PredicateKind.simtri ||
    PredicateKind.contri => _leastOf(_triangleForms(points)),
  };
}

/// `ab ⋈ cd` with both segments unordered and the two interchangeable.
Iterable<List<GeoPoint>> _pairForms(List<GeoPoint> p) {
  final first = _sorted(p.sublist(0, 2));
  final second = _sorted(p.sublist(2, 4));
  return [
    [...first, ...second],
    [...second, ...first],
  ];
}

/// The eight arrangements of `[[s1, s2], [s3, s4]]`.
///
/// Both eight-point kinds relate four segments in the same shape —
/// `∠(s1, s2) = ∠(s3, s4)` and `|s1|/|s2| = |s3|/|s4|` — so they share
/// one symmetry group, and it is the dihedral group of the 2×2 matrix,
/// generated by three rewrites:
///
/// - **row swap**, the two sides of an equation commuting;
/// - **column swap**, negating both angles (`∠(s2, s1) = ∠(s4, s3)`, and
///   angles between *lines* are read mod π so the negation is exact) or
///   inverting both ratios;
/// - **transpose**, the one that is easy to miss and doubles the
///   collapse: `θ2 − θ1 ≡ θ4 − θ3` rearranges to `θ3 − θ1 ≡ θ4 − θ2`,
///   which is `∠(s1, s3) = ∠(s2, s4)`; and `s1/s2 = s3/s4` cross-
///   multiplies to `s1·s4 = s2·s3`, which is `s1/s3 = s2/s4`.
///
/// Those three generate all eight symmetries of the square, listed below
/// as cell permutations. Each segment is sorted first — that is
/// independent of the arrangement, since every element here permutes
/// whole segments.
Iterable<List<GeoPoint>> _matrixForms(List<GeoPoint> p) {
  final segments = [
    for (var i = 0; i < 8; i += 2) _sorted(p.sublist(i, i + 2)),
  ];
  const arrangements = [
    [0, 1, 2, 3], // identity
    [2, 3, 0, 1], // row swap
    [1, 0, 3, 2], // column swap
    [3, 2, 1, 0], // both — a half turn
    [0, 2, 1, 3], // transpose
    [3, 1, 2, 0], // anti-transpose
    [1, 3, 0, 2], // quarter turn
    [2, 0, 3, 1], // three-quarter turn
  ];
  return [
    for (final arrangement in arrangements)
      [for (final cell in arrangement) ...segments[cell]],
  ];
}

/// A triangle correspondence: one permutation applied to both triples,
/// and the two triangles interchangeable — twelve forms.
Iterable<List<GeoPoint>> _triangleForms(List<GeoPoint> p) {
  const permutations = [
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ];
  return [
    for (final sigma in permutations) ...[
      [for (final i in sigma) p[i], for (final i in sigma) p[i + 3]],
      [for (final i in sigma) p[i + 3], for (final i in sigma) p[i]],
    ],
  ];
}

List<GeoPoint> _sorted(List<GeoPoint> points) =>
    List.of(points)..sort((a, b) => a.id.compareTo(b.id));

/// Lexicographically least by point id. [forms] is never empty.
List<GeoPoint> _leastOf(Iterable<List<GeoPoint>> forms) {
  late List<GeoPoint> best;
  var seen = false;
  for (final form in forms) {
    if (!seen || _compareIds(form, best) < 0) {
      best = form;
      seen = true;
    }
  }
  return best;
}

int _compareIds(List<GeoPoint> a, List<GeoPoint> b) {
  for (var i = 0; i < a.length; i++) {
    final order = a[i].id.compareTo(b[i].id);
    if (order != 0) {
      return order;
    }
  }
  return 0;
}
