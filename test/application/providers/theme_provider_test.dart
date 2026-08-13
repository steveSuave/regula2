import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/preferences_provider.dart';
import 'package:regula/application/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  Future<ProviderContainer> containerWithPrefs({
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a fresh install follows the system', () async {
    final container = await containerWithPrefs();
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('a stored choice wins on startup', () async {
    final container = await containerWithPrefs(stored: {'themeMode': 'dark'});
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('garbage in the store falls back to system', () async {
    final container = await containerWithPrefs(stored: {'themeMode': 'plaid'});
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('toggle flips against the rendered brightness and persists', () async {
    final container = await containerWithPrefs();
    final notifier = container.read(themeModeProvider.notifier);

    notifier.toggle(Brightness.light);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(preferences.getString('themeMode'), 'dark');

    notifier.toggle(Brightness.dark);
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(preferences.getString('themeMode'), 'light');
  });

  test('setMode(system) clears the stored choice', () async {
    final container = await containerWithPrefs(stored: {'themeMode': 'dark'});
    container.read(themeModeProvider.notifier).setMode(ThemeMode.system);
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(preferences.getString('themeMode'), isNull);
  });

  test('unoverridden preferences throw, pointing at main()', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(themeModeProvider), throwsA(isA<Object>()));
  });
}
