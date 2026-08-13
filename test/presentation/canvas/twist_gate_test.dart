import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/canvas/twist_gate.dart';

void main() {
  group('TwistGate arming', () {
    test('stays inert below the arming threshold', () {
      final gate = TwistGate();
      expect(gate.applied(0.02), 0);
      expect(gate.applied(-0.05), 0);
      expect(gate.applied(0.09), 0);
      expect(gate.armed, isFalse);
    });

    test('arms at the threshold and rebaselines — no jump', () {
      final gate = TwistGate();
      expect(gate.applied(0.04), 0);
      // The arming frame itself applies 0: the twist starts from here.
      expect(gate.applied(0.12), 0);
      expect(gate.armed, isTrue);
      expect(gate.applied(0.3), closeTo(0.18, 1e-12));
    });

    test('arms on a negative twist too', () {
      final gate = TwistGate();
      expect(gate.applied(-0.11), 0);
      expect(gate.armed, isTrue);
      expect(gate.applied(-0.5), closeTo(-0.39, 1e-12));
    });

    test('stays armed when the rotation returns below the threshold', () {
      final gate = TwistGate();
      gate.applied(0.2);
      expect(
        gate.applied(0.05),
        closeTo(-0.15, 1e-12),
        reason: 'an armed twist keeps tracking through small angles',
      );
      expect(gate.armed, isTrue);
    });

    test('unwraps the recognizer jump across the atan2 cut', () {
      final gate = TwistGate();
      gate.applied(-0.2); // arms; offset −0.2
      expect(gate.applied(-1.4), closeTo(-1.2, 1e-12));
      // The finger line crosses ±π: the raw value leaps by +2π
      // (−1.5 reported as −1.5 + 2π). The applied angle must not.
      expect(
        gate.applied(-1.5 + 2 * math.pi),
        closeTo(-1.3, 1e-12),
        reason: 'a 2π jump in the raw samples is the cut, not a twist',
      );
      expect(gate.applied(-1.7 + 2 * math.pi), closeTo(-1.5, 1e-12));
      // Crossing back unwinds the same way.
      expect(gate.applied(-1.4), closeTo(-1.2, 1e-12));
    });
  });

  group('TwistGate.settled', () {
    test('snaps a nearly-level release to exactly 0', () {
      expect(TwistGate.settled(0.01), 0);
      expect(TwistGate.settled(-0.03), 0);
      expect(
        TwistGate.settled(2 * math.pi / 180),
        0,
        reason: 'the boundary itself still snaps',
      );
    });

    test('keeps a deliberate angle', () {
      expect(TwistGate.settled(0.5), 0.5);
      expect(TwistGate.settled(-1.2), -1.2);
    });

    test('a full extra turn is level too', () {
      expect(TwistGate.settled(2 * math.pi + 0.01), 0);
      expect(TwistGate.settled(-2 * math.pi - 0.02), 0);
    });

    test('normalizes a cumulative angle past π into (−π, π]', () {
      expect(TwistGate.settled(math.pi * 1.5), closeTo(-math.pi / 2, 1e-12));
      expect(TwistGate.settled(-math.pi * 1.5), closeTo(math.pi / 2, 1e-12));
    });
  });

  group('normalizeAngle', () {
    test('wraps into (−π, π]', () {
      expect(normalizeAngle(0), 0);
      expect(normalizeAngle(math.pi), math.pi);
      expect(
        normalizeAngle(-math.pi),
        math.pi,
        reason: '−π and π are the same angle; the convention keeps π',
      );
      expect(normalizeAngle(3 * math.pi), closeTo(math.pi, 1e-12));
      expect(
        normalizeAngle(190 * math.pi / 180),
        closeTo(-170 * math.pi / 180, 1e-12),
      );
      expect(normalizeAngle(-0.25), closeTo(-0.25, 1e-12));
    });
  });
}
