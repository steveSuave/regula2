import 'package:glados/glados.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

import '../domain/math/generators.dart';
import 'harmonic.dart';

void main() {
  group('harmonicConjugate on canonical configurations', () {
    const a = Vec2.zero;
    const b = Vec2(4, 0);

    test('C at the quarter point maps to the mirror external point', () {
      // t = 1/4 → d = (1/4)/(−1/2) = −1/2, i.e. (−2, 0).
      final d = harmonicConjugate(a, b, const Vec2(1, 0));
      expect(d!.closeTo(const Vec2(-2, 0), 1e-12), isTrue);
    });

    test('C at either endpoint is its own conjugate', () {
      expect(harmonicConjugate(a, b, a)!.closeTo(a, 1e-12), isTrue);
      expect(harmonicConjugate(a, b, b)!.closeTo(b, 1e-12), isTrue);
    });

    test('C at the midpoint has no conjugate (D at infinity)', () {
      expect(harmonicConjugate(a, b, const Vec2(2, 0)), isNull);
    });

    test('C off the line has no conjugate', () {
      expect(harmonicConjugate(a, b, const Vec2(1, 3)), isNull);
    });

    test('coincident base points have no conjugate', () {
      expect(harmonicConjugate(a, a, const Vec2(1, 0)), isNull);
    });

    test('an external C maps inside the segment', () {
      // The involution partner of the first case.
      final d = harmonicConjugate(a, b, const Vec2(-2, 0));
      expect(d!.closeTo(const Vec2(1, 0), 1e-12), isTrue);
    });
  });

  group('harmonicConjugate properties', () {
    // C is generated *on* line AB by its affine parameter so the
    // collinearity gate always passes. Each property skips the midpoint's
    // ill-conditioned neighborhood (|2t − 1| < 0.05), where the conjugate
    // shoots toward infinity and tolerances test floating point only.
    final harmonicParameter = any.intInRange(-2000, 2001).map((i) => i / 1000);
    bool nearMidpoint(double t) => (2 * t - 1).abs() < 0.05;

    Glados3(any.vec2, any.vec2, harmonicParameter).test(
      'cross-ratio (A,B;C,D) is −1',
      (a, b, t) {
        if (a.closeTo(b, 1e-3) || nearMidpoint(t)) {
          return;
        }
        if (t.abs() < 1e-3 || (1 - t).abs() < 1e-3) {
          return; // endpoints are fixed points: both signed ratios degenerate
        }
        final c = a + (b - a) * t;
        final d = harmonicConjugate(a, b, c);
        if (d == null) {
          return; // c landed inside the midpoint guard band
        }
        // Signed ratios along AB: AC/CB = −AD/DB.
        final ab = b - a;
        double param(Vec2 p) => (p - a).dot(ab) / ab.normSquared;
        final tc = param(c);
        final td = param(d);
        final ratioC = tc / (1 - tc);
        final ratioD = td / (1 - td);
        expect(ratioC / ratioD, closeTo(-1, 1e-6));
      },
    );

    Glados3(any.vec2, any.vec2, harmonicParameter).test(
      'the conjugate lies on line AB',
      (a, b, t) {
        if (a.closeTo(b, 1e-3) || nearMidpoint(t)) {
          return;
        }
        final c = a + (b - a) * t;
        final d = harmonicConjugate(a, b, c);
        if (d == null) {
          return;
        }
        expect(isCollinear(a, b, d, 1e-6), isTrue);
      },
    );

    Glados3(any.vec2, any.vec2, harmonicParameter).test(
      'the map is an involution: conjugate of the conjugate is C',
      (a, b, t) {
        if (a.closeTo(b, 1e-3) || nearMidpoint(t)) {
          return;
        }
        final c = a + (b - a) * t;
        final d = harmonicConjugate(a, b, c);
        if (d == null) {
          return;
        }
        final back = harmonicConjugate(a, b, d);
        if (back == null) {
          return; // d landed within the midpoint guard of the reverse map
        }
        final scale = (b - a).norm;
        expect(back.distanceTo(c) / scale, lessThan(1e-6));
      },
    );
  });
}
