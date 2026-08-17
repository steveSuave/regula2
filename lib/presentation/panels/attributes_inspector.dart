import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/command_stack_provider.dart';
import '../../application/providers/construction_provider.dart';
import '../../application/providers/selection_provider.dart';
import '../../domain/commands/change_attributes_command.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/object_attributes.dart';
import '../../domain/construction/object_naming.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/expression_text.dart';
import '../../domain/construction/objects/five_point_conic.dart';
import '../../domain/construction/objects/line_through_two_points.dart';
import '../../domain/construction/objects/segment.dart';
import '../canvas/measure_format.dart';
import 'object_kind_label.dart';

/// Side panel showing the current selection's attributes; collapses to
/// nothing while the selection is empty.
///
/// A single selected object gets its kind as the header plus editable
/// fields (name, visibility, label visibility, color, width). A
/// multi-selection shows the count, the same controls applied to the
/// whole selection (a dash or no highlight means the values are mixed;
/// a tap sets everything), and a read-only list of what's in it. Width
/// is two controls — stroke width for line-like kinds, point size for
/// points — each shown only when the selection contains that kind and
/// applied only to it.
///
/// Hiding a selected object does not deselect it: hidden objects can't
/// be hit on the canvas, so staying in the inspector is the way back to
/// un-hiding until the object tree panel lands.
///
/// Every edit is one [ChangeAttributesCommand] on the shared stack, so
/// attribute changes undo exactly like geometry changes. Deletion is
/// deliberately *not* here (Phase 41): it isn't styling, and compact
/// mode hid the old button behind the palette icon — the app-bar
/// delete button and the Del/Backspace shortcut are the delete paths.
class AttributesInspector extends ConsumerWidget {
  const AttributesInspector({super.key});

