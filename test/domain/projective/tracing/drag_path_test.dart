import 'package:glados/glados.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/tracing/drag_path.dart';

import '../generators.dart';

void main() {
  final unitT = any.intInRange(0, 1001).map((i) => i / 1000);

  group('DragPath.at', () {
    Glados2(any.vec2, any.vec2).test('endpoints are bitwise exact', (s, e) {
      final path = DragPath(s, e);
      expect(path.at(0), s);
      expect(path.at(1), e);
    });

    Glados2(any.vec2, any.vec2).test('midpoint halves the segment', (s, e) {
      final mid = DragPath(s, e).at(0.5);
      expect(mid.closeTo((s + e) / 2), isTrue);
    });

    Glados3(any.vec2, any.vec2, unitT).test('stays on the segment', (
      s,
      e,
      t,
    ) {
      final p = DragPath(s, e).at(t);
      // Collinear with the endpoints, at the right fraction of the way.
      expect((p - s).cross(e - s).abs(), lessThan(1e-6 * (1 + (e - s).norm)));
      expect(p.distanceTo(s), closeTo(t * (e - s).norm, 1e-6));
    });
  });

  group('DragPath.evaluate', () {
    Glados3(any.vec2, any.vec2, unitT).test(
      'agrees exactly with the lift of at() for real t',
      (s, e, t) {
        final path = DragPath(s, e);
        final p = path.evaluate(Complex(t));
        final chart = path.at(t);
        expect(p.x, Complex(chart.x));
        expect(p.y, Complex(chart.y));
        expect(p.w, Complex.one);
      },
    );

    Glados3(any.vec2, any.vec2, any.complex).test(
      'is the holomorphic continuation: Im rides the drag delta',
      (s, e, t) {
        final p = DragPath(s, e).evaluate(t);
        final chart = DragPath(s, e).at(t.re);
        final scale = 1 +
            s.norm +
            e.norm +
            t.im.abs() * ((e - s).norm + 1);
        expect(p.w, Complex.one);
        expect((p.x.re - chart.x).abs(), lessThan(1e-9 * scale));
        expect((p.y.re - chart.y).abs(), lessThan(1e-9 * scale));
        expect((p.x.im - t.im * (e.x - s.x)).abs(), lessThan(1e-9 * scale));
        expect((p.y.im - t.im * (e.y - s.y)).abs(), lessThan(1e-9 * scale));
      },
    );

    test('a real detour endpoint equals the real evaluation', () {
      // The Phase 115 contract in miniature: leaving the real axis and
      // coming back lands on the same real path point.
      final path = DragPath(const Vec2(-3, 2), const Vec2(5, -1));
      final onAxis = path.evaluate(const Complex(0.75));
      final backFromDetour = path.evaluate(const Complex(0.75, 0));
      expect(onAxis.closeTo(backFromDetour), isTrue);
      expect(onAxis.isReal(), isTrue);
    });
  });
}
