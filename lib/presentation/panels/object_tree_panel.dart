import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/command_stack_provider.dart';
import '../../application/providers/construction_provider.dart';
import '../../application/providers/selection_provider.dart';
import '../../domain/commands/change_attributes_command.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/objects/bifocal_conic.dart';
import '../../domain/construction/objects/five_point_conic.dart';
import '../../domain/construction/objects/focal_conic.dart';
import 'object_kind_label.dart';

/// Side panel listing every object in the construction, grouped by
/// sealed kind (points, lines, circles, angles) in insertion order.
///
/// The tree is the selection surface of last resort: rows select on tap,
/// toggle on shift-tap and long-press — the canvas gestures exactly —
/// which makes it the only way to reach objects the canvas can't hit,
/// i.e. hidden ones. Each row also carries an eye toggle flipping
/// `visible` as one [ChangeAttributesCommand], so un-hiding is one tap
/// rather than select-then-inspector.
///
/// A search field pinned at the top filters rows by display label
/// (name, or kind label when unnamed; case-insensitive substring).
/// While a query is active the group headers select only the matches —
/// the header acts on the rows it is heading, always. The query is view
/// state: it resets when the panel closes and is never persisted.
///
/// Each group folds via the chevron on its header, hiding the rows but
/// not the header — select-by-kind keeps working on a folded group, and
/// a count takes the rows' place so the header still says what it hides.
/// Groups start folded, so a fresh panel is a compact per-kind overview
/// and expanding is opting into detail. An active search overrides
/// folding (a match inside a folded group must not read as "no
/// matches"); expansion is view state like the query.
///
/// Collapsing lives with the parent: the editor's app bar shows and
/// hides the whole panel, so an empty construction here still renders
/// (with a hint) rather than collapsing to nothing like the inspector.
class ObjectTreePanel extends ConsumerStatefulWidget {
  const ObjectTreePanel({super.key});

  static const double panelWidth = 240;

  @override
  ConsumerState<ObjectTreePanel> createState() => _ObjectTreePanelState();
}

class _ObjectTreePanelState extends ConsumerState<ObjectTreePanel> {
  final TextEditingController _searchController = TextEditingController();

  /// Labels of the groups the user has expanded — empty at first, so
  /// every group starts folded. View state, like the search query: gone
  /// when the panel closes.
  final Set<String> _expanded = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The row's display label — what the user reads and therefore what
  /// the filter matches: the name, or the kind label while unnamed.
  static String _displayLabel(GeoObject object) {
    final name = object.attributes.name;
    return name.isNotEmpty ? name : objectKindLabel(object);
  }

