/// Native arm of `event_loop_yield.dart` — see the facade for the
/// decision and the measurements.
library;

/// One turn of the event loop. No browser, no clamp: a zero timer is
/// the idiomatic yield here, and the `MessageChannel` machinery has
/// nothing to route around.
Future<void> yieldToEventLoop() => Future<void>.delayed(Duration.zero);
