import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/construction_provider.dart';
import '../../application/providers/tool_provider.dart';
import '../../domain/projective/tracing/trace_diagnostics.dart';

/// The Phase 116 tracing debug overlay: a small non-interactive chip in
/// the canvas corner showing what the most recent traced drag frame cost
/// the step controller — accepted and rejected trials, detours walked,
/// or that the frame bailed to the static solve. Mounted behind the
/// Show/hide trace overlay shortcut; renders a waiting hint until the
/// first traced frame runs.
///
/// Watching the construction keeps the chip live mid-gesture: every
/// preview frame notifies, so the counts update as the drag moves. The
/// stats survive the gesture (`ToolNotifier.lastTraceStats`), so the
/// chip keeps showing what the last drag cost until the next one.
///
/// Phase 117c adds the second line: what the frame *cost* — wall
/// milliseconds, the locus sweep's share of them, and the chain solves
/// they went on. Counts alone never distinguished a frame that felt
/// instant from one that took a second, which is exactly the complaint
/// the overlay existed to diagnose. Ctrl/⌘⇧O dumps the full history.
class TraceStatsOverlay extends ConsumerWidget {
  const TraceStatsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(constructionProvider);
    final stats = ref.read(toolProvider.notifier).lastTraceStats;
    final text = switch (stats) {
      null => 'trace: waiting for a traced drag',
      (:final bailed, accepted: _, rejected: _, detours: _) when bailed =>
        'trace: static bail',
      (:final accepted, :final rejected, :final detours, bailed: _) =>
        'trace: $accepted accepted · $rejected rejected · '
            '$detours detour${detours == 1 ? '' : 's'}',
    };
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.onSecondaryContainer,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final history = TraceDiagnostics.history;
    final last = history.isEmpty ? null : history.last;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: style),
                  if (last != null)
                    Text(
                      'cost: ${last.totalMs.toStringAsFixed(1)} ms '
                      '(locus ${last.locusMs.toStringAsFixed(1)} ms) · '
                      '${last[TraceCounter.chainSolves]} solves'
                      '${last.stalled ? ' · STALLED' : ''}',
                      style: style,
                    )
                  else if (!TraceDiagnostics.enabled)
                    Text('cost: not recorded (release build)', style: style),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
