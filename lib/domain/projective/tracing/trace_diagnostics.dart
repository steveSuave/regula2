/// Field instrumentation for the tracing engine (Phase 117c).
///
/// The engine's cost is invisible from outside: a drag frame that takes
/// a second looks exactly like one that takes a millisecond, and a frame
/// that never returns looks like a frozen tab. This records what each
/// frame actually spent — where, on how many chain solves — and can say
/// so *while a frame is still running*, which is the only way a stall
/// inside a bounded-but-huge loop ever gets reported.
///
/// Pure Dart by construction (`lib/domain` may not import Flutter): text
/// leaves through [sink], which the app points at the console.
///
/// Cost when armed is a counter bump per event and one `Stopwatch` per
/// frame; [enabled] is checked first at every site so a disarmed build
/// pays a bool read. Nothing here is on the correctness path — the
/// engine must behave identically with it armed or not.
library;

/// What a frame spent its work on.
///
/// The unit that matters is [chainSolves]: one recompute of the affected
/// subgraph. Trials, probes and dives are all just ways of spending
/// those, and it is chain solves — not trials — that a slow frame is
/// made of.
enum TraceCounter {
  /// Traced drag passes started (one per preview frame that traces).
  dragPasses,

  /// Trials the drag step controller accepted.
  dragAccepted,

  /// Trials it rejected (each one a wasted chain solve).
  dragRejected,

  /// Detour arcs walked around a root collision during a drag.
  dragDetours,

  /// Trials spent *inside* those arcs, accepted and rejected alike —
  /// the arc's own share of [dragAccepted] + [dragRejected], so a
  /// detour's cost can be read apart from the creep that triggered it
  /// and the exit that follows it (Phase 189).
  dragArcTrials,

  /// Passes that gave up and fell back to the static solve.
  dragBails,

  /// `Locus.recompute` calls that actually swept.
  locusRecomputes,

  /// `Locus.recompute` calls a preview frame skipped, because the last
  /// sweep had not yet earned another (see `LocusRefresh`). A frame
  /// showing these is a frame whose locus is deliberately lagging the
  /// pointer to keep the gesture live.
  locusCoalesced,

  /// Canonical scan samples solved (the structure pass).
  locusScanSolves,

  /// Trials the locus walk spent.
  locusTrials,

  /// Trials the locus walk spent refining for *drawing* density rather
  /// than for branch safety — bounded in advance, and kept apart so
  /// `locusTrials` stays a reading of the walk's own effort.
  locusDensityTrials,

  /// Detour arcs the locus walk walked.
  locusDetours,

  /// Locus legs that ended by exhausting their trial budget — the walk
  /// paying full price and still not arriving.
  locusBudgetEnds,

  /// Fold ends the locus walk turned around at (each one a swap and a
  /// reversed leg — the walk paying for the same span twice).
  locusFolds,

  /// Separation-profile probes spent locating a collision. Each is a
  /// chain solve, and they are *not* trials — a starvation that measures
  /// costs far more than its trial count suggests.
  collisionProbes,

  /// Every recompute of an affected subgraph, from any of the above.
  chainSolves,
}

/// One frame's record.
class TraceFrameRecord {
  TraceFrameRecord(this.index, this.label);

  /// Monotonic frame number since the last [TraceDiagnostics.reset].
  final int index;

  /// What the frame was ('drag C', 'slide D', 'load', …).
  final String label;

  /// Wall time for the whole frame.
  double totalMs = 0;

  /// Of which, inside `Locus.recompute`.
  double locusMs = 0;

  /// Whether the frame ran long enough to report a stall mid-flight.
  bool stalled = false;

  final Map<TraceCounter, int> counts = {};

  int operator [](TraceCounter c) => counts[c] ?? 0;

