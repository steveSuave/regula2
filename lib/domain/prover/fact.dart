import '../construction/geo_object.dart';
import 'predicate.dart';
import 'rational.dart';

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
  /// Canonicalizes [points] — and, for a value-carrying kind whose
  /// symmetry moves its value, [value] with them: `rconst`'s pair swap
  /// inverts the ratio, so `rconst(a,b,c,d; q)` and `rconst(c,d,a,b; 1/q)`
  /// land on one form; `aconst`'s pair swap negates the angle mod 1, so
  /// `aconst(a,b,c,d; r)` and `aconst(c,d,a,b; 1−r)` do.
  ///
  /// Throws [ArgumentError] on the wrong number of points or a value
  /// whose presence or range does not match the kind, the same
  /// programmer-error contract as [Predicate] (which the delegated
  /// construction below enforces).
  factory Fact(PredicateKind kind, List<GeoPoint> points, {Rational? value}) {
    // Predicate owns the arity/value contract; building one applies it.
    Predicate(kind, points, value: value);
    if (kind == PredicateKind.rconst || kind == PredicateKind.aconst) {
      final (canonical, kept) = _canonicalValueCoupled(kind, points, value!);
      return Fact._(kind, List.unmodifiable(canonical), kept);
    }
    return Fact._(
      kind,
      List.unmodifiable(_canonicalArguments(kind, points)),
      value,
    );
  }

  /// The canonical form of [predicate]'s statement.
  factory Fact.of(Predicate predicate) =>
      Fact(predicate.kind, predicate.points, value: predicate.value);

  Fact._(this.kind, this.points, this.value);

  final PredicateKind kind;

  /// The arguments in canonical order — a valid argument list for
  /// [kind], naming the same statement the fact was built from.
  final List<GeoPoint> points;

  /// The stated value, canonicalized with [points] — non-null exactly
  /// for a [PredicateKind.carriesValue] kind, and part of the fact's
  /// identity: `rconst` at 2 and at 3 are different facts.
  final Rational? value;

  /// The fact as an evaluable statement again. Numerically identical to
  /// any predicate that canonicalizes here, which is exactly what the
  /// symmetry table is tested against.
  Predicate get statement => Predicate(kind, points, value: value);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Fact || other.kind != kind || other.value != value) {
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
  int get hashCode => Object.hashAll([kind, value, ...points]);

  @override
  String toString() =>
      '${kind.name}(${points.map((p) => p.id).join(', ')}'
      '${value == null ? '' : '; $value'})';
}

/// The canonical spelling of the two kinds whose pair swap transforms
/// the value: both pairs sorted within, then the lexicographically
/// lesser pair order — **transforming the value when the swap wins**.
/// `rconst`'s swap inverts (`|s1|/|s2| = q` and `|s2|/|s1| = 1/q` are
/// one statement); `aconst`'s negates mod 1 (the angle from l₂ to l₁ is
/// the angle from l₁ to l₂ taken backwards). When the two orders tie
/// (the same pair twice), the lesser value breaks the tie, so
/// `rconst(s,s; q)` / `rconst(s,s; 1/q)` — and `aconst`'s fixed points
/// 0 and ½, where negation returns the value itself — still land on one
/// form.
(List<GeoPoint>, Rational) _canonicalValueCoupled(
  PredicateKind kind,
  List<GeoPoint> points,
  Rational value,
) {
  final first = _sorted(points.sublist(0, 2));
  final second = _sorted(points.sublist(2, 4));
  final kept = [...first, ...second];
  final swapped = [...second, ...first];
  final transformed = kind == PredicateKind.rconst
      ? Rational.one / value
      : (-value).modOne();
  final order = _compareIds(swapped, kept);
  if (order < 0 || (order == 0 && transformed.compareTo(value) < 0)) {
    return (swapped, transformed);
  }
  return (kept, value);
}

