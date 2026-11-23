import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/construction_provider.dart';
import '../../application/providers/tool_provider.dart';
import '../../domain/tools/name_points_tool.dart';

/// The Phase 53 canvas hint: while the name-points tool is active, a
/// small non-interactive chip in the canvas corner shows the name the
/// next tap will assign — the sequence's only forward-looking feedback —
/// or that a naming string has run out. Renders nothing for every other
/// tool, so the canvas stack can mount it unconditionally.
class NamePointsHint extends ConsumerWidget {
  const NamePointsHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the whole tool state (not just the tool) keeps the chip
    // current: the revision bumps on every committed tap.
    final tool = ref.watch(toolProvider).tool;
    if (tool is! NamePointsTool) {
      return const SizedBox.shrink();
    }
    final construction = ref.watch(constructionProvider).construction;
    final upcoming = tool.upcomingName({
      for (final object in construction.objects)
        if (object.attributes.name.isNotEmpty) object.attributes.name,
    });
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                upcoming == null
                    ? 'All letters assigned'
                    : 'Next name: $upcoming',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
