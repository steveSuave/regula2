import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/presentation/shortcuts/shortcut_resolver.dart';
import 'package:regula/presentation/shortcuts/shortcut_table.dart';

void main() {
  late ShortcutResolver resolver;

  setUp(() => resolver = ShortcutResolver(shortcutTable));

  ShortcutResolution stroke(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool control = false,
    bool meta = false,
    bool alt = false,
  }) => resolver.onStroke(
    key,
    shiftDown: shift,
    controlDown: control,
    metaDown: meta,
    altDown: alt,
  );

  AppAction actionOf(ShortcutResolution resolution) =>
      (resolution as ShortcutMatched).binding.action;

  test('single letters resolve to their tools', () {
    expect(actionOf(stroke(LogicalKeyboardKey.keyP)), AppAction.pointTool);
    expect(actionOf(stroke(LogicalKeyboardKey.keyS)), AppAction.segmentTool);
    expect(actionOf(stroke(LogicalKeyboardKey.keyA)), AppAction.angleTool);
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyT, shift: true)),
      AppAction.parallelTool,
    );
    expect(
      stroke(LogicalKeyboardKey.keyA, shift: true),
      isA<ShortcutUnmatched>(),
      reason: '⇧A was freed by the Phase 46 angle-tool merge',
    );
  });

  test('primary modifier accepts control or meta, rejects neither', () {
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyZ, control: true)),
      AppAction.undo,
    );
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyZ, meta: true)),
      AppAction.undo,
    );
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyZ, control: true, shift: true)),
      AppAction.redo,
    );
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyY, control: true)),
      AppAction.redo,
    );
    // Plain Z is no shortcut at all.
    expect(stroke(LogicalKeyboardKey.keyZ), isA<ShortcutUnmatched>());
  });

  test('a modified letter never fires the bare-letter binding', () {
    expect(
      stroke(LogicalKeyboardKey.keyP, control: true),
      isA<ShortcutUnmatched>(),
    );
    expect(
      stroke(LogicalKeyboardKey.keyP, alt: true),
      isA<ShortcutUnmatched>(),
    );
  });

  test('shift-agnostic strokes match both ways', () {
    expect(actionOf(stroke(LogicalKeyboardKey.equal)), AppAction.zoomIn);
    expect(
      actionOf(stroke(LogicalKeyboardKey.equal, shift: true)),
      AppAction.zoomIn,
    );
  });

  test('⇧G/⇧X toggle grid and axes without arming the leaders', () {
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyG, shift: true)),
      AppAction.toggleGrid,
    );
    expect(
      resolver.hasPendingLeader,
      isFalse,
      reason: '⇧G must not leave the G leader pending',
    );
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyX, shift: true)),
      AppAction.toggleAxes,
    );
    expect(
      resolver.hasPendingLeader,
      isFalse,
      reason: '⇧X must not leave the X leader pending',
    );
    // The very next stroke resolves standalone, not as a chord second.
    expect(actionOf(stroke(LogicalKeyboardKey.keyS)), AppAction.segmentTool);
  });

  test('G leader chords: pending, then the second stroke picks', () {
    expect(stroke(LogicalKeyboardKey.keyG), isA<ShortcutPending>());
    expect(resolver.hasPendingLeader, isTrue);
    expect(actionOf(stroke(LogicalKeyboardKey.keyC)), AppAction.centroidTool);
    expect(resolver.hasPendingLeader, isFalse);

    stroke(LogicalKeyboardKey.keyG);
    expect(
      actionOf(stroke(LogicalKeyboardKey.digit3)),
      AppAction.threePointCircleTool,
    );

    stroke(LogicalKeyboardKey.keyG);
    expect(actionOf(stroke(LogicalKeyboardKey.keyM)), AppAction.namePointsTool);

    stroke(LogicalKeyboardKey.keyG);
    expect(actionOf(stroke(LogicalKeyboardKey.keyE)), AppAction.textTool);
  });

  test('X leader chords reach the macros', () {
    stroke(LogicalKeyboardKey.keyX);
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyS)),
      AppAction.squareMacroTool,
    );
  });

  test('the same second stroke means different things per leader', () {
    stroke(LogicalKeyboardKey.keyG);
    expect(actionOf(stroke(LogicalKeyboardKey.keyS)), AppAction.sectorTool);
    stroke(LogicalKeyboardKey.keyX);
    expect(
      actionOf(stroke(LogicalKeyboardKey.keyS)),
      AppAction.squareMacroTool,
    );
  });

  test('Esc cancels a pending leader without firing its own binding', () {
    stroke(LogicalKeyboardKey.keyG);
    expect(stroke(LogicalKeyboardKey.escape), isA<ShortcutSwallowed>());
    expect(resolver.hasPendingLeader, isFalse);
    // Esc is back to being the cancel binding afterwards.
    expect(
      actionOf(stroke(LogicalKeyboardKey.escape)),
      AppAction.cancelOrReturnToMoveSelect,
    );
  });

  test('a failed chord is swallowed, not re-resolved standalone', () {
    stroke(LogicalKeyboardKey.keyG);
    expect(stroke(LogicalKeyboardKey.keyQ), isA<ShortcutSwallowed>());
    // The table is clean again: S is the segment tool, not G S.
    expect(actionOf(stroke(LogicalKeyboardKey.keyS)), AppAction.segmentTool);
  });

  test('pure modifier presses neither resolve nor cancel a leader', () {
    expect(stroke(LogicalKeyboardKey.shiftLeft), isA<ShortcutUnmatched>());
    stroke(LogicalKeyboardKey.keyG);
    expect(stroke(LogicalKeyboardKey.shiftLeft), isA<ShortcutUnmatched>());
    expect(resolver.hasPendingLeader, isTrue);
    expect(actionOf(stroke(LogicalKeyboardKey.keyA)), AppAction.arcTool);
  });

  test('reset drops a pending leader', () {
    stroke(LogicalKeyboardKey.keyG);
    resolver.reset();
    expect(resolver.hasPendingLeader, isFalse);
    expect(actionOf(stroke(LogicalKeyboardKey.keyS)), AppAction.segmentTool);
  });
}
