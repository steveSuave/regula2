import 'package:material_ui/material_ui.dart';

/// How the export frames the construction. `region` is only selectable
/// once the user has dragged one on the canvas (see `RegionPickOverlay`).
enum ExportFramingChoice { fitConstruction, currentView, region }

/// The user-facing export knobs. Kept by the editor screen across dialog
/// round trips, so picking a region (which closes and reopens the dialog)
/// doesn't reset scale or background.
class ExportOptions {
  const ExportOptions({
    this.framing = ExportFramingChoice.fitConstruction,
    this.scale = 1,
    this.transparent = false,
    this.includeAxesGrid = true,
  });

  final ExportFramingChoice framing;

  /// Output pixels per logical pixel (1, 2 or 4).
  final int scale;

  /// No background fill — the PNG keeps alpha 0 outside the geometry.
  final bool transparent;

  /// Renders the document's axes/grid toggles into the export exactly as
  /// shown on the canvas. Moot (and hidden in the dialog) while both
  /// toggles are off — the default `true` makes the layer export by
  /// default the moment either is on.
  final bool includeAxesGrid;

  ExportOptions copyWith({
    ExportFramingChoice? framing,
    int? scale,
    bool? transparent,
    bool? includeAxesGrid,
  }) => ExportOptions(
    framing: framing ?? this.framing,
    scale: scale ?? this.scale,
    transparent: transparent ?? this.transparent,
    includeAxesGrid: includeAxesGrid ?? this.includeAxesGrid,
  );
}

/// What the export dialog resolved to; null (dialog dismissed) means
/// cancel. Both outcomes carry the options as last seen, so the editor
/// can restore them when the dialog reopens.
sealed class ExportDialogOutcome {
  const ExportDialogOutcome(this.options);

  final ExportOptions options;
}

/// Export now with [options].
class ExportConfirmed extends ExportDialogOutcome {
  const ExportConfirmed(super.options);
}

/// The user asked to drag an export region on the canvas. The dialog has
/// closed; the editor arms the region-pick overlay and reopens the dialog
/// with the picked rectangle.
class ExportRegionPickRequested extends ExportDialogOutcome {
  const ExportRegionPickRequested(super.options);
}

/// Shows the export options dialog.
///
/// [canvasSize] is the canvas's laid-out logical size (the output size of
/// the fit and current-view framings); [region] is the previously picked
/// region, if any; [canFit] is false when nothing visible can be framed
/// (empty construction), disabling the fit option; [hasBackgroundLayer]
/// is true while the document shows axes or a grid — it gates the
/// "Include axes & grid" checkbox (meaningless when both are off).
Future<ExportDialogOutcome?> showExportDialog(
  BuildContext context, {
  required Size canvasSize,
  required bool canFit,
  Rect? region,
  ExportOptions initial = const ExportOptions(),
  bool hasBackgroundLayer = false,
}) => showDialog<ExportDialogOutcome>(
  context: context,
  builder: (context) => _ExportDialog(
    canvasSize: canvasSize,
    canFit: canFit,
    region: region,
    initial: initial,
    hasBackgroundLayer: hasBackgroundLayer,
  ),
);

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.canvasSize,
    required this.canFit,
    required this.region,
    required this.initial,
    required this.hasBackgroundLayer,
  });

  final Size canvasSize;
  final bool canFit;
  final Rect? region;
  final ExportOptions initial;
  final bool hasBackgroundLayer;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    _options = widget.initial;
    // Sanitize a stale initial framing: fit needs something visible,
    // region needs a picked rectangle.
    if ((_options.framing == ExportFramingChoice.fitConstruction &&
            !widget.canFit) ||
        (_options.framing == ExportFramingChoice.region &&
            widget.region == null)) {
      _options = _options.copyWith(
        framing: widget.canFit
            ? ExportFramingChoice.fitConstruction
            : ExportFramingChoice.currentView,
      );
    }
  }

  /// The output's logical size under the current framing choice; the
  /// physical pixel size shown to the user is this times the scale.
  Size get _logicalSize => switch (_options.framing) {
    ExportFramingChoice.region => widget.region!.size,
    _ => widget.canvasSize,
  };

  void _setFraming(ExportFramingChoice framing) =>
      setState(() => _options = _options.copyWith(framing: framing));

  /// A radio row built from plain [ListTile]s (Flutter's radio tiles are
  /// mid-migration to `RadioGroup`; the icon pair keeps this stable).
  Widget _framingTile(
    ExportFramingChoice choice,
    String title, {
    String? subtitle,
    bool enabled = true,
    Widget? trailing,
  }) {
    final selected = _options.framing == choice;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        selected && enabled
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing,
      onTap: enabled ? () => _setFraming(choice) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final region = widget.region;
    final logical = _logicalSize;
    final outWidth = (logical.width * _options.scale).round();
    final outHeight = (logical.height * _options.scale).round();

    return AlertDialog(
      title: const Text('Export as PNG'),
      // Scrollable so a short window (the dialog's content area can drop
      // below the options' natural height) scrolls instead of
      // overflowing the Column.
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _framingTile(
                ExportFramingChoice.fitConstruction,
                'Fit construction',
                subtitle: widget.canFit ? null : 'Nothing visible to frame',
                enabled: widget.canFit,
              ),
              _framingTile(ExportFramingChoice.currentView, 'Current view'),
              _framingTile(
                ExportFramingChoice.region,
                'Selected region',
                subtitle: region == null
                    ? 'Drag a rectangle on the canvas'
                    : '${region.width.round()} × ${region.height.round()} px '
                          'of the window',
                enabled: region != null,
                trailing: TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    ExportRegionPickRequested(_options),
                  ),
                  child: Text(region == null ? 'Select…' : 'Reselect…'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Scale'),
                  const Spacer(),
                  SegmentedButton<int>(
                    segments: [
                      for (final scale in const [1, 2, 4])
                        ButtonSegment(value: scale, label: Text('$scale×')),
                    ],
                    selected: {_options.scale},
                    onSelectionChanged: (selection) => setState(
                      () =>
                          _options = _options.copyWith(scale: selection.single),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Transparent background'),
                value: _options.transparent,
                onChanged: (value) => setState(
                  () => _options = _options.copyWith(transparent: value),
                ),
              ),
              if (widget.hasBackgroundLayer)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Include axes & grid (as shown)'),
                  value: _options.includeAxesGrid,
                  onChanged: (value) => setState(
                    () => _options = _options.copyWith(includeAxesGrid: value),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Output: $outWidth × $outHeight px',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ExportConfirmed(_options)),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
