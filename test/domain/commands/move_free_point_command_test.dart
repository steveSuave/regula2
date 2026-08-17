import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/move_free_point_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('MoveFreePointCommand', () {
    test('apply moves the point to `to`, undo back to `from`', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      c.add(a);
      final cmd = MoveFreePointCommand(
        pointId: 'a',
        from: Vec2.zero,
        to: const Vec2(3, 4),
      );

      cmd.apply(c);
      expect(a.position, const Vec2(3, 4));

      cmd.undo(c);
      expect(a.position, Vec2.zero);
    });

    test('apply and undo both recompute transitive dependents', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final m2 = Midpoint(id: 'm2', point1: m, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m)
        ..add(m2);
      final cmd = MoveFreePointCommand(
        pointId: 'a',
        from: Vec2.zero,
        to: const Vec2(8, 4),
      );

      cmd.apply(c);
      expect(m.position, const Vec2(6, 2));
      expect(m2.position, const Vec2(5, 1));

      cmd.undo(c);
      expect(m.position, const Vec2(2, 0));
      expect(m2.position, const Vec2(3, 0));
    });

    test('undo then apply restores the same state (redo)', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      c.add(a);
      final cmd = MoveFreePointCommand(
        pointId: 'a',
        from: const Vec2(1, 1),
        to: const Vec2(-2, 5),
      );

      cmd.apply(c);
      cmd.undo(c);
      cmd.apply(c);
      expect(a.position, const Vec2(-2, 5));
    });

    test('branch changes replay with the move in both directions '
        '(Phase 116 adoption)', () {
      // Line y = 0 and a circle of radius 3 around the dragged center:
      // at cy = 1 the roots sit at ±√8, at cy = 2 at ±√5. The command
      // carries the branch adoption a traced gesture ended with, so
      // apply lands the intersection on the adopted branch and undo
      // restores the original — position and identity together.
      final c = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final center = FreePoint(id: 'c', position: const Vec2(0, 1));
      final k = FixedRadiusCircle(id: 'k', center: center, radius: 3);
      final p = IntersectionPoint(
        id: 'p',
        curve1: l,
        curve2: k,
        branchIndex: 0,
      );
      c
        ..add(a)
        ..add(b)
        ..add(l)
        ..add(center)
        ..add(k)
        ..add(p);
      final cmd = MoveFreePointCommand(
        pointId: 'c',
        from: const Vec2(0, 1),
        to: const Vec2(0, 2),
        branchChanges: const [(id: 'p', from: 0, to: 1)],
      );

      cmd.apply(c);
      expect(center.position, const Vec2(0, 2));
      expect(p.branchIndex, 1);
      expect(p.position!.closeTo(Vec2(math.sqrt(5), 0)), isTrue);

      cmd.undo(c);
      expect(center.position, const Vec2(0, 1));
      expect(p.branchIndex, 0);
      expect(p.position!.closeTo(Vec2(-math.sqrt(8), 0)), isTrue);

      cmd.apply(c);
      expect(p.branchIndex, 1);
      expect(p.position!.closeTo(Vec2(math.sqrt(5), 0)), isTrue);
    });

    test('throws on a non-free point', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m);
      final cmd = MoveFreePointCommand(
        pointId: 'm',
        from: const Vec2(2, 0),
        to: const Vec2(3, 0),
      );

      expect(() => cmd.apply(c), throwsArgumentError);
    });
  });
}
