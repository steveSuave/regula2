/// The prover's yield to the event loop (PLAN §"The prover yields with a
/// MessageChannel, not a timer") — the primitive Phase 140 measured and
/// M-P2b is the first consumer of, promoted here from the browser gate's
/// measurement rig.
///
/// On web this is a `MessageChannel` `postMessage` round trip: a
/// macrotask, so the browser renders between chunks, but not a timer, so
/// the HTML spec's 4 ms nested-`setTimeout` clamp never applies —
/// measured 105× cheaper than `Future.delayed(Duration.zero)` in a real
/// browser, which is the difference between a fixpoint chunking at no
/// measurable overhead and one running 150× slower than unchunked. A
/// microtask (`await null`) is rejected in the other direction: cheaper
/// still, and worthless, because the microtask queue drains before the
/// browser renders.
///
/// On the VM and AOT, `Future.delayed(Duration.zero)` has no clamp and
/// is the ordinary event-loop turn.
///
/// The split is a **conditional import, never a runtime capability
/// check** — the Phase 140 rule: `dart:isolate` (and the reverse,
/// `dart:js_interop` on the VM) compiles cleanly where it cannot run and
/// fails only at runtime, so the analyzer proves nothing here and the
/// browser gate is what holds the seam.
library;

export 'event_loop_yield_vm.dart'
    if (dart.library.js_interop) 'event_loop_yield_web.dart';
