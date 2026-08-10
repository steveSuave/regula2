import 'package:freezed_annotation/freezed_annotation.dart';

part 'object_attributes.freezed.dart';
part 'object_attributes.g.dart';

/// Display attributes shared by every [GeoObject].
///
/// Immutable; edits go through `copyWith` so a `ChangeAttributesCommand`
/// can hold the before/after values for undo.
///
/// [colorArgb] is a raw ARGB int (e.g. `0xFF2196F3`) rather than a Flutter
/// `Color` — the domain layer is pure Dart. `null` means "use the theme's
/// default color for this object kind", which keeps saved files portable
/// across light/dark themes unless the user explicitly recolors an object.
@freezed
abstract class ObjectAttributes with _$ObjectAttributes {
  const factory ObjectAttributes({
    /// User-facing label, e.g. "A" or "circumcircle". Empty = unnamed.
    @Default('') String name,

    /// Explicit ARGB color, or null to inherit the theme default.
    int? colorArgb,
    @Default(true) bool visible,
    @Default(true) bool labelVisible,

    /// Whether the label shows the object's measured value (a segment's
    /// length, an angle's degrees). Independent of [labelVisible], which
    /// governs only the *name* part: a value-showing label paints even
    /// while the name is hidden. Meaningless for kinds without a value.
    @Default(false) bool showValue,

    /// Decimal digits (0–5) for the value part of a label — a
    /// measurement's value, a segment's shown length, an angle's
    /// degrees, a text's `{…}` slots. Null = the kind default: 2 for
    /// lengths, areas, and text slots, 1 for angles (the pre-Phase-72
    /// fixed counts). The count stays fixed per object — no adaptive
    /// precision — so a value's width doesn't jitter while its object
    /// is dragged.
    int? valueDecimals,

    /// Label offset from the object's anchor to the text's top-left, in
    /// *screen* logical pixels (so zoom never flings a label away from
    /// its object). The defaults match the pre-Phase-17 fixed offset;
    /// label dragging clamps the magnitude, the fields themselves don't.
    @Default(6.0) double labelDx,
    @Default(-18.0) double labelDy,

    /// Label font size in logical pixels; like stroke widths, it does
    /// not scale with zoom. The default is the inspector's 'L' preset
    /// (Phase 54, user request — 12.0, the pre-Phase-28 fixed constant,
    /// until then); documents carry the field explicitly, so only
    /// pre-Phase-28 saves ride the decode fallback up with it.
    @Default(16.0) double labelFontSize,

    /// Stroke width in logical pixels (lines, circles, arcs).
    @Default(2.0) double strokeWidth,

    /// Dash period in logical pixels for stroked kinds: 0 = solid,
    /// > 0 = dashed with dash = gap = period / 2. Like stroke widths,
    /// it does not scale with zoom.
    @Default(0.0) double dashPeriod,

    /// Number of equal-length tick marks (0–3) drawn as short strokes
    /// perpendicular to the segment at its midpoint — the classic
    /// congruence notation. Like stroke widths, tick geometry is in
    /// logical pixels and does not scale with zoom. Segments only;
    /// other kinds ignore it.
    @Default(0) int tickMarks,

    /// Point radius in logical pixels (point kinds only).
    @Default(4.0) double pointSize,

    /// Angle-marker radius in logical pixels (angle kinds only). Like
    /// stroke widths, it does not scale with zoom.
    /// The default is the inspector's 'L' preset (Phase 54, user
    /// request — 20.0, the 'M' preset, until then); like the label
    /// size, documents carry the field explicitly.
    @Default(28.0) double angleMarkerRadius,

    /// Fill opacity in [0, 1] for filled kinds (sectors and angle
    /// markers); null = unfilled.
    double? fillAlpha,

    /// Cinderella-style display extent for line kinds (infinite lines and
    /// rays; segments are already their own clip and ignore this):
    /// 0 = infinite (default), 1 = clipped to the segment between the two
    /// defining points (`LineThroughTwoPoints` only), 2 = clipped to the
    /// span of the visible points structurally incident to the line (see
    /// `lineClipSpan`). Display and hit-test only — the carrier stays
    /// infinite for intersection math.
    @Default(0) int lineClip,
  }) = _ObjectAttributes;

  factory ObjectAttributes.fromJson(Map<String, dynamic> json) =>
      _$ObjectAttributesFromJson(json);
}
