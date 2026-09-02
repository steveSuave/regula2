// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document_settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Axes/grid toggles for the current document. Not undoable; replaced
/// wholesale by File > New (defaults) and File > Open (the file's snapshot).

@ProviderFor(DocumentSettingsNotifier)
final documentSettingsProvider = DocumentSettingsNotifierProvider._();

/// Axes/grid toggles for the current document. Not undoable; replaced
/// wholesale by File > New (defaults) and File > Open (the file's snapshot).
final class DocumentSettingsNotifierProvider
    extends $NotifierProvider<DocumentSettingsNotifier, DocumentSettings> {
  /// Axes/grid toggles for the current document. Not undoable; replaced
  /// wholesale by File > New (defaults) and File > Open (the file's snapshot).
  DocumentSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'documentSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$documentSettingsNotifierHash();

  @$internal
  @override
  DocumentSettingsNotifier create() => DocumentSettingsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DocumentSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DocumentSettings>(value),
    );
  }
}

String _$documentSettingsNotifierHash() =>
    r'136b9bd967ea1fbb63667a4cf7ca1b1539384ca5';

/// Axes/grid toggles for the current document. Not undoable; replaced
/// wholesale by File > New (defaults) and File > Open (the file's snapshot).

abstract class _$DocumentSettingsNotifier extends $Notifier<DocumentSettings> {
  DocumentSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DocumentSettings, DocumentSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DocumentSettings, DocumentSettings>,
              DocumentSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
