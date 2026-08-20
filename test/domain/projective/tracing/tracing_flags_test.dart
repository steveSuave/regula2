import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/projective/tracing/tracing_flags.dart';

/// Phase 139: the trial budget is an amount of work divided by what one
/// trial of a given construction costs, not a constant number of trials.
/// PLAN §"The step budget is an amount of work, not a number of trials".
void main() {
  group('dragStepBudgetFor', () {
    test('the gate rig gets exactly what shipped as the constant', () {
      // This is the whole claim of the recalibration: the work quota is
      // the old constant restated against the construction it was tuned
      // on, so that construction's budget does not move. 100 objects,
      // 96 of them downstream of the dragged point.
      expect(TracingFlags.dragStepBudgetFor(96), 128);
      expect(TracingFlags.dragStepBudgetWork, 128 * 96);
    });

    test('a smaller graph is handed proportionally more trials', () {
      // Half the per-trial work, twice the trials — the same wall-clock
      // cost for a starving frame, which is the invariant the shape
      // exists to buy.
      expect(TracingFlags.dragStepBudgetFor(48), 256);
      expect(TracingFlags.dragStepBudgetFor(24), 512);
      expect(TracingFlags.dragStepBudgetFor(12), 1024);
    });

    test('the floor is the previous constant, so nothing loses budget', () {
      // Past the crossover the derivation would hand out less than
      // shipped. It does not: large graphs behave exactly as before,
      // which is what makes this change safe to land.
      expect(
        TracingFlags.dragStepBudgetFor(97),
        TracingFlags.dragStepBudgetMin,
      );
      expect(TracingFlags.dragStepBudgetFor(384), 128);
      expect(TracingFlags.dragStepBudgetFor(100000), 128);
      expect(TracingFlags.dragStepBudgetMin, 128);
    });

    test('the ceiling bounds the small-graph case', () {
      // Four objects downstream would otherwise be handed 3072 trials,
      // and a starving walk stops progressing well before that.
      expect(TracingFlags.dragStepBudgetFor(4), TracingFlags.dragStepBudgetMax);
      expect(TracingFlags.dragStepBudgetFor(1), 2048);
      expect(TracingFlags.dragStepBudgetMax, 2048);
    });

    test('a graph with nothing downstream is still a legal budget', () {
      // Dragging a point nothing depends on: the pass has no slots to
      // seed and collapses to one static solve, but the budget it is
      // handed must still satisfy recomputeAlongPath's `>= 1`.
      expect(TracingFlags.dragStepBudgetFor(0), greaterThanOrEqualTo(1));
      expect(TracingFlags.dragStepBudgetFor(-1), greaterThanOrEqualTo(1));
    });

    test('it is monotone: more work per trial is never more trials', () {
      var previous = TracingFlags.dragStepBudgetFor(1);
      for (var objects = 2; objects <= 512; objects++) {
        final budget = TracingFlags.dragStepBudgetFor(objects);
        expect(budget, lessThanOrEqualTo(previous), reason: 'at $objects');
        previous = budget;
      }
    });
  });

  group('the pin', () {
    tearDown(() => TracingFlags.dragStepBudget = null);

    test('defaults to null — derived, not set', () {
      expect(TracingFlags.dragStepBudget, isNull);
    });

    test('zero is a legal pin, and it is the bail switch', () {
      // `recomputeAlongPath` throws on a budget below 1, and the drag
      // sessions' catch-all turns that into a static frame — the
      // harshest stand-in for an engine failure, used by
      // drag_session_tracing_test.
      TracingFlags.dragStepBudget = 0;
      expect(TracingFlags.dragStepBudget, 0);
    });
  });
}
