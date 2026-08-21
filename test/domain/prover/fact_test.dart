import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
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
        Predicate(kind, rig).holdsNow,
        isTrue,
        reason: '${kind.name} rig should hold',
      );
    }
  });

  group('the orbit collapses to one fact', () {
    for (final kind in PredicateKind.values) {
      test(kind.name, () {
        final rig = rigFor(kind);
        final canonical = Fact(kind, rig);
        for (final form in _orbit(kind)) {
          expect(
            Fact(kind, reorder(rig, form)),
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

    for (final kind in PredicateKind.values) {
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
              Predicate(kind, reorder(points, form)).holdsNow,
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
        expect(Predicate(kind, broken).holdsNow, isFalse);
        for (final form in _orbit(kind)) {
          expect(
            Predicate(kind, reorder(broken, form)).holdsNow,
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
        final once = Fact(kind, reorder(rig, form));
        expect(Fact(kind, once.points).points, once.points);
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
}
