import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_chase.dart';
import 'package:regula/domain/prover/angle_closure.dart';
import 'package:regula/domain/prover/angle_translation.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  FreePoint free(String id) => FreePoint(id: id, position: Vec2.zero);

  final a = free('a');
  final b = free('b');
  final c = free('c');
  final d = free('d');
  final e = free('e');
  final f = free('f');
  final aux = free('aux');

  Fact para(List<GeoPoint> p) => Fact(PredicateKind.para, p);
  Fact perp(List<GeoPoint> p) => Fact(PredicateKind.perp, p);
  Fact coll(List<GeoPoint> p) => Fact(PredicateKind.coll, p);
  Fact cong(List<GeoPoint> p) => Fact(PredicateKind.cong, p);

  BigInt big(int value) => BigInt.from(value);
  Rational half() => Rational.fromInts(1, 2);

  group('an equation written for a reader', () {
    const names = {'x': 'AB', 'y': 'CD', 'z': 'EF', 'w': 'GH'};

    test('para is an equality of directions', () {
      expect(
        renderAngleEquation(
          AngleEquation.difference('x', 'y', Rational.zero),
          names,
        ),
        'θ(AB) = θ(CD)',
      );
    });

    test('perp carries the right angle onto the other side', () {
      expect(
        renderAngleEquation(AngleEquation.difference('x', 'y', half()), names),
        'θ(AB) = θ(CD) + π/2',
      );
    });

    test('an eqangle splits two and two', () {
      expect(
        renderAngleEquation(
          AngleEquation({
            'x': -BigInt.one,
            'y': BigInt.one,
            'z': BigInt.one,
            'w': -BigInt.one,
          }, Rational.zero),
          names,
        ),
        // Terms come out in the equation's canonical variable order
        // (w, x, y, z), not in the order the predicate spelled them —
        // `AngleEquation` is a statement, and a statement has one
        // spelling.
        'θ(CD) + θ(EF) = θ(GH) + θ(AB)',
      );
    });

    test('a doubled row shows its coefficient, because it is the point', () {
      // The row that entails neither `para` nor `perp` reads as what it
      // is rather than as either of them (PLAN §"AR is a Z-module").
      expect(
        renderAngleEquation(
          AngleEquation({'x': big(2), 'y': big(-2)}, Rational.zero),
          names,
        ),
        '2θ(AB) = 2θ(CD)',
      );
    });

    test('an empty side is written as zero, not left blank', () {
      expect(
        renderAngleEquation(
          AngleEquation({'x': BigInt.one, 'y': BigInt.one}, Rational.zero),
          names,
        ),
        'θ(AB) + θ(CD) = 0',
      );
      expect(
        renderAngleEquation(
          AngleEquation({'x': -BigInt.one}, Rational.zero),
          names,
        ),
        '0 = θ(AB)',
      );
    });

    test('constants read in units of pi', () {
      String constant(Rational value) =>
          renderAngleEquation(AngleEquation({'x': BigInt.one}, value), names);
      expect(constant(Rational.zero), 'θ(AB) = 0');
      expect(constant(half()), 'θ(AB) = π/2');
      expect(constant(Rational.fromInts(1, 3)), 'θ(AB) = π/3');
      expect(constant(Rational.fromInts(2, 3)), 'θ(AB) = 2π/3');
    });

    test('a variable no name covers falls back to the variable', () {
      expect(
        renderAngleEquation(
          AngleEquation.difference('x', 'unnamed', Rational.zero),
          names,
        ),
        'θ(AB) = θ(unnamed)',
      );
    });
  });

  group('the chase itself', () {
    test('perp twice over reads as two lines and their sum', () {
      final chase = AngleChase.of(para([a, b, e, f]), [
        perp([a, b, c, d]),
        perp([c, d, e, f]),
      ]);
      expect(chase, isNotNull);
      expect(chase!.lines.length, 2);
      expect(chase.isSound, isTrue);
      expect(chase.render(), [
        'θ(ab) = θ(cd) + π/2',
        'θ(cd) = θ(ef) + π/2',
        '⟹ θ(ab) = θ(ef)',
      ]);
    });

    test('the lines sum to the conclusion, which is the whole claim', () {
      final chase = AngleChase.of(perp([a, b, e, f]), [
        perp([a, b, c, d]),
        para([c, d, e, f]),
      ])!;
      var total = AngleEquation(const {}, Rational.zero);
      for (final line in chase.lines) {
        total = total + line.equation;
      }
      expect(total, chase.conclusion);
      expect(chase.isSound, isTrue);
    });

    test('a relation used backwards is a negative multiple', () {
      // Both premises point *at* `cd`; the chase needs one of them
      // reversed, and the multiple says so rather than the rendering
      // silently swapping sides. (A backwards *spelling* would not do
      // it: `Fact` canonicalizes its arguments, so `para(c,d,a,b)` and
      // `para(a,b,c,d)` are one fact.)
      final chase = AngleChase.of(para([c, d, e, f]), [
        para([a, b, c, d]),
        para([a, b, e, f]),
      ])!;
      final backwards = chase.lines.firstWhere(
        (line) => line.source == para([a, b, c, d]),
      );
      expect(backwards.multiple, -BigInt.one);
      expect(chase.isSound, isTrue);
      expect(chase.render().last, '⟹ θ(cd) = θ(ef)');
    });

    test('one coll contributes two lines, and both cite it', () {
      // The reason a chase line is an *equation* and not a premise fact:
      // there is no well-defined multiple per cited fact.
      final chase = AngleChase.of(para([a, c, b, c]), [
        coll([a, b, c]),
      ])!;
      expect(chase.lines.length, greaterThanOrEqualTo(1));
      expect(
        chase.lines.every((line) => line.source == coll([a, b, c])),
        isTrue,
      );
      expect(chase.isSound, isTrue);
    });

    test('citations are rendered, and in step order', () {
      final first = perp([a, b, c, d]);
      final second = perp([c, d, e, f]);
      final chase = AngleChase.of(para([a, b, e, f]), [first, second])!;
      final numbers = {first: 7, second: 3};
      expect(chase.render(cite: (fact) => numbers[fact]), [
        'θ(cd) = θ(ef) + π/2  [3]',
        'θ(ab) = θ(cd) + π/2  [7]',
        '⟹ θ(ab) = θ(ef)',
      ]);
    });

    test('a citation nothing answers for is omitted, never invented', () {
      final chase = AngleChase.of(para([a, b, e, f]), [
        perp([a, b, c, d]),
        perp([c, d, e, f]),
      ])!;
      final rendered = chase.render(cite: (fact) => null);
      expect(rendered.any((line) => line.contains('[')), isFalse);
    });
  });

  group('what it refuses', () {
    test('a conclusion the algebra cannot state', () {
      expect(
        AngleChase.of(coll([a, b, c]), [
          coll([a, b, c]),
        ]),
        isNull,
      );
      expect(
        AngleChase.of(cong([a, b, c, d]), [
          para([a, b, c, d]),
        ]),
        isNull,
      );
    });

    test('premises that do not entail it', () {
      expect(
        AngleChase.of(para([a, b, e, f]), [
          perp([a, b, c, d]),
        ]),
        isNull,
      );
    });

    test('the halving a Q-vector space would allow', () {
      // Two eqangles entail 2θ_ab = 2θ_cd and neither `para` nor `perp`,
      // so neither has a chase. See `angle_closure.dart`.
      final premises = [
        Fact(PredicateKind.eqangle, [a, b, c, d, e, f, aux, d]),
        Fact(PredicateKind.eqangle, [a, b, c, d, aux, d, e, f]),
      ];
      expect(AngleChase.of(para([a, b, c, d]), premises), isNull);
      expect(AngleChase.of(perp([a, b, c, d]), premises), isNull);
    });
  });

  group('naming', () {
    test('single-letter points join, the geometric spelling', () {
      final chase = AngleChase.of(para([a, b, e, f]), [
        perp([a, b, c, d]),
        perp([c, d, e, f]),
      ])!;
      expect(chase.conclusionText, 'θ(ab) = θ(ef)');
    });

    test('a longer name switches the whole chase to a separator', () {
      // One rendering must not mix `θ(ab)` with `θ(auxd)`, which reads
      // as a name no point has.
      final chase = AngleChase.of(para([a, b, e, f]), [
        perp([a, b, aux, d]),
        perp([aux, d, e, f]),
      ])!;
      expect(chase.conclusionText, 'θ(a,b) = θ(e,f)');
      expect(chase.render().first, 'θ(a,b) = θ(aux,d) + π/2');
    });
  });

  group('inside a proof', () {
    Construction jgexDocument() {
      final construction = decodeDocument(
        jsonDecode(
          File('test/fixtures/perp-true-unproved.rgl').readAsStringSync(),
        ) as Map<String, dynamic>,
      ).construction;
      GeoPoint named(String name) => construction.objects
          .whereType<GeoPoint>()
          .firstWhere((point) => point.attributes.name == name);
      construction.add(
        Midpoint(id: 'aux', point1: named('B'), point2: named('C')),
      );
      return construction;
    }

    ({FactDatabase database, Prover prover}) exchange(
      Construction construction,
    ) {
      final filter = DiagramFilter.probe(construction.objects);
      final database = FactDatabase();
      seedHypotheses(database, hypotheses(construction.objects), filter);
      final prover = Prover(database: database, filter: filter);
      prover.run(maxApplications: 30000);
      return (database: database, prover: prover);
    }

    test('every angle step in a real run explains itself, and soundly', () {
      final run = exchange(jgexDocument());
      var angleSteps = 0;
      for (final fact in run.database.facts) {
        if (run.database.derivationOf(fact)!.rule != angleArithmeticRule) {
          continue;
        }
        final proof = Proof.of(fact, run.database);
        final step = proof.steps.last;
        expect(step.fact, fact);
        expect(
          step.chase,
          isNotNull,
          reason: 'the angle step for $fact is still a black box',
        );
        expect(step.chase!.isSound, isTrue);
        // `ProofStep.chase` is the `ArithmeticChase` interface since
        // Phase 165 — there are two algebras now — and this rig is
        // about the angle one, so the cast is the claim, not a
        // workaround.
        expect((step.chase! as AngleChase).lines, isNotEmpty);
        angleSteps++;
      }
      expect(angleSteps, greaterThan(0));
    });

    test('a chase cites steps that stand above it', () {
      // The premises-strictly-older invariant, surfaced: a chase line
      // must point upwards in the numbered list like any other citation.
      final run = exchange(jgexDocument());
      final goal = run.database.facts.firstWhere(
        (fact) => run.database.derivationOf(fact)!.rule == angleArithmeticRule,
      );
      final proof = Proof.of(goal, run.database);
      final numbering = proof.numbering;
      for (final step in proof.steps) {
        final chase = step.chase;
        if (chase is! AngleChase) continue;
        for (final line in chase.lines) {
          final cited = numbering[line.source];
          expect(cited, isNotNull);
          expect(cited!, lessThan(step.number));
        }
      }
    });

    test('only angle steps carry a chase', () {
      final run = exchange(jgexDocument());
      final goal = run.database.facts.firstWhere(
        (fact) => run.database.derivationOf(fact)!.rule == angleArithmeticRule,
      );
      for (final step in Proof.of(goal, run.database).steps) {
        expect(
          step.chase == null,
          step.rule != angleArithmeticRule,
          reason: 'step ${step.number} (${step.rule}) has the wrong chase',
        );
      }
    });

    test('render puts the chase under its step and nowhere else', () {
      final run = exchange(jgexDocument());
      final goal = run.database.facts.firstWhere(
        (fact) => run.database.derivationOf(fact)!.rule == angleArithmeticRule,
      );
      final proof = Proof.of(goal, run.database);
      final rendered = proof.render().split('\n');
      final chase = proof.steps.last.chase!;
      final cited = chase.render(cite: (fact) => proof.numbering[fact]);
      final stepLine = rendered.indexWhere(
        (line) => line.contains('angle_arithmetic'),
      );
      expect(stepLine, greaterThan(0));
      for (var i = 0; i < cited.length; i++) {
        expect(rendered[stepLine + 1 + i].trim(), cited[i]);
      }
      // The concluding line of the chase is the last thing rendered,
      // because the AR step is the goal and the goal comes last.
      expect(rendered.last.trim(), startsWith('⟹'));
    });
  });
}
