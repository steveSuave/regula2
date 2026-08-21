/// Web arm of `event_loop_yield.dart` — see the facade for the decision
/// and the measurements. The `MessageChannel` idiom is the Phase 140
/// measurement rig's (`test/web/yield_cost_web_test.dart`), promoted:
/// one channel for the life of the isolate, because building one per
/// yield would spend the yield's own budget on allocation.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';

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

final _pending = Queue<Completer<void>>();

final _MessageChannel _channel = () {
  final channel = _MessageChannel();
  channel.port1.onmessage = ((JSObject _) {
    // FIFO: messages arrive in post order, so the front completer is
    // the one whose message this is.
    _pending.removeFirst().complete();
  }).toJS;
  channel.port1.start();
  channel.port2.start();
  return channel;
}();

/// One macrotask round trip through the channel: returns to the event
/// loop (the browser renders) without ever touching a timer (nothing
/// clamps).
Future<void> yieldToEventLoop() {
  final completer = Completer<void>();
  _pending.add(completer);
  _channel.port2.postMessage(0.toJS);
  return completer.future;
}
