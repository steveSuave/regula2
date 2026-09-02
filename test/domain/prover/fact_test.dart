import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/predicate.dart';

/// Ids in alphabetical order, so a canonical form is easy to read off by
/// eye and the sort has something to do.
const _ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// A configuration in which the kind's predicate is **true**, given in
/// the kind's documented argument order.
///
/// The orbit tests need truth, not just agreement: a rewrite that is not
/// a symmetry generically evaluates false, so it is a true rig that
/// separates the real symmetries from the plausible ones.
const Map<PredicateKind, List<(double, double)>> _trueRigs = {
  // Three points on the x-axis.
  PredicateKind.coll: [(0, 0), (2, 0), (5, 0)],
  // ab and cd both horizontal, four distinct points.
  PredicateKind.para: [(0, 0), (2, 0), (1, 3), (4, 3)],
  // ab horizontal, cd vertical, four distinct points.
  PredicateKind.perp: [(0, 0), (2, 0), (5, 1), (5, 6)],
  // |ab| = |cd| = 3.
  PredicateKind.cong: [(0, 0), (3, 0), (1, 4), (1, 7)],
  // Four points of the unit circle.
  PredicateKind.cyclic: [(1, 0), (0, 1), (-1, 0), (0, -1)],
  // ∠(ab, cd) = 45° = ∠(ef, gh): directions 0°, 45°, 90°, 135°.
  PredicateKind.eqangle: [
    (0, 0),
    (2, 0),
    (0, 1),
    (1, 2),
    (3, 0),
    (3, 2),
    (5, 0),
    (4, 1),
  ],
  // 2 / 1 = 6 / 3.
  PredicateKind.eqratio: [
    (0, 0),
    (2, 0),
    (0, 5),
    (1, 5),
    (0, 10),
    (6, 10),
    (0, 15),
    (3, 15),
  ],
  // m is the midpoint of ab.
  PredicateKind.midp: [(1, 0), (0, 0), (2, 0)],
  // A 3-4-5 triangle and its double, in correspondence.
  PredicateKind.simtri: [(0, 0), (3, 0), (0, 4), (10, 0), (16, 0), (10, 8)],
  // The same triangle, translated.
  PredicateKind.contri: [(0, 0), (3, 0), (0, 4), (10, 1), (13, 1), (10, 5)],
  // ∠(ab, cd) = 45°: ab horizontal, cd at 45°, stated value 1/4 of π.
  PredicateKind.aconst: [(0, 0), (2, 0), (0, 1), (1, 2)],
  // |ab| / |cd| = 2 / 1, at the stated value 2.
  PredicateKind.rconst: [(0, 0), (2, 0), (1, 4), (1, 5)],
  // |ab| = 3, at the stated value 3.
  PredicateKind.lconst: [(0, 0), (3, 0)],
};

/// The stated value each value-carrying rig is true at.
final Map<PredicateKind, Rational> _rigValues = {
  PredicateKind.aconst: Rational.fromInts(1, 4),
  PredicateKind.rconst: Rational.fromInts(2, 1),
  PredicateKind.lconst: Rational.fromInts(3, 1),
};

