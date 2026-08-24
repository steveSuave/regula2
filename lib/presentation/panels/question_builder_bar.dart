import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/construction_provider.dart';
import '../../application/providers/prover_provider.dart';
import '../../application/providers/question_draft_provider.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/prover/question_draft.dart';
import '../../domain/prover/question_template.dart';
import 'object_kind_label.dart';
import 'proof_panel.dart';

/// The question builder (Phase 160, PLAN §"The question builder"): a
/// relation picker, the template's slots grouped as the statement
/// groups them, the verdict the figure gives before any run, and *Ask*.
///
/// Over the canvas rather than inside the proof panel, on every layout,
/// for one reason: the primary gesture is a tap on the figure, and on a
/// phone the proof panel is a modal sheet that covers the figure. A bar
/// along the bottom of the canvas leaves the figure tappable at any
/// width; its slot row scrolls sideways, so eight slots fit a phone.
///
/// The next open slot is highlighted; a tap on the figure fills it and
/// the highlight moves on. Every slot chip — empty, seeded or filled —
/// opens a menu of the objects that fit it, the fallback for a point
/// the figure makes hard to hit and the way to correct one slot without
/// clearing the rest; a filled one can also be cleared. Nothing here
/// touches the selection.
class QuestionBuilderBar extends ConsumerWidget {
  const QuestionBuilderBar({super.key, this.onAsked});

  /// Called after *Ask* hands the question to the prover — the editor's
  /// chance to bring the proof panel into view (dock it, or reopen the
  /// sheet the builder closed).
  final VoidCallback? onAsked;

  static const Key barKey = Key('question-builder-bar');

  static Key slotKey(int index) => Key('question-slot-$index');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(questionDraftProvider);
    if (draft == null) return const SizedBox.shrink();
    final check = ref.watch(draftCheckProvider);
    // Watched for names: a slot reads its object's name, and a rename
    // is a construction change.
    final objects = ref.watch(constructionProvider).construction.objects;
    final theme = Theme.of(context);
    final notifier = ref.read(questionDraftProvider.notifier);
    final question = check?.question;
    final canAsk = question != null && !check!.refuted;

    return Material(
      key: barKey,
      elevation: 3,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DropdownButton<QuestionTemplate>(
                    value: draft.template,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: theme.textTheme.titleSmall,
                    items: [
                      for (final template in QuestionTemplate.values)
                        DropdownMenuItem(
                          value: template,
                          child: Text(template.label),
                        ),
                    ],
                    onChanged: (template) {
                      if (template != null) notifier.open(template);
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close the question builder',
                    icon: const Icon(Icons.close),
                    onPressed: notifier.close,
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var g = 0; g < draft.template.groups.length; g++) ...[
                      if (g > 0) const SizedBox(width: 16),
                      Text(
                        draft.template.groups[g].label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (final i in _slotsOf(draft.template, g)) ...[
                        _SlotChip(
                          key: slotKey(i),
                          draft: draft,
                          index: i,
                          candidates: [
                            for (final object in objects)
                              if (draft.accepts(i, object)) object,
                          ],
                          onPut: (object) => notifier.put(i, object),
                          onClear: () => notifier.clearSlot(i),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _status(draft, check),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: check?.refuted ?? false
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canAsk
                        ? () async {
                            notifier.close();
                            onAsked?.call();
                            await ref
                                .read(proverProvider.notifier)
                                .ask(question);
                          }
                        : null,
                    child: const Text('Ask'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The flat slot indices of group [g].
  static List<int> _slotsOf(QuestionTemplate template, int g) {
    var start = 0;
    for (var i = 0; i < g; i++) {
      start += template.groups[i].slots.length;
    }
    return [
      for (var i = 0; i < template.groups[g].slots.length; i++) start + i,
    ];
  }

  /// What the bar says under the slots: what to tap next, or the
  /// verdict before *OK*.
  static String _status(QuestionDraft draft, DraftCheck? check) {
    final current = draft.current;
    if (current != null) {
      final slot = draft.template.slots[current];
      final group = draft.template.groups[draft.template.groupOf(current)];
      final held = draft.values[current];
      final what = switch (slot.type) {
        SlotType.point => 'a point',
        SlotType.line =>
          held is PairValue ? 'a second point' : 'a line, or two points',
        SlotType.segment =>
          held is PairValue ? 'a second point' : 'a segment, or two points',
        SlotType.circle => 'a circle',
      };
      return 'Tap $what on the figure: ${slot.role} (${group.label}).';
    }
    if (check == null) return '';
    final question = check.question;
    if (question == null) {
      return 'Those name no statement — check the slots.';
    }
    if (check.refuted) {
      return 'Not true in this figure — it breaks when the figure is '
          'perturbed.';
    }
    return questionLabel(question);
  }
}

/// A slot as a chip: its object's name (or its role while empty), the
/// current one outlined, and a menu of what fits it.
class _SlotChip extends StatelessWidget {
  const _SlotChip({
    super.key,
    required this.draft,
    required this.index,
    required this.candidates,
    required this.onPut,
    required this.onClear,
  });

  final QuestionDraft draft;
  final int index;
  final List<GeoObject> candidates;
  final ValueChanged<GeoObject> onPut;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final slot = draft.template.slots[index];
    final value = draft.values[index];
    final current = draft.current == index;
    final filled = value != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: current ? scheme.primary : scheme.outline,
        width: current ? 2 : 1,
      ),
    );
    return PopupMenuButton<Object>(
      tooltip: '${slot.role} — pick from the list',
      onSelected: (choice) {
        if (choice is GeoObject) {
          onPut(choice);
        } else {
          onClear();
        }
      },
      itemBuilder: (context) => [
        for (final object in candidates)
          PopupMenuItem<Object>(
            value: object,
            child: Text('${_name(object)} · ${objectKindLabel(object)}'),
          ),
        if (filled) ...[
          if (candidates.isNotEmpty) const PopupMenuDivider(),
          const PopupMenuItem<Object>(value: _clear, child: Text('Clear')),
        ],
      ],
      child: Material(
        color: filled ? scheme.secondaryContainer : Colors.transparent,
        shape: shape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            _label(value, slot),
            style: theme.textTheme.labelLarge?.copyWith(
              color: filled ? scheme.onSecondaryContainer : scheme.onSurface,
              fontStyle: filled ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }

  static const Object _clear = Object();

  static String _label(SlotValue? value, QuestionSlot slot) => switch (value) {
    null => slot.role,
    PointValue(:final point) => _name(point),
    CarrierValue(:final line) => _name(line),
    PairValue(:final first, :final second) =>
      '${_name(first)}·${second == null ? '?' : _name(second)}',
    CircleValue(:final circle) => _name(circle),
  };

  static String _name(GeoObject object) =>
      object.attributes.name.isEmpty ? object.id : object.attributes.name;
}
