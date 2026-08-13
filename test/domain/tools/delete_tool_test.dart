import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/delete_objects_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/delete_tool.dart';
import 'package:regula/domain/tools/tool.dart';

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

  test('a tap commits one DeleteObjectsCommand over exactly the hit', () {
    const tool = DeleteTool();
    final result = tool.onInput(ToolInput(const Vec2(2, 0), hit: s));

    expect(result, isA<ToolCommitted>());
    final command = (result as ToolCommitted).command as DeleteObjectsCommand;
    expect(command.ids, ['s'], reason: 'the tapped object, nothing batched');
  });

  test('applying the command cascades to dependents and undo restores', () {
    const tool = DeleteTool();
    final result = tool.onInput(ToolInput(Vec2.zero, hit: a));
    final command = (result as ToolCommitted).command;

    command.apply(construction);
    expect(construction.contains('a'), isFalse);
    expect(
      construction.contains('s'),
      isFalse,
      reason: 'the segment depends on the deleted endpoint',
    );
    expect(construction.contains('b'), isTrue);

    command.undo(construction);
    expect(construction.contains('a'), isTrue);
    expect(construction.contains('s'), isTrue);
  });

  test('an empty-canvas tap does nothing', () {
    const tool = DeleteTool();
    expect(tool.onInput(const ToolInput(Vec2(9, 9))), isA<ToolIgnored>());
  });

  test('reset is a no-op at any time — the tool is stateless', () {
    const tool = DeleteTool();
    tool.reset();
    expect(tool.onInput(ToolInput(Vec2.zero, hit: b)), isA<ToolCommitted>());
    tool.reset();
    expect(tool.onInput(ToolInput(Vec2.zero, hit: b)), isA<ToolCommitted>());
  });
}
