import 'dart:math' as math;

import 'package:glados/glados.dart';
import 'package:regula/domain/projective/tracing/singularity.dart';

void main() {
  group('estimateSingularParameter', () {
    test(
      'recovers t* exactly from the tangency collapse law s = C·√(t*−t)',
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
      },
    );

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
    test('plans a safety-margined arc strictly enclosing the singularity', () {
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

    test(
      'shrinks to fit the path end while still enclosing the singularity',
      () {
        // Safety-margined radius would put the exit past 1; the shrunken
        // arc must still strictly enclose t* and stay strictly inside.
        final arc = DetourArc.plan(entry: 0.5, tStar: 0.9, orientation: 1)!;
        expect(arc.exit, lessThan(1));
        expect(arc.exit, greaterThan(0.9));
        expect(arc.entry, 0.5);
      },
    );

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
      expect(
        DetourArc.plan(entry: 0.5, tStar: double.nan, orientation: 1),
        isNull,
      );
      expect(
        DetourArc.plan(entry: 0.5, tStar: double.infinity, orientation: 1),
        isNull,
      );
    });

    Glados2(
      any.intInRange(0, 900).map((i) => i / 1000),
      any.intInRange(1, 1000).map((i) => i / 1000),
    ).test('every planned arc strictly encloses t* inside (entry, 1)', (
      entry,
      fraction,
    ) {
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

  group('detour orientation (Phase 120c convention)', () {
    test('drags take a constant half-plane', () {
      // Constant is the design, not an implementation detail: it reads
      // nothing about the gesture, so pointer noise has no seam to land
      // on, and it makes a round trip close a loop around the branch
      // point — which is the honest monodromy of the root split. The
      // reversal-identity rule it replaced (`detourOrientation`, odd in
      // the drag direction) is gone; see singularity.dart.
      expect(dragDetourOrientation.abs(), 1.0);
    });

    test('the 1D rule stays for locus runs, and is odd', () {
      expect(detourOrientation1D(5, 0), 1);
      expect(detourOrientation1D(0, 5), -1);
      expect(detourOrientation1D(-2, -7), 1);
      for (final (from, to) in const [(0.0, 5.0), (3.0, -4.0), (1.5, 1.6)]) {
        expect(detourOrientation1D(from, to), -detourOrientation1D(to, from));
      }
    });
  });

  group('collisionStepLimit (Phase 117b)', () {
    test('keeps a step short of the collision under the √ law', () {
      // The estimator is exact here, so the limit is a plain fraction
      // of the true remaining distance — and stepping by it lands
      // strictly before t*, which is the whole contract.
      const tStar = 0.4;
      double s(double t) => 3 * math.sqrt(tStar - t);
      const t1 = 0.3, t2 = 0.35;
      final limit = collisionStepLimit(t1: t1, s1: s(t1), t2: t2, s2: s(t2));
      expect(limit, closeTo(collisionStepFraction * (tStar - t2), 1e-12));
      expect(t2 + limit, lessThan(tStar));
    });

    test('keeps a step short of the collision under the linear law too — '
        'the case that used to be stepped straight over', () {
      // Two roots passing through each other transversally. The
      // estimator undershoots here (that is fine: the limit only has to
      // be conservative), but before this limit existed the controller
      // took whole scan cells across such a collision, which is how a
      // sheet swap slipped past every acceptance rule.
      const tStar = 0.4;
      double s(double t) => 3 * (tStar - t);
      for (final (t1, t2) in const [(0.0, 0.2), (0.3, 0.35), (0.39, 0.399)]) {
        final limit = collisionStepLimit(t1: t1, s1: s(t1), t2: t2, s2: s(t2));
        expect(limit, greaterThan(0), reason: 't2=$t2');
        expect(t2 + limit, lessThan(tStar), reason: 't2=$t2');
      }
    });

    test('does not throttle when the samples point at no collision ahead', () {
      expect(
        collisionStepLimit(t1: 0.1, s1: 0.5, t2: 0.2, s2: 0.5),
        double.infinity,
      );
      expect(
        collisionStepLimit(t1: 0.1, s1: double.infinity, t2: 0.2, s2: 0.5),
        double.infinity,
      );
    });

    test('is self-scaling: a slowly closing separation barely throttles', () {
      // s falls by 1% over a 0.1 step: the collision extrapolates ~10
      // units ahead, so nothing near-term is capped.
      final limit = collisionStepLimit(t1: 0.1, s1: 1.0, t2: 0.2, s2: 0.99);
      expect(limit, greaterThan(1));
    });
  });

  group('locateSeparationMinimum (Phase 117b)', () {
    test('finds a linear collision and calls it one', () {
      // |t − 0.4|: a transversal crossing, the profile the collapse-law
      // fit cannot extrapolate.
      final found = locateSeparationMinimum(
        from: 0.1,
        end: 1,
        firstStep: 1e-3,
        separationAt: (t) => (t - 0.4).abs(),
      );
      expect(found, isNotNull);
      expect(found!.t, closeTo(0.4, 1e-6));
      expect(found.isCollision, isTrue);
    });

    test('locates a √ collision — the tangency law — just as accurately', () {
      // Classification is covered below; what matters here is that the
      // parameter comes out right whatever the exponent, which is the
      // whole reason for measuring instead of extrapolating.
      final found = locateSeparationMinimum(
        from: 0.1,
        end: 1,
        firstStep: 1e-3,
        separationAt: (t) => math.sqrt((t - 0.4).abs()),
      );
      expect(found, isNotNull);
      expect(found!.t, closeTo(0.4, 1e-9));
    });

    test('a profile that reaches zero is a collision on either law — the '
        'kernel snaps coincident roots, so real ones do reach it', () {
      for (final s in <double Function(double)>[
        (t) => (t - 0.4).abs(),
        (t) => math.sqrt((t - 0.4).abs()),
        (t) => 3 * (t - 0.4) * (t - 0.4),
      ]) {
        // Mirror the kernel: below its coincidence tolerance the solver
        // returns the double root itself, so the profile bottoms at a
        // hard zero rather than trailing off.
        double snapped(double t) {
          final v = s(t);
          return v < 1e-12 ? 0 : v;
        }

        final found = locateSeparationMinimum(
          from: 0.1,
          end: 1,
          firstStep: 1e-3,
          separationAt: snapped,
        );
        expect(found, isNotNull);
        expect(found!.t, closeTo(0.4, 1e-5));
        expect(found.isCollision, isTrue);
      }
    });

    test('finds a near-miss and refuses to call it a collision — the '
        'discriminator the extrapolation cannot provide', () {
      // s = √((t − a)² + b²) bottoms out at b > 0. Misclassifying this
      // as a collision would plan an arc around complex zeros the real
      // path passes *between*, winding and swapping the branches.
      for (final b in [1e-2, 1e-4, 1e-5]) {
        final found = locateSeparationMinimum(
          from: 0.1,
          end: 1,
          firstStep: 1e-3,
          separationAt: (t) => math.sqrt((t - 0.4) * (t - 0.4) + b * b),
        );
        expect(found, isNotNull, reason: 'b=$b');
        expect(found!.t, closeTo(0.4, 1e-3), reason: 'b=$b');
        expect(found.separation, closeTo(b, b * 1e-3), reason: 'b=$b');
        expect(found.isCollision, isFalse, reason: 'b=$b');
      }
    });

    test('a miss tighter than doubleRootEpsilon reads as a collision — the '
        'kernel already calls roots that close a double root', () {
      // Not a wart: below this separation the solver itself snaps the
      // pair, `collisionFree` waives its refusal and branch adoption
      // declines to re-derive an index. Treating such a miss as a
      // collision is the same convention, not a new one.
      final found = locateSeparationMinimum(
        from: 0.1,
        end: 1,
        firstStep: 1e-3,
        separationAt: (t) => math.sqrt((t - 0.4) * (t - 0.4) + 1e-16),
      );
      expect(found, isNotNull);
      expect(found!.isCollision, isTrue);
    });

    test('returns null when the profile never turns around inside the '
        'window — nothing to aim at, so the caller keeps its estimate', () {
      // Monotonically rising.
      expect(
        locateSeparationMinimum(
          from: 0.1,
          end: 1,
          firstStep: 1e-3,
          separationAt: (t) => t,
        ),
        isNull,
      );
      // Monotonically falling: the minimum sits past the window's end.
      expect(
        locateSeparationMinimum(
          from: 0.1,
          end: 1,
          firstStep: 1e-3,
          separationAt: (t) => 2 - t,
        ),
        isNull,
      );
      // Degenerate windows.
      expect(
        locateSeparationMinimum(
          from: 0.5,
          end: 0.5,
          firstStep: 1e-3,
          separationAt: (t) => (t - 0.4).abs(),
        ),
        isNull,
      );
    });

    test('a collision thousands of first-steps ahead is still bracketed — '
        'the search doubles its stride', () {
      // The walks always ask from close in (their own step has already
      // collapsed to detourTriggerStep), but the stride must still cover
      // a collision several decades further out than the first probe.
      final found = locateSeparationMinimum(
        from: 0.8,
        end: 1,
        firstStep: 1e-5,
        separationAt: (t) => (t - 0.9).abs(),
      );
      expect(found, isNotNull);
      // Located to a few parts in 10⁴ of the distance travelled, which
      // is where a *confirmed* collision stops being refined (Phase
      // 117c): all the parameter is for is centring an arc whose radius
      // is a fraction of that same distance.
      expect(found!.t, closeTo(0.9, 1e-4 * (0.9 - 0.8)));
      expect(found.isCollision, isTrue);
    });

    test('a confirmed collision stops being refined once the verdict '
        'lands — the probe count is the point (Phase 117c)', () {
      // The measurement runs on every starving step of every frame and
      // each probe is a chain solve, so "how many" is a behavioural
      // contract, not an implementation detail: at the floating-point
      // floor a single crossing cost ~205 probes, which on a document
      // carrying a locus was more than half the frame.
      var probes = 0;
      final found = locateSeparationMinimum(
        from: 0.8,
        end: 1,
        firstStep: 1e-5,
        separationAt: (t) {
          probes++;
          return (t - 0.9).abs();
        },
      );
      expect(found!.isCollision, isTrue);
      expect(probes, lessThan(80));
    });

    test('a near-miss is still refined to the floor — the cheap stopping '
        'rule applies only once a probe has been below the threshold', () {
      // The relaxed rule may never decide the *verdict*: a miss is told
      // from a collision below its own closest approach, so stopping
      // early here would read this profile as a collision — the
      // expensive direction, an arc planned around branch points the
      // real path passes between.
      var probes = 0;
      final found = locateSeparationMinimum(
        from: 0.8,
        end: 1,
        firstStep: 1e-5,
        separationAt: (t) {
          probes++;
          return (t - 0.9).abs() + 1e-4;
        },
      );
      expect(found!.isCollision, isFalse);
      expect(found.t, closeTo(0.9, 1e-9));
      expect(probes, greaterThan(100));
    });

    test('a collision just short of the window edge is reachable — the '
        'last probe clamps to the edge instead of giving up', () {
      final found = locateSeparationMinimum(
        from: 0.998,
        end: 1,
        firstStep: 1e-5,
        separationAt: (t) => (t - 0.999).abs(),
      );
      expect(found, isNotNull);
      expect(found!.t, closeTo(0.999, 1e-9));
      expect(found.isCollision, isTrue);
    });

    test('a profile still falling at the window edge has no interior '
        'minimum: a collision at or past the end is not this function\'s '
        'to find (no arc can enclose a singular endpoint anyway)', () {
      expect(
        locateSeparationMinimum(
          from: 0.5,
          end: 1,
          firstStep: 1e-5,
          separationAt: (t) => (t - 1.0).abs(),
        ),
        isNull,
      );
    });
  });
}
