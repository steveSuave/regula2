import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/canvas/measure_format.dart';

void main() {
  group('formatLength', () {
    test('two fixed decimals', () {
      expect(formatLength(3), '3.00');
      expect(formatLength(3.14159), '3.14');
      expect(formatLength(0.005), '0.01');
      expect(formatLength(12345.678), '12345.68');
    });

    test('explicit decimals override the default (Phase 72)', () {
      expect(formatLength(3.14159, decimals: 0), '3');
      expect(formatLength(3.14159, decimals: 4), '3.1416');
      expect(formatLength(3, decimals: 5), '3.00000');
      expect(formatLength(3.14159, decimals: null), '3.14');
    });

    test('non-finite values render — (Phase 112: infinite slopes)', () {
      expect(formatLength(double.infinity), '—');
      expect(formatLength(double.negativeInfinity), '—');
      expect(formatLength(double.nan), '—');
    });
  });

  group('formatAngle', () {
    test('degrees with one decimal and the ° suffix', () {
      expect(formatAngle(math.pi), '180.0°');
      expect(formatAngle(math.pi / 3), '60.0°');
      expect(formatAngle(1), '57.3°');
    });

    test('the right angle reads exactly 90.0°', () {
      expect(formatAngle(math.pi / 2), '90.0°');
    });

    test('a reflex angle keeps its full measure', () {
      expect(formatAngle(3 * math.pi / 2), '270.0°');
    });

    test('explicit decimals override the default (Phase 72)', () {
      expect(formatAngle(math.pi, decimals: 0), '180°');
      expect(formatAngle(1, decimals: 3), '57.296°');
    });
  });

  group('formatArea', () {
    test('same shape as lengths', () {
      expect(formatArea(2.5), formatLength(2.5));
      expect(formatArea(2.5, decimals: 3), formatLength(2.5, decimals: 3));
    });
  });
}
