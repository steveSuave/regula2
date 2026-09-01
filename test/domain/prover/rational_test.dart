import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/math/rational.dart';

void main() {
  Rational r(int n, [int d = 1]) => Rational.fromInts(n, d);

  group('canonical form', () {
    test('reduces, and the sign lives in the numerator', () {
      expect(r(2, 4), r(1, 2));
      expect(r(-2, 4), r(-1, 2));
      // A negative denominator is not a different number, and storing it
      // as one would break == and hashCode together.
      expect(r(1, -2), r(-1, 2));
      expect(r(-1, -2), r(1, 2));
      expect(r(1, -2).denominator, BigInt.from(2));
      expect(r(1, -2).numerator, BigInt.from(-1));
    });

    test('zero has one spelling', () {
      expect(r(0, 5), r(0, 1));
      expect(r(0, -5), Rational.zero);
      expect(Rational.zero.denominator, BigInt.one);
      expect(r(0, 7).isZero, isTrue);
    });

    test('equal values hash equally', () {
      expect({r(2, 4), r(1, 2), r(3, 6)}.length, 1);
      expect({r(1, 2), r(1, 3)}.length, 2);
    });

    test('a zero denominator is a programmer error', () {
      expect(() => r(1, 0), throwsArgumentError);
      expect(() => r(1, 2) / Rational.zero, throwsArgumentError);
    });
  });

  group('arithmetic', () {
    test('the four operations, exactly', () {
      expect(r(1, 3) + r(1, 6), r(1, 2));
      expect(r(1, 3) - r(1, 2), r(-1, 6));
      expect(r(2, 3) * r(3, 4), r(1, 2));
      expect(r(2, 3) / r(4, 9), r(3, 2));
      expect(-r(2, 3), r(-2, 3));
    });

    test('a third is exactly a third, which is the whole point', () {
      // The reason this type exists rather than a double: one third
      // added three times is one, with nothing left over.
      var total = Rational.zero;
      for (var i = 0; i < 3; i++) {
        total = total + r(1, 3);
      }
      expect(total, Rational.one);
      expect(total.isInteger, isTrue);
    });

    test('scaling by an integer is the angle system s only product', () {
      expect(r(1, 2).scaled(BigInt.from(2)), Rational.one);
      expect(r(1, 2).scaled(BigInt.from(-3)), r(-3, 2));
      expect(r(1, 2).scaled(BigInt.zero), Rational.zero);
    });

    test('big enough to leave 53 bits behind', () {
      // Why BigInt and not int: 2^53 + 1 is not representable as a
      // dart2js int, so an int-backed rational would answer differently
      // on the web than in this test run. Exactness must not depend on
      // the target.
      final big = BigInt.two.pow(53) + BigInt.one;
      final value = Rational(big, BigInt.one);
      expect(value.numerator, big);
      expect((value + Rational.one).numerator, big + BigInt.one);
      expect(value * value, Rational(big * big, BigInt.one));
      expect(Rational(big * big, big), Rational(big, BigInt.one));
    });
  });

  group('ordering', () {
    test('compares across denominators', () {
      expect(r(1, 3) < r(1, 2), isTrue);
      expect(r(-1, 3) < r(1, 300), isTrue);
      expect(r(2, 4) <= r(1, 2), isTrue);
      expect(r(2, 4) >= r(1, 2), isTrue);
      expect(r(3, 2) > r(1, 1), isTrue);
    });

    test('sorts', () {
      final values = [r(1, 2), r(-3, 4), r(0), r(5, 6), r(1, 3)]..sort();
      expect(values.map((v) => '$v').toList(), [
        '-3/4',
        '0',
        '1/3',
        '1/2',
        '5/6',
      ]);
    });

    test('sign and abs', () {
      expect(r(-2, 3).sign, -1);
      expect(Rational.zero.sign, 0);
      expect(r(2, 3).sign, 1);
      expect(r(-2, 3).abs, r(2, 3));
      expect(r(2, 3).abs, r(2, 3));
    });
  });

  group('modOne — the angle system is in Q/Z', () {
    test('lands in [0, 1)', () {
      expect(r(1, 2).modOne(), r(1, 2));
      expect(r(3, 2).modOne(), r(1, 2));
      expect(r(1).modOne(), Rational.zero);
      expect(r(-1, 2).modOne(), r(1, 2));
      expect(r(-3, 2).modOne(), r(1, 2));
      expect(r(-1, 4).modOne(), r(3, 4));
    });

    test('perp twice over is para, by arithmetic', () {
      // The constant is in units of pi. A right angle is 1/2; two of
      // them are 1, which is 0 — which is `perp_perp_para`, and it
      // arrives without a rule.
      final right = r(1, 2);
      expect((right + right).modOne(), Rational.zero);
      // Three of them are a right angle again.
      expect((right + right + right).modOne(), r(1, 2));
    });

    test('two values are the same angle exactly when modOne agrees', () {
      expect(r(5, 2).modOne(), r(1, 2).modOne());
      expect(r(1, 3).modOne() == r(2, 3).modOne(), isFalse);
    });

    test('is idempotent', () {
      for (final value in [r(7, 3), r(-7, 3), r(0), r(4), r(-4)]) {
        expect(value.modOne().modOne(), value.modOne());
        expect(value.modOne() >= Rational.zero, isTrue);
        expect(value.modOne() < Rational.one, isTrue);
      }
    });
  });

  test('reads back the way it is written', () {
    expect('${r(1, 2)}', '1/2');
    expect('${r(-1, 2)}', '-1/2');
    expect('${r(4, 2)}', '2');
    expect('${Rational.zero}', '0');
  });
}
