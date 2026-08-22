@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/angle_closure.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/proof.dart';
import 'package:regula/domain/prover/prover.dart';
import 'package:regula/domain/prover/rational.dart';
import 'package:regula/domain/prover/rule_engine.dart';

/// Phase 152 / M-P3, held in a real browser.
///
/// AR is the first thing in this app whose correctness rests on **exact
/// integer arithmetic**, and integers are the one primitive that is not
/// the same type on every target: 64-bit on the VM and under dart2wasm,
/// a double-backed 53-bit integer under dart2js. `Rational` is
/// `BigInt`-backed for exactly that reason, and this is the gate that
/// says the reason was honoured — a green VM suite is not evidence about
/// the compile target (CLAUDE.md), and "the arithmetic is exact" is a
/// claim about the target, not about the source.
///
/// The ℤ-versus-ℚ decision is pinned here too. It is a *soundness*
/// property, and a browser where the coefficients quietly went through a
/// double would satisfy the VM tests and publish `para` for a figure
/// that is only parallel-or-perpendicular.
void main() {
  Rational r(int n, [int d = 1]) => Rational.fromInts(n, d);

  group('exactness survives the compile target', () {
    test('a third is exactly a third here too', () {
      var total = Rational.zero;
      for (var i = 0; i < 3; i++) {
        total = total + r(1, 3);
      }
      expect(total, Rational.one);
      expect(total.isInteger, isTrue);
    });

    test('and 53 bits is not the ceiling', () {
      // The number that separates a BigInt from a dart2js int. If this
      // holds in the browser, `Rational` is carrying what it claims to.
      final big = BigInt.two.pow(53) + BigInt.one;
      expect(big + BigInt.one, isNot(big));
      final value = Rational(big, BigInt.one);
      expect((value + Rational.one).numerator, big + BigInt.one);
      expect(Rational(big * big, big), value);
    });

    test('modOne lands where it does on the VM', () {
      expect(r(3, 2).modOne(), r(1, 2));
      expect(r(-1, 4).modOne(), r(3, 4));
      expect((r(1, 2) + r(1, 2)).modOne(), Rational.zero);
    });
  });

  group('the 2θ row, in a browser', () {
    // The decision PLAN records, executable on the target that ships.
    AngleEquation eqangle(String a, String b, String c, String d) =>
        AngleEquation({
          a: -BigInt.one,
          b: BigInt.one,
          c: BigInt.one,
          d: -BigInt.one,
        }, Rational.zero);

    test('two eqangles entail the doubled relation and neither reading', () {
      final closure = AngleClosure()
        ..add(eqangle('l1', 'l2', 'l3', 'l4'))
        ..add(eqangle('l1', 'l2', 'l4', 'l3'));
      expect(
        closure.proves(
          AngleEquation({'l1': -BigInt.two, 'l2': BigInt.two}, Rational.zero),
        ),
        isTrue,
      );
      expect(
        closure.proves(AngleEquation.difference('l1', 'l2', Rational.zero)),
        isFalse,
        reason: 'halving a mod-pi relation is unsound on every target',
      );
      expect(
        closure.proves(AngleEquation.difference('l1', 'l2', r(1, 2))),
        isFalse,
      );
    });

    test('perp twice over is para, by arithmetic', () {
      final closure = AngleClosure()
        ..add(AngleEquation.difference('a', 'b', r(1, 2)))
        ..add(AngleEquation.difference('b', 'c', r(1, 2)));
      final certificate = closure.entails(
        AngleEquation.difference('a', 'c', Rational.zero),
      );
      expect(certificate, isNotNull);
      expect(
        closure.recombine(certificate!),
        AngleEquation.difference('a', 'c', Rational.zero),
      );
    });
  });

  test('the exchange runs, and its steps verify, in the browser', () {
    // The whole facade on the compile target: DD and AR interleaved, and
    // every angle step re-derived from its own record.
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(6, 1));
    final c = FreePoint(id: 'c', position: const Vec2(7, 5));
    final d = FreePoint(id: 'd', position: const Vec2(1, 4));
    for (final object in <GeoObject>[
      a,
      b,
      c,
      d,
      Midpoint(id: 'mab', point1: a, point2: b),
      Midpoint(id: 'mbc', point1: b, point2: c),
      Midpoint(id: 'mcd', point1: c, point2: d),
      Midpoint(id: 'mda', point1: d, point2: a),
    ]) {
      construction.add(object);
    }
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    final prover = Prover(database: database, filter: filter);
    prover.run(maxApplications: 30000);

    expect(prover.isComplete, isTrue);
    expect(database.isNotEmpty, isTrue);
    for (final fact in database.facts) {
      expect(
        Proof.of(fact, database).verify(),
        isEmpty,
        reason: 'the proof of $fact is not a certificate in the browser',
      );
    }
  });
}
