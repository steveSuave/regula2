@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/event_loop_yield.dart';
import 'package:regula/domain/prover/fact_database.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/rule_engine.dart';

/// Phase 143 / M-P2b: the shipped yield, held to the Phase 140 finding
/// in a real browser.
///
/// `yield_cost_web_test.dart` measured the primitive; this pins the
/// *promotion*: `lib`'s `yieldToEventLoop` reaches the web arm through
/// its conditional import and behaves like the channel, not like a
/// timer. The failure this exists to catch is silent in every other
/// harness — the VM arm (`Future.delayed`) compiles cleanly for web and
/// merely runs 100× slower under the setTimeout clamp, so only a
/// browser measurement can tell the arms apart (the Phase 140 rule:
/// the analyzer proves nothing about a conditional import's seam).
///
/// Run with `flutter test --platform chrome test/web`.
Future<double> _perYieldMs(int n, Future<void> Function() yield_) async {
  // The warmup is load-bearing: the setTimeout clamp only engages once
  // the nesting level passes five, so an unwarmed run would measure the
  // unclamped cost and could not tell the arms apart.
  for (var i = 0; i < 10; i++) {
    await yield_();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await yield_();
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000 / n;
}

void main() {
  test('the shipped yield is the channel, not a timer', () async {
    const yields = 120;
    final timerMs = await _perYieldMs(
      yields,
      () => Future<void>.delayed(Duration.zero),
    );
    final shippedMs = await _perYieldMs(yields, yieldToEventLoop);

    // ignore: avoid_print
    print(
      'shipped yield ${shippedMs.toStringAsFixed(3)} ms, '
      'timer ${timerMs.toStringAsFixed(3)} ms',
    );

    expect(
      timerMs,
      greaterThan(1.0),
      reason: 'a nested setTimeout(0) must show the clamp',
    );
    expect(
      shippedMs,
      lessThan(timerMs / 2),
      reason:
          'the shipped yield must not be clamped like a timer — if it '
          'is, the conditional import resolved to the wrong arm',
    );
  });

  test(
    'a chunked fixpoint in the browser derives the straight result',
    () async {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(6, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 5));
      final mab = Midpoint(id: 'mab', point1: a, point2: b);
      final mbc = Midpoint(id: 'mbc', point1: b, point2: c);
      final construction = Construction();
      for (final object in [a, b, c, mab, mbc]) {
        construction.add(object);
      }
      final filter = DiagramFilter.probe(construction.objects);

      ProverEngine engine() {
        final database = FactDatabase();
        seedHypotheses(database, hypotheses(construction.objects), filter);
        return ProverEngine(database: database, filter: filter);
      }

      final straight = engine();
      straight.run();
      final chunked = engine();
      final total = await chunked.runChunked(chunkBudget: 1);

      expect(chunked.isComplete, isTrue);
      expect(total, straight.applications);
      expect(
        [for (final fact in chunked.database.facts) '$fact'],
        [for (final fact in straight.database.facts) '$fact'],
      );
    },
  );
}
