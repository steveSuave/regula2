// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'viewport_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Pan/zoom state for the canvas. Not undoable, not persisted with the
/// construction's undo history (the save format snapshots it separately).
///
/// Zoom-about-a-focal-point and scale clamping are gesture concerns,
/// decided where the gestures land (Phases 5 and 8) — this notifier only
/// stores state.

@ProviderFor(ViewportNotifier)
final viewportProvider = ViewportNotifierProvider._();

/// Pan/zoom state for the canvas. Not undoable, not persisted with the
/// construction's undo history (the save format snapshots it separately).
///
/// Zoom-about-a-focal-point and scale clamping are gesture concerns,
/// decided where the gestures land (Phases 5 and 8) — this notifier only
/// stores state.
final class ViewportNotifierProvider
    extends $NotifierProvider<ViewportNotifier, ViewportState> {
  /// Pan/zoom state for the canvas. Not undoable, not persisted with the
  /// construction's undo history (the save format snapshots it separately).
  ///
  /// Zoom-about-a-focal-point and scale clamping are gesture concerns,
  /// decided where the gestures land (Phases 5 and 8) — this notifier only
  /// stores state.
  ViewportNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewportProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewportNotifierHash();

  @$internal
  @override
  ViewportNotifier create() => ViewportNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ViewportState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ViewportState>(value),
    );
  }
}

String _$viewportNotifierHash() => r'4ba7ffbb00c63ed400ae9d10f980c0d7025321fc';

/// Pan/zoom state for the canvas. Not undoable, not persisted with the
/// construction's undo history (the save format snapshots it separately).
///
/// Zoom-about-a-focal-point and scale clamping are gesture concerns,
/// decided where the gestures land (Phases 5 and 8) — this notifier only
/// stores state.

abstract class _$ViewportNotifier extends $Notifier<ViewportState> {
  ViewportState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ViewportState, ViewportState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ViewportState, ViewportState>,
              ViewportState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
