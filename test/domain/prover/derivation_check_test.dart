import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/derivation_check.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/length_translation.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/rule_engine.dart';

void main() {
  FreePoint free(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  Construction build(Iterable<GeoObject> objects) {
    final construction = Construction();
    for (final object in objects) {
      construction.add(object);
    }
    return construction;
  }

  test('every derivation a real fixpoint produces is accepted', () {
    final a = free('a', 0, 0);
    final b = free('b', 6, 0);
    final c = free('c', 2, 5);
    final construction = build([
      a,
      b,
      c,
      Midpoint(id: 'mab', point1: a, point2: b),
      Midpoint(id: 'mbc', point1: b, point2: c),
      Midpoint(id: 'mac', point1: a, point2: c),
    ]);
    final filter = DiagramFilter.probe(construction.objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(construction.objects), filter);
    ProverEngine(database: database, filter: filter).run();

    var checked = 0;
    for (final fact in database.facts) {
      final derivation = database.derivationOf(fact)!;
      if (derivation.isHypothesis) continue;
      checked++;
      expect(
        checkDerivation(fact, derivation).reason,
        isNull,
        reason: 'the engine derived $fact by $derivation',
      );
    }
    expect(checked, greaterThan(10), reason: 'a run worth checking');
  });

  test('a given is valid with nothing checked', () {
    final a = free('a', 0, 0);
    final b = free('b', 1, 0);
    final c = free('c', 2, 0);
    expect(
      checkDerivation(
        Fact(PredicateKind.coll, [a, b, c]),
        const Derivation.hypothesis(),
      ).isValid,
      isTrue,
    );
  });

  test('binds against the premise\'s full orbit, not its canonical form', () {
    // cong(o,a,o,b) repeats a variable, and canonical order sorts the
    // repetition apart: Fact(cong, [o,a,o,b]) stores as [a,o,b,o]. A
    // checker that read only the stored spelling would reject the
    // engine's own perp_bisector steps.
    final o = free('o', 0, 3);
    final p = free('p', 0, -2);
    final a = free('a', -4, 0);
    final b = free('b', 4, 0);
    final first = Fact(PredicateKind.cong, [o, a, o, b]);
    final second = Fact(PredicateKind.cong, [p, a, p, b]);
    expect(
      [for (final point in first.points) point.id],
      ['a', 'o', 'b', 'o'],
      reason: 'the canonical spelling is not the pattern\'s',
    );
    expect(
      checkDerivation(
        Fact(PredicateKind.perp, [o, p, a, b]),
        Derivation('perp_bisector', [first, second]),
      ).isValid,
      isTrue,
    );
  });

  group('rejects', () {
    final a = free('a', 0, 0);
    final b = free('b', 6, 0);
    final c = free('c', 2, 5);
    final m = free('m', 3, 0);
    final n = free('n', 1, 2.5);
    final midM = Fact(PredicateKind.midp, [m, a, b]);
    final midN = Fact(PredicateKind.midp, [n, a, c]);
    final midline = Fact(PredicateKind.para, [m, n, b, c]);

    test('a rule the table does not hold', () {
      final check = checkDerivation(
        midline,
        Derivation('midline_parra', [midM, midN]),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('unknown rule'));
    });

    test('a premise count the rule does not take', () {
      final check = checkDerivation(
        midline,
        Derivation('midline_para', [midM]),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('takes 2 premises'));
    });

    test('premises recorded out of slot order', () {
      // intercept_eqratio is coll & coll & para; recording the para
      // second is a different claim, and the slot order is what says so.
      final d = free('d', 4, 3);
      final o = free('o', 0, 0);
      final coll1 = Fact(PredicateKind.coll, [o, a, c]);
      final coll2 = Fact(PredicateKind.coll, [o, b, d]);
      final para = Fact(PredicateKind.para, [a, b, c, d]);
      final conclusion = Fact(PredicateKind.eqratio, [o, a, o, c, o, b, o, d]);
      expect(
        checkDerivation(
          conclusion,
          Derivation('intercept_eqratio', [coll1, para, coll2]),
        ).reason,
        contains('premise 2 is coll'),
      );
    });

    test('premises that do not entail a conclusion which is true anyway', () {
      // The pin the M-P2b session named: the DiagramFilter screens the
      // *conclusion*, so a mis-joined derivation whose conclusion happens
      // to be true passes every other check there is. Here the rule name
      // is right and `midline` is a genuine theorem of the rig — only
      // the join is wrong, one midpoint cited for both premises.
      final check = checkDerivation(
        midline,
        Derivation('midline_para', [midM, midM]),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('does not instantiate'));
    });

    test('a conclusion the binding does not produce', () {
      // Premises join fine; the recorded conclusion is a different fact.
      expect(
        checkDerivation(
          Fact(PredicateKind.para, [m, n, a, b]),
          Derivation('midline_para', [midM, midN]),
        ).isValid,
        isFalse,
      );
      expect(
        checkDerivation(
          midline,
          Derivation('midline_para', [midM, midN]),
        ).isValid,
        isTrue,
        reason: 'the same premises do entail the real midline',
      );
    });
  });

  group('a length_arithmetic step is re-derived, not trusted', () {
    final p = free('p', 0, 0);
    final r = free('r', 1, 0);
    final s = free('s', 2, 0);
    final t = free('t', 3, 0);
    final u = free('u', 4, 0);
    final v = free('v', 5, 0);

    Fact cong(List<GeoPoint> points) => Fact(PredicateKind.cong, points);
    Fact eqratio(List<GeoPoint> points) => Fact(PredicateKind.eqratio, points);

    test('a chain of congs entails the pair it closes', () {
      expect(
        checkDerivation(
          cong([p, r, u, v]),
          Derivation(lengthArithmeticRule, [
            cong([p, r, s, t]),
            cong([s, t, u, v]),
          ]),
        ).isValid,
        isTrue,
      );
    });

    test('a step with no premises proves nothing', () {
      final check = checkDerivation(
        cong([p, r, s, t]),
        Derivation(lengthArithmeticRule, const []),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('proves nothing'));
    });

    test('a premise with no length content is a defect in the record', () {
      final check = checkDerivation(
        cong([p, r, u, v]),
        Derivation(lengthArithmeticRule, [
          Fact(PredicateKind.para, [p, r, s, t]),
        ]),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('says nothing about lengths'));
    });

    test('midp may be cited and may not be concluded', () {
      // The asymmetry `LengthTranslation.equationOf` keeps: equal
      // halves follow from a midpoint, and a midpoint does not follow
      // from equal halves.
      final midpoint = Fact(PredicateKind.midp, [r, p, s]);
      expect(
        checkDerivation(
          cong([p, r, r, s]),
          Derivation(lengthArithmeticRule, [midpoint]),
        ).isValid,
        isTrue,
        reason: 'a midpoint is sound input',
      );
      final check = checkDerivation(
        Fact(PredicateKind.midp, [r, p, s]),
        Derivation(lengthArithmeticRule, [
          cong([p, r, r, s]),
        ]),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('cannot conclude'));
    });

    test('premises that do not entail the conclusion are refused', () {
      final check = checkDerivation(
        cong([p, r, u, v]),
        Derivation(lengthArithmeticRule, [
          cong([s, t, u, v]),
        ]),
      );
      expect(check.isValid, isFalse);
      expect(check.reason, contains('does not entail'));
      expect(check.reason, contains('length algebra'));
    });

    test('and the ℚ step is accepted, which is the phase', () {
      // `provoleas2`'s shape: the repeated segment in the similar-
      // triangle eqratio carries a coefficient 2, so the combination is
      // one no union-find over congruence classes can form. The checker
      // rebuilds the closure and agrees.
      expect(
        checkDerivation(
          cong([p, r, u, v]),
          Derivation(lengthArithmeticRule, [
            eqratio([s, t, p, r, p, r, u, v]),
            cong([s, t, p, r]),
          ]),
        ).isValid,
        isTrue,
      );
    });
  });
}