/// Every argument order that names the same statement as [points] under
/// [kind]'s symmetry group — the **full** orbit, within-segment swaps
/// included, unlike the canonicalizer's internal enumeration (which
/// sorts within segments first because it only needs the least element).
///
/// The consumer is M-P2b's rule matcher: a stored fact is one canonical
/// spelling, and a rule premise must be allowed to bind any spelling —
/// `cong(o,a,o,b)`'s pattern requires slot 1 and slot 3 to be the same
/// point, which the canonical order may well have sorted away. Orbit
/// sizes: 6 (`coll`), 24 (`cyclic`), 8 (`para`/`perp`/`cong`), 2
/// (`midp`), 12 (`simtri`/`contri`), 128 (`eqangle`/`eqratio` — the
/// eight arrangements times sixteen within-segment swaps).
///
/// Forms may repeat when [points] repeats; the matcher deduplicates by
/// what it binds, not by form. Throws [ArgumentError] on the wrong
/// number of points, like [Fact].
List<List<GeoPoint>> orbitArguments(PredicateKind kind, List<GeoPoint> points) {
  if (points.length != kind.arity) {
    throw ArgumentError.value(
      points,
      'points',
      '${kind.name} takes ${kind.arity} points, got ${points.length}',
    );
  }
  return switch (kind) {
    PredicateKind.coll || PredicateKind.cyclic => _permutations(points),
    PredicateKind.para ||
    PredicateKind.perp ||
    PredicateKind.cong => _segmentOrbit(points, const [
      [0, 1],
      [1, 0],
    ]),
    PredicateKind.midp => [
      points,
      [points[0], points[2], points[1]],
    ],
    PredicateKind.eqangle || PredicateKind.eqratio => _segmentOrbit(
      points,
      const [
        [0, 1, 2, 3],
        [2, 3, 0, 1],
        [1, 0, 3, 2],
        [3, 2, 1, 0],
        [0, 2, 1, 3],
        [3, 1, 2, 0],
        [1, 3, 0, 2],
        [2, 0, 3, 1],
      ],
    ),
    PredicateKind.simtri ||
    PredicateKind.contri => [for (final form in _triangleForms(points)) form],
    // The value-carrying kinds list their **value-preserving** forms
    // only: rconst's and aconst's pair swaps transform the value, which
    // a point list cannot express. No rule matches these kinds (PLAN
    // §"The constants stack"), so the matcher never binds them; the
    // forms here exist for the contract's sake and are honest as far as
    // they go.
    PredicateKind.aconst || PredicateKind.rconst => _segmentOrbit(
      points,
      const [
        [0, 1],
      ],
    ),
    PredicateKind.lconst => [
      points,
      [points[1], points[0]],
    ],
  };
}

/// Segment arrangements crossed with every within-segment swap: the
/// pair points of each two-point segment commute independently of how
/// the segments are arranged.
List<List<GeoPoint>> _segmentOrbit(
  List<GeoPoint> points,
  List<List<int>> arrangements,
) {
  final segmentCount = points.length ~/ 2;
  final out = <List<GeoPoint>>[];
  for (final arrangement in arrangements) {
    for (var swaps = 0; swaps < (1 << segmentCount); swaps++) {
      out.add([
        for (var cell = 0; cell < segmentCount; cell++)
          ...() {
            final segment = arrangement[cell];
            final a = points[2 * segment];
            final b = points[2 * segment + 1];
            return (swaps >> cell) & 1 == 0 ? [a, b] : [b, a];
          }(),
      ]);
    }
  }
  return out;
}

List<List<GeoPoint>> _permutations(List<GeoPoint> points) {
  if (points.length <= 1) return [points];
  final out = <List<GeoPoint>>[];
  for (var i = 0; i < points.length; i++) {
    final rest = [...points.sublist(0, i), ...points.sublist(i + 1)];
    for (final tail in _permutations(rest)) {
      out.add([points[i], ...tail]);
    }
  }
  return out;
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
/// - **`lconst`** — one unordered segment; the value rides along
///   unchanged. `rconst` and `aconst` are the kinds whose symmetries
///   move their values and are canonicalized in [Fact]'s factory, not
///   here.
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
    // `lconst` names one unordered segment; `rconst` and `aconst` never
    // reach this switch — their pair swaps move the value too, so
    // [Fact]'s factory canonicalizes them through
    // [_canonicalValueCoupled] instead.
    PredicateKind.lconst => _sorted(points),
    PredicateKind.aconst || PredicateKind.rconst => throw StateError(
      '${kind.name} canonicalizes with its value',
    ),
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
