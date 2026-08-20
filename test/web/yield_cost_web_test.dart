@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';

/// Phase 140 / M-P0: what one yield to the event loop costs, measured in
/// a real browser, because nothing else can answer this.
///
/// `benchmark/threading_bench.dart` found that cooperatively chunking a
/// 90 ms fixpoint costs 154× on dart2wasm and times out on dart2js when
/// the yield is `Future.delayed(Duration.zero)`. That is not a property
/// of chunking. `Future.delayed` compiles to `setTimeout(f, 0)`, and
/// setTimeout is **clamped**: the HTML spec requires a 4 ms floor once
/// five timeouts have nested, so a loop that yields this way runs at
/// most ~250 chunks/second however small the chunks are.
///
/// The clamp is a browser rule and Node does not implement the same one
/// — Node clamps to ~1 ms, and worse, dart2js under Node exits silently
/// part-way through a microtask-yield loop. So the numbers that decide
/// M-P0 cannot come from the benchmark harness; they have to come from
/// here. That is the same rule Phase 126d wrote this directory for: web
/// is the compile target, and the VM (or Node) harness is not evidence
/// about it.
///
/// Run with `flutter test --platform chrome test/web`.
@JS('MessageChannel')
extension type _MessageChannel._(JSObject _) implements JSObject {
  external factory _MessageChannel();
  external _MessagePort get port1;
  external _MessagePort get port2;
}

extension type _MessagePort._(JSObject _) implements JSObject {
  external void postMessage(JSAny? message);
  external set onmessage(JSFunction? handler);
  external void start();
}

/// A yield that is a macrotask — so the browser gets to render — and is
/// not a timer, so no clamp applies. This is the primitive browser
/// schedulers settle on for exactly this reason.
///
/// One channel for the life of the run: building one per yield would
/// measure allocation rather than scheduling.
class _ChannelYield {
  _ChannelYield() {
    _channel.port1.onmessage = ((JSObject _) {
      final pending = _pending;
      _pending = null;
      pending?.complete();
    }).toJS;
    _channel.port1.start();
    _channel.port2.start();
  }

  final _MessageChannel _channel = _MessageChannel();
  Completer<void>? _pending;

  Future<void> call() {
    final completer = Completer<void>();
    _pending = completer;
    _channel.port2.postMessage(0.toJS);
    return completer.future;
  }
}

/// Milliseconds per yield over [n] yields.
///
/// The warmup is load-bearing rather than hygiene: the timer clamp only
/// engages once the nesting level passes five, so a measurement that
/// does not first nest deeply enough reports the *unclamped* cost of
/// setTimeout and misses the entire finding.
Future<double> _perYieldMs(int n, Future<void> Function() yield_) async {
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
  // Enough to sit well past the nesting threshold, few enough that a
  // clamped run still finishes in about a second.
  const yields = 120;

  test('setTimeout is clamped and MessageChannel is not', () async {
    final timerMs = await _perYieldMs(
      yields,
      () => Future<void>.delayed(Duration.zero),
    );
    final channelMs = await _perYieldMs(yields, _ChannelYield().call);
    final microtaskMs = await _perYieldMs(yields, () async {});

    // Printed because the numbers are the deliverable — M-P0 is a
    // measurement phase, and this is where its web half is taken.
    // ignore: avoid_print
    print(
      'yield cost: timer ${timerMs.toStringAsFixed(3)} ms, '
      'MessageChannel ${channelMs.toStringAsFixed(3)} ms, '
      'microtask ${microtaskMs.toStringAsFixed(4)} ms '
      '— timer/channel = ${(timerMs / channelMs).toStringAsFixed(1)}x',
    );

    // The finding, stated as a property rather than as a number, so it
    // holds across browsers and machines: a nested setTimeout costs
    // milliseconds, and the channel costs a small fraction of one.
    expect(
      timerMs,
      greaterThan(1.0),
      reason: 'a nested setTimeout(0) must show the clamp',
    );
    expect(
      channelMs,
      lessThan(timerMs / 2),
      reason: 'MessageChannel must not be clamped like a timer',
    );

    // And the microtask shows no clamp either — it is comparably cheap,
    // which is exactly why cost is not what disqualifies it: it never
    // returns to the event loop, so nothing renders between chunks.
    // Deliberately *not* ordered against the channel: both sit at a few
    // hundredths of a millisecond, inside scheduling noise of each other
    // on a shared runner, and no decision rests on which photo-finishes
    // first (a CI run measured 0.039 vs 0.037 and failed the strict
    // ordering this assertion used to state).
    expect(microtaskMs, lessThan(timerMs / 2));
  });

  test('a chunked run yields often enough to stay interactive', () async {
    // The shape the prover will run in: chunks of work separated by a
    // yield the browser can render through. At a 4 ms chunk — comfortably
    // inside a 16.7 ms frame alongside the app's own painting — the
    // question is what fraction of wall-clock the scheduling costs.
    final channel = _ChannelYield();
    const chunks = 60;
    var sink = 0;
    final sw = Stopwatch()..start();
    for (var i = 0; i < chunks; i++) {
      final chunkEnd = sw.elapsedMicroseconds + 4000;
      while (sw.elapsedMicroseconds < chunkEnd) {
        sink += i;
      }
      await channel();
    }
    sw.stop();
    final overhead = (sw.elapsedMilliseconds - chunks * 4) / chunks;

    // ignore: avoid_print
    print(
      'chunked run: $chunks x 4 ms chunks took '
      '${sw.elapsedMilliseconds} ms — ${overhead.toStringAsFixed(3)} ms '
      'per yield of overhead',
    );
    expect(sink, greaterThan(0));
    // A 4 ms chunk must not be doubled by its own scheduling. The timer
    // route fails this outright, which is the whole point.
    expect(
      sw.elapsedMilliseconds,
      lessThan(chunks * 8),
      reason: 'scheduling must not cost as much as the work',
    );
  });
}
