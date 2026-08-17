import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/commands/add_object_command.dart';
import '../../domain/commands/command.dart';
import '../../domain/commands/macro_command.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/object_naming.dart';
import '../../domain/math/vec2.dart';
import '../../domain/tools/drag_session.dart';
import '../../domain/tools/tool.dart';
import 'command_stack_provider.dart';
import 'construction_provider.dart';

part 'tool_provider.g.dart';

/// Snapshot handle for the active tool, mirroring `ConstructionState`'s
/// pattern: tools mutate in place as they collect inputs, so [revision]
/// gives watchers a value that *does* change when the tool's in-progress
/// state does (repaint input previews).
///
/// [tool] is null when no construction tool is active — the canvas is in
/// move/select mode (the default; Phase 7 builds selection on it).
class ActiveToolState {
  const ActiveToolState(this.tool, this.revision);

  final Tool? tool;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ActiveToolState &&
      identical(other.tool, tool) &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(identityHashCode(tool), revision);
}

/// The active construction tool and the funnel for canvas input.
///
/// The canvas delivers every hit-tested tap to [handleInput]; a command
/// committed by the tool is executed on the command stack here, so the
/// presentation layer never handles commands itself.
@Riverpod(keepAlive: true, name: 'toolProvider')
class ToolNotifier extends _$ToolNotifier {
  /// The move/select-mode drag in progress, if any. Not part of [state]:
  /// preview frames repaint through the construction's own revision, so
  /// nothing needs to watch the session itself.
  DragSession? _drag;

  TraceFrameStats? _lastTraceStats;

  /// The most recent traced preview frame's step counts, retained past
  /// the gesture so the debug overlay can show what the last drag cost.
  /// Null until a traced frame has run. Read imperatively (like [_drag],
  /// this is not [state]): the overlay repaints on the construction's
  /// revision, which every preview frame bumps.
  TraceFrameStats? get lastTraceStats => _lastTraceStats;

  @override
  ActiveToolState build() {
    // A swapped-in construction (File > New / Open) invalidates any
    // objects a mid-collection tool holds — committing against the new
    // construction would add a child whose parents aren't in it.
    ref.listen(
      constructionProvider.select((ConstructionState s) => s.construction),
      (_, _) => resetInProgress(),
    );
    return const ActiveToolState(null, 0);
  }

  /// Makes [tool] the active tool (null returns to move/select). The
  /// outgoing tool's partially-collected input is discarded.
  ///
  /// A move/select drag still in progress is **committed** as its one
  /// start → end command when a real tool activates (Phase 30b): a
  /// keyboard tool switch a beat before the pointer lifts must not
  /// silently discard the move — a committed half-drag is one undo away,
  /// a rolled-back one is unrecoverable. Deactivating (null — `Esc`/`V`)
  /// keeps the rollback: Esc mid-drag is the deliberate abort gesture.
  void activate(Tool? tool) {
    if (tool != null) {
      endDrag();
    } else {
      _abandonDrag();
    }
    state.tool?.reset();
    state = ActiveToolState(tool, 0);
  }

  /// Esc: back to move/select.
  void deactivate() => activate(null);

  /// Discards the active tool's partially-collected input (the tool stays
  /// active) and bumps the revision so input previews clear.
  ///
  /// Called whenever the construction may have changed under the tool —
  /// undo/redo, construction swap — since a collected object may no
  /// longer be in the graph and committing on top of it would throw.
  void resetInProgress() {
    _abandonDrag();
    final tool = state.tool;
    if (tool == null) {
      return;
    }
    tool.reset();
    state = ActiveToolState(tool, state.revision + 1);
  }

  /// Starts a move/select-mode drag of [target], grabbed at [grabStart]
  /// (world). Returns whether a drag began — false with a tool active or
  /// for targets that don't drag — so the canvas knows whether to route
  /// the pan's remaining frames here or to its rubber band.
  ///
  /// [gridSnapStep] > 0 quantizes a single free point's drag to the grid
  /// (Phase 45); the canvas supplies the drawn grid's adaptive step while
  /// the document's snap toggle is on.
  bool startDrag(GeoObject target, Vec2 grabStart, {double gridSnapStep = 0}) {
    if (state.tool != null) {
      return false;
    }
    _drag = DragSession.start(
      ref.read(constructionProvider).construction,
      target,
      grabStart,
      gridSnapStep: gridSnapStep,
    );
    return _drag != null;
  }

