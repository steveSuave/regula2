import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/commands/macro_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/fixed_radius_circle_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late int nextId;
  late FixedRadiusCircleTool tool;

  setUp(() {
    nextId = 0;
    tool = FixedRadiusCircleTool(newId: () => 'n${nextId++}', radius: 2.5);
  });

  group('FixedRadiusCircleTool', () {
    test('an empty-canvas tap commits a free center plus the circle', () {
      final construction = Construction();
      final result =
          tool.onInput(const ToolInput(Vec2(3, -1))) as ToolCommitted;

      expect(result.command, isA<MacroCommand>());
      result.command.apply(construction);
      expect(construction.length, 2);
      final circle = construction.objects.whereType<FixedRadiusCircle>().single;
      expect(circle.radius, 2.5);
      expect(circle.circle!.center, const Vec2(3, -1));
      expect(circle.center, isA<FreePoint>());

      result.command.undo(construction);
      expect(
        construction.isEmpty,
        isTrue,
        reason: 'center and circle are one undo unit',
      );
    });

    test('a tap on an existing point reuses it as the center', () {
      final construction = Construction();
      final e = FreePoint(id: 'e', position: const Vec2(1, 1));
      construction.add(e);

      final result =
          tool.onInput(ToolInput(e.position, hit: e)) as ToolCommitted;
      expect(
        result.command,
        isA<AddObjectCommand>(),
        reason: 'nothing but the circle is added',
      );
      result.command.apply(construction);

      final circle = construction.objects.whereType<FixedRadiusCircle>().single;
      expect(identical(circle.center, e), isTrue);

      // The circle follows its center.
      construction.moveFreePoint('e', const Vec2(4, 5));
      expect(circle.circle!.center, const Vec2(4, 5));
      expect(circle.circle!.radius, 2.5);
    });
  });
}
