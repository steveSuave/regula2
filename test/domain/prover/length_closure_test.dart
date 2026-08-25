/// The length half of AR, specified where the angle half is: the
/// arithmetic, the vocabulary's three arrows onto it, the provenance a
/// proof leans on, and — the property that is genuinely available here
/// and not there — agreement with an *evaluator*.
///
/// Over ℚ the row span of a system is exactly the set of relations that
/// vanish on every solution, so with one degree of freedom left the
/// closure's answer and a numeric assignment's answer must agree in both
/// directions. That is the sweep in the last group, and it is a stronger
/// check than the angle side can run: a ℤ-module's span is a proper
/// subset of what vanishes, which is the whole `2θ` story.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/prover/length_closure.dart';
import 'package:regula/domain/prover/rational.dart';

void main() {
  Rational q(int n, [int d = 1]) => Rational.fromInts(n, d);

  /// `l[a] − l[b] = 0` — `cong(a, b)` on segment variables.
  LengthEquation cong(String a, String b) => LengthEquation.difference(a, b);

  /// `|a|/|b| = |c|/|d|`.
  LengthEquation eqratio(String a, String b, String c, String d) =>
      LengthEquation.eqratio(a, b, c, d);

  LengthEquation row(Map<String, int> coefficients) => LengthEquation({
    for (final entry in coefficients.entries) entry.key: q(entry.value),
  });

  group('an equation is a relation, canonically', () {
    test('drops zero coefficients and orders the variables', () {
      final equation = LengthEquation({'c': q(1), 'a': q(-1), 'b': q(0)});
      expect(equation.coefficients.keys.toList(), ['a', 'c']);
      expect(equation.leading, 'a');
    });

    test('two spellings of one relation are one value', () {
      expect(cong('a', 'b'), cong('a', 'b'));
      expect({cong('a', 'b'), cong('a', 'b')}.length, 1);
      expect(-cong('a', 'b'), cong('b', 'a'));
    });

    test('a repeated variable adds up rather than overwriting', () {
      // `|ab|/|cd| = |ab|/|ef|` is an ordinary eqratio, and a map
      // literal would have kept one `l_ab` and lost the other.
      expect(eqratio('x', 'c', 'x', 'e'), row({'c': -1, 'e': 1}));
      // The same segment on both sides of a cong says nothing at all.
      expect(cong('a', 'a').isTrivial, isTrue);
      expect(cong('a', 'a').leading, isNull);
    });

    test('there is no contradictory emptiness', () {
      // Every row is homogeneous, so an empty row is always `0 = 0` —
      // a length system cannot be inconsistent, and the all-lengths-
      // equal assignment is the witness.
      final trivial = LengthEquation(const {});
      expect(trivial.isTrivial, isTrue);
      expect(trivial.evaluate(const {}), Rational.zero);
    });

    test('scaling takes the whole relation, and ℚ scaling is allowed', () {
      final doubled = cong('a', 'b').scaled(q(2));
      expect(doubled, row({'a': 2, 'b': -2}));
      // The angle system's forbidden move, and here it is arithmetic:
      // halving is scaling by ½ and the result is a statement.
      expect(doubled.scaled(q(1, 2)), cong('a', 'b'));
      expect(doubled.normalized, cong('a', 'b'));
      expect(LengthEquation(const {}).normalized.isTrivial, isTrue);
    });

    test('an assignment evaluates a relation', () {
      final assignment = {'a': q(3), 'b': q(1), 'c': q(2)};
      expect(cong('a', 'a').evaluate(assignment), Rational.zero);
      expect(row({'a': 1, 'b': -1}).evaluate(assignment), q(2));
      // A variable the assignment omits reads as zero.
      expect(row({'a': 1, 'z': 5}).evaluate(assignment), q(3));
    });
  });

  group('the vocabulary maps onto rows, and only these three do', () {
    test('cong is a difference of log-lengths', () {
      // |ab| = |cd| ⟺ l_ab − l_cd = 0.
      expect(cong('ab', 'cd'), row({'ab': 1, 'cd': -1}));
    });

    test('eqratio is a difference of differences', () {
      // |ab|/|cd| = |ef|/|gh| ⟺ (l_ab − l_cd) − (l_ef − l_gh) = 0.
      expect(
        eqratio('ab', 'cd', 'ef', 'gh'),
        row({'ab': 1, 'cd': -1, 'ef': -1, 'gh': 1}),
      );
    });

    test('midp contributes its equal halves, and not its 1:2', () {
      // `midp(m, a, b)` says |ma| = |mb|, which is a cong; it also says
      // |ab| = 2|ma|, whose row needs an `ln 2` variable. Session 174
      // measured that constant as buying nothing on the corpus, so the
      // translation leaves it out — and the closure needs no change on
      // the day it comes back, because it enters as a variable.
      expect(cong('ma', 'mb'), row({'ma': 1, 'mb': -1}));
      final withConstant = LengthEquation.fromTerms([
        ('ab', Rational.one),
        ('ma', -Rational.one),
        ('ln 2', -Rational.one),
      ]);
      expect(withConstant.variables, ['ab', 'ln 2', 'ma']);
    });
  });

  group('closure over the vocabulary', () {
    test('cong is transitive, and so is the chain of three', () {
      final closure = LengthClosure()
        ..add(cong('a', 'b'))
        ..add(cong('b', 'c'))
        ..add(cong('c', 'd'));
      expect(closure.proves(cong('a', 'd')), isTrue);
      expect(closure.proves(cong('d', 'a')), isTrue);
      expect(closure.proves(cong('a', 'z')), isFalse);
    });

    test('an eqratio chain closes, with no rule for it', () {
      final closure = LengthClosure()
        ..add(eqratio('a', 'b', 'c', 'd'))
        ..add(eqratio('c', 'd', 'e', 'f'));
      expect(closure.proves(eqratio('a', 'b', 'e', 'f')), isTrue);
    });

    test('a cong turns an eqratio into a cong', () {
      final closure = LengthClosure()
        ..add(eqratio('a', 'b', 'c', 'd'))
        ..add(cong('a', 'b'));
      expect(closure.proves(cong('c', 'd')), isTrue);
    });

    test('redundant input is recognised as redundant', () {
      final closure = LengthClosure();
      expect(closure.add(cong('a', 'b')), LengthAddOutcome.added);
      expect(closure.add(cong('a', 'b')), LengthAddOutcome.redundant);
      expect(closure.add(cong('b', 'a')), LengthAddOutcome.redundant);
      // A rescaling of a known row is redundant too — over ℚ, unlike
      // over ℤ where `2θ` and `θ` are different information.
      expect(closure.add(row({'a': 3, 'b': -3})), LengthAddOutcome.redundant);
      expect(closure.rank, 1);
      // Redundant or not, it is still an input the caller supplied, and
      // certificates index by position.
      expect(closure.inputs.length, 4);
    });

    test('no input contradicts another', () {
      // The angle side's `contradiction` outcome has no counterpart:
      // `l_a = l_b` and `l_a = l_c` and `l_b ≠ l_c` is not sayable, so
      // the closure only ever learns or does not learn.
      final closure = LengthClosure()
        ..add(cong('a', 'b'))
        ..add(row({'a': 1, 'b': -1, 'c': 1}));
      expect(closure.proves(row({'c': 1})), isTrue);
      expect(closure.rank, 2);
    });

    test('the constrained variables are the ones the rows mention', () {
      final closure = LengthClosure()
        ..add(cong('a', 'b'))
        ..add(cong('b', 'a'));
      expect(closure.variables, ['a', 'b']);
      expect(closure.rank, 1);
    });
  });

  group('this is a ℚ elimination — the angle side is not, deliberately', () {
    test('a doubled relation entails the relation itself', () {
      // The exact step PLAN §"AR is a ℤ-module" forbids for θ, and the
      // reason the two closures are two files. A log-length has no
      // modulus: 2·l₁ = 2·l₂ says |ab| = |cd| and nothing weaker.
      final closure = LengthClosure()..add(row({'a': 2, 'b': -2}));
      expect(closure.proves(cong('a', 'b')), isTrue);
      expect(closure.proves(row({'a': 1, 'b': -3})), isFalse);
    });

    test('the payoff is a cong no union-find can reach', () {
      // `provoleas2.json`, in variables (session 174's measurement, and
      // Phase 165's regression): O is the midpoint of AB, M of AO, and
      // AON is equilateral. The intercept fact |MO|/|ON| = |OB|/|LO|
      // and the similar-triangle fact |MA|/|AO| = |AO|/|AB| — note the
      // repeated AO, which is where the coefficient 2 comes from —
      // together entail |AB| = |LO|.
      LengthClosure withCongs() => LengthClosure()
        ..add(cong('AO', 'OB')) // O is the midpoint of AB
        ..add(cong('AM', 'MO')) // M is the midpoint of AO
        ..add(cong('AO', 'ON')); // AON is equilateral

      final closure = withCongs()
        ..add(eqratio('MO', 'ON', 'OB', 'LO'))
        ..add(eqratio('AM', 'AO', 'AO', 'AB'));
      expect(closure.proves(cong('AB', 'LO')), isTrue);

      // The similar-triangle row carries the 2, and that is what the
      // union-find over congruence classes cannot form: merging classes
      // never produces a coefficient other than ±1.
      expect(
        eqratio('AM', 'AO', 'AO', 'AB').coefficients['AO'],
        q(-2),
        reason: 'the repeated segment is the coefficient 2',
      );
      expect(
        withCongs().proves(cong('AB', 'LO')),
        isFalse,
        reason: 'the cong facts alone are already saturated',
      );

      // And the certificate names both eqratios: the chase is genuinely
      // through them, not through the midpoints alone.
      final certificate = closure.entails(cong('AB', 'LO'))!;
      expect(certificate.keys, containsAll([3, 4]));
      expect(closure.recombine(certificate), cong('AB', 'LO'));
    });
  });

  group('provenance — a step must name what it came from', () {
    test('a certificate recombines to the equation it certifies', () {
      final closure = LengthClosure()
        ..add(cong('a', 'b'))
        ..add(cong('b', 'c'));
      final goal = cong('a', 'c');
      final certificate = closure.entails(goal)!;
      expect(certificate, isNotEmpty);
      expect(closure.recombine(certificate), goal);
    });

    test('it cites only inputs, and only the ones it used', () {
      final closure = LengthClosure()
        ..add(cong('a', 'b'))
        ..add(cong('x', 'y'))
        ..add(cong('b', 'c'));
      final certificate = closure.entails(cong('a', 'c'))!;
      expect(certificate.keys.toSet(), {0, 2});
      expect(certificate.values, everyElement(isNot(Rational.zero)));
      expect(closure.recombine(certificate), cong('a', 'c'));
    });

    test('a scaled row is cited with its multiplier', () {
      final closure = LengthClosure()..add(row({'a': 2, 'b': -2}));
      final certificate = closure.entails(cong('a', 'b'))!;
      expect(certificate, {0: q(1, 2)});
      expect(closure.recombine(certificate), cong('a', 'b'));
    });

    test('the trivial equation is certified by nothing', () {
      final closure = LengthClosure()..add(cong('a', 'b'));
      final certificate = closure.entails(LengthEquation(const {}))!;
      expect(certificate, isEmpty);
      expect(closure.recombine(certificate).isTrivial, isTrue);
    });

    test('recombining survives back-substitution', () {
      // `b` becomes a pivot *after* the row mentioning it was stored, so
      // that row is rewritten and its support becomes a combination of
      // combinations — which is where the bookkeeping would go wrong
      // quietly. The stored basis is `a − 2z` and `b − z`, and neither
      // input says `a − 2z`.
      final closure = LengthClosure()
        ..add(row({'a': 1, 'b': -1, 'z': -1}))
        ..add(row({'b': 1, 'z': -1}))
        ..add(row({'c': 1, 'z': -2}));
      expect(closure.rows.first, row({'a': 1, 'z': -2}));

      final goal = cong('a', 'c');
      final certificate = closure.entails(goal)!;
      expect(certificate, {0: q(1), 1: q(1), 2: q(-1)});
      expect(closure.recombine(certificate), goal);

      // Rewritten or not, every basis row is a consequence of the
      // inputs, so an assignment satisfying those satisfies these.
      final assignment = {'a': q(2), 'b': q(1), 'c': q(2), 'z': q(1)};
      for (final input in closure.inputs) {
        expect(input.evaluate(assignment), Rational.zero);
      }
      for (final basisRow in closure.rows) {
        expect(basisRow.evaluate(assignment), Rational.zero);
      }
    });

    test('an index no input holds is a programmer error', () {
      final closure = LengthClosure()..add(cong('a', 'b'));
      expect(() => closure.recombine({7: Rational.one}), throwsRangeError);
      expect(() => closure.recombine({-1: Rational.one}), throwsRangeError);
    });
  });

  group('asking does not assert', () {
    test('a refused question leaves the closure exactly as it was', () {
      final closure = LengthClosure()..add(cong('a', 'b'));
      final before = closure.rows.map((row) => '$row').toList();
      expect(closure.proves(cong('x', 'y')), isFalse);
      expect(closure.proves(cong('a', 'z')), isFalse);
      expect(closure.rows.map((row) => '$row').toList(), before);
      expect(closure.rank, 1);
      expect(closure.inputs.length, 1);
    });

    test('and residual does not assert either', () {
      final closure = LengthClosure()..add(cong('a', 'b'));
      expect(closure.residual(cong('x', 'y')), cong('x', 'y'));
      expect(closure.rank, 1);
      expect(closure.inputs.length, 1);
    });
  });

  group('the residual is a canonical coset representative', () {
    test('an entailed relation residualises to nothing', () {
      final closure = LengthClosure()
        ..add(cong('a', 'b'))
        ..add(cong('b', 'c'));
      expect(closure.residual(cong('a', 'c')).isTrivial, isTrue);
      expect(closure.residual(cong('a', 'z')).isTrivial, isFalse);
    });

    test('two relations share a residual exactly when they are '
        'interderivable', () {
      final closure = LengthClosure()..add(cong('a', 'b'));
      expect(
        closure.residual(cong('a', 'x')),
        closure.residual(cong('b', 'x')),
      );
      expect(
        closure.residual(cong('a', 'x')) == closure.residual(cong('a', 'y')),
        isFalse,
      );
    });

    test('every pivot is eliminated, not only the leading one', () {
      // The property the eqratio enumeration rests on. `b` becomes a
      // pivot *after* the row mentioning it was stored, so a basis kept
      // in plain echelon form would leave `b` in that row, and the two
      // interderivable targets below would residualise differently.
      final closure = LengthClosure()
        ..add(row({'a': 1, 'b': -1, 'z': -1}))
        ..add(row({'b': 1, 'z': -1}));
      expect(closure.residual(row({'a': 1})), row({'z': 2}));
      expect(closure.residual(row({'a': 1})), closure.residual(row({'z': 2})));

      final basis = closure.rows.toList();
      for (var i = 0; i < basis.length; i++) {
        final pivot = basis[i].leading!;
        for (var j = 0; j < basis.length; j++) {
          if (i == j) continue;
          expect(
            basis[j].coefficients.containsKey(pivot),
            isFalse,
            reason: '$pivot survives in ${basis[j]}',
          );
        }
      }
    });

    test('the eqratio bucketing trick reads statements off residuals', () {
      // Four segments with |a|/|b| = |c|/|d| entailed: the residuals of
      // `l_a − l_b` and `l_c − l_d` agree, which is how the enumeration
      // finds it in n² reductions instead of n⁴.
      final closure = LengthClosure()
        ..add(eqratio('a', 'b', 'c', 'd'))
        ..add(cong('e', 'f'));
      expect(
        closure.residual(cong('a', 'b')),
        closure.residual(cong('c', 'd')),
      );
      expect(closure.proves(eqratio('a', 'b', 'c', 'd')), isTrue);
      expect(
        closure.residual(cong('a', 'b')) == closure.residual(cong('e', 'f')),
        isFalse,
      );
    });
  });

  group('order does not change what is provable', () {
    test('the same equations in any order prove the same things', () {
      final equations = [
        cong('a', 'b'),
        eqratio('a', 'b', 'c', 'd'),
        cong('d', 'e'),
        eqratio('c', 'd', 'e', 'f'),
      ];
      final forwards = LengthClosure();
      for (final equation in equations) {
        forwards.add(equation);
      }
      final backwards = LengthClosure();
      for (final equation in equations.reversed) {
        backwards.add(equation);
      }
      expect(backwards.rank, forwards.rank);
      expect(backwards.variables, forwards.variables);
      final segments = ['a', 'b', 'c', 'd', 'e', 'f'];
      for (final first in segments) {
        for (final second in segments) {
          if (first == second) continue;
          expect(
            backwards.proves(cong(first, second)),
            forwards.proves(cong(first, second)),
            reason: 'order changed the answer for |$first| = |$second|',
          );
        }
      }
    });
  });

  group('against an evaluator — soundness and completeness together', () {
    // With `n` variables and rank `n − 1`, the row span *is* the set of
    // relations vanishing on the one-dimensional solution ray, so the
    // closure's answer and the assignment's must agree in both
    // directions. That is not true of the angle side, where the ℤ-span
    // is a proper subset of what vanishes — the `2θ` disjunction.
    const segments = ['a', 'b', 'c', 'd', 'e', 'f'];

    for (final seed in [1, 7, 12345]) {
      test('the closure proves exactly what vanishes (seed $seed)', () {
        final random = Random(seed);
        Rational pick() =>
            Rational.fromInts(random.nextInt(11) - 5, random.nextInt(4) + 1);
        Rational nonZero() {
          while (true) {
            final value = pick();
            if (!value.isZero) return value;
          }
        }

        // A random assignment of log-lengths, all non-zero so the last
        // variable can always be solved for.
        final assignment = {for (final s in segments) s: nonZero()};
        final last = segments.last;

        /// `l_s − (v_s / v_last)·l_last`, which vanishes at the
        /// assignment and leads with `s`. These five span the whole
        /// null space; the closure never sees them.
        LengthEquation basis(String s) => LengthEquation({
          s: Rational.one,
          last: -(assignment[s]! / assignment[last]!),
        });
        final spanning = [
          for (final s in segments.take(segments.length - 1)) basis(s),
        ];

        // What the closure *is* given: random combinations, so it has
        // to recover the span rather than be handed it.
        final closure = LengthClosure();
        for (var i = 0; i < 9; i++) {
          var combination = LengthEquation(const {});
          for (final b in spanning) {
            combination = combination + b.scaled(pick());
          }
          closure.add(combination);
        }
        expect(closure.rank, segments.length - 1, reason: 'degenerate draw');
        expect(closure.variables, segments);

        var proved = 0;
        var refused = 0;
        for (var trial = 0; trial < 60; trial++) {
          // Half the targets are drawn from the null space, so both
          // verdicts are exercised; the other half are arbitrary.
          final fromSpan = trial.isEven;
          var target = LengthEquation(const {});
          if (fromSpan) {
            for (final b in spanning) {
              target = target + b.scaled(pick());
            }
          } else {
            target = LengthEquation({for (final s in segments) s: pick()});
          }
          final vanishes = target.evaluate(assignment).isZero;
          final certificate = closure.entails(target);
          expect(
            certificate != null,
            vanishes,
            reason: 'closure and evaluator disagree on $target',
          );
          if (certificate == null) {
            refused++;
          } else {
            proved++;
            expect(closure.recombine(certificate), target);
          }
        }
        expect(proved, greaterThan(0));
        expect(refused, greaterThan(0));
      });
    }

    test('residuals agree exactly when the difference is entailed', () {
      final random = Random(99);
      Rational pick() =>
          Rational.fromInts(random.nextInt(9) - 4, random.nextInt(3) + 1);
      const segments = ['a', 'b', 'c', 'd', 'e', 'f'];
      final closure = LengthClosure()
        ..add(eqratio('a', 'b', 'c', 'd'))
        ..add(cong('d', 'e'))
        ..add(row({'a': 2, 'f': -1, 'b': -1}));
      final basis = closure.rows.toList();

      var agreed = 0;
      var differed = 0;
      for (var trial = 0; trial < 80; trial++) {
        final first = LengthEquation({for (final s in segments) s: pick()});
        // Half the draws differ from the first by something the closure
        // entails, so agreement is exercised rather than waited for.
        var second = LengthEquation({for (final s in segments) s: pick()});
        if (trial.isEven) {
          second = first;
          for (final basisRow in basis) {
            second = second + basisRow.scaled(pick());
          }
        }
        final same = closure.residual(first) == closure.residual(second);
        expect(
          same,
          closure.proves(first - second),
          reason: 'residuals and entailment disagree on $first vs $second',
        );
        if (same) {
          agreed++;
        } else {
          differed++;
        }
      }
      expect(agreed, greaterThan(0));
      expect(differed, greaterThan(0));
    });
  });
}
