import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/locus_refresh.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/drag_session.dart';

/// Phase 117d: a locus is the only leaf whose recompute has no bounded
/// cost, so during a drag preview it is allowed to lag the pointer
/// rather than pace it. These pin the policy and — more importantly —
/// that lagging never reaches the committed construction.
void main() {
  tearDown(() {
    LocusRefresh.previewing = false;
    LocusRefresh.maxShare = 0.5;
  });

  group('LocusRefresh.due', () {
    test('outside a preview, always', () {
      LocusRefresh.previewing = false;
      expect(LocusRefresh.due(lastSweepMs: 1000, idleMs: 0), isTrue);
    });

    test('a locus that has never swept always sweeps — a first frame '
        'must draw something', () {
      LocusRefresh.previewing = true;
      expect(LocusRefresh.due(lastSweepMs: 0, idleMs: 0), isTrue);
    });

    test('at the default half share, a sweep must sit out its own '
        'duration', () {
      LocusRefresh.previewing = true;
      expect(LocusRefresh.due(lastSweepMs: 10, idleMs: 9.9), isFalse);
      expect(LocusRefresh.due(lastSweepMs: 10, idleMs: 10), isTrue);
      // Self-tuning: the rule holds no wall-clock constant, so a sweep
      // 40x more expensive simply waits 40x longer.
      expect(LocusRefresh.due(lastSweepMs: 400, idleMs: 399), isFalse);
      expect(LocusRefresh.due(lastSweepMs: 400, idleMs: 400), isTrue);
    });

    test('share 1 restores the pre-117d behaviour: every frame sweeps, '
        'however long it takes', () {
      LocusRefresh.previewing = true;
      LocusRefresh.maxShare = 1;
      expect(LocusRefresh.due(lastSweepMs: 1e6, idleMs: 0), isTrue);
    });

    test('a tiny share throttles hard, and share is clamped out of '
        'nonsense', () {
      LocusRefresh.previewing = true;
      LocusRefresh.maxShare = 0.1;
      expect(LocusRefresh.due(lastSweepMs: 10, idleMs: 89), isFalse);
      expect(LocusRefresh.due(lastSweepMs: 10, idleMs: 90), isTrue);
      LocusRefresh.maxShare = 0;
      expect(LocusRefresh.due(lastSweepMs: 1, idleMs: 998), isFalse);
      LocusRefresh.maxShare = 5;
      expect(LocusRefresh.due(lastSweepMs: 1e6, idleMs: 0), isTrue);
    });
  });

  group('LocusRefresh.preview', () {
    test('scopes the flag, nests, and restores even on a throw', () {
      expect(LocusRefresh.previewing, isFalse);
      LocusRefresh.preview(() {
        expect(LocusRefresh.previewing, isTrue);
        LocusRefresh.preview(() => expect(LocusRefresh.previewing, isTrue));
        expect(LocusRefresh.previewing, isTrue);
      });
      expect(LocusRefresh.previewing, isFalse);

      expect(
        () => LocusRefresh.preview(() => throw StateError('boom')),
        throwsStateError,
      );
      expect(
        LocusRefresh.previewing,
        isFalse,
        reason: 'a stuck flag would freeze every locus until the next commit',
      );
    });
  });

  group('a dragged construction carrying a locus', () {
    late Construction construction;
    late FreePoint anchor;
    late Locus locus;

    setUp(() {
      construction = Construction();
      anchor = FreePoint(id: 'a', position: Vec2.zero);
      final circle = FixedRadiusCircle(id: 'k', center: anchor, radius: 4);
      final driver = PointOnObject(id: 'd', curve: circle, parameter: 0);
      final traced = Midpoint(id: 'm', point1: anchor, point2: driver);
      locus = Locus(id: 'L', driver: driver, traced: traced);
      construction
        ..add(anchor)
        ..add(circle)
        ..add(driver)
        ..add(traced)
        ..add(locus);
    });

    List<Vec2?> samples() => List.of(locus.samples!);

    test('preview frames coalesce the sweep, and the command that ends '
        'the gesture leaves it current', () {
      // A share this small makes any sweep that took measurable time
      // owe a wait far longer than a synchronous test loop, so the
      // coalescing is deterministic rather than a race with the clock.
      LocusRefresh.maxShare = 1e-3;
      final before = samples();
      final session = DragSession.start(construction, anchor, Vec2.zero)!;
      for (var i = 1; i <= 8; i++) {
        session.update(Vec2(i * 3.0, 0));
      }
      expect(
        locus.samples,
        before,
        reason: 'the previewed sweeps were skipped — the locus lags',
      );

      final command = session.end()!;
      command.apply(construction);
      expect(
        locus.samples,
        isNot(before),
        reason: 'the commit is never stale: it runs outside the preview',
      );
      // The committed locus is the one a fresh sweep would produce.
      final committed = samples();
      locus.recompute();
      expect(locus.samples, committed);
    });

    test('a cancelled gesture leaves the locus back at its start, not at '
        'whatever frame the throttle last let through', () {
      LocusRefresh.maxShare = 1e-3;
      final before = samples();
      final session = DragSession.start(construction, anchor, Vec2.zero)!;
      for (var i = 1; i <= 8; i++) {
        session.update(Vec2(i * 3.0, 0));
      }
      session.cancel();
      expect(locus.samples, before);
    });

    test('at full share nothing is coalesced — the throttle is opt-out, '
        'and off it is the old behaviour exactly', () {
      LocusRefresh.maxShare = 1;
      final session = DragSession.start(construction, anchor, Vec2.zero)!;
      session.update(const Vec2(12, 0));
      final previewed = samples();
      expect(previewed, isNot(locus.samples!.map((_) => null).toList()));
      // The previewed sweep is the sweep the same state produces cold.
      session.cancel();
      construction.moveFreePoint('a', const Vec2(12, 0));
      expect(locus.samples, previewed);
    });
  });
}
