import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/preferences_provider.dart';
import 'package:regula/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../wide_window.dart';

void main() {
  Future<SharedPreferences> pumpApp(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
  }) async {
    // The theme-toggle icon button only sits in the wide app bar.
    useWideTestWindow(tester);
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MainApp(),
      ),
    );
    return preferences;
  }

  Brightness renderedBrightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold))).brightness;

  testWidgets('the toggle flips to dark and persists the choice', (
    tester,
  ) async {
    final preferences = await pumpApp(tester);
    // The test platform reports light, so "system" renders light.
    expect(renderedBrightness(tester), Brightness.light);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    expect(renderedBrightness(tester), Brightness.dark);
    expect(preferences.getString('themeMode'), 'dark');

    // The icon now offers the way back.
    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pumpAndSettle();

    expect(renderedBrightness(tester), Brightness.light);
    expect(preferences.getString('themeMode'), 'light');
  });

  testWidgets('a stored dark choice applies from the first frame', (
    tester,
  ) async {
    await pumpApp(tester, stored: {'themeMode': 'dark'});
    expect(renderedBrightness(tester), Brightness.dark);
  });
}
