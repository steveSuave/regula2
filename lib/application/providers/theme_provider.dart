import 'dart:async';

import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'preferences_provider.dart';

part 'theme_provider.g.dart';

/// The user's theme choice, persisted across restarts.
///
/// [ThemeMode.system] until the user explicitly picks — a fresh install
/// follows the OS. An explicit choice is stored in `shared_preferences`
/// and wins from then on; writes are fire-and-forget (the in-memory state
/// already changed, and a lost write only costs the preference).
@Riverpod(keepAlive: true, name: 'themeModeProvider')
class ThemeModeNotifier extends _$ThemeModeNotifier {
  static const String _prefsKey = 'themeMode';

  @override
  ThemeMode build() =>
      switch (ref.watch(sharedPreferencesProvider).getString(_prefsKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// Sets and persists an explicit choice ([ThemeMode.system] clears the
  /// stored one, back to following the OS).
  void setMode(ThemeMode mode) {
    state = mode;
    final preferences = ref.read(sharedPreferencesProvider);
    unawaited(
      mode == ThemeMode.system
          ? preferences.remove(_prefsKey)
          : preferences.setString(_prefsKey, mode.name),
    );
  }

  /// Flips to the opposite of [current] — the brightness actually being
  /// rendered, which the caller reads from its `Theme`. Toggling from
  /// "system" therefore lands on the mode that visibly changes something.
  void toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
