import 'package:glados/glados.dart';
import 'package:regula/domain/math/polygon_math.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('polygonSignedArea', () {
    const unitSquareCcw = [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)];

    test('unit square is 1, positive when counter-clockwise', () {
      expect(polygonSignedArea(unitSquareCcw), 1);
    });

    test('clockwise loop negates the sign', () {
      expect(polygonSignedArea(unitSquareCcw.reversed.toList()), -1);
    });

    test('triangle area matches the closed form', () {
      // Base 4, height 3 → area 6.
      const triangle = [Vec2(0, 0), Vec2(4, 0), Vec2(2, 3)];
      expect(polygonSignedArea(triangle), 6);
    });

    test('collinear vertices have zero area', () {
      const flat = [Vec2(0, 0), Vec2(1, 1), Vec2(3, 3)];
      expect(polygonSignedArea(flat), 0);
    });

    test('fewer than 3 vertices have zero area', () {
      expect(polygonSignedArea(const []), 0);
      expect(polygonSignedArea(const [Vec2(1, 2)]), 0);
      expect(polygonSignedArea(const [Vec2(1, 2), Vec2(3, 4)]), 0);
    });

    test('bowtie reports the alternating region sum', () {
      // Two opposing unit-ish triangles crossing at (1, 0.5): the loop
      // (0,0) → (2,0) → (0,1) → (2,1) walks one triangle CCW and the
      // other CW, so the shoelace value cancels to 0 — pinning the
      // documented self-intersection behavior.
      const bowtie = [Vec2(0, 0), Vec2(2, 0), Vec2(0, 1), Vec2(2, 1)];
      expect(polygonSignedArea(bowtie), 0);
    });

    Glados(any.vec2).test('translation leaves the area unchanged', (offset) {
      final translated = [for (final v in unitSquareCcw) v + offset];
      expect(polygonSignedArea(translated), closeTo(1, 1e-6));
    });

    Glados3(any.vec2, any.vec2, any.vec2).test(
      'reversing any triangle negates its signed area',
      (a, b, c) {
        final forward = polygonSignedArea([a, b, c]);
        final backward = polygonSignedArea([c, b, a]);
        expect(backward, closeTo(-forward, 1e-6));
      },
    );
  });
}
