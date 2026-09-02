// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The user's theme choice, persisted across restarts.
///
/// [ThemeMode.system] until the user explicitly picks — a fresh install
/// follows the OS. An explicit choice is stored in `shared_preferences`
/// and wins from then on; writes are fire-and-forget (the in-memory state
/// already changed, and a lost write only costs the preference).

@ProviderFor(ThemeModeNotifier)
final themeModeProvider = ThemeModeNotifierProvider._();

/// The user's theme choice, persisted across restarts.
///
/// [ThemeMode.system] until the user explicitly picks — a fresh install
/// follows the OS. An explicit choice is stored in `shared_preferences`
/// and wins from then on; writes are fire-and-forget (the in-memory state
/// already changed, and a lost write only costs the preference).
final class ThemeModeNotifierProvider
    extends $NotifierProvider<ThemeModeNotifier, ThemeMode> {
  /// The user's theme choice, persisted across restarts.
  ///
  /// [ThemeMode.system] until the user explicitly picks — a fresh install
  /// follows the OS. An explicit choice is stored in `shared_preferences`
  /// and wins from then on; writes are fire-and-forget (the in-memory state
  /// already changed, and a lost write only costs the preference).
  ThemeModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeNotifierHash();

  @$internal
  @override
  ThemeModeNotifier create() => ThemeModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeNotifierHash() => r'bb0a72b19b70fcca9b7d6c7485cbb298bd908039';

/// The user's theme choice, persisted across restarts.
///
/// [ThemeMode.system] until the user explicitly picks — a fresh install
/// follows the OS. An explicit choice is stored in `shared_preferences`
/// and wins from then on; writes are fire-and-forget (the in-memory state
/// already changed, and a lost write only costs the preference).

abstract class _$ThemeModeNotifier extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode, ThemeMode>,
              ThemeMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
