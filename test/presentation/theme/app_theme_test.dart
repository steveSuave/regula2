import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:regula/presentation/theme/app_theme.dart';

/// WCAG contrast ratio between two colors, in [1, 21].
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  /// 3:1 is WCAG's minimum for graphical objects — geometry must stay
  /// readable against the canvas (= scaffold background) in both themes.
  const minCanvasContrast = 3.0;

  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group('$name theme', () {
      test('default object color reads against the canvas', () {
        expect(
          contrastRatio(
            theme.colorScheme.primary,
            theme.scaffoldBackgroundColor,
          ),
          greaterThanOrEqualTo(minCanvasContrast),
        );
      });

      test('selection color reads against the canvas', () {
        expect(
          contrastRatio(
            theme.colorScheme.tertiary,
            theme.scaffoldBackgroundColor,
          ),
          greaterThanOrEqualTo(minCanvasContrast),
        );
      });

      test('selection is distinguishable from the default object color', () {
        expect(theme.colorScheme.tertiary, isNot(theme.colorScheme.primary));
      });
    });
  }

  test('the two canvases actually differ in brightness', () {
    expect(
      AppTheme.light().scaffoldBackgroundColor.computeLuminance(),
      greaterThan(0.5),
    );
    expect(
      AppTheme.dark().scaffoldBackgroundColor.computeLuminance(),
      lessThan(0.1),
    );
  });
}