/// Every rewrite of the argument list that names the same statement, as
/// index permutations — written out here independently of the
/// implementation's own table, which is the point.
List<List<int>> _orbit(PredicateKind kind) => switch (kind) {
  // Fully symmetric: a set of points on one line, or on one circle.
  PredicateKind.coll => _permutations([0, 1, 2]),
  PredicateKind.cyclic => _permutations([0, 1, 2, 3]),
  // Unordered segments, interchangeable.
  PredicateKind.para || PredicateKind.perp || PredicateKind.cong => [
    for (final first in const [
      [0, 1],
      [1, 0],
    ])
      for (final second in const [
        [2, 3],
        [3, 2],
      ]) ...[
        [...first, ...second],
        [...second, ...first],
      ],
  ],
  // The midpoint is a role; the ends are not.
  PredicateKind.midp => const [
    [0, 1, 2],
    [0, 2, 1],
  ],
  // The eight arrangements of the 2x2 matrix of segments, times the
  // four segment reversals.
  PredicateKind.eqangle || PredicateKind.eqratio => [
    for (final arrangement in const [
      [0, 1, 2, 3], // identity
      [2, 3, 0, 1], // row swap: the sides of an equation commute
      [1, 0, 3, 2], // column swap: negate both angles / invert both ratios
      [3, 2, 1, 0], // half turn
      [0, 2, 1, 3], // transpose
      [3, 1, 2, 0], // anti-transpose
      [1, 3, 0, 2], // quarter turn
      [2, 0, 3, 1], // three-quarter turn
    ])
      for (final reversals in _reversalMasks)
        [
          for (var cell = 0; cell < 4; cell++)
            ...() {
              final segment = arrangement[cell];
              final head = segment * 2;
              return reversals[cell] ? [head + 1, head] : [head, head + 1];
            }(),
        ],
  ],
  // One permutation applied to both triples, and the triangles swapped.
  PredicateKind.simtri || PredicateKind.contri => [
    for (final sigma in _permutations([0, 1, 2])) ...[
      [...sigma, for (final i in sigma) i + 3],
      [for (final i in sigma) i + 3, ...sigma],
    ],
  ],
  // The **value-preserving** forms only: rconst's pair swap inverts its
  // value and aconst's negates it mod 1, rewrites no index permutation
  // expresses — the value-carrying kinds' own group below tests the
  // value-coupled symmetry directly.
  PredicateKind.aconst || PredicateKind.rconst => const [
    [0, 1, 2, 3],
    [1, 0, 2, 3],
    [0, 1, 3, 2],
    [1, 0, 3, 2],
  ],
  PredicateKind.lconst => const [
    [0, 1],
    [1, 0],
  ],
};

/// The sixteen ways to reverse a subset of four segments.
final List<List<bool>> _reversalMasks = [
  for (var mask = 0; mask < 16; mask++)
    [for (var bit = 0; bit < 4; bit++) mask & (1 << bit) != 0],
];

List<List<int>> _permutations(List<int> items) {
  if (items.length <= 1) {
    return [List.of(items)];
  }
  return [
    for (var i = 0; i < items.length; i++)
      for (final rest in _permutations([...items]..removeAt(i)))
        [items[i], ...rest],
  ];
}