  /// Previews the drag at [pointer] (world). No-op when nothing drags.
  void updateDrag(Vec2 pointer) {
    _drag?.update(pointer);
    _lastTraceStats = _drag?.traceStats ?? _lastTraceStats;
  }

  /// Ends the drag: the session's preview is rolled back and its single
  /// start → end command executed (none when the pointer never moved).
  void endDrag() {
    final command = _drag?.end();
    _drag = null;
    if (command != null) {
      ref.read(commandStackProvider.notifier).execute(command);
    }
  }

  /// Rolls back and drops the drag without a command (pan cancel).
  void cancelDrag() => _abandonDrag();

  /// Cancel with a session-may-be-stale guard: also reached via
  /// [resetInProgress] during undo/redo and construction swaps, where the
  /// session's points may already be gone (the session skips those).
  void _abandonDrag() {
    _drag?.cancel();
    _drag = null;
  }

  /// Routes one canvas input to the active tool and returns its verdict.
  ///
  /// [ToolCommitted] commands are executed on the command stack. Any
  /// result that changed the tool's state ([ToolAccepted], or
  /// [ToolCommitted]'s self-reset) bumps [ActiveToolState.revision] so
  /// preview watchers repaint. With no active tool the input is
  /// [ToolIgnored] — a tap in move/select mode is selection's business
  /// (Phase 7), not ours.
  ToolResult handleInput(ToolInput input) {
    final tool = state.tool;
    if (tool == null) {
      return const ToolIgnored();
    }
    final result = tool.onInput(input);
    switch (result) {
      case ToolCommitted(:final command):
        _autoNameNewObjects(command);
        ref.read(commandStackProvider.notifier).execute(command);
        state = ActiveToolState(tool, state.revision + 1);
      case ToolAccepted():
        state = ActiveToolState(tool, state.revision + 1);
      case ToolIgnored():
        break;
    }
    return result;
  }

  /// Bakes auto-names into the objects [command] is about to add, before
  /// its first apply. This is the one funnel every tool-created
  /// `AddObjectCommand` passes through; since the command holds the object
  /// instance and redo re-adds it, a name set here survives undo/redo with
  /// no extra command state.
  ///
  /// Only unnamed, *visible* objects are named — hidden macro scaffolding
  /// burns no letters. Lines and circles are named but get
  /// `labelVisible: false`: the name shows in the tree/inspector, not on
  /// the canvas, until the user reveals it. Angles additionally get
  /// `showValue: true`, so a fresh angle reads as its measure (`47.3°`)
  /// rather than its name (user request), and a zero label offset — the
  /// bisector base (`labelBaseTopLeft`, Phase 63) already places the
  /// text past the arc, so the generic (6, −18) nudge would just skew it.
  void _autoNameNewObjects(Command command) {
    final construction = ref.read(constructionProvider).construction;
    final used = <String>{
      for (final object in construction.objects)
        if (object.attributes.name.isNotEmpty) object.attributes.name,
    };
    _nameObjectsIn(command, used);
  }

  void _nameObjectsIn(Command command, Set<String> used) {
    switch (command) {
      case AddObjectCommand(:final object)
          when object.attributes.name.isEmpty && object.attributes.visible:
        final name = nextAutoName(used, object);
        used.add(name);
        final hideLabel =
            object is GeoLine ||
            object is GeoCircle ||
            object is GeoPolygon ||
            object is GeoLocus ||
            object is GeoText ||
            object is GeoAngle;
        final isAngle = object is GeoAngle;
        object.attributes = object.attributes.copyWith(
          name: name,
          labelVisible: object.attributes.labelVisible && !hideLabel,
          showValue: object.attributes.showValue || isAngle,
          labelDx: isAngle ? 0 : object.attributes.labelDx,
          labelDy: isAngle ? 0 : object.attributes.labelDy,
        );
      case MacroCommand(:final commands):
        for (final child in commands) {
          _nameObjectsIn(child, used);
        }
      default:
        break;
    }
  }
}