  static const double panelWidth = 280;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(selectionProvider);
    // Watched (not read) so undo/redo of attribute edits refreshes the
    // fields — the revision bumps on every construction change.
    final construction = ref.watch(constructionProvider).construction;
    // The selection prunes deleted ids by *listening*, which can lag this
    // build by a frame — byId's null filters casualties out meanwhile.
    final objects = [
      for (final id in selectedIds)
        if (construction.byId(id) case final GeoObject object) object,
    ];
    if (objects.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final single = objects.length == 1 ? objects.first : null;
    // Width means different things per kind, so the two selectors each
    // target their own slice of the selection.
    final points = [
      for (final object in objects)
        if (object is GeoPoint) object,
    ];
    // Measurements and texts are pure label text — the label pass reads
    // font size and color only, so the stroke rows would be silent
    // no-ops on them (the dash-for-angles reasoning below).
    final strokes = [
      for (final object in objects)
        if (object is! GeoPoint &&
            object is! GeoMeasurement &&
            object is! GeoText)
          object,
    ];
    // Angle markers deliberately never dash (Phase 17), so the dash row
    // targets the strokes that do — showing it for an angle-only
    // selection would be a silent no-op.
    final dashables = [
      for (final object in strokes)
        if (object is! GeoAngle) object,
    ];
    final angles = [
      for (final object in objects)
        if (object is GeoAngle) object,
    ];
    // The kinds the painter can fill (Phase 37): angle markers, polygons,
    // and circle-carrier kinds — sectors as pie wedges, full circles as
    // discs. Arcs excluded: their fill shape is ambiguous, the painter
    // skips them. Conic-valued kinds are excluded for the same reason
    // (Phase 120): a hyperbola bounds nothing and a clipped ellipse would
    // have to be closed along the viewport edges, so the row would be a
    // silent no-op. By *kind*, not by the current value — an undefined
    // circle must keep its fill row, and a conic that happens to be
    // circle-shaped today need not gain one.
    final fillables = [
      for (final object in objects)
        if (object is GeoAngle ||
            object is GeoPolygon ||
            (object is GeoCircle &&
                object is! Arc &&
                object is! FivePointConic))
          object,
    ];
    // The kinds with a measurable value (Phase 35): segment lengths and
    // angle degrees.
    final measurables = [
      for (final object in objects)
        if (object is Segment || object is GeoAngle) object,
    ];
    // The kinds whose label renders a numeric value (Phase 72): the
    // measurables, measurements (whose value is the object itself), and
    // texts with `{…}` slots — the decimals row targets all of them. A
    // literal-only text is excluded: the row would be a silent no-op.
    final valued = [
      for (final object in objects)
        if (object is Segment ||
            object is GeoAngle ||
            object is GeoMeasurement ||
            (object is ExpressionText && object.hasExpressions))
          object,
    ];
    // The kinds that carry equal-mark ticks (Phase 51): segments only —
    // the classic congruence notation at the midpoint.
    final tickables = [
      for (final object in objects)
        if (object is Segment) object,
    ];
    // A text never composes `name = content` (its content is the whole
    // on-canvas presence — see labelText), so the show-label toggle
    // would be a silent no-op on a text-only selection.
    final labelables = [
      for (final object in objects)
        if (object is! GeoText) object,
    ];
    // The kinds the lineClip modes apply to (Phase 44): lines and rays.
    // Segments are already their own clip and ignore the attribute.
    final clippables = [
      for (final object in objects)
        if (object is GeoLine && object is! Segment) object,
    ];
    // Mode 1 clips to the defining pair, which only a LineThroughTwoPoints
    // has on its carrier — the segment is offered only when one is here.
    final hasDefiningPair = clippables.any((o) => o is LineThroughTwoPoints);
    return SizedBox(
      width: panelWidth,
      child: Row(
        children: [
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  single != null
                      ? (single.attributes.name.isEmpty
                            ? objectKindLabel(single)
                            : '${single.attributes.name} — '
                                  '${objectKindLabel(single)}')
                      : '${objects.length} selected',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (single != null) ...[
                  _NameField(
                    // Keyed by id *and* name: an external change (undo,
                    // selecting another object) swaps the field out for a
                    // fresh one; the user's own typing changes neither.
                    key: ValueKey((single.id, single.attributes.name)),
                    initialName: single.attributes.name,
                    onCommit: (text) => _renameTo(ref, single.id, text),
                  ),
                  const SizedBox(height: 8),
                ],
                _AttributeToggle(
                  label: 'Visible',
                  values: [
                    for (final object in objects) object.attributes.visible,
                  ],
                  onChanged: (value) => _setForAll(
                    ref,
                    objects,
                    (attributes) => attributes.copyWith(visible: value),
                  ),
                ),
                if (labelables.isNotEmpty)
                  _AttributeToggle(
                    label: 'Show label',
                    values: [
                      for (final object in labelables)
                        object.attributes.labelVisible,
                    ],
                    onChanged: (value) => _setForAll(
                      ref,
                      labelables,
                      (attributes) => attributes.copyWith(labelVisible: value),
                    ),
                  ),
                if (measurables.isNotEmpty)
                  _AttributeToggle(
                    label: 'Show value',
                    values: [
                      for (final object in measurables)
                        object.attributes.showValue,
                    ],
                    onChanged: (value) => _setForAll(
                      ref,
                      measurables,
                      (attributes) => attributes.copyWith(showValue: value),
                    ),
                  ),
                if (valued.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _PresetSelector(
                    key: const ValueKey('value-decimals'),
                    label: 'Decimals',
                    presets: _decimalsPresets,
                    values: [
                      for (final object in valued)
                        (object.attributes.valueDecimals ??
                                (object is GeoAngle
                                    ? defaultAngleDecimals
                                    : defaultLengthDecimals))
                            .toDouble(),
                    ],
                    onChanged: (count) => _setForAll(
                      ref,
                      valued,
                      (attributes) =>
                          attributes.copyWith(valueDecimals: count.toInt()),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _ColorRow(
                  values: [
                    for (final object in objects) object.attributes.colorArgb,
                  ],
                  onChanged: (argb) => _setForAll(
                    ref,
                    objects,
                    (attributes) => attributes.copyWith(colorArgb: argb),
                  ),
                ),
                if (strokes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WidthSelector(
                    key: const ValueKey('stroke-width'),
                    label: 'Stroke width',
                    options: const [1, 2, 4, 6],
                    values: [
                      for (final object in strokes)
                        object.attributes.strokeWidth,
                    ],
                    onChanged: (width) => _setForAll(
                      ref,
                      strokes,
                      (attributes) => attributes.copyWith(strokeWidth: width),
                    ),
                  ),
                ],
                if (dashables.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PresetSelector(
                    key: const ValueKey('dash-style'),
                    label: 'Line style',
                    presets: _dashPresets,
                    values: [
                      for (final object in dashables)
                        object.attributes.dashPeriod,
                    ],
                    onChanged: (period) => _setForAll(
                      ref,
                      dashables,
                      (attributes) => attributes.copyWith(dashPeriod: period),
                    ),
                  ),
                ],
                if (tickables.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PresetSelector(
                    key: const ValueKey('tick-marks'),
                    label: 'Equal marks',
                    presets: _tickPresets,
                    values: [
                      for (final object in tickables)
                        object.attributes.tickMarks.toDouble(),
                    ],
                    onChanged: (count) => _setForAll(
                      ref,
                      tickables,
                      (attributes) =>
                          attributes.copyWith(tickMarks: count.toInt()),
                    ),
                  ),
                ],
                if (clippables.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PresetSelector(
                    key: const ValueKey('line-extent'),
                    label: 'Extent',
                    presets: [
                      for (final preset in _extentPresets)
                        if (preset.$3 != 1 || hasDefiningPair) preset,
                    ],
                    values: [
                      for (final object in clippables)
                        object.attributes.lineClip.toDouble(),
                    ],
                    onChanged: (mode) => _setForAll(
                      ref,
                      clippables,
                      (attributes) =>
                          attributes.copyWith(lineClip: mode.toInt()),
                    ),
                  ),
                ],
                if (points.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WidthSelector(
                    key: const ValueKey('point-size'),
                    label: 'Point size',
                    options: const [3, 4, 6, 8],
                    values: [
                      for (final object in points) object.attributes.pointSize,
                    ],
                    onChanged: (size) => _setForAll(
                      ref,
                      points,
                      (attributes) => attributes.copyWith(pointSize: size),
                    ),
                  ),
                ],
                if (angles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PresetSelector(
                    key: const ValueKey('marker-radius'),
                    label: 'Marker size',
                    presets: _radiusPresets,
                    values: [
                      for (final object in angles)
                        object.attributes.angleMarkerRadius,
                    ],
                    onChanged: (radius) => _setForAll(
                      ref,
                      angles,
                      (attributes) =>
                          attributes.copyWith(angleMarkerRadius: radius),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _PresetSelector(
                  key: const ValueKey('label-size'),
                  label: 'Label size',
                  presets: _labelSizePresets,
                  values: [
                    for (final object in objects)
                      object.attributes.labelFontSize,
                  ],
                  onChanged: (size) => _setForAll(
                    ref,
                    objects,
                    (attributes) => attributes.copyWith(labelFontSize: size),
                  ),
                ),
                if (fillables.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _AttributeToggle(
                    label: 'Fill',
                    values: [
                      for (final object in fillables)
                        object.attributes.fillAlpha != null,
                    ],
                    onChanged: (value) => _setForAll(
                      ref,
                      fillables,
                      (attributes) => attributes.copyWith(
                        fillAlpha: value ? _fillAlphaOn : null,
                      ),
                    ),
                  ),
                ],
                if (single == null) ...[
                  const Divider(),
                  for (final object in objects)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        object.attributes.name.isEmpty
                            ? objectKindLabel(object)
                            : object.attributes.name,
                      ),
                      subtitle: object.attributes.name.isEmpty
                          ? null
                          : Text(objectKindLabel(object)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Commits a rename as one command; unchanged names (and objects that
  /// vanished between the field's build and its commit) do nothing, so
  /// tabbing through the field never pollutes the undo stack.
  ///
  /// Names stay unique (Phase 27): if another object already holds the
  /// submitted name, it is evicted to the first free numbered variant
  /// ([evictedName]) in the same command, so both renames are one undo
  /// unit and the user's chosen name is never rejected.
  void _renameTo(WidgetRef ref, String id, String text) {
    final construction = ref.read(constructionProvider).construction;
    final object = construction.byId(id);
    final name = text.trim();
    if (object == null || object.attributes.name == name) {
      return;
    }
    final updates = {id: object.attributes.copyWith(name: name)};
    if (name.isNotEmpty) {
      final holder = construction.objects.cast<GeoObject?>().firstWhere(
        (other) => other!.id != id && other.attributes.name == name,
        orElse: () => null,
      );
      if (holder != null) {
        final used = {
          for (final other in construction.objects)
            if (other.attributes.name.isNotEmpty) other.attributes.name,
        };
        updates[holder.id] = holder.attributes.copyWith(
          name: evictedName(used, name),
        );
      }
    }
    ref
        .read(commandStackProvider.notifier)
        .execute(ChangeAttributesCommand(updates));
  }

  /// Applies [change] to every selected object in one command, so a
  /// multi-object toggle undoes as a single step. Objects re-read by id
  /// at commit time (cf. [_renameTo]); ones the change leaves untouched
  /// stay out of the command.
  void _setForAll(
    WidgetRef ref,
    List<GeoObject> objects,
    ObjectAttributes Function(ObjectAttributes) change,
  ) {
    final construction = ref.read(constructionProvider).construction;
    final updates = <String, ObjectAttributes>{};
    for (final stale in objects) {
      final object = construction.byId(stale.id);
      if (object == null) {
        continue;
      }
      final updated = change(object.attributes);
      if (updated != object.attributes) {
        updates[object.id] = updated;
      }
    }
    if (updates.isEmpty) {
      return;
    }
    ref
        .read(commandStackProvider.notifier)
        .execute(ChangeAttributesCommand(updates));
  }
}

/// One boolean attribute over the whole selection, as a checkbox row.
///
/// All-on shows checked, all-off unchecked, mixed the tristate dash.
/// Tapping ignores Flutter's three-way cycle: anything but all-on turns
/// everything on; all-on turns everything off.
class _AttributeToggle extends StatelessWidget {
  const _AttributeToggle({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<bool> values;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final allOn = values.every((value) => value);
    final anyOn = values.any((value) => value);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      tristate: true,
      value: allOn || !anyOn ? allOn : null,
      onChanged: (_) => onChanged(!allOn),
    );
  }
}

/// The fill opacity the Fill checkbox turns on (the alpha byte 64 of the
/// PLAN, as the attribute's 0–1 scale); off is null — unfilled.
const double _fillAlphaOn = 0.25;

/// The colors the inspector offers, as (tooltip, raw ARGB) pairs; null
/// is "Auto" — inherit the theme default, the portable choice that
/// adapts when light/dark themes land in Phase 9.
const _palette = <(String, int?)>[
  ('Auto', null),
  ('Red', 0xFFE53935),
  ('Orange', 0xFFFB8C00),
  ('Green', 0xFF43A047),
  ('Blue', 0xFF1E88E5),
  ('Purple', 0xFF8E24AA),
  ('Gray', 0xFF616161),
];

/// The selection's color as a row of tappable swatches.
///
/// A swatch is highlighted only when the whole selection carries exactly
/// its color — a mixed selection highlights nothing. The Auto swatch is
/// drawn in the theme primary (what the canvas paints for `null`) with a
/// reset glyph to tell it apart from the fixed blues and purples.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.values, required this.onChanged});

  final List<int?> values;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uniform = values.toSet().length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Color', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final (name, argb) in _palette)
              Tooltip(
                message: name,
                child: InkWell(
                  onTap: () => onChanged(argb),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(argb ?? scheme.primary.toARGB32()),
                      border: Border.all(
                        color: uniform && argb == values.first
                            ? scheme.onSurface
                            : scheme.outlineVariant,
                        width: uniform && argb == values.first ? 3 : 1,
                      ),
                    ),
                    child: argb == null
                        ? Icon(
                            Icons.format_color_reset,
                            size: 16,
                            color: scheme.onPrimary,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One width attribute over (a slice of) the selection, as a row of
/// discrete choices — discrete so each tap is exactly one command on the
/// undo stack, where a live slider would emit one per frame.
///
/// Nothing is highlighted when the values are mixed, or uniform but not
/// among [options] (possible once saved files arrive).
class _WidthSelector extends StatelessWidget {
  const _WidthSelector({
    super.key,
    required this.label,
    required this.options,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<double> options;
  final List<double> values;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final uniform = values.toSet().length == 1;
    final selected = uniform && options.contains(values.first)
        ? {values.first}
        : const <double>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: [
            for (final option in options)
              ButtonSegment(value: option, label: Text('${option.round()}')),
          ],
          selected: selected,
          // Allowing empty lets `selected` model the mixed state; a tap
          // on the already-selected segment then arrives as an empty set,
          // which is a no-op rather than a "no width".
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onChanged(selection.first);
            }
          },
        ),
      ],
    );
  }
}

/// The line-style presets: a dash period of 0 is solid; the rest dash at
/// that period in logical pixels (dash = gap = period / 2). Segment
/// labels are single characters — the four full words overflow the
/// 280-px panel (Phase 25) — with the word in the tooltip.
const _dashPresets = <(String, String, double)>[
  ('–', 'Solid', 0),
  ('S', 'Fine', 4),
  ('M', 'Medium', 8),
  ('L', 'Coarse', 16),
];

/// The angle-marker radius presets in logical pixels, same single-letter
/// convention as [_dashPresets].
const _radiusPresets = <(String, String, double)>[
  ('S', 'Small', 12),
  ('M', 'Medium', 20),
  ('L', 'Large', 28),
  ('XL', 'Extra large', 36),
];

/// The equal-mark tick-count presets (`ObjectAttributes.tickMarks`,
/// carried as doubles for [_PresetSelector]), same single-character
/// convention as [_dashPresets].
const _tickPresets = <(String, String, double)>[
  ('–', 'None', 0),
  ('1', 'One tick', 1),
  ('2', 'Two ticks', 2),
  ('3', 'Three ticks', 3),
];

/// The Phase 44 line-extent presets (`ObjectAttributes.lineClip`, carried
/// as doubles for [_PresetSelector]), same single-letter convention as
/// [_dashPresets] with the full wording in the tooltip. The 'D' segment
/// is offered only while a `LineThroughTwoPoints` is selected; on other
/// kinds mode 1 draws infinite (see `lineClipSpan`).
const _extentPresets = <(String, String, double)>[
  ('∞', 'Infinite', 0),
  ('D', 'Between the defining points', 1),
  ('P', 'Span of the incident points', 2),
];

/// The value-decimals presets (`ObjectAttributes.valueDecimals`, carried
/// as doubles for [_PresetSelector]). The row shows each object's
/// *effective* count, so a fresh length highlights 2 and a fresh angle 1
/// (the kind defaults) until an explicit choice is made.
const _decimalsPresets = <(String, String, double)>[
  ('0', 'No decimals', 0),
  ('1', '1 decimal', 1),
  ('2', '2 decimals', 2),
  ('3', '3 decimals', 3),
  ('4', '4 decimals', 4),
  ('5', '5 decimals', 5),
];

/// The label font-size presets in logical pixels, same single-letter
/// convention as [_dashPresets]. Every kind carries a label, so the row
/// targets the whole selection.
const _labelSizePresets = <(String, String, double)>[
  ('S', 'Small', 9),
  ('M', 'Medium', 12),
  ('L', 'Large', 16),
  ('XL', 'Extra large', 22),
];

/// A labelled-segment preset row — the discrete-choice sibling of
/// [_WidthSelector], so each tap is exactly one command. Single-character
/// segment labels with the full word in the tooltip (full words overflow
/// the 280-px panel); backs the dash-style and marker-radius selectors.
///
/// Nothing is highlighted when the values are mixed, or uniform but not
/// among the presets (possible once saved files arrive).
class _PresetSelector extends StatelessWidget {
  const _PresetSelector({
    super.key,
    required this.label,
    required this.presets,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<(String, String, double)> presets;
  final List<double> values;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final uniform = values.toSet().length == 1;
    final presetValues = [for (final (_, _, value) in presets) value];
    final selected = uniform && presetValues.contains(values.first)
        ? {values.first}
        : const <double>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: [
            for (final (short, word, value) in presets)
              ButtonSegment(value: value, label: Text(short), tooltip: word),
          ],
          selected: selected,
          // Same empty-selection idiom as _WidthSelector: a tap on the
          // already-selected segment arrives empty and is a no-op.
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.bodySmall,
            ),
          ),
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onChanged(selection.first);
            }
          },
        ),
      ],
    );
  }
}

/// The name editor: commits on submit and on focus loss. Owns its
/// controller; external name changes replace the whole widget via the
/// parent's key instead of mutating the controller mid-edit.
class _NameField extends StatefulWidget {
  const _NameField({
    super.key,
    required this.initialName,
    required this.onCommit,
  });

  final String initialName;
  final ValueChanged<String> onCommit;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // hasFocus covers the descendant TextField, so this fires when the
      // user clicks away; a double commit after submit is a no-op.
      onFocusChange: (focused) {
        if (!focused) {
          widget.onCommit(_controller.text);
        }
      },
      child: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Name',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: widget.onCommit,
      ),
    );
  }
}
