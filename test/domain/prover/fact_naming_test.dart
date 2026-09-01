import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_naming.dart';
import 'package:regula/domain/prover/predicate.dart';

/// Phase 157: `readFact`, the prose renderer beside `describeFact`.
///
/// The expectations below are written against the *canonical* argument
/// order — `Fact` reorders its points on construction — so every rig
/// uses ids already in canonical position (alphabetical, identity
/// arrangement least). A rig whose canonical form surprised the test
/// would be testing the canonicalizer, which `fact_test.dart` owns.
void main() {
  FreePoint point(String id, {String name = ''}) => FreePoint(
    id: id,
    position: Vec2.zero,
    attributes: ObjectAttributes(name: name),
  );

  List<FreePoint> points(String ids) => [
    for (final id in ids.split('')) point(id),
  ];

  group('predicateKindLabel', () {
    // Phase 158: the display-name table over the closed enum. Pinned
    // string by string because these are headings a user reads, and in
    // declaration order because that order is what a grouped list
    // renders in.
    test('every kind, by name, in declaration order', () {
      expect(PredicateKind.values.map(predicateKindLabel), [
        'Collinear points',
        'Parallel lines',
        'Perpendicular lines',
        'Equal lengths',
        'Concyclic points',
        'Equal angles',
        'Equal ratios',
        'Midpoints',
        'Similar triangles',
        'Congruent triangles',
        'Stated angles',
        'Stated ratios',
        'Stated lengths',
      ]);
    });

    test('labels are distinct — two kinds under one heading would merge', () {
      final labels = PredicateKind.values.map(predicateKindLabel).toSet();
      expect(labels.length, PredicateKind.values.length);
    });
  });

  group('readFact, one honest reading per kind', () {
    test('coll — a list, not a segment', () {
      final fact = Fact(PredicateKind.coll, points('abc'));
      expect(readFact(fact), 'a, b, c are collinear');
    });

    test('para', () {
      final fact = Fact(PredicateKind.para, points('abcd'));
      expect(readFact(fact), 'ab is parallel to cd');
    });

    test('perp', () {
      final fact = Fact(PredicateKind.perp, points('abcd'));
      expect(readFact(fact), 'ab is perpendicular to cd');
    });

    test('cong — equal in length, never "=", which reads as coinciding '
        'points', () {
      final fact = Fact(PredicateKind.cong, points('abcd'));
      expect(readFact(fact), 'ab and cd are equal in length');
      expect(readFact(fact), isNot(contains('=')));
    });

    test('cyclic', () {
      final fact = Fact(PredicateKind.cyclic, points('abcd'));
      expect(readFact(fact), 'a, b, c, d lie on a circle');
    });

    test('midp — the midpoint keeps its role', () {
      final fact = Fact(PredicateKind.midp, points('mab'));
      expect(readFact(fact), 'm is the midpoint of ab');
    });

    test('eqratio', () {
      final fact = Fact(PredicateKind.eqratio, points('abcdefgh'));
      expect(readFact(fact), 'ab : cd = ef : gh');
    });

    test('simtri — vertex order is the correspondence, preserved', () {
      final fact = Fact(PredicateKind.simtri, points('abcdef'));
      expect(readFact(fact), 'triangles abc and def are similar');
    });

    test('contri', () {
      final fact = Fact(PredicateKind.contri, points('abcdef'));
      expect(readFact(fact), 'triangles abc and def are congruent');
    });
  });

  group('eqangle, the kind that can lie', () {
    test('shared vertex on both pairs spells three-point angles', () {
      final [a, b, c] = points('abc');
      final [d, e, f] = points('def');
      final fact = Fact(PredicateKind.eqangle, [a, b, b, c, d, e, e, f]);
      expect(readFact(fact), 'angles abc and def are equal');
    });

    test('no shared vertex spells the lines — a three-point name would '
        'invent a point', () {
      final fact = Fact(PredicateKind.eqangle, points('abcdefgh'));
      expect(
        readFact(fact),
        'the angle from ab to cd equals the angle from ef to gh',
      );
    });

    test('the shapes are detected per pair, so a mixed fact mixes', () {
      final [a, b, c] = points('abc');
      final [d, e, f, g] = points('defg');
      final fact = Fact(PredicateKind.eqangle, [a, b, b, c, d, e, f, g]);
      expect(readFact(fact), 'angle abc equals the angle from de to fg');
    });

    test('a pair sharing both points is one line twice, not an angle', () {
      final [a, b] = points('ab');
      final [d, e, f] = points('def');
      final fact = Fact(PredicateKind.eqangle, [a, b, a, b, d, e, e, f]);
      expect(readFact(fact), 'the angle from ab to ab equals angle def');
    });

    test('the vertex is found wherever canonicalization put it', () {
      // b–a and a–c share a at the *first* slot of each segment; the
      // canonical form keeps a there (segments sort to (a,b), (a,c)),
      // so the vertex is not in the middle of the stored tuple — the
      // reading still puts it in the middle of the name.
      final [a, b, c] = points('abc');
      final [d, e, f] = points('def');
      final fact = Fact(PredicateKind.eqangle, [b, a, a, c, e, d, d, f]);
      expect(readFact(fact), 'angles bac and edf are equal');
    });
  });

  group('readPredicate reads as spelled (Phase 162)', () {
    test('a question keeps its spelling; a fact reads its orbit', () {
      FreePoint named(String id, String name) => FreePoint(
        id: id,
        position: Vec2.zero,
        attributes: ObjectAttributes(name: name),
      );
      final b = named('b', 'B');
      final c = named('c', 'C');
      final d = named('d', 'D');
      final e = named('e', 'E');
      // ∠(BC, CE) = ∠(BD, DC): the tangent–chord theorem's own spelling.
      final asked = Predicate(PredicateKind.eqangle, [b, c, c, e, b, d, d, c]);
      expect(readPredicate(asked), 'angles BCE and BDC are equal');
      // Its transpose is the same fact and a different sentence.
      final transposed = Predicate(PredicateKind.eqangle, [
        b,
        c,
        b,
        d,
        c,
        e,
        d,
        c,
      ]);
      expect(Fact.of(transposed), Fact.of(asked));
      expect(readPredicate(transposed), 'angles CBD and ECD are equal');
      // readFact is readPredicate of the canonical spelling — one
      // implementation, and the fact side has not moved.
      final fact = Fact.of(asked);
      expect(readFact(fact), readPredicate(fact.statement));
    });
  });

  group('the separator rule, taken from the chase and not re-invented', () {
    test('one multi-character name switches the whole fact to commas', () {
      final fact = Fact(PredicateKind.para, [
        point('a', name: 'A'),
        point('b', name: 'B'),
        point('c', name: 'C'),
        point('d', name: 'p17'),
      ]);
      expect(readFact(fact), 'A,B is parallel to C,p17');
    });

    test('an unnamed point falls back to its id, and the id counts '
        'toward the separator decision', () {
      final fact = Fact(PredicateKind.midp, [
        point('m9'),
        point('a', name: 'A'),
        point('b', name: 'B'),
      ]);
      expect(readFact(fact), 'm9 is the midpoint of A,B');
    });

    test('a multi-character name reaches the angle spelling too', () {
      final [a, b, c] = [
        point('a', name: 'A'),
        point('b', name: 'mid'),
        point('c', name: 'C'),
      ];
      final [d, e, f] = points('def');
      final fact = Fact(PredicateKind.eqangle, [a, b, b, c, d, e, e, f]);
      expect(readFact(fact), 'angles A,mid,C and d,e,f are equal');
    });

    test('names are read, ids order — the sentence uses what the figure '
        'shows', () {
      final fact = Fact(PredicateKind.perp, [
        point('a', name: 'P'),
        point('b', name: 'Q'),
        point('c', name: 'R'),
        point('d', name: 'S'),
      ]);
      expect(readFact(fact), 'PQ is perpendicular to RS');
    });
  });

  group('describeFact does not move', () {
    // The pin Phase 157 asks for: prose is a second renderer, and the
    // certificate spelling `Proof.render()` prints must not drift behind
    // it. `proof_test.dart` pins the render side ('coll(a, b, m)').
    test('the raw spelling is byte-unchanged beside the prose', () {
      final fact = Fact(PredicateKind.perp, points('abcd'));
      expect(describeFact(fact), 'perp(a, b, c, d)');
      final eight = Fact(PredicateKind.eqangle, points('abcdefgh'));
      expect(describeFact(eight), 'eqangle(a, b, c, d, e, f, g, h)');
    });
  });

  test('the convention is stated once, not hedged per line', () {
    expect(factReadingConvention, contains('mod π'));
    expect(factReadingConvention, contains('mirror'));
    final angles = Fact(PredicateKind.eqangle, points('abcdefgh'));
    final similar = Fact(PredicateKind.simtri, points('abcdef'));
    expect(readFact(angles), isNot(contains('mod')));
    expect(readFact(similar), isNot(contains('mirror')));
  });
}