  @override
  Widget build(BuildContext context) {
    // Watched so undo/redo, deletes and attribute edits refresh the rows.
    final construction = ref.watch(constructionProvider).construction;
    final selectedIds = ref.watch(selectionProvider);
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();

    // Group headers appear in fixed kind order; rows within a group keep
    // insertion order, like every other listing of objects. Filtering
    // happens before grouping, so header select-by-kind naturally acts
    // on the filtered matches only.
    final groups = <String, List<GeoObject>>{
      'Points': [],
      'Lines': [],
      'Circles': [],
      'Conics': [],
      'Angles': [],
      'Polygons': [],
      'Measurements': [],
      'Texts': [],
      'Loci': [],
    };
    for (final object in construction.objects) {
      if (query.isNotEmpty &&
          !_displayLabel(object).toLowerCase().contains(query)) {
        continue;
      }
      groups[switch (object) {
            GeoPoint() => 'Points',
            GeoLine() => 'Lines',
            // The three genuine conic kinds get their own header: they
            // are `GeoCircle` subclasses because that is where the
            // conic-valued carrier lives, not because a user thinks of
            // them as circles. Matched by *kind*, never by whether the
            // current geometry happens to project to a `CircleEq` — a
            // five-point conic that passes through circularity mid-drag
            // must not hop between headers while the pointer is down.
            // Arcs, sectors and the CK circles stay under Circles, which
            // is what they are called everywhere else in the UI.
            FivePointConic() || BifocalConic() || FocalConic() => 'Conics',
            GeoCircle() => 'Circles',
            GeoAngle() => 'Angles',
            GeoPolygon() => 'Polygons',
            GeoMeasurement() => 'Measurements',
            GeoText() => 'Texts',
            GeoLocus() => 'Loci',
          }]!
          .add(object);
    }
    final visibleGroups = [
      for (final entry in groups.entries)
        if (entry.value.isNotEmpty) entry,
    ];

    return SizedBox(
      width: ObjectTreePanel.panelWidth,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    key: const ValueKey('tree-search-field'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setState(_searchController.clear),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: visibleGroups.isEmpty
                      ? Center(
                          child: Text(
                            construction.objects.isEmpty
                                ? 'No objects yet'
                                : 'No matches',
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            // A divider between groups (not above the
                            // first) keeps the headers readable as
                            // section breaks rather than rows.
                            for (final (
                                  index,
                                  MapEntry(key: label, value: objects),
                                )
                                in visibleGroups.indexed) ...[
                              if (index > 0)
                                const Divider(
                                  height: 17,
                                  indent: 12,
                                  endIndent: 12,
                                ),
                              _GroupHeader(
                                label: label,
                                ids: [for (final object in objects) object.id],
                                // Search overrides folding: a matching row
                                // hidden inside a folded group would read
                                // as "no matches".
                                folded:
                                    query.isEmpty && !_expanded.contains(label),
                                onToggleFold: query.isEmpty
                                    ? () => setState(() {
                                        if (!_expanded.remove(label)) {
                                          _expanded.add(label);
                                        }
                                      })
                                    : null,
                              ),
                              if (query.isNotEmpty || _expanded.contains(label))
                                for (final object in objects)
                                  _ObjectRow(
                                    object: object,
                                    selected: selectedIds.contains(object.id),
                                  ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
        ],
      ),
    );
  }
}

/// A kind's group header doubling as select-by-kind: tap replaces the
/// selection with every object of the kind — hidden ones included, this
/// being the panel whose point is reaching them — shift-tap unions
/// (band semantics), and long-press unions too, the touch stand-in for
/// shift. Union rather than the canvas long-press's toggle: headers
/// select groups, the canvas toggles individuals. While a search query
/// is active the ids are the filtered matches only.
///
/// The leading chevron folds the group's rows away; it is its own tap
/// target so folding never selects. Selection keeps acting on the whole
/// group while folded — the fold hides rows, it doesn't disown them —
/// and a trailing count stands in for the hidden rows. [onToggleFold]
/// is null while a search is active, disabling the chevron: the search
/// already forces every match visible.
class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({
    required this.label,
    required this.ids,
    required this.folded,
    required this.onToggleFold,
  });

  final String label;
  final List<String> ids;
  final bool folded;
  final VoidCallback? onToggleFold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lower = label.toLowerCase();
    void select({required bool additive}) => ref
        .read(selectionProvider.notifier)
        .selectMany(ids, additive: additive);
    return Tooltip(
      message: 'Select all $lower',
      child: InkWell(
        onTap: () => select(additive: HardwareKeyboard.instance.isShiftPressed),
        onLongPress: () {
          HapticFeedback.selectionClick();
          select(additive: true);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: folded ? 'Expand $lower' : 'Collapse $lower',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(
                  folded ? Icons.chevron_right : Icons.expand_more,
                  color: theme.colorScheme.primary,
                ),
                onPressed: onToggleFold,
              ),
              Expanded(
                child: Text(
                  // Primary color + a heavier weight so headers read as
                  // section titles, not as just another (unnamed) row.
                  label,
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (folded)
                Text(
                  '${ids.length}',
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One object's row: tap selects, shift-tap and long-press toggle
/// (canvas semantics — long-press is the touch shift-tap, Phase 25b
/// convention), and the trailing eye flips visibility as one undoable
/// command.
class _ObjectRow extends ConsumerWidget {
  const _ObjectRow({required this.object, required this.selected});

  final GeoObject object;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attributes = object.attributes;
    final named = attributes.name.isNotEmpty;
    return ListTile(
      dense: true,
      selected: selected,
      title: Text(named ? attributes.name : objectKindLabel(object)),
      subtitle: named ? Text(objectKindLabel(object)) : null,
      onTap: () {
        final notifier = ref.read(selectionProvider.notifier);
        if (HardwareKeyboard.instance.isShiftPressed) {
          notifier.toggle(object.id);
        } else {
          notifier.select(object.id);
        }
      },
      onLongPress: () {
        HapticFeedback.selectionClick();
        ref.read(selectionProvider.notifier).toggle(object.id);
      },
      trailing: IconButton(
        tooltip: attributes.visible ? 'Hide' : 'Show',
        icon: Icon(
          attributes.visible ? Icons.visibility : Icons.visibility_off,
          size: 18,
        ),
        onPressed: () => ref
            .read(commandStackProvider.notifier)
            .execute(
              ChangeAttributesCommand({
                object.id: attributes.copyWith(visible: !attributes.visible),
              }),
            ),
      ),
    );
  }
}