void main() {
  List<FreePoint> pointsAt(List<(double, double)> positions) => [
    for (var i = 0; i < positions.length; i++)
      FreePoint(id: _ids[i], position: Vec2(positions[i].$1, positions[i].$2)),
  ];

  List<FreePoint> rigFor(PredicateKind kind) => pointsAt(_trueRigs[kind]!);

  List<FreePoint> reorder(List<FreePoint> points, List<int> form) => [
    for (final i in form) points[i],
  ];

  // The generic sweeps below run over every kind, so they hand a
  // value-carrying kind its rig value; a rewrite from the (value-
  // preserving) [_orbit] table never changes it.
  Fact factOf(PredicateKind kind, List<GeoPoint> points) =>
      Fact(kind, points, value: _rigValues[kind]);
  Predicate predicateOf(PredicateKind kind, List<GeoPoint> points) =>
      Predicate(kind, points, value: _rigValues[kind]);

  test('arity is enforced, the Predicate contract', () {
    final a = FreePoint(id: 'a', position: Vec2.zero);
    expect(() => Fact(PredicateKind.coll, [a, a]), throwsArgumentError);
    expect(
      () => Fact(PredicateKind.eqangle, [a, a, a, a]),
      throwsArgumentError,
    );
  });

  test('every rig is what it claims: the predicate holds as written', () {
    for (final kind in PredicateKind.values) {
      final rig = rigFor(kind);
      expect(rig.length, kind.arity, reason: '${kind.name} rig arity');
      expect(
        predicateOf(kind, rig).holdsNow,
        isTrue,
        reason: '${kind.name} rig should hold',
      );
    }
  });

  group('the orbit collapses to one fact', () {
    for (final kind in PredicateKind.values) {
      test(kind.name, () {
        final rig = rigFor(kind);
        final canonical = factOf(kind, rig);
        for (final form in _orbit(kind)) {
          expect(
            factOf(kind, reorder(rig, form)),
            canonical,
            reason: '${kind.name} form $form',
          );
        }
      });
    }
  });

  group('the orbit is numerically one statement', () {
    // The soundness pin. Keying two statements alike is only correct if
    // they *are* the same statement, and the canonicalizer cannot be
    // asked about that — only the evaluators can. Each form is checked
    // against the true rig under random similarities (which preserve
    // every predicate in the vocabulary, applied to all points at once)
    // and against a broken rig, so both answers are exercised.
    final rng = math.Random(1729);

    // `lconst` is deliberately absent from the similarity sweep: a
    // stated length is the vocabulary's one non-scale-invariant
    // statement, and its own group below pins exactly that.
    for (final kind in PredicateKind.values.where(
      (kind) => kind != PredicateKind.lconst,
    )) {
      test(kind.name, () {
        final base = _trueRigs[kind]!;
        for (var trial = 0; trial < 24; trial++) {
          final angle = rng.nextDouble() * 2 * math.pi;
          final scale = 0.2 + rng.nextDouble() * 4;
          final dx = (rng.nextDouble() - 0.5) * 20;
          final dy = (rng.nextDouble() - 0.5) * 20;
          final moved = [
            for (final (x, y) in base)
              (
                scale * (x * math.cos(angle) - y * math.sin(angle)) + dx,
                scale * (x * math.sin(angle) + y * math.cos(angle)) + dy,
              ),
          ];
          final points = pointsAt(moved);
          for (final form in _orbit(kind)) {
            expect(
              predicateOf(kind, reorder(points, form)).holdsNow,
              isTrue,
              reason: '${kind.name} form $form, trial $trial',
            );
          }
        }

        // And false stays false: nudging the last point off the rig
        // breaks every form, not just the one it was written in.
        final broken = pointsAt([
          ...base.sublist(0, base.length - 1),
          (base.last.$1 + 0.7, base.last.$2 - 0.4),
        ]);
        expect(predicateOf(kind, broken).holdsNow, isFalse);
        for (final form in _orbit(kind)) {
          expect(
            predicateOf(kind, reorder(broken, form)).holdsNow,
            isFalse,
            reason: '${kind.name} broken form $form',
          );
        }
      });
    }
  });

  test('canonicalization is idempotent', () {
    for (final kind in PredicateKind.values) {
      final rig = rigFor(kind);
      for (final form in _orbit(kind)) {
        final once = factOf(kind, reorder(rig, form));
        expect(Fact(kind, once.points, value: once.value).points, once.points);
        expect(Fact.of(once.statement), once);
      }
    }
  });

  group('a rewrite outside the orbit is a different fact', () {
    // The other half of soundness: the group must not be everything.
    // Each of these is a rewrite that reads plausible and is not a
    // symmetry, so it must key differently *and* evaluate differently
    // on the rig.
    const outside = {
      // Swapping across the two pairs is not a segment symmetry.
      PredicateKind.para: [0, 2, 1, 3],
      PredicateKind.perp: [0, 2, 1, 3],
      PredicateKind.cong: [0, 2, 1, 3],
      // An end promoted to the midpoint role.
      PredicateKind.midp: [1, 0, 2],
      // Reversing *one* angle: the negation has to happen on both sides.
      PredicateKind.eqangle: [2, 3, 0, 1, 4, 5, 6, 7],
      // Inverting *one* ratio, likewise.
      PredicateKind.eqratio: [2, 3, 0, 1, 4, 5, 6, 7],
      // Permuting one triple breaks the correspondence.
      PredicateKind.simtri: [0, 1, 2, 4, 3, 5],
      PredicateKind.contri: [0, 1, 2, 4, 3, 5],
    };

    for (final entry in outside.entries) {
      test(entry.key.name, () {
        final rig = rigFor(entry.key);
        final rewritten = reorder(rig, entry.value);
        expect(Fact(entry.key, rewritten), isNot(Fact(entry.key, rig)));
        expect(Predicate(entry.key, rewritten).holdsNow, isFalse);
      });
    }
  });

  test('a Set of facts is the database: equal facts hash alike', () {
    final rig = rigFor(PredicateKind.para);
    final facts = <Fact>{
      for (final form in _orbit(PredicateKind.para))
        Fact(PredicateKind.para, reorder(rig, form)),
    };
    expect(facts, hasLength(1));
    expect(facts.first.points.map((p) => p.id), ['a', 'b', 'c', 'd']);
  });

  test('different kinds over the same points are different facts', () {
    final rig = rigFor(PredicateKind.para);
    expect(Fact(PredicateKind.para, rig), isNot(Fact(PredicateKind.cong, rig)));
  });

  test('the canonical form is by id, not by construction order', () {
    // Two points built in the opposite order still key the same way,
    // which is what keeps a proof reproducible across sessions.
    final z = FreePoint(id: 'z', position: Vec2(1, 1));
    final a = FreePoint(id: 'a', position: Vec2(0, 0));
    final m = FreePoint(id: 'm', position: Vec2(0.5, 0.5));
    expect(Fact(PredicateKind.midp, [m, z, a]).points.map((p) => p.id), [
      'm',
      'a',
      'z',
    ]);
  });

  test('two points with the same id are still two points', () {
    // The sort orders by id and the equality is by identity, so a
    // duplicated id degrades ordering but never merges the points.
    final first = FreePoint(id: 'a', position: Vec2.zero);
    final second = FreePoint(id: 'a', position: Vec2(1, 0));
    final c = FreePoint(id: 'c', position: Vec2(2, 0));
    expect(
      Fact(PredicateKind.coll, [first, second, c]),
      isNot(Fact(PredicateKind.coll, [first, first, c])),
    );
  });

  group('orbitArguments — the matcher-facing full orbit', () {
    const sizes = {
      PredicateKind.coll: 6,
      PredicateKind.cyclic: 24,
      PredicateKind.para: 8,
      PredicateKind.perp: 8,
      PredicateKind.cong: 8,
      PredicateKind.midp: 2,
      PredicateKind.eqangle: 128,
      PredicateKind.eqratio: 128,
      PredicateKind.simtri: 12,
      PredicateKind.contri: 12,
      // Value-preserving forms only — the value-coupled symmetry cannot
      // be a point permutation. See the value-carrying group.
      PredicateKind.aconst: 4,
      PredicateKind.rconst: 4,
      PredicateKind.lconst: 2,
    };

    test('the orbit sizes are the groups\' orders', () {
      for (final kind in PredicateKind.values) {
        expect(
          orbitArguments(kind, rigFor(kind)).length,
          sizes[kind],
          reason: kind.name,
        );
      }
    });

    test('every form keys to the same fact and evaluates true', () {
      for (final kind in PredicateKind.values) {
        final rig = rigFor(kind);
        final fact = factOf(kind, rig);
        for (final form in orbitArguments(kind, rig)) {
          expect(factOf(kind, form), fact, reason: '$kind $form');
          expect(
            predicateOf(kind, form).holdsNow,
            isTrue,
            reason: '${kind.name} orbit form must be the same statement',
          );
        }
      }
    });

    test('the canonical form is the least element of the full orbit', () {
      // The canonicalizer enumerates a reduced set (segments pre-sorted);
      // this pins that reduction against the full orbit the matcher
      // sees, so the two can never disagree about which spelling is
      // canonical. `rconst` and `aconst` are the exclusions: their full
      // orbits are value-coupled, so `orbitArguments` lists only the
      // value-preserving half and the least element can live in the
      // other.
      String key(List<GeoPoint> form) => form.map((p) => p.id).join(',');
      final random = math.Random(7);
      for (final kind in PredicateKind.values.where(
        (kind) => kind != PredicateKind.rconst && kind != PredicateKind.aconst,
      )) {
        final rig = rigFor(kind);
        for (var round = 0; round < 5; round++) {
          final tuple = List<GeoPoint>.of(rig)..shuffle(random);
          final least = orbitArguments(
            kind,
            tuple,
          ).map(key).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
          expect(key(factOf(kind, tuple).points), least, reason: kind.name);
        }
      }
    });
  });

  group('the value-carrying kinds — the value is part of the identity', () {
    Rational q(int n, [int d = 1]) => Rational.fromInts(n, d);

    test('the value contract is enforced, both ways and positive', () {
      final rig = rigFor(PredicateKind.rconst);
      expect(() => Fact(PredicateKind.rconst, rig), throwsArgumentError);
      expect(
        () => Fact(PredicateKind.cong, rig, value: q(2)),
        throwsArgumentError,
      );
      expect(
        () => Fact(PredicateKind.rconst, rig, value: Rational.zero),
        throwsArgumentError,
      );
      expect(
        () => Fact(PredicateKind.rconst, rig, value: q(-2)),
        throwsArgumentError,
      );
    });

    test('different values over the same points are different facts', () {
      final rig = rigFor(PredicateKind.rconst);
      final atTwo = Fact(PredicateKind.rconst, rig, value: q(2));
      expect(atTwo, isNot(Fact(PredicateKind.rconst, rig, value: q(3))));
      expect({atTwo, Fact(PredicateKind.rconst, rig, value: q(2))}.length, 1);
    });

    test('rconst\'s pair swap inverts the value — one fact, and '
        'numerically one statement', () {
      final rig = rigFor(PredicateKind.rconst);
      final swapped = [rig[2], rig[3], rig[0], rig[1]];
      expect(
        Fact(PredicateKind.rconst, swapped, value: q(1, 2)),
        Fact(PredicateKind.rconst, rig, value: q(2)),
      );
      expect(
        Predicate(PredicateKind.rconst, swapped, value: q(1, 2)).holdsNow,
        isTrue,
      );
      // And the swap *without* the inversion is a different, false
      // statement — the rewrite that must not be keyed as a symmetry.
      expect(
        Fact(PredicateKind.rconst, swapped, value: q(2)),
        isNot(Fact(PredicateKind.rconst, rig, value: q(2))),
      );
      expect(
        Predicate(PredicateKind.rconst, swapped, value: q(2)).holdsNow,
        isFalse,
      );
    });

    test('the same segment twice ties on points and the value breaks '
        'it', () {
      final rig = rigFor(PredicateKind.rconst);
      final twice = [rig[0], rig[1], rig[0], rig[1]];
      expect(
        Fact(PredicateKind.rconst, twice, value: q(2)),
        Fact(PredicateKind.rconst, twice, value: q(1, 2)),
      );
    });

    test('aconst\'s value is a residue mod 1, and the range is '
        'enforced', () {
      final rig = rigFor(PredicateKind.aconst);
      expect(
        () => Fact(PredicateKind.aconst, rig, value: q(1)),
        throwsArgumentError,
      );
      expect(
        () => Fact(PredicateKind.aconst, rig, value: q(-1, 4)),
        throwsArgumentError,
      );
      expect(
        () => Fact(PredicateKind.aconst, rig, value: q(5, 4)),
        throwsArgumentError,
      );
      // Zero is a residue like any other — the plainer spelling is
      // `para`, but that precedence is the translator's, not the kind's.
      expect(
        Fact(PredicateKind.aconst, rig, value: Rational.zero).value,
        Rational.zero,
      );
    });

    test('aconst\'s pair swap negates the value mod 1 — one fact, and '
        'numerically one statement', () {
      final rig = rigFor(PredicateKind.aconst);
      final swapped = [rig[2], rig[3], rig[0], rig[1]];
      // ∠(ab → cd) = π/4, so ∠(cd → ab) = 3π/4.
      expect(
        Fact(PredicateKind.aconst, swapped, value: q(3, 4)),
        Fact(PredicateKind.aconst, rig, value: q(1, 4)),
      );
      expect(
        Predicate(PredicateKind.aconst, swapped, value: q(3, 4)).holdsNow,
        isTrue,
      );
      // And the swap *without* the negation is a different, false
      // statement — the rewrite that must not be keyed as a symmetry.
      expect(
        Fact(PredicateKind.aconst, swapped, value: q(1, 4)),
        isNot(Fact(PredicateKind.aconst, rig, value: q(1, 4))),
      );
      expect(
        Predicate(PredicateKind.aconst, swapped, value: q(1, 4)).holdsNow,
        isFalse,
      );
    });

    test('aconst\'s fixed points survive the swap unchanged', () {
      // Negation mod 1 fixes 0 and ½ — a right angle spelled from
      // either side is one fact at one value.
      final rig = rigFor(PredicateKind.perp);
      final swapped = [rig[2], rig[3], rig[0], rig[1]];
      final half = Rational.fromInts(1, 2);
      expect(
        Fact(PredicateKind.aconst, swapped, value: half),
        Fact(PredicateKind.aconst, rig, value: half),
      );
      expect(
        Predicate(PredicateKind.aconst, rig, value: half).holdsNow,
        isTrue,
      );
      expect(
        Predicate(PredicateKind.aconst, swapped, value: half).holdsNow,
        isTrue,
      );
    });

    test('lconst sorts its pair and keeps its value', () {
      final rig = rigFor(PredicateKind.lconst);
      final fact = Fact(PredicateKind.lconst, [rig[1], rig[0]], value: q(3));
      expect(fact.points.map((p) => p.id), ['a', 'b']);
      expect(fact.value, q(3));
      expect(fact, Fact(PredicateKind.lconst, rig, value: q(3)));
    });

    test('a stated length is the one non-scale-invariant statement', () {
      // Rotation and translation preserve it; scaling genuinely changes
      // its truth, which is why the similarity sweep above excludes it —
      // and why `rconst`, a ratio, is not excluded.
      final rig = _trueRigs[PredicateKind.lconst]!;
      final rotated = pointsAt([for (final (x, y) in rig) (-y + 5, x - 2)]);
      expect(
        Predicate(PredicateKind.lconst, rotated, value: q(3)).holdsNow,
        isTrue,
      );
      final scaled = pointsAt([for (final (x, y) in rig) (2 * x, 2 * y)]);
      expect(
        Predicate(PredicateKind.lconst, scaled, value: q(3)).holdsNow,
        isFalse,
      );
      expect(
        Predicate(PredicateKind.lconst, scaled, value: q(6)).holdsNow,
        isTrue,
      );
      final rconstRig = _trueRigs[PredicateKind.rconst]!;
      final rconstScaled = pointsAt([
        for (final (x, y) in rconstRig) (2 * x, 2 * y),
      ]);
      expect(
        Predicate(PredicateKind.rconst, rconstScaled, value: q(2)).holdsNow,
        isTrue,
      );
    });

    test('the value survives the round trip through statement', () {
      final fact = Fact(
        PredicateKind.rconst,
        rigFor(PredicateKind.rconst),
        value: q(2),
      );
      expect(fact.statement.value, fact.value);
      expect(Fact.of(fact.statement), fact);
      expect('$fact', 'rconst(a, b, c, d; 2)');
    });
  });
}