  /// A single line, fixed field order, safe to paste into an issue.
  String get line {
    final fields = [
      'f$index',
      label,
      '${totalMs.toStringAsFixed(1)}ms',
      'locus=${locusMs.toStringAsFixed(1)}ms',
      'solves=${this[TraceCounter.chainSolves]}',
      'drag=${this[TraceCounter.dragAccepted]}a/'
          '${this[TraceCounter.dragRejected]}r/'
          '${this[TraceCounter.dragDetours]}d',
      'locusWalk=${this[TraceCounter.locusTrials]}t'
          '+${this[TraceCounter.locusDensityTrials]}dens/'
          '${this[TraceCounter.locusDetours]}d/'
          '${this[TraceCounter.locusFolds]}fold',
      'probes=${this[TraceCounter.collisionProbes]}',
      if (this[TraceCounter.locusCoalesced] > 0)
        'coalesced=${this[TraceCounter.locusCoalesced]}',
      if (this[TraceCounter.locusBudgetEnds] > 0)
        'BUDGET-END×${this[TraceCounter.locusBudgetEnds]}',
      if (this[TraceCounter.dragBails] > 0)
        'BAIL×${this[TraceCounter.dragBails]}',
      if (stalled) 'STALLED',
    ];
    return fields.join(' · ');
  }
}

/// The recorder. Process-global and deliberately mutable, like
/// `TracingFlags` next door.
abstract final class TraceDiagnostics {
  /// Master switch. Off by default: an unarmed build pays one bool read
  /// per instrumented site and records nothing.
  static bool enabled = false;

  /// Where text goes. Null discards it (the default, and what tests
  /// want unless they are testing the text itself).
  static void Function(String line)? sink;

  /// Frames at least this slow are streamed to [sink] as they finish.
  /// A frame that never finishes is covered by [stallReportMs] instead.
  static double slowFrameMs = 32;

  /// How long a frame may run before the engine starts reporting from
  /// *inside* it, and the interval between those reports. This is the
  /// part that survives a freeze: a tab wedged in a walk still prints
  /// where the walk is, every [stallReportMs], until it finishes or the
  /// user kills the tab.
  static double stallReportMs = 1000;

  /// How many frame records to keep.
  static int historyLimit = 300;

  static final List<TraceFrameRecord> _history = [];
  static TraceFrameRecord? _current;
  static Stopwatch? _clock;
  static double _lastStallReport = double.negativeInfinity;
  static int _frames = 0;
  static Stopwatch? _locusClock;
  static int _depth = 0;

  /// The frames recorded so far, oldest first.
  static List<TraceFrameRecord> get history => List.unmodifiable(_history);

  /// The frame being recorded, if one is open.
  static TraceFrameRecord? get current => _current;

  /// Clears the history and the frame counter.
  static void reset() {
    _history.clear();
    _current = null;
    _clock = null;
    _locusClock = null;
    _frames = 0;
    _depth = 0;
    _lastStallReport = double.negativeInfinity;
  }

  /// Opens a frame, or joins the one already open.
  ///
  /// Frames nest by depth so entry points may be instrumented freely
  /// without knowing who called them — a locus recompute inside a drag
  /// frame counts towards that drag, and the same recompute triggered by
  /// a load or an undo opens a frame of its own. The outermost label
  /// wins, which is the one that names what the user did.
  ///
  /// Every [frameBegin] must be matched by a [frameEnd] in a `finally`.
  static void frameBegin(String label) {
    if (!enabled) {
      return;
    }
    if (_depth++ > 0) {
      return;
    }
    _current = TraceFrameRecord(_frames++, label);
    _clock = Stopwatch()..start();
    _locusClock = null;
    _lastStallReport = double.negativeInfinity;
  }

  /// Closes the innermost open frame; the outermost one records.
  static void frameEnd() {
    if (_depth > 0 && --_depth > 0) {
      return;
    }
    final frame = _current;
    final clock = _clock;
    if (frame == null || clock == null) {
      return;
    }
    frame.totalMs = clock.elapsedMicroseconds / 1000;
    _current = null;
    _clock = null;
    _history.add(frame);
    while (_history.length > historyLimit) {
      _history.removeAt(0);
    }
    if (frame.totalMs >= slowFrameMs || frame.stalled) {
      sink?.call('[trace] ${frame.line}');
    }
  }

