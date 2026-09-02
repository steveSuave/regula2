import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/math/rational.dart';

/// `Rational`'s arithmetic is pinned in `test/domain/prover/rational_test`
/// from before the type moved here (Phase 182); this file covers what
/// the app-facing constants added — the exact parser the constant
/// tools' dialogs read through (Phase 184).
void main() {
  Rational r(int n, [int d = 1]) => Rational.fromInts(n, d);

  group('Rational.tryParse', () {
    test('integers, signed either way, with surrounding whitespace', () {
      expect(Rational.tryParse('3'), r(3));
      expect(Rational.tryParse('-2'), r(-2));
      expect(Rational.tryParse('+7'), r(7));
      expect(Rational.tryParse('  12  '), r(12));
      expect(Rational.tryParse('0'), Rational.zero);
    });

    test('decimals are exact fractions over a power of ten', () {
      expect(Rational.tryParse('2.5'), r(5, 2));
      expect(Rational.tryParse('.75'), r(3, 4));
      expect(Rational.tryParse('-0.125'), r(-1, 8));
      expect(Rational.tryParse('22.5'), r(45, 2));
      // Nothing is rounded: the decimal is read digit for digit.
      expect(
        Rational.tryParse('0.1000000000000000055511151231257827'),
        Rational(
          BigInt.parse('1000000000000000055511151231257827'),
          BigInt.from(10).pow(34),
        ),
      );
    });

    test('fractions of integers reduce, and the sign lives up front', () {
      expect(Rational.tryParse('1/3'), r(1, 3));
      expect(Rational.tryParse('2/6'), r(1, 3));
      expect(Rational.tryParse('-45/2'), r(-45, 2));
      expect(Rational.tryParse('45 / 2'), r(45, 2));
      expect(Rational.tryParse('4/4'), Rational.one);
    });

    test('what is not an exact rational reads as null, never rounded', () {
      for (final text in [
        '',
        '   ',
        'sqrt(2)',
        'pi',
        '1/0',
        '1/sqrt(2)',
        '2.',
        '1.5/2',
        '3/-4',
        '1e3',
        'abc',
        '.',
      ]) {
        expect(Rational.tryParse(text), isNull, reason: '"$text"');
      }
    });
  });
}
