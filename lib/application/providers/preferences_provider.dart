import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'preferences_provider.g.dart';

/// The app's [SharedPreferences] instance.
///
/// Loading it is async, so `main()` awaits `SharedPreferences.getInstance`
/// once before `runApp` and injects it via a `ProviderScope` override —
/// settings providers (theme choice, …) then read stored values
/// synchronously in their `build`. Unoverridden access throws: it means a
/// missing override in `main()` or in a test's container.
@Riverpod(keepAlive: true, name: 'sharedPreferencesProvider')
SharedPreferences sharedPreferences(Ref ref) => throw UnimplementedError(
  'sharedPreferencesProvider must be overridden with the instance '
  'loaded in main()',
);
