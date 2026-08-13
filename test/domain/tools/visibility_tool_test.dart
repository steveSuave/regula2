import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/change_attributes_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/tool.dart';
import 'package:regula/domain/tools/visibility_tool.dart';

void main() {
  late Construction construction;
  late FreePoint a;
  late FreePoint b;
  late Segment s;

  setUp(() {
    construction = Construction();
    a = FreePoint(id: 'a', position: Vec2.zero);
    b = FreePoint(id: 'b', position: const Vec2(4, 0));
    s = Segment(id: 's', point1: a, point2: b);
    construction
      ..add(a)
      ..add(b)
      ..add(s);
  });

  /// Runs one tap through [tool] and applies the committed command.
  ChangeAttributesCommand tapAndApply(VisibilityTool tool, ToolInput input) {
    final result = tool.onInput(input);
    expect(result, isA<ToolCommitted>());
    final command =
        (result as ToolCommitted).command as ChangeAttributesCommand;
    command.apply(construction);
    return command;
  }

  group('VisibilityTool.hide', () {
    test('a tap on a visible object hides it, one command per tap', () {
      final tool = VisibilityTool.hide();
      final command = tapAndApply(tool, ToolInput(Vec2.zero, hit: a));

      expect(a.attributes.visible, isFalse);
      expect(
        command.newAttributes.keys,
        ['a'],
        reason: 'exactly the tapped object, nothing batched',
      );

      command.undo(construction);
      expect(a.attributes.visible, isTrue);
    });

    test('taps hide only the hit object, not the selection or parents', () {
      final tool = VisibilityTool.hide();
      tapAndApply(tool, ToolInput(const Vec2(2, 0), hit: s));

      expect(s.attributes.visible, isFalse);
      expect(a.attributes.visible, isTrue);
      expect(b.attributes.visible, isTrue);
    });

    test('an empty-canvas tap does nothing', () {
      final tool = VisibilityTool.hide();
      expect(tool.onInput(const ToolInput(Vec2(9, 9))), isA<ToolIgnored>());
    });

    test('a hidden hit is ignored — hide never un-hides', () {
      construction.setAttributes('a', const ObjectAttributes(visible: false));
      final tool = VisibilityTool.hide();
      expect(tool.onInput(ToolInput(Vec2.zero, hit: a)), isA<ToolIgnored>());
      expect(a.attributes.visible, isFalse);
    });

    test('does not reveal hidden objects to the canvas', () {
      expect(VisibilityTool.hide().revealsHidden, isFalse);
    });
  });

  group('VisibilityTool.showHide', () {
    test('taps toggle visibility both directions, one command each', () {
      final tool = VisibilityTool.showHide();

      tapAndApply(tool, ToolInput(Vec2.zero, hit: a));
      expect(a.attributes.visible, isFalse);

      final command = tapAndApply(tool, ToolInput(Vec2.zero, hit: a));
      expect(a.attributes.visible, isTrue, reason: 'a dimmed tap re-shows');

      command.undo(construction);
      expect(
        a.attributes.visible,
        isFalse,
        reason: 'each tap is its own undo step',
      );
    });

    test('an empty-canvas tap does nothing', () {
      final tool = VisibilityTool.showHide();
      expect(tool.onInput(const ToolInput(Vec2(9, 9))), isA<ToolIgnored>());
    });

    test('reveals hidden objects to the canvas', () {
      expect(VisibilityTool.showHide().revealsHidden, isTrue);
    });
  });

  group('VisibilityTool.hideAll', () {
    test('one command hides every visible object, undo restores all', () {
      final command = VisibilityTool.hideAll([a, b, s])!;
      command.apply(construction);

      expect(a.attributes.visible, isFalse);
      expect(b.attributes.visible, isFalse);
      expect(s.attributes.visible, isFalse);

      command.undo(construction);
      expect(a.attributes.visible, isTrue);
      expect(b.attributes.visible, isTrue);
      expect(s.attributes.visible, isTrue);
    });

    test('already-hidden objects are skipped — undo must not reveal them', () {
      construction.setAttributes('b', const ObjectAttributes(visible: false));
      final command = VisibilityTool.hideAll([a, b])!;
      expect(command.newAttributes.keys, ['a']);

      command.apply(construction);
      command.undo(construction);
      expect(a.attributes.visible, isTrue);
      expect(
        b.attributes.visible,
        isFalse,
        reason: 'b was hidden before hideAll and must stay hidden',
      );
    });

    test('returns null for an all-hidden or empty input', () {
      construction.setAttributes('a', const ObjectAttributes(visible: false));
      expect(VisibilityTool.hideAll([a]), isNull);
      expect(VisibilityTool.hideAll(const []), isNull);
    });

    test('preserves every other attribute', () {
      construction.setAttributes(
        'a',
        const ObjectAttributes(name: 'A', colorArgb: 0xFF123456),
      );
      VisibilityTool.hideAll([a])!.apply(construction);
      expect(a.attributes.name, 'A');
      expect(a.attributes.colorArgb, 0xFF123456);
    });
  });

  test('toggling preserves every other attribute', () {
    construction.setAttributes(
      'a',
      const ObjectAttributes(name: 'A', colorArgb: 0xFF123456, pointSize: 7),
    );
    final tool = VisibilityTool.hide();
    tapAndApply(tool, ToolInput(Vec2.zero, hit: a));

    expect(a.attributes.name, 'A');
    expect(a.attributes.colorArgb, 0xFF123456);
    expect(a.attributes.pointSize, 7);
  });

  test('reset is a no-op at any time — the tool is stateless', () {
    final tool = VisibilityTool.showHide();
    tool.reset();
    tool.onInput(ToolInput(Vec2.zero, hit: a));
    tool.reset();
    expect(tool.onInput(ToolInput(Vec2.zero, hit: a)), isA<ToolCommitted>());
  });
}
