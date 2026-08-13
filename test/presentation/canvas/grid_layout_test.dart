import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/canvas/grid_layout.dart';

void main() {
  group('gridStep', () {
    /// Steps of the form {1, 2, 5} × 10^k.
    bool isRoundStep(double step) {
      final exponent = (math.log(step) / math.ln10).floor();
      for (final mantissa in const [1.0, 2.0, 5.0]) {
        for (final k in [exponent - 1, exponent, exponent + 1]) {
          final candidate = mantissa * math.pow(10.0, k);
          if ((step - candidate).abs() <= step * 1e-9) {
            return true;
          }
        }
      }
      return false;
    }

    test('across the zoom clamp: round decimal step spanning ≥ 48 px', () {
      // 200 scales log-spaced over the canvas's 0.05×–50× clamp.
      for (var i = 0; i <= 200; i++) {
        final scale = 0.05 * math.pow(1000, i / 200);
        final step = gridStep(scale);
        expect(
          isRoundStep(step),
          isTrue,
          reason: 'step $step at scale $scale is not {1,2,5}×10^k',
        );
        expect(
          step * scale,
          greaterThanOrEqualTo(48 * (1 - 1e-12)),
          reason: 'step $step at scale $scale spans < 48 px',
        );
        // Minimal: the next round step down violates the minimum. The
        // lower neighbor is a factor 2.5 away from a 5-mantissa step
        // (5 → 2) and a factor 2 otherwise (2 → 1, 1 → 0.5).
        final decade = math.pow(10.0, (math.log(step) / math.ln10).floor());
        final mantissaIsFive = (step / decade - 5).abs() < 0.5;
        final lowerNeighbor = mantissaIsFive ? step / 2.5 : step / 2;
        expect(
          lowerNeighbor * scale,
          lessThan(48),
          reason: 'step $step at scale $scale is not the smallest',
        );
      }
    });

    test('known values', () {
      expect(gridStep(1), 50); // minWorld 48 → 50
      expect(gridStep(48), 1); // minWorld 1 → 1 exactly
      expect(gridStep(50), 1); // minWorld 0.96 → 1
      expect(gridStep(0.05), 1000); // minWorld 960 → 1000
      expect(gridStep(10), 5); // minWorld 4.8 → 5
      expect(gridStep(25), 2); // minWorld 1.92 → 2
    });

    test('step shrinks monotonically as the zoom deepens', () {
      var previous = double.infinity;
      for (var i = 0; i <= 60; i++) {
        final scale = 0.05 * math.pow(1000, i / 60);
        final step = gridStep(scale);
        expect(
          step,
          lessThanOrEqualTo(previous),
          reason: 'zooming in coarsened the grid at scale $scale',
        );
        previous = step;
      }
    });

    test('honours a custom minimum spacing', () {
      expect(gridStep(1, minPx: 10), 10);
      expect(gridStep(1, minPx: 101), 200);
    });
  });

  group('formatTick', () {
    test('zero is a single 0', () {
      expect(formatTick(0), '0');
    });

    test('integers lose their decimals', () {
      expect(formatTick(2), '2');
      expect(formatTick(-150), '-150');
      expect(formatTick(1000), '1000');
    });

    test('fractions keep only significant decimals', () {
      expect(formatTick(0.5), '0.5');
      expect(formatTick(-0.02), '-0.02');
      expect(formatTick(2.5), '2.5');
    });

    test('absorbs floating-point dust on tick multiples', () {
      expect(formatTick(3 * 0.2), '0.6');
      expect(formatTick(3 * 0.1), '0.3');
    });
  });
}
