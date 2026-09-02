// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The active construction tool and the funnel for canvas input.
///
/// The canvas delivers every hit-tested tap to [handleInput]; a command
/// committed by the tool is executed on the command stack here, so the
/// presentation layer never handles commands itself.

@ProviderFor(ToolNotifier)
final toolProvider = ToolNotifierProvider._();

/// The active construction tool and the funnel for canvas input.
///
/// The canvas delivers every hit-tested tap to [handleInput]; a command
/// committed by the tool is executed on the command stack here, so the
/// presentation layer never handles commands itself.
final class ToolNotifierProvider
    extends $NotifierProvider<ToolNotifier, ActiveToolState> {
  /// The active construction tool and the funnel for canvas input.
  ///
  /// The canvas delivers every hit-tested tap to [handleInput]; a command
  /// committed by the tool is executed on the command stack here, so the
  /// presentation layer never handles commands itself.
  ToolNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'toolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$toolNotifierHash();

  @$internal
  @override
  ToolNotifier create() => ToolNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActiveToolState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActiveToolState>(value),
    );
  }
}

String _$toolNotifierHash() => r'4cfd52b9ce243c37c2658aa98d2d027fe2beac63';

/// The active construction tool and the funnel for canvas input.
///
/// The canvas delivers every hit-tested tap to [handleInput]; a command
/// committed by the tool is executed on the command stack here, so the
/// presentation layer never handles commands itself.

abstract class _$ToolNotifier extends $Notifier<ActiveToolState> {
  ActiveToolState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActiveToolState, ActiveToolState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActiveToolState, ActiveToolState>,
              ActiveToolState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
