/// A `length_arithmetic` step reads as the chase it is — `AngleChase`'s
/// three decisions carried over, and the one decision this side had to
/// make on its own: the lines are products, not ratios.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/length_chase.dart';
import 'package:regula/domain/prover/length_closure.dart';
import 'package:regula/domain/prover/length_translation.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  FreePoint free(String id) => FreePoint(id: id, position: Vec2.zero);

  final a = free('A');
  final b = free('B');
  final c = free('C');
  final d = free('D');
  final e = free('E');
  final f = free('F');
  final g = free('G');
  final h = free('H');

  Fact cong(List<GeoPoint> p) => Fact(PredicateKind.cong, p);
  Fact eqratio(List<GeoPoint> p) => Fact(PredicateKind.eqratio, p);

  group('a chase is the sum, written multiplicatively', () {
    test('a chain of congs reads as two equalities and a conclusion', () {
      final chase = LengthChase.of(cong([a, b, e, f]), [
        cong([a, b, c, d]),
        cong([c, d, e, f]),
      ])!;
      expect(chase.isSound, isTrue);
      expect(chase.render(), ['|AB| = |CD|', '|CD| = |EF|', '⟹ |AB| = |EF|']);
    });

    test('an eqratio reads cross-multiplied', () {
      // The decision this class had to make. `|AB|/|CD| = |EF|/|GH|` is
      // the stored spelling; a chase line is an arbitrary ℚ-combination
      // of rows and a general row has no canonical split into two
      // ratios, so the whole chase is products.
      //
      // Which side a factor lands on follows the sign of its
      // coefficient in the *canonical* fact, not the order the
      // arguments were written here — `Fact` reorders `eqratio`'s
      // eight points, and the chase renders what was stored.
      final chase = LengthChase.of(cong([c, d, g, h]), [
        eqratio([a, b, c, d, e, f, g, h]),
        cong([a, b, e, f]),
      ])!;
      expect(chase.isSound, isTrue);
      expect(chase.render(), [
        '|CD|·|EF| = |AB|·|GH|',
        '|AB| = |EF|',
        '⟹ |CD| = |GH|',
      ]);
    });

    test('a scaled row is shown scaled, as an exponent', () {
      // `AngleChase`'s third decision: the line carries the multiple
      // already applied, so what the reader adds up is what the step
      // used. Doubling a row over log-lengths squares it.
      //
      // The second line is squared because the elimination pivoted that
      // way — using the `cong` once against a halved first row would be
      // as sound, and which of the two comes out is the closure's
      // choice, not a fact about the geometry. Pinned as it is, and
      // pinned identically on the browser gate.
      final chase = LengthChase.of(cong([a, b, e, f]), [
        eqratio([a, b, c, d, c, d, e, f]),
        cong([a, b, c, d]),
      ])!;
      expect(chase.isSound, isTrue);
      expect(chase.render(), [
        '|CD|^2 = |AB|·|EF|',
        '|AB|^2 = |CD|^2',
        '⟹ |AB| = |EF|',
      ], reason: 'the repeated segment is an exponent, not a coefficient');
    });

    test('the separator is decided once per chase', () {
      // Single-letter names run together; anything longer would make
      // `|mabmbc|` out of two point names, so the chase commas
      // throughout rather than mixing two notations.
      final long = free('mab');
      final other = free('mbc');
      final chase = LengthChase.of(cong([long, other, e, f]), [
        cong([long, other, c, d]),
        cong([c, d, e, f]),
      ])!;
      expect(chase.render().first, '|C,D| = |mab,mbc|');
    });

    test('lines are read out in citation order', () {
      final first = cong([a, b, c, d]);
      final second = cong([c, d, e, f]);
      final chase = LengthChase.of(cong([a, b, e, f]), [first, second])!;
      final numbering = {second: 1, first: 2};
      expect(chase.render(cite: (fact) => numbering[fact]), [
        '|CD| = |EF|  [1]',
        '|AB| = |CD|  [2]',
        '⟹ |AB| = |EF|',
      ]);
    });

    test('an uncited line carries no citation rather than an invented one', () {
      final chase = LengthChase.of(cong([a, b, e, f]), [
        cong([a, b, c, d]),
        cong([c, d, e, f]),
      ])!;
      expect(chase.render(cite: (fact) => null), [
        '|AB| = |CD|',
        '|CD| = |EF|',
        '⟹ |AB| = |EF|',
      ]);
    });
  });

  group('a stated value renders as its number', () {
    Rational q(int n, [int d = 1]) => Rational.fromInts(n, d);

    test('a ratio leads its side as a plain number', () {
      expect(
        renderLengthEquation(LengthEquation.rconst('ab', 'ma', q(2)), {
          'ab': 'AB',
          'ma': 'MA',
        }),
        '|AB| = 2·|MA|',
      );
    });

    test('a stated length can leave a side to the empty product', () {
      // The `1` the class doc calls unreachable from the homogeneous
      // vocabulary is exactly right for an lconst.
      expect(
        renderLengthEquation(LengthEquation.lconst('ab', q(3, 2)), {
          'ab': 'AB',
        }),
        '2·|AB| = 3',
      );
      expect(
        renderLengthEquation(LengthEquation.lconst('ab', q(1)), {'ab': 'AB'}),
        '|AB| = 1',
      );
    });

    test('whole exponents multiply out; a ℚ-scaled one stays symbolic', () {
      expect(
        renderLengthEquation(LengthEquation.lconst('ab', q(1, 6)), {
          'ab': 'AB',
        }),
        '6·|AB| = 1',
      );
      expect(
        renderLengthEquation(
          LengthEquation.rconst('ab', 'ma', q(2)).scaled(q(1, 2)),
          {'ab': 'AB', 'ma': 'MA'},
        ),
        '|AB|^1/2 = 2^1/2·|MA|^1/2',
      );
    });
  });

  group('a chase that cannot be re-derived is refused', () {
    test('premises that do not entail the conclusion', () {
      expect(
        LengthChase.of(cong([a, b, e, f]), [
          cong([c, d, e, f]),
        ]),
        isNull,
      );
    });

    test('a conclusion the algebra may not draw', () {
      expect(
        LengthChase.of(Fact(PredicateKind.midp, [a, b, c]), [
          cong([a, b, a, c]),
        ]),
        isNull,
      );
      expect(
        LengthChase.of(Fact(PredicateKind.para, [a, b, c, d]), [
          cong([a, b, c, d]),
        ]),
        isNull,
      );
    });

    test('a tautology is not a chase', () {
      // `|AB| = |BA|` follows from nothing, and a step saying so would
      // render as an empty sum under a conclusion.
      expect(
        LengthChase.of(cong([a, b, b, a]), [
          cong([a, b, c, d]),
        ]),
        isNull,
      );
    });
  });

  group('on the document that motivated the phase', () {
    test('provoleas2 proves |AB| = |LO| and the chase names its facts', () {
      final construction = decodeDocument(
        jsonDecode(File('test/fixtures/provoleas2.json').readAsStringSync())
            as Map<String, dynamic>,
      ).construction;
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      Prover(database: database, filter: filter).run(maxApplications: 30000);

      final step = database.facts.singleWhere(
        (fact) => database.derivationOf(fact)!.rule == lengthArithmeticRule,
      );
      expect(describeFact(step), 'cong(A, B, L, O)');

      final proof = Proof.of(step, database);
      expect(proof.verify(), isEmpty, reason: 'the step is a certificate');

      final chase = proof.steps.last.chase!;
      expect(chase.isSound, isTrue);
      expect(chase.conclusionText, '|AB| = |LO|');

      // The whole chase, cited against the proof's own numbering. Read
      // downwards: the midpoint doubled, the equilateral side, the
      // half-segment, then the intercept and similar-triangle facts
      // cross-multiplied — and the squares are the coefficient 2 no
      // union-find over congruence classes can form.
      final numbering = proof.numbering;
      expect(chase.render(cite: (fact) => numbering[fact]), [
        '|OA|^2 = |OB|^2  [1]',
        '|OB| = |ON|  [2]',
        '|MO| = |MA|  [3]',
        '|ON|·|OB| = |MO|·|LO|  [14]',
        '|MA|·|AB| = |OA|^2  [21]',
        '⟹ |AB| = |LO|',
      ]);

      final premises = database.derivationOf(step)!.premises.map(describeFact);
      expect(premises, contains('eqratio(M, O, O, N, O, B, L, O)'));
      expect(premises, contains('eqratio(M, A, A, O, A, O, A, B)'));

      // The panel's own path to the same lines, so the rendering the
      // user reads is the one pinned above.
      expect(proof.render(), contains('|MA|·|AB| = |OA|^2  [21]'));
    });
  });
}
