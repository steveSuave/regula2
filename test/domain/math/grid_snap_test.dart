import 'package:glados/glados.dart';
import 'package:regula/domain/math/grid_snap.dart';
import 'package:regula/domain/math/vec2.dart';

import 'generators.dart';

void main() {
  group('snapToGrid', () {
    test('rounds each component to the nearest step multiple', () {
      expect(snapToGrid(const Vec2(2.4, 2.6), 1), const Vec2(2, 3));
      expect(snapToGrid(const Vec2(7, -3), 5), const Vec2(5, -5));
      expect(snapToGrid(const Vec2(0.26, -0.26), 0.5), const Vec2(0.5, -0.5));
      expect(snapToGrid(Vec2.zero, 2), Vec2.zero);
    });

    test('negatives round toward the nearest crossing, not toward zero', () {
      expect(snapToGrid(const Vec2(-2.4, -2.6), 1), const Vec2(-2, -3));
    });

    test('halfway ties round away from zero (Dart rounding)', () {
      expect(snapToGrid(const Vec2(2.5, -2.5), 1), const Vec2(3, -3));
      expect(snapToGrid(const Vec2(1, -1), 2), const Vec2(2, -2));
    });

    test('a zero, negative or non-finite step passes the point through', () {
      const p = Vec2(1.234, -5.678);
      expect(snapToGrid(p, 0), same(p));
      expect(snapToGrid(p, -1), same(p));
      expect(snapToGrid(p, double.nan), same(p));
      expect(snapToGrid(p, double.infinity), same(p));
    });

    Glados2(any.vec2, any.positiveRadius).test('idempotent: snapping twice '
        'is snapping once', (p, step) {
      final once = snapToGrid(p, step);
      expect(snapToGrid(once, step), once);
    });

    Glados2(any.vec2, any.positiveRadius).test(
      'the result is never more than half a step away per component',
      (p, step) {
        final snapped = snapToGrid(p, step);
        // Strict half-step plus float slack for large multiples.
        final slack = step * (0.5 + 1e-9);
        expect((snapped.x - p.x).abs(), lessThanOrEqualTo(slack));
        expect((snapped.y - p.y).abs(), lessThanOrEqualTo(slack));
      },
    );
  });
}
