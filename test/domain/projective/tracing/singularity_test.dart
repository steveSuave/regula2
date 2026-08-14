import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/singularity.dart';

void main() {
  group('estimateSingularParameter', () {
    test('recovers t* exactly from the tangency collapse law s = C·√(t*−t)',
        () {
      const tStar = 0.4;
      const c = 3.0;
      double s(double t) => c * math.sqrt(tStar - t);
      final estimate = estimateSingularParameter(
        t1: 0.3,
        s1: s(0.3),
        t2: 0.35,
        s2: s(0.35),
      );
      expect(estimate, isNotNull);
      expect(estimate, closeTo(tStar, 1e-12));
    });

    Glados2(
      // t* ∈ [0.05, 1.0], C ∈ [0.1, 5.0]; samples at 3/4 and 7/8 of the
      // way to t* from 0, so s1 > s2 > 0 across the whole family.
      any.intInRange(5, 101).map((i) => i / 100),
      any.intInRange(1, 51).map((i) => i / 10),
    ).test('recovers t* across scales of the collapse law', (tStar, c) {
      double s(double t) => c * math.sqrt(tStar - t);
      final t1 = 0.75 * tStar;
      final t2 = 0.875 * tStar;
      final estimate = estimateSingularParameter(
        t1: t1,
        s1: s(t1),
        t2: t2,
        s2: s(t2),
      );
      expect(estimate, isNotNull);
      expect(estimate, closeTo(tStar, 1e-9 * tStar));
    });

    test('undershoots the closest approach of a near-miss while the samples '
        'are farther from it than its depth', () {
      // s² = C²·((t − a)² + b²): no real zero, complex zeros at a ± ib.
      // With both samples at distance > b from a, the linear fit's zero
      // crossing lands strictly before a — the bias that keeps a detour
      // planned from it from enclosing the complex zeros (homotopy safety).
      const a = 0.6;
      const c = 2.0;
      for (final b in [1e-2, 1e-4, 1e-7]) {
        for (final d2 in [2 * b, 10 * b, 1e3 * b]) {
          final d1 = 2 * d2;
          double s(double d) => c * math.sqrt(d * d + b * b);
          final estimate = estimateSingularParameter(
            t1: a - d1,
            s1: s(d1),
            t2: a - d2,
            s2: s(d2),
          );
          expect(estimate, isNotNull, reason: 'b=$b d2=$d2');
          expect(estimate, lessThan(a), reason: 'b=$b d2=$d2');
          expect(estimate, greaterThan(a - d2), reason: 'b=$b d2=$d2');
        }
      }
    });

    test('rejects samples that do not point at a singularity ahead', () {
      // Separation not strictly decreasing.
      expect(
        estimateSingularParameter(t1: 0.1, s1: 0.5, t2: 0.2, s2: 0.5),
        isNull,
      );
      expect(
        estimateSingularParameter(t1: 0.1, s1: 0.5, t2: 0.2, s2: 0.7),
        isNull,
      );
      // Samples unordered or coincident in t.
      expect(
        estimateSingularParameter(t1: 0.2, s1: 0.5, t2: 0.1, s2: 0.3),
        isNull,
      );
      expect(
        estimateSingularParameter(t1: 0.2, s1: 0.5, t2: 0.2, s2: 0.3),
        isNull,
      );
      // Already on the singularity: s2 == 0 puts t* at t2, not ahead.
      expect(
        estimateSingularParameter(t1: 0.1, s1: 0.5, t2: 0.2, s2: 0),
        isNull,
      );
      // Non-finite samples (a coasting branch reports infinity).
      expect(
        estimateSingularParameter(
          t1: 0.1,
          s1: double.infinity,
          t2: 0.2,
          s2: 0.5,
        ),
        isNull,
      );
      expect(
        estimateSingularParameter(t1: 0.1, s1: double.nan, t2: 0.2, s2: 0.5),
        isNull,
      );
      expect(
        estimateSingularParameter(t1: 0.1, s1: 0.5, t2: 0.2, s2: double.nan),
        isNull,
      );
    });
  });

  group('DetourArc', () {
    test('plans a safety-margined arc strictly enclosing the singularity',
        () {
      final arc = DetourArc.plan(entry: 0.3, tStar: 0.4, orientation: 1)!;
      expect(arc.entry, 0.3);
      expect(arc.radius, closeTo(detourSafety * 0.1, 1e-15));
      expect(arc.center, closeTo(0.45, 1e-15));
      // Strict enclosure: entry < t* < exit ≤ 1.
      expect(arc.exit, greaterThan(0.4));
      expect(arc.exit, lessThan(1));
    });

    test('the exit is exactly real and bitwise equal to tAt(0)', () {
      final arc = DetourArc.plan(entry: 0.25, tStar: 0.375, orientation: 1)!;
      final end = arc.tAt(0);
      expect(end.re, arc.exit);
      expect(end.im, 0.0);
    });

    test('the arc stays in the closed upper half-plane and spans '
        'entry → exit', () {
      final arc = DetourArc.plan(entry: 0.1, tStar: 0.3, orientation: 1)!;
      expect(arc.tAt(math.pi).re, closeTo(arc.entry, 1e-15));
      expect(arc.tAt(math.pi).im.abs(), lessThan(1e-15 * arc.radius + 1e-30));
      for (var k = 0; k <= 16; k++) {
        final t = arc.tAt(math.pi * k / 16);
        expect(t.im, greaterThanOrEqualTo(0));
        expect(t.re, greaterThanOrEqualTo(arc.entry - 1e-15));
        expect(t.re, lessThanOrEqualTo(arc.exit + 1e-15));
      }
      // The top of the arc clears the center by the full radius.
      expect(arc.tAt(math.pi / 2).im, closeTo(arc.radius, 1e-15));
    });

    test('shrinks to fit the path end while still enclosing the singularity',
        () {
      // Safety-margined radius would put the exit past 1; the shrunken
      // arc must still strictly enclose t* and stay strictly inside.
      final arc = DetourArc.plan(entry: 0.5, tStar: 0.9, orientation: 1)!;
      expect(arc.exit, lessThan(1));
      expect(arc.exit, greaterThan(0.9));
      expect(arc.entry, 0.5);
    });

    test('refuses arcs that cannot enclose: singular or near-singular '
        'endpoint, singularity behind the entry', () {
      // t* at or past the end: the pass would have to finish complex.
      expect(DetourArc.plan(entry: 0.5, tStar: 1.0, orientation: 1), isNull);
      expect(DetourArc.plan(entry: 0.5, tStar: 1.2, orientation: 1), isNull);
      // t* so close to the end the shrunken arc cannot get past it.
      expect(DetourArc.plan(entry: 0.0, tStar: 0.9999, orientation: 1), isNull);
      // t* behind or at the entry.
      expect(DetourArc.plan(entry: 0.5, tStar: 0.5, orientation: 1), isNull);
      expect(DetourArc.plan(entry: 0.5, tStar: 0.4, orientation: 1), isNull);
      expect(DetourArc.plan(entry: 0.5, tStar: double.nan, orientation: 1), isNull);
      expect(DetourArc.plan(entry: 0.5, tStar: double.infinity, orientation: 1), isNull);
    });

    Glados2(
      any.intInRange(0, 900).map((i) => i / 1000),
      any.intInRange(1, 1000).map((i) => i / 1000),
    ).test('every planned arc strictly encloses t* inside (entry, 1)',
        (entry, fraction) {
      final tStar = entry + fraction * (1 - entry);
      final arc = DetourArc.plan(entry: entry, tStar: tStar, orientation: 1);
      if (arc == null) {
        return;
      }
      expect(arc.entry, entry);
      expect(arc.radius, greaterThan(0));
      expect(arc.exit, greaterThan(tStar));
      expect(arc.exit, lessThan(1));
      expect(arc.tAt(0).im, 0.0);
      expect(arc.tAt(0).re, arc.exit);
    });

    test('orientation −1 mirrors the arc into the lower half-plane, '
        'endpoints unchanged', () {
      final upper = DetourArc.plan(entry: 0.1, tStar: 0.3, orientation: 1)!;
      final lower = DetourArc.plan(entry: 0.1, tStar: 0.3, orientation: -1)!;
      expect(lower.entry, upper.entry);
      expect(lower.exit, upper.exit);
      for (var k = 0; k <= 16; k++) {
        final theta = math.pi * k / 16;
        expect(lower.tAt(theta).re, upper.tAt(theta).re);
        expect(lower.tAt(theta).im, -upper.tAt(theta).im);
        expect(lower.tAt(theta).im, lessThanOrEqualTo(0));
      }
      expect(lower.tAt(0).im, 0.0);
      expect(lower.tAt(0).re, lower.exit);
    });
  });

  group('detourOrientation', () {
    test('is odd: reversing the drag flips the half-plane', () {
      const pairs = [
        (Vec2(0, 5), Vec2(0, 0)),
        (Vec2(0, 0), Vec2(0, 5)),
        (Vec2(-1, 2), Vec2(3, -4)),
        (Vec2(0, 0), Vec2(7, 0)), // horizontal: decided by dx
        (Vec2(7, 0), Vec2(0, 0)),
      ];
      for (final (start, end) in pairs) {
        final forward = detourOrientation(start, end);
        final back = detourOrientation(end, start);
        expect(forward.abs(), 1.0);
        expect(back, -forward, reason: '$start → $end');
      }
    });

    test('descending and leftward drags detour upper (the recorded rule)',
        () {
      expect(detourOrientation(const Vec2(0, 5), const Vec2(0, 0)), 1);
      expect(detourOrientation(const Vec2(0, 0), const Vec2(0, 5)), -1);
      expect(detourOrientation(const Vec2(3, 0), const Vec2(0, 0)), 1);
      expect(detourOrientation(const Vec2(0, 0), const Vec2(3, 0)), -1);
    });

    test('the 1D rule (parameter drives) is odd and matches the horizontal '
        'convention', () {
      expect(detourOrientation1D(5, 0), 1);
      expect(detourOrientation1D(0, 5), -1);
      expect(detourOrientation1D(-2, -7), 1);
      for (final (from, to) in const [(0.0, 5.0), (3.0, -4.0), (1.5, 1.6)]) {
        expect(detourOrientation1D(from, to), -detourOrientation1D(to, from));
        expect(
          detourOrientation1D(from, to),
          detourOrientation(Vec2(from, 0), Vec2(to, 0)),
        );
      }
    });
  });
}
