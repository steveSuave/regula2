import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/text_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  var counter = 0;
  String newId() => 'id${counter++}';

  Construction withPoints() {
    final construction = Construction()
      ..add(
        FreePoint(
          id: 'a',
          position: const Vec2(0, 0),
          attributes: const ObjectAttributes(name: 'A'),
        ),
      )
      ..add(
        FreePoint(
          id: 'b',
          position: const Vec2(3, 4),
          attributes: const ObjectAttributes(name: 'B'),
        ),
      );
    return construction;
  }

  setUp(() => counter = 0);

  group('TextTool', () {
    test('a raw tap (null text) is not for this tool', () {
      final tool = TextTool(newId: newId);
      expect(tool.onInput(const ToolInput(Vec2(1, 1))), isA<ToolIgnored>());
    });

    test('empty or blank content is ignored', () {
      final tool = TextTool(newId: newId);
      expect(
        tool.onInput(const ToolInput(Vec2(1, 1), text: '')),
        isA<ToolIgnored>(),
      );
      expect(
        tool.onInput(const ToolInput(Vec2(1, 1), text: '   ')),
        isA<ToolIgnored>(),
      );
    });

    test('creates a text at the tap with zero label offset', () {
      final construction = withPoints();
      final tool = TextTool(newId: newId);
      final result = tool.onInput(
        ToolInput(
          const Vec2(2, 5),
          objects: construction.objects,
          text: 'AB = {dist(A, B)}',
        ),
      );
      final command = (result as ToolCommitted).command;
      final text = (command as AddObjectCommand).object as ExpressionText;
      expect(text.anchor, const Vec2(2, 5));
      expect(text.attributes.labelDx, 0);
      expect(text.attributes.labelDy, 0);
      expect(text.parents.map((p) => p.id), ['a', 'b']);

      command.apply(construction);
      expect(text.renderedText, 'AB = 5.00');
    });

    test('static text commits with no parents', () {
      final tool = TextTool(newId: newId);
      final result = tool.onInput(
        const ToolInput(Vec2(0, 0), text: 'hello world'),
      );
      final text =
          ((result as ToolCommitted).command as AddObjectCommand).object
              as ExpressionText;
      expect(text.parents, isEmpty);
      expect(text.renderedText, 'hello world');
    });

    test('a reference the construction no longer has is ignored', () {
      // The dialog validated against a construction that has since lost
      // point B (undo under the open dialog).
      final construction = Construction()
        ..add(
          FreePoint(
            id: 'a',
            position: const Vec2(0, 0),
            attributes: const ObjectAttributes(name: 'A'),
          ),
        );
      final tool = TextTool(newId: newId);
      final result = tool.onInput(
        ToolInput(
          const Vec2(2, 5),
          objects: construction.objects,
          text: '{dist(A, B)}',
        ),
      );
      expect(result, isA<ToolIgnored>());
    });

    test('malformed content is ignored, never thrown', () {
      final tool = TextTool(newId: newId);
      expect(
        tool.onInput(const ToolInput(Vec2(0, 0), text: '{1 +}')),
        isA<ToolIgnored>(),
      );
      expect(
        tool.onInput(const ToolInput(Vec2(0, 0), text: 'open {brace')),
        isA<ToolIgnored>(),
      );
    });

    test(
      'editing replaces under one macro, keeping id, anchor, attributes',
      () {
        final construction = withPoints();
        final original = ExpressionText(
          id: 'txt',
          content: 'old note',
          anchor: const Vec2(7, 7),
          references: const [],
          attributes: const ObjectAttributes(
            name: 't',
            colorArgb: 0xff112233,
            labelDx: 10,
            labelDy: -5,
            labelFontSize: 22,
          ),
        );
        construction.add(original);

        final tool = TextTool(newId: newId);
        final result = tool.onInput(
          ToolInput(
            const Vec2(7, 7),
            hit: original,
            objects: construction.objects,
            text: 'AB = {dist(A, B)}',
          ),
        );
        final macro = (result as ToolCommitted).command as MacroCommand;
        macro.apply(construction);

        final replacement = construction.byId('txt')! as ExpressionText;
        expect(replacement.renderedText, 'AB = 5.00');
        expect(replacement.anchor, const Vec2(7, 7));
        expect(replacement.attributes.name, 't');
        expect(replacement.attributes.colorArgb, 0xff112233);
        expect(replacement.attributes.labelDx, 10);
        expect(replacement.attributes.labelFontSize, 22);
        expect(replacement.parents.map((p) => p.id), ['a', 'b']);

        // One undo restores the original exactly.
        macro.undo(construction);
        expect(construction.byId('txt'), same(original));
        expect(original.renderedText, 'old note');
      },
    );

    test('editing a text that vanished under the dialog is ignored', () {
      final construction = withPoints();
      final ghost = ExpressionText(
        id: 'gone',
        content: 'note',
        anchor: const Vec2(0, 0),
        references: const [],
      );
      final tool = TextTool(newId: newId);
      final result = tool.onInput(
        ToolInput(
          const Vec2(0, 0),
          hit: ghost,
          objects: construction.objects,
          text: 'new note',
        ),
      );
      expect(result, isA<ToolIgnored>());
    });

    test('reset is a no-op (stateless tool)', () {
      TextTool(newId: newId).reset();
    });
  });
}
