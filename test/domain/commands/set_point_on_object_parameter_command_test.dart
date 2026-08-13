import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/set_point_on_object_parameter_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  test('apply/undo round-trips the parameter float-exact on a line', () {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    final b = FreePoint(id: 'b', position: const Vec2(10, 0));
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final p = PointOnObject(id: 'p', curve: line, parameter: 3);
    final mid = Midpoint(id: 'm', point1: a, point2: p);
    construction
      ..add(a)
      ..add(b)
      ..add(line)
      ..add(p)
      ..add(mid);
    expect(p.position, const Vec2(3, 0));

    final command = SetPointOnObjectParameterCommand(
      pointId: 'p',
      from: 3,
      to: 7,
    );
    command.apply(construction);
    expect(p.parameter, 7);
    expect(p.position, const Vec2(7, 0));
    expect(
      mid.position,
      const Vec2(3.5, 0),
      reason: 'dependents recompute when the parameter changes',
    );

    command.undo(construction);
    expect(p.parameter, 3);
    expect(p.position, const Vec2(3, 0));
    expect(mid.position, const Vec2(1.5, 0));
  });

  test('replays against a circle host', () {
    final construction = Construction();
    final center = FreePoint(id: 'c', position: Vec2.zero);
    final rim = FreePoint(id: 'r', position: const Vec2(2, 0));
    final circle = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
    final p = PointOnObject(id: 'p', curve: circle, parameter: 0);
    construction
      ..add(center)
      ..add(rim)
      ..add(circle)
      ..add(p);

    final quarterTurn = SetPointOnObjectParameterCommand(
      pointId: 'p',
      from: 0,
      to: 1.5707963267948966,
    );
    quarterTurn.apply(construction);
    expect(p.position!.x, closeTo(0, 1e-12));
    expect(p.position!.y, closeTo(2, 1e-12));
    quarterTurn.undo(construction);
    expect(p.position, const Vec2(2, 0));
  });

  test('throws for a non-PointOnObject id before mutating anything', () {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: Vec2.zero);
    construction.add(a);

    final command = SetPointOnObjectParameterCommand(
      pointId: 'a',
      from: 0,
      to: 1,
    );
    expect(() => command.apply(construction), throwsArgumentError);
    expect(a.position, Vec2.zero);
  });
}
