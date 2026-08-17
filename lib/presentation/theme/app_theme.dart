import 'package:flutter/material.dart';

/// Light and dark themes with a palette tuned for canvas contrast.
///
/// The canvas has no background of its own — it paints over the scaffold —
/// so `scaffoldBackgroundColor` *is* the drawing surface. Objects without
/// an explicit color draw in [ColorScheme.primary], selection halos and
/// the rubber band in [ColorScheme.tertiary]; both are pinned to explicit
/// values (rather than whatever `fromSeed` derives) so geometry keeps a
/// guaranteed contrast against the canvas in both themes — see the
/// contrast-ratio test in `test/presentation/theme/`.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF1565C0);

  /// Axes on the light canvas: a mid grey — visible but clearly chrome,
  /// never competing with object colors.
  static const Color _lightAxis = Color(0xFF757575);

  /// Grid hairlines on the light canvas: a whisper over white.
  static const Color _lightGrid = Color(0xFFE3E6EA);

  /// Dark-canvas counterparts, tuned against the near-black canvas.
  static const Color _darkAxis = Color(0xFF8F969E);
  static const Color _darkGrid = Color(0xFF262C33);

  /// The Cayley-Klein absolute on the light canvas (Phase 126): a muted
  /// amber. Deliberately unlike both chrome and any object color — the
  /// absolute is neither. It is not a construction the user made, and it
  /// is not decoration either: it is the edge of the plane they are
  /// drawing in, and crossing it is what makes a figure undefined.
  static const Color _lightAbsolute = Color(0xFFB26A00);
  static const Color _darkAbsolute = Color(0xFFE0A44B);

  /// Default object color on the light canvas: a deep blue.
  static const Color _lightPrimary = Color(0xFF1565C0);

  /// Selection color on the light canvas: a deep pink, clearly distinct
  /// from any of the inspector's swatch colors at a glance.
  static const Color _lightTertiary = Color(0xFFC2185B);

  static const Color _lightCanvas = Colors.white;

  /// Dark-canvas counterparts: light enough to read on near-black.
  static const Color _darkPrimary = Color(0xFF90CAF9);
  static const Color _darkTertiary = Color(0xFFF48FB1);

  /// Slightly blue near-black — softer than pure black under halos and
  /// hairlines, still far from every object color.
  static const Color _darkCanvas = Color(0xFF14181D);

  static ThemeData light() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
    ).copyWith(primary: _lightPrimary, tertiary: _lightTertiary),
    scaffoldBackgroundColor: _lightCanvas,
    extensions: const [
      CanvasColors(
        axis: _lightAxis,
        grid: _lightGrid,
        absolute: _lightAbsolute,
      ),
    ],
  );

  static ThemeData dark() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(primary: _darkPrimary, tertiary: _darkTertiary),
    scaffoldBackgroundColor: _darkCanvas,
    extensions: const [
      CanvasColors(axis: _darkAxis, grid: _darkGrid, absolute: _darkAbsolute),
    ],
  );
}

/// Canvas chrome colors the [ColorScheme] has no honest slot for — the
/// Phase 36 axes and grid. A [ThemeExtension] rather than hijacking
/// `outline`/`outlineVariant`, which Material widgets (text-field borders,
/// segmented buttons) already read for their own chrome.
@immutable
class CanvasColors extends ThemeExtension<CanvasColors> {
  const CanvasColors({
    required this.axis,
    required this.grid,
    this.absolute = const Color(0xFFB26A00),
  });

  /// Axis strokes and tick labels.
  final Color axis;

  /// Grid hairlines.
  final Color grid;

  /// The fundamental conic of a non-Euclidean document, and the wash over
  /// the region outside it (Phase 126).
  final Color absolute;

  @override
  CanvasColors copyWith({Color? axis, Color? grid, Color? absolute}) =>
      CanvasColors(
        axis: axis ?? this.axis,
        grid: grid ?? this.grid,
        absolute: absolute ?? this.absolute,
      );

  @override
  CanvasColors lerp(CanvasColors? other, double t) {
    if (other == null) {
      return this;
    }
    return CanvasColors(
      axis: Color.lerp(axis, other.axis, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      absolute: Color.lerp(absolute, other.absolute, t)!,
    );
  }
}