  /// Adds [n] to [counter] in the open frame.
  static void count(TraceCounter counter, [int n = 1]) {
    final frame = _current;
    if (frame == null) {
      return;
    }
    frame.counts[counter] = (frame.counts[counter] ?? 0) + n;
  }

  /// Marks the start of a `Locus.recompute`, so its share of the frame
  /// is attributed separately. Nested calls are ignored — the outermost
  /// span wins, which is what "time inside the locus" means.
  static void locusBegin() {
    if (!enabled || _current == null || _locusClock != null) {
      return;
    }
    _locusClock = Stopwatch()..start();
  }

  /// Ends the span opened by [locusBegin].
  static void locusEnd() {
    final clock = _locusClock;
    if (clock == null) {
      return;
    }
    _current?.locusMs += clock.elapsedMicroseconds / 1000;
    _locusClock = null;
  }

  /// Reports from inside a long-running frame.
  ///
  /// Call it from the engine's inner loops with a cheap [where] and a
  /// lazily-built [detail]: nothing is formatted until a frame has
  /// actually overrun, and then at most once per [stallReportMs]. This
  /// is what makes a freeze legible — the reports arrive *during* the
  /// wedge, not after it.
  static void checkpoint(String where, {String Function()? detail}) {
    final clock = _clock;
    if (clock == null) {
      return;
    }
    final ms = clock.elapsedMicroseconds / 1000;
    // Two gates, both read live so the interval can be retuned between
    // reports: the frame must have overrun, and the last report must be
    // an interval old.
    if (ms < stallReportMs || ms - _lastStallReport < stallReportMs) {
      return;
    }
    _lastStallReport = ms;
    final frame = _current!..stalled = true;
    sink?.call(
      '[trace] STALL ${ms.toStringAsFixed(0)}ms in $where '
      '(f${frame.index} ${frame.label}) '
      'solves=${frame[TraceCounter.chainSolves]}'
      '${detail == null ? '' : ' — ${detail()}'}',
    );
  }

  /// A copy-pasteable report over the recorded history: totals, the
  /// slowest frames, and the tail in full.
  static String report() {
    if (_history.isEmpty) {
      return 'trace diagnostics: nothing recorded '
          '(enabled=$enabled — arm it, reproduce, then dump again)';
    }
    final buffer = StringBuffer()
      ..writeln('=== regula trace diagnostics ===')
      ..writeln(
        'frames recorded: ${_history.length} (of $_frames since reset)',
      );
    final times = [for (final f in _history) f.totalMs]..sort();
    double pct(double p) => times[((times.length - 1) * p).round()];
    buffer
      ..writeln(
        'frame ms: median ${pct(0.5).toStringAsFixed(1)} · '
        'p90 ${pct(0.9).toStringAsFixed(1)} · '
        'worst ${times.last.toStringAsFixed(1)}',
      )
      ..writeln(
        'locus share: '
        '${(_history.fold(0.0, (s, f) => s + f.locusMs) * 100 / _history.fold(1e-9, (s, f) => s + f.totalMs)).toStringAsFixed(0)}%',
      );
    final totals = <TraceCounter, int>{};
    for (final f in _history) {
      for (final e in f.counts.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
      }
    }
    buffer.writeln('totals:');
    for (final c in TraceCounter.values) {
      if ((totals[c] ?? 0) > 0) {
        buffer.writeln('  ${c.name}: ${totals[c]}');
      }
    }
    final slowest = [..._history]
      ..sort((a, b) => b.totalMs.compareTo(a.totalMs));
    buffer.writeln('slowest frames:');
    for (final f in slowest.take(10)) {
      buffer.writeln('  ${f.line}');
    }
    buffer.writeln('last frames:');
    for (final f in _history.skip(
      _history.length > 40 ? _history.length - 40 : 0,
    )) {
      buffer.writeln('  ${f.line}');
    }
    buffer.write('=== end ===');
    return buffer.toString();
  }
}
