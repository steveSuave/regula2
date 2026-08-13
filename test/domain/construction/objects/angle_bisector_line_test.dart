import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('AngleBisectorLine', () {
    test('right angle at the origin bisects to y = x', () {
      final a = FreePoint(id: 'a', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 5));
      final bisector = AngleBisectorLine(id: 'k', arm1: a, vertex: v, arm2: b);

      expect(bisector.parents, [a, v, b]);
      expect(
        bisector.line!.closeTo(
          LineEq.throughPoints(Vec2.zero, const Vec2(1, 1)),
        ),
        isTrue,
      );
    });

    test('arm dragged onto the vertex: undefined, then recovers', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 5));
      final bisector = AngleBisectorLine(id: 'k', arm1: a, vertex: v, arm2: b);
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(bisector);

      construction.moveFreePoint('a', const Vec2(0, 0));
      expect(bisector.isDefined, isFalse);
      expect(bisector.line, isNull);

      construction.moveFreePoint('a', const Vec2(5, 0));
      expect(bisector.isDefined, isTrue);
      expect(bisector.line!.contains(const Vec2(1, 1)), isTrue);
    });

    test('tracks a moving vertex', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(5, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(0, 5));
      final bisector = AngleBisectorLine(id: 'k', arm1: a, vertex: v, arm2: b);
      construction
        ..add(a)
        ..add(v)
        ..add(b)
        ..add(bisector);

      construction.moveFreePoint('v', const Vec2(1, 1));
      expect(bisector.line!.contains(const Vec2(1, 1)), isTrue);
      final u = (a.position - const Vec2(1, 1)).normalized();
      final w = (b.position - const Vec2(1, 1)).normalized();
      expect(
        bisector.line!.distanceTo(const Vec2(1, 1) + u),
        closeTo(bisector.line!.distanceTo(const Vec2(1, 1) + w), 1e-9),
      );
    });
  });
}
