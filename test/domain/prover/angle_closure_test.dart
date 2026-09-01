import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/prover/angle_closure.dart';

void main() {
  Rational r(int n, [int d = 1]) => Rational.fromInts(n, d);
  final half = r(1, 2);

  /// `θa − θb ≡ constant`.
  AngleEquation diff(String a, String b, Rational constant) =>
      AngleEquation.difference(a, b, constant);

  AngleEquation para(String a, String b) => diff(a, b, Rational.zero);
  AngleEquation perp(String a, String b) => diff(a, b, half);

  /// `∠(a,b) = ∠(c,d)`, i.e. `−θa + θb + θc − θd ≡ 0`.
  AngleEquation eqangle(String a, String b, String c, String d) =>
      AngleEquation({
        a: -BigInt.one,
        b: BigInt.one,
        c: BigInt.one,
        d: -BigInt.one,
      }, Rational.zero);

  group('an equation is a statement, canonically', () {
    test('drops zero coefficients and orders the variables', () {
      final equation = AngleEquation({
        'c': BigInt.one,
        'a': -BigInt.one,
        'b': BigInt.zero,
      }, r(3, 2));
      expect(equation.coefficients.keys.toList(), ['a', 'c']);
      expect(equation.constant, half);
    });

    test('two spellings of one relation are one value', () {
      expect(para('l1', 'l2'), para('l1', 'l2'));
      expect({para('l1', 'l2'), para('l1', 'l2')}.length, 1);
      // Negating both sides is the same statement only when the
      // constant negates with it — 0 does, 1/2 does too (mod 1).
      expect(-para('l1', 'l2'), para('l2', 'l1'));
      expect(-perp('l1', 'l2'), perp('l2', 'l1'));
    });

    test('trivial and contradictory are different emptinesses', () {
      final trivial = AngleEquation(const {}, Rational.zero);
      final absurd = AngleEquation(const {}, half);
      expect(trivial.isTrivial, isTrue);
      expect(trivial.isContradiction, isFalse);
      expect(absurd.isTrivial, isFalse);
      expect(absurd.isContradiction, isTrue);
      expect(trivial.leading, isNull);
    });

    test('scaling takes the whole relation, coefficients included', () {
      // The point of the phase, in one assertion: doubling `perp` does
      // *not* give `para`. It gives `2θ₁ − 2θ₂ ≡ 0`, which is a weaker
      // statement about a doubled angle — the constant came back to zero
      // but the coefficients doubled with it, and the two moves are the
      // same move. Only a *division* would produce `para`, and there
      // isn't one.
      final doubled = perp('l1', 'l2').scaled(BigInt.two);
      expect(doubled.constant, Rational.zero);
      expect(doubled.coefficients.values.toList(), [BigInt.two, -BigInt.two]);
      expect(doubled == para('l1', 'l2'), isFalse);

      // Three right angles are a right angle again, on three times the
      // coefficients.
      final tripled = perp('l1', 'l2').scaled(BigInt.from(3));
      expect(tripled.constant, half);
      expect(tripled.coefficients['l1'], BigInt.from(3));
    });
  });

  group('closure over the vocabulary', () {
    test('perp twice over is para, with no rule for it', () {
      // `perp_perp_para` in the rule table; here it is addition.
      final closure = AngleClosure();
      expect(closure.add(perp('a', 'b')), AngleAddOutcome.added);
      expect(closure.add(perp('b', 'c')), AngleAddOutcome.added);
      expect(closure.proves(para('a', 'c')), isTrue);
      expect(closure.proves(perp('a', 'c')), isFalse);
    });

    test('para is transitive, and so is the chain of three', () {
      final closure = AngleClosure()
        ..add(para('a', 'b'))
        ..add(para('b', 'c'))
        ..add(para('c', 'd'));
      expect(closure.proves(para('a', 'd')), isTrue);
      expect(closure.proves(para('d', 'a')), isTrue);
    });

    test('para and perp compose both ways', () {
      // `para_perp_perp` and `perp_perp_para`, both for free.
      final closure = AngleClosure()
        ..add(para('a', 'b'))
        ..add(perp('b', 'c'));
      expect(closure.proves(perp('a', 'c')), isTrue);
      expect(closure.proves(para('a', 'c')), isFalse);
    });

    test('Chasles is what addition is', () {
      // No rule states it: three lines with two known angles fix the
      // third, because the rows are differences of the same variables.
      final closure = AngleClosure()
        ..add(diff('a', 'b', r(1, 3)))
        ..add(diff('b', 'c', r(1, 6)));
      expect(closure.proves(diff('a', 'c', r(1, 2))), isTrue);
      expect(closure.proves(diff('a', 'c', r(1, 3))), isFalse);
    });

    test('an eqangle chain closes', () {
      // The DD table's `eqangle_transitive`, as a row sum — and since
      // Phase 163 this *is* that rule: the table no longer carries it.
      final closure = AngleClosure()
        ..add(eqangle('a', 'b', 'c', 'd'))
        ..add(eqangle('c', 'd', 'e', 'f'));
      expect(closure.proves(eqangle('a', 'b', 'e', 'f')), isTrue);
    });

    test('redundant input is recognised as redundant', () {
      final closure = AngleClosure();
      expect(closure.add(para('a', 'b')), AngleAddOutcome.added);
      expect(closure.add(para('a', 'b')), AngleAddOutcome.redundant);
      expect(closure.add(para('b', 'a')), AngleAddOutcome.redundant);
      expect(closure.rank, 1);
      // Redundant or not, it is still an input the caller supplied, and
      // certificates index by position.
      expect(closure.inputs.length, 3);
    });

    test('contradictory input is named, not silently absorbed', () {
      final closure = AngleClosure()..add(para('a', 'b'));
      expect(closure.add(perp('a', 'b')), AngleAddOutcome.contradiction);
      expect(closure.isInconsistent, isTrue);
    });

    test('an unrelated line is not related to anything', () {
      final closure = AngleClosure()..add(para('a', 'b'));
      expect(closure.proves(para('a', 'z')), isFalse);
      expect(closure.proves(perp('y', 'z')), isFalse);
    });
  });

  group('the 2-theta row — why this is not Gaussian elimination', () {
    // PLAN §"AR is a ℤ-module, not a ℚ-vector space". This group is the
    // decision, executable.

    AngleClosure ambiguous() => AngleClosure()
      // ∠(l1,l2) = ∠(l3,l4)
      ..add(eqangle('l1', 'l2', 'l3', 'l4'))
      // ∠(l1,l2) = ∠(l4,l3) — the same angle, read the other way
      ..add(eqangle('l1', 'l2', 'l4', 'l3'));

    test('two eqangles give 2θ, and 2θ ≡ 0 is not para', () {
      final closure = ambiguous();
      // What the pair really says: twice the angle vanishes mod π, so
      // the lines are parallel *or* perpendicular. Both readings are
      // consistent with the premises, so neither may be published.
      expect(
        closure.proves(
          AngleEquation({'l1': -BigInt.two, 'l2': BigInt.two}, Rational.zero),
        ),
        isTrue,
        reason: 'the doubled relation is genuinely entailed',
      );
      expect(
        closure.proves(para('l1', 'l2')),
        isFalse,
        reason: 'halving a mod-pi relation is exactly the unsound step',
      );
      expect(closure.proves(perp('l1', 'l2')), isFalse);
    });

    test('the row is kept, and still combines', () {
      // Not published is not discarded: told additionally that the two
      // lines are *not* perpendicular — here, by being parallel to a
      // pair that is not — the disjunction resolves by ordinary means.
      final closure = ambiguous()..add(para('l1', 'm'));
      expect(
        closure.proves(
          AngleEquation({'m': -BigInt.two, 'l2': BigInt.two}, Rational.zero),
        ),
        isTrue,
        reason: '2θ combined with a fresh row is still 2θ about m',
      );
      expect(closure.rank, greaterThan(1));
    });

    test('a 2θ row admits its own doublings and nothing finer', () {
      final closure = ambiguous();
      for (final multiple in [2, 4, 6, -2]) {
        expect(
          closure.proves(
            AngleEquation({
              'l1': -BigInt.from(multiple),
              'l2': BigInt.from(multiple),
            }, Rational.zero),
          ),
          isTrue,
        );
      }
      for (final multiple in [1, 3, -1]) {
        expect(
          closure.proves(
            AngleEquation({
              'l1': -BigInt.from(multiple),
              'l2': BigInt.from(multiple),
            }, Rational.zero),
          ),
          isFalse,
          reason: '$multiple·θ is not a ℤ-multiple of 2·θ',
        );
      }
    });

    test('the Bézout replacement keeps the whole lattice', () {
      // Distilled from `large_examples.txt:regular_hexagon` (Phase 179):
      // the seven premises of a recorded angle step, absorbed in the
      // order the step cited them, and the step's own conclusion. The
      // entailment is real — its certificate scales one perp by 4 and
      // another by 2, wiping their halves mod 1 — but the old Bézout
      // step continued elimination with a determinant-|y| combination
      // of the two rows it merged, so the surviving basis generated a
      // sublattice and `entails` answered a false no. The verifier
      // then reported a sound proof as unsound, which is how this was
      // found.
      final closure = AngleClosure()
        ..add(
          AngleEquation({
            'a': -BigInt.one,
            'c': BigInt.two,
            'e': -BigInt.one,
          }, Rational.zero),
        )
        ..add(perp('c', 'f'))
        ..add(
          AngleEquation({
            'a': -BigInt.one,
            'd': -BigInt.one,
            'f': BigInt.two,
          }, Rational.zero),
        )
        ..add(perp('d', 'g'))
        ..add(perp('b', 'h'))
        ..add(
          AngleEquation({
            'a': -BigInt.two,
            'c': BigInt.one,
            'e': BigInt.one,
          }, Rational.zero),
        )
        ..add(
          AngleEquation({
            'b': -BigInt.one,
            'c': -BigInt.one,
            'g': BigInt.two,
          }, Rational.zero),
        );
      final goal = perp('a', 'h');
      final certificate = closure.entails(goal);
      expect(certificate, isNotNull);
      expect(closure.recombine(certificate!), goal);
    });

    test('the gcd step reaches what two coarse rows share', () {
      // Neither 2θ nor 3θ divides the other, and their lattice contains
      // θ itself — Bézout, which is the step Gaussian elimination
      // replaces with a division.
      final closure = AngleClosure()
        ..add(AngleEquation({'a': BigInt.two, 'b': -BigInt.two}, Rational.zero))
        ..add(
          AngleEquation({
            'a': BigInt.from(3),
            'b': BigInt.from(-3),
          }, Rational.zero),
        );
      expect(closure.proves(para('a', 'b')), isTrue);
    });
  });

  group('provenance — a step must name what it came from', () {
    test('a certificate recombines to the equation it certifies', () {
      final closure = AngleClosure()
        ..add(perp('a', 'b'))
        ..add(perp('b', 'c'));
      final goal = para('a', 'c');
      final certificate = closure.entails(goal)!;
      expect(certificate, isNotEmpty);
      expect(closure.recombine(certificate), goal);
    });

    test('it cites only inputs, and only the ones it used', () {
      final closure = AngleClosure()
        ..add(para('a', 'b'))
        ..add(para('x', 'y'))
        ..add(para('b', 'c'));
      final certificate = closure.entails(para('a', 'c'))!;
      expect(certificate.keys.toSet(), {0, 2});
      expect(certificate.values, everyElement(isNot(BigInt.zero)));
      expect(closure.recombine(certificate), para('a', 'c'));
    });

    test('the trivial equation is certified by nothing', () {
      final closure = AngleClosure()..add(para('a', 'b'));
      final certificate = closure.entails(
        AngleEquation(const {}, Rational.zero),
      )!;
      expect(certificate, isEmpty);
      expect(closure.recombine(certificate).isTrivial, isTrue);
    });

    test('recombining survives the gcd path too', () {
      // The replacement rows are combinations of combinations, so this
      // is where support bookkeeping would go wrong quietly.
      final closure = AngleClosure()
        ..add(AngleEquation({'a': BigInt.two, 'b': -BigInt.two}, Rational.zero))
        ..add(
          AngleEquation({
            'a': BigInt.from(3),
            'b': BigInt.from(-3),
          }, Rational.zero),
        );
      final certificate = closure.entails(para('a', 'b'))!;
      expect(closure.recombine(certificate), para('a', 'b'));
    });

    test('every derivable relation recombines, over a tangled closure', () {
      // A sweep rather than a case: whatever the closure claims to
      // prove, the certificate must multiply back out to it.
      final closure = AngleClosure()
        ..add(perp('a', 'b'))
        ..add(eqangle('a', 'b', 'c', 'd'))
        ..add(para('d', 'e'))
        ..add(diff('e', 'f', r(1, 3)))
        ..add(eqangle('c', 'd', 'f', 'g'));
      final lines = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      var proved = 0;
      for (final first in lines) {
        for (final second in lines) {
          if (first == second) continue;
          for (final constant in [Rational.zero, half, r(1, 3), r(2, 3)]) {
            final goal = diff(first, second, constant);
            final certificate = closure.entails(goal);
            if (certificate == null) continue;
            proved++;
            expect(closure.recombine(certificate), goal);
          }
        }
      }
      expect(proved, greaterThan(0));
    });

    test('an index no input holds is a programmer error', () {
      final closure = AngleClosure()..add(para('a', 'b'));
      expect(() => closure.recombine({7: BigInt.one}), throwsRangeError);
      expect(() => closure.recombine({-1: BigInt.one}), throwsRangeError);
    });
  });

  group('asking does not assert', () {
    test('a refused question leaves the closure exactly as it was', () {
      final closure = AngleClosure()..add(para('a', 'b'));
      final before = closure.rows.map((row) => '$row').toList();
      expect(closure.proves(perp('x', 'y')), isFalse);
      expect(closure.proves(para('a', 'z')), isFalse);
      expect(closure.rows.map((row) => '$row').toList(), before);
      expect(closure.rank, 1);
      expect(closure.inputs.length, 1);
    });

    test('and a question is not answered by having been asked', () {
      final closure = AngleClosure()..add(para('a', 'b'));
      expect(closure.proves(perp('a', 'b')), isFalse);
      expect(closure.proves(perp('a', 'b')), isFalse);
    });
  });

  group('order does not change what is provable', () {
    test('the same equations in any order prove the same things', () {
      final equations = [
        perp('a', 'b'),
        eqangle('a', 'b', 'c', 'd'),
        para('d', 'e'),
        perp('e', 'f'),
      ];
      final forwards = AngleClosure();
      for (final equation in equations) {
        forwards.add(equation);
      }
      final backwards = AngleClosure();
      for (final equation in equations.reversed) {
        backwards.add(equation);
      }
      expect(backwards.rank, forwards.rank);
      final lines = ['a', 'b', 'c', 'd', 'e', 'f'];
      for (final first in lines) {
        for (final second in lines) {
          if (first == second) continue;
          for (final constant in [Rational.zero, half]) {
            final goal = diff(first, second, constant);
            expect(
              backwards.proves(goal),
              forwards.proves(goal),
              reason: 'order changed the answer for $goal',
            );
          }
        }
      }
    });
  });
}
