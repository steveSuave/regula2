import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/projective/tracing/trace_diagnostics.dart';

void main() {
  final lines = <String>[];

  setUp(() {
    TraceDiagnostics.reset();
    lines.clear();
    TraceDiagnostics.sink = lines.add;
    TraceDiagnostics.enabled = true;
    TraceDiagnostics.slowFrameMs = 32;
    TraceDiagnostics.stallReportMs = 1000;
  });

  tearDown(() {
    TraceDiagnostics.enabled = false;
    TraceDiagnostics.sink = null;
    TraceDiagnostics.reset();
  });

  group('TraceDiagnostics', () {
    test('records a frame with its counters', () {
      TraceDiagnostics.frameBegin('drag A');
      TraceDiagnostics.count(TraceCounter.chainSolves, 7);
      TraceDiagnostics.count(TraceCounter.dragAccepted);
      TraceDiagnostics.count(TraceCounter.dragAccepted);
      TraceDiagnostics.frameEnd();

      final history = TraceDiagnostics.history;
      expect(history, hasLength(1));
      expect(history.single.label, 'drag A');
      expect(history.single[TraceCounter.chainSolves], 7);
      expect(history.single[TraceCounter.dragAccepted], 2);
      expect(history.single[TraceCounter.dragDetours], 0);
    });

    test('disarmed, nothing is recorded and nothing is emitted', () {
      TraceDiagnostics.enabled = false;
      TraceDiagnostics.frameBegin('drag A');
      TraceDiagnostics.count(TraceCounter.chainSolves, 100);
      TraceDiagnostics.checkpoint('walk');
      TraceDiagnostics.frameEnd();
      expect(TraceDiagnostics.history, isEmpty);
      expect(lines, isEmpty);
    });

    test('frames nest: an inner span joins the outer frame under the '
        "outer's label", () {
      // The property that lets entry points be instrumented without
      // knowing who called them — a locus recompute inside a drag.
      TraceDiagnostics.frameBegin('drag A');
      TraceDiagnostics.frameBegin('locus d');
      TraceDiagnostics.count(TraceCounter.chainSolves, 3);
      TraceDiagnostics.frameEnd();
      expect(
        TraceDiagnostics.history,
        isEmpty,
        reason: 'the inner end does not close the frame',
      );
      TraceDiagnostics.count(TraceCounter.chainSolves, 2);
      TraceDiagnostics.frameEnd();

      expect(TraceDiagnostics.history, hasLength(1));
      expect(TraceDiagnostics.history.single.label, 'drag A');
      expect(TraceDiagnostics.history.single[TraceCounter.chainSolves], 5);
    });

    test('the same span standing alone opens a frame of its own', () {
      TraceDiagnostics.frameBegin('locus d');
      TraceDiagnostics.count(TraceCounter.locusRecomputes);
      TraceDiagnostics.frameEnd();
      expect(TraceDiagnostics.history.single.label, 'locus d');
    });

    test('a slow frame is streamed; a fast one is not', () {
      TraceDiagnostics.slowFrameMs = 0;
      TraceDiagnostics.frameBegin('slow');
      TraceDiagnostics.frameEnd();
      expect(lines, hasLength(1));
      expect(lines.single, contains('slow'));

      TraceDiagnostics.slowFrameMs = 1e9;
      TraceDiagnostics.frameBegin('fast');
      TraceDiagnostics.frameEnd();
      expect(lines, hasLength(1), reason: 'the fast frame stayed quiet');
    });

    test('a checkpoint reports from inside an overrunning frame, rate '
        'limited, and marks it stalled', () {
      // The freeze-survivable path: the report has to leave *during* the
      // frame, because a frame that never returns never ends.
      TraceDiagnostics.stallReportMs = 0;
      TraceDiagnostics.frameBegin('wedged');
      TraceDiagnostics.count(TraceCounter.chainSolves, 4);
      TraceDiagnostics.checkpoint('locus leg', detail: () => 'd=0.5');
      expect(lines, hasLength(1));
      expect(lines.single, contains('STALL'));
      expect(lines.single, contains('locus leg'));
      expect(lines.single, contains('wedged'));
      expect(lines.single, contains('solves=4'));
      expect(lines.single, contains('d=0.5'));
      expect(TraceDiagnostics.current!.stalled, isTrue);

      TraceDiagnostics.stallReportMs = 1e9;
      TraceDiagnostics.checkpoint('locus leg');
      expect(lines, hasLength(1), reason: 'rate limited');
      TraceDiagnostics.frameEnd();
      expect(TraceDiagnostics.history.single.stalled, isTrue);
    });

    test('a checkpoint outside a frame is a no-op', () {
      TraceDiagnostics.stallReportMs = 0;
      TraceDiagnostics.checkpoint('nowhere');
      expect(lines, isEmpty);
    });

    test('detail is not built unless the frame has actually overrun', () {
      var built = 0;
      TraceDiagnostics.stallReportMs = 1e9;
      TraceDiagnostics.frameBegin('quick');
      TraceDiagnostics.checkpoint('leg', detail: () => '${built++}');
      TraceDiagnostics.frameEnd();
      expect(built, 0);
    });

    test('history is capped at historyLimit, oldest dropped', () {
      TraceDiagnostics.historyLimit = 3;
      addTearDown(() => TraceDiagnostics.historyLimit = 300);
      for (var i = 0; i < 6; i++) {
        TraceDiagnostics.frameBegin('f$i');
        TraceDiagnostics.frameEnd();
      }
      expect(
        [for (final f in TraceDiagnostics.history) f.label],
        ['f3', 'f4', 'f5'],
      );
    });

    test('report names the totals, the worst frames and the empty case', () {
      expect(TraceDiagnostics.report(), contains('nothing recorded'));
      TraceDiagnostics.frameBegin('drag A');
      TraceDiagnostics.count(TraceCounter.collisionProbes, 410);
      TraceDiagnostics.frameEnd();
      final report = TraceDiagnostics.report();
      expect(report, contains('collisionProbes: 410'));
      expect(report, contains('slowest frames'));
      expect(report, contains('drag A'));
      expect(
        report,
        isNot(contains('dragBails')),
        reason: 'counters that never fired stay out of the report',
      );
    });

    test('reset clears history and the frame counter', () {
      TraceDiagnostics.frameBegin('drag A');
      TraceDiagnostics.frameEnd();
      TraceDiagnostics.reset();
      expect(TraceDiagnostics.history, isEmpty);
      TraceDiagnostics.frameBegin('drag B');
      TraceDiagnostics.frameEnd();
      expect(TraceDiagnostics.history.single.index, 0);
    });
  });
}
