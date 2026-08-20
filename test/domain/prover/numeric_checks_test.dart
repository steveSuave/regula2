import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/numeric_checks.dart';

import '../math/generators.dart';

void main() {
  group('collinear', () {
    test('exact and near cases', () {
      expect(
        collinear(const Vec2(0, 0), const Vec2(1, 1), const Vec2(5, 5)),
        isTrue,
      );
      expect(
        collinear(const Vec2(0, 0), const Vec2(1, 1), const Vec2(5, 5.1)),
        isFalse,
      );
    });

    test('coincident points are collinear — the deliberate exception', () {
      expect(
        collinear(const Vec2(2, 3), const Vec2(2, 3), const Vec2(9, -1)),
        isTrue,
      );
      expect(
        collinear(const Vec2(2, 3), const Vec2(2, 3), const Vec2(2, 3)),
        isTrue,
      );
    });

    Glados3(any.vec2, any.vec2, any.unitInterval).test(
      'any affine combination of two points is collinear with them',
      (a, b, t) {
        expect(collinear(a, b, a + (b - a) * t), isTrue);
      },
    );

    test('the residual is a sine, so huge coordinates stay exact-friendly', () {
      const a = Vec2(1e8, 2e8);
      const b = Vec2(2e8, 4e8);
      const c = Vec2(5e8, 1e9);
      expect(collinear(a, b, c), isTrue);
      expect(collinear(a, b, c + const Vec2(0, 1e4)), isFalse);
    });
  });

  group('parallel / perpendicular', () {
    test('exact cases', () {
      expect(
        parallel(
          const Vec2(0, 0),
          const Vec2(3, 4),
          const Vec2(10, 0),
          const Vec2(13, 4),
        ),
        isTrue,
      );
      expect(
        parallel(
          const Vec2(0, 0),
          const Vec2(3, 4),
          const Vec2(10, 0),
          const Vec2(13, 4.01),
        ),
        isFalse,
      );
      expect(
        perpendicular(
          const Vec2(0, 0),
          const Vec2(3, 4),
          const Vec2(0, 0),
          const Vec2(-4, 3),
        ),
        isTrue,
      );
      expect(
        perpendicular(
          const Vec2(0, 0),
          const Vec2(3, 4),
          const Vec2(0, 0),
          const Vec2(-4, 3.01),
        ),
        isFalse,
      );
    });

    test('a zero direction is no line: false, not vacuously true', () {
      expect(
        parallel(
          const Vec2(1, 1),
          const Vec2(1, 1),
          const Vec2(0, 0),
          const Vec2(1, 0),
        ),
        isFalse,
      );
      expect(
        perpendicular(
          const Vec2(0, 0),
          const Vec2(1, 0),
          const Vec2(2, 2),
          const Vec2(2, 2),
        ),
        isFalse,
      );
    });

    Glados2(any.vec2, any.vec2).test(
      'a translated segment is parallel to itself',
      (a, b) {
        if (a == b) return;
        const shift = Vec2(17, -3);
        expect(parallel(a, b, a + shift, b + shift), isTrue);
      },
    );
  });

  group('congruent', () {
    test('exact and near cases', () {
      expect(
        congruent(
          const Vec2(0, 0),
          const Vec2(3, 4),
          const Vec2(10, 10),
          const Vec2(10, 15),
        ),
        isTrue,
      );
      expect(
        congruent(
          const Vec2(0, 0),
          const Vec2(3, 4),
          const Vec2(10, 10),
          const Vec2(10, 15.001),
        ),
        isFalse,
      );
    });

    test('tolerance is relative to the lengths compared', () {
      // 1e-3 apart: far outside tolerance at unit scale, inside it
      // relative to a 1e9 length.
      expect(
        congruent(
          const Vec2(0, 0),
          const Vec2(0, 1),
          const Vec2(0, 0),
          const Vec2(0, 1.001),
        ),
        isFalse,
      );
      expect(
        congruent(
          const Vec2(0, 0),
          const Vec2(0, 1e9),
          const Vec2(0, 0),
          const Vec2(0, 1e9 + 0.001),
        ),
        isTrue,
      );
    });
  });

  group('midpointOf', () {
    Glados2(any.vec2, any.vec2).test('the exact midpoint qualifies', (a, b) {
      expect(midpointOf((a + b) / 2, a, b), isTrue);
    });

    test('an off-midpoint point does not', () {
      expect(
        midpointOf(const Vec2(2, 2.01), const Vec2(0, 0), const Vec2(4, 4)),
        isFalse,
      );
    });
  });

  group('concyclic', () {
    Vec2 onCircle(Vec2 center, double r, double angle) =>
        center + Vec2(math.cos(angle), math.sin(angle)) * r;

    test('four points of one circle', () {
      const center = Vec2(3, -2);
      expect(
        concyclic(
          onCircle(center, 5, 0.3),
          onCircle(center, 5, 1.7),
          onCircle(center, 5, 3.1),
          onCircle(center, 5, 5.2),
        ),
        isTrue,
      );
    });

    test('a fourth point off the circle', () {
      const center = Vec2(3, -2);
      expect(
        concyclic(
          onCircle(center, 5, 0.3),
          onCircle(center, 5, 1.7),
          onCircle(center, 5, 3.1),
          onCircle(center, 5.01, 5.2),
        ),
        isFalse,
      );
    });

    test('four collinear points are a line, not a circle', () {
      expect(
        concyclic(
          const Vec2(0, 0),
          const Vec2(1, 1),
          const Vec2(2, 2),
          const Vec2(3, 3),
        ),
        isFalse,
      );
    });

    test('a coincident pair determines no circle', () {
      expect(
        concyclic(
          const Vec2(0, 0),
          const Vec2(1, 0),
          const Vec2(0, 1),
          const Vec2(0, 1),
        ),
        isFalse,
      );
    });
  });

  group('equalAngles', () {
    test('congruent angle pairs at different places and scales', () {
      // 45° between ab and cd; 45° between ef and gh, rotated and scaled.
      expect(
        equalAngles(
          const Vec2(0, 0),
          const Vec2(1, 0), // ab: horizontal
          const Vec2(0, 0),
          const Vec2(1, 1), // cd: 45°
          const Vec2(5, 5),
          const Vec2(5, 15), // ef: vertical
          const Vec2(5, 5),
          const Vec2(-5, 15), // gh: 135° = vertical + 45°
        ),
        isTrue,
      );
    });

    test('mod π: reversing a direction names the same line angle', () {
      expect(
        equalAngles(
          const Vec2(0, 0),
          const Vec2(1, 0),
          const Vec2(0, 0),
          const Vec2(1, 1),
          const Vec2(0, 0),
          const Vec2(-1, 0), // ab reversed
          const Vec2(0, 0),
          const Vec2(1, 1),
        ),
        isTrue,
      );
    });

    test('unequal angles', () {
      expect(
        equalAngles(
          const Vec2(0, 0),
          const Vec2(1, 0),
          const Vec2(0, 0),
          const Vec2(1, 1),
          const Vec2(0, 0),
          const Vec2(1, 0),
          const Vec2(0, 0),
          const Vec2(1, 1.01),
        ),
        isFalse,
      );
    });

    test('a zero direction has no angle', () {
      expect(
        equalAngles(
          const Vec2(0, 0),
          const Vec2(0, 0),
          const Vec2(0, 0),
          const Vec2(1, 1),
          const Vec2(0, 0),
          const Vec2(1, 0),
          const Vec2(0, 0),
          const Vec2(1, 1),
        ),
        isFalse,
      );
    });
  });

  group('equalRatios', () {
    test('equal and unequal ratios', () {
      // 3/6 vs 5/10.
      expect(
        equalRatios(
          const Vec2(0, 0),
          const Vec2(3, 0),
          const Vec2(0, 0),
          const Vec2(6, 0),
          const Vec2(0, 0),
          const Vec2(0, 5),
          const Vec2(0, 0),
          const Vec2(0, 10),
        ),
        isTrue,
      );
      expect(
        equalRatios(
          const Vec2(0, 0),
          const Vec2(3, 0),
          const Vec2(0, 0),
          const Vec2(6, 0),
          const Vec2(0, 0),
          const Vec2(0, 5),
          const Vec2(0, 0),
          const Vec2(0, 10.01),
        ),
        isFalse,
      );
    });

    test('zero numerators agree; a lone zero denominator does not', () {
      // 0/6 = 0/10.
      expect(
        equalRatios(
          const Vec2(1, 1),
          const Vec2(1, 1),
          const Vec2(0, 0),
          const Vec2(6, 0),
          const Vec2(2, 2),
          const Vec2(2, 2),
          const Vec2(0, 0),
          const Vec2(0, 10),
        ),
        isTrue,
      );
      // 3/0 vs 5/10: infinite against finite.
      expect(
        equalRatios(
          const Vec2(0, 0),
          const Vec2(3, 0),
          const Vec2(1, 1),
          const Vec2(1, 1),
          const Vec2(0, 0),
          const Vec2(0, 5),
          const Vec2(0, 0),
          const Vec2(0, 10),
        ),
        isFalse,
      );
    });
  });

  group('similarTriangles / congruentTriangles', () {
    // A scaled, rotated, translated copy of (0,0)(4,0)(1,3), and a
    // reflected one.
    const a = Vec2(0, 0), b = Vec2(4, 0), c = Vec2(1, 3);
    Vec2 image(Vec2 p, {required double scale, required bool reflect}) {
      final q = reflect ? Vec2(p.x, -p.y) : p;
      // Rotate by the exact-ish angle of (3,4)/5 and translate.
      final rotated = Vec2(0.6 * q.x - 0.8 * q.y, 0.8 * q.x + 0.6 * q.y);
      return rotated * scale + const Vec2(20, -7);
    }

    test('a scaled copy is similar, not congruent', () {
      final d = image(a, scale: 2.5, reflect: false);
      final e = image(b, scale: 2.5, reflect: false);
      final f = image(c, scale: 2.5, reflect: false);
      expect(similarTriangles(a, b, c, d, e, f), isTrue);
      expect(congruentTriangles(a, b, c, d, e, f), isFalse);
    });

    test('an isometric copy is both, reflected included', () {
      for (final reflect in [false, true]) {
        final d = image(a, scale: 1, reflect: reflect);
        final e = image(b, scale: 1, reflect: reflect);
        final f = image(c, scale: 1, reflect: reflect);
        expect(
          similarTriangles(a, b, c, d, e, f),
          isTrue,
          reason: 'reflect: $reflect',
        );
        expect(
          congruentTriangles(a, b, c, d, e, f),
          isTrue,
          reason: 'reflect: $reflect',
        );
      }
    });

    test('a wrong correspondence order fails', () {
      final d = image(a, scale: 1, reflect: false);
      final e = image(b, scale: 1, reflect: false);
      final f = image(c, scale: 1, reflect: false);
      // (a, b, c) against (e, f, d): sides no longer correspond.
      expect(similarTriangles(a, b, c, e, f, d), isFalse);
      expect(congruentTriangles(a, b, c, e, f, d), isFalse);
    });

    test('a degenerate triangle is similar and congruent to nothing', () {
      const flat1 = Vec2(0, 0), flat2 = Vec2(1, 0), flat3 = Vec2(2, 0);
      expect(
        similarTriangles(flat1, flat2, flat3, flat1, flat2, flat3),
        isFalse,
      );
      expect(
        congruentTriangles(flat1, flat2, flat3, flat1, flat2, flat3),
        isFalse,
      );
    });
  });
}
