import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  group('Construction: add', () {
    test('preserves insertion order and rejects duplicate ids', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      c
        ..add(a)
        ..add(b);
      expect(c.objects.map((o) => o.id), ['a', 'b']);
      expect(c.length, 2);
      expect(
        () => c.add(FreePoint(id: 'a', position: Vec2.zero)),
        throwsArgumentError,
      );
    });

    test('nameOf labels an object for diagnostics: its name, else its '
        'kind and id', () {
      final c = Construction();
      final named = FreePoint(
        id: 'aaaaaaaa-1111',
        position: Vec2.zero,
        attributes: const ObjectAttributes(name: 'A'),
      );
      final anonymous = FreePoint(id: 'bbbbbbbb-2222', position: Vec2.zero);
      c
        ..add(named)
        ..add(anonymous);
      expect(c.nameOf(named.id), 'A');
      expect(c.nameOf(anonymous.id), 'FreePoint#bbbbbb');
      expect(
        c.nameOf('gone'),
        contains('gone'),
        reason: 'a deleted object still labels its own log line',
      );
    });

    test('rejects an object whose parents are not in the construction', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      c.add(a); // b deliberately left out
      expect(
        () => c.add(Midpoint(id: 'm', point1: a, point2: b)),
        throwsArgumentError,
      );
    });

    test('rejects a same-id impostor posing as a present parent', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      c.add(a);
      // Same id, different instance: graph is wired by reference, so this
      // midpoint would silently track the wrong object if allowed in.
      final impostor = FreePoint(id: 'a', position: const Vec2(9, 9));
      expect(
        () => c.add(Midpoint(id: 'm', point1: impostor, point2: a)),
        throwsArgumentError,
      );
    });
  });

  group('Construction: moveFreePoint', () {
    test('moves the point and recomputes transitive dependents in order', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      // Chain: midpoint of (midpoint, b) — depends on m, so recompute
      // order matters.
      final m2 = Midpoint(id: 'm2', point1: m, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m)
        ..add(m2);

      c.moveFreePoint('a', const Vec2(0, 8));
      expect(m.position, const Vec2(2, 4));
      expect(m2.position, const Vec2(3, 2));
    });

    test('throws for unknown ids and for derived points', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m);
      expect(() => c.moveFreePoint('nope', Vec2.zero), throwsArgumentError);
      expect(() => c.moveFreePoint('m', Vec2.zero), throwsArgumentError);
    });
  });

  group('Construction: setPointOnObjectParameter', () {
    test('re-parameterizes the point and recomputes its dependents', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final p = PointOnObject(id: 'p', curve: l, parameter: 2);
      final m = Midpoint(id: 'm', point1: a, point2: p);
      c
        ..add(a)
        ..add(b)
        ..add(l)
        ..add(p)
        ..add(m);

      var notified = 0;
      c.addListener(() => notified++);
      c.setPointOnObjectParameter('p', 6);
      expect(p.parameter, 6);
      expect(p.position, const Vec2(6, 0));
      expect(m.position, const Vec2(3, 0));
      expect(notified, 1);
    });

    test('throws for unknown ids and for other point kinds', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m);
      expect(() => c.setPointOnObjectParameter('nope', 0), throwsArgumentError);
      expect(() => c.setPointOnObjectParameter('a', 0), throwsArgumentError);
      expect(() => c.setPointOnObjectParameter('m', 0), throwsArgumentError);
    });
  });

  group('Construction: setIntersectionBranch', () {
    test('re-points the branch and recomputes its dependents', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final center = FreePoint(id: 'e', position: const Vec2(0, 1));
      final rim = FreePoint(id: 'f', position: const Vec2(3, 1));
      final k = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final p = IntersectionPoint(id: 'p', curve1: l, curve2: k, branchIndex: 0);
      final m = Midpoint(id: 'm', point1: a, point2: p);
      c
        ..add(a)
        ..add(b)
        ..add(l)
        ..add(center)
        ..add(rim)
        ..add(k)
        ..add(p)
        ..add(m);
      // Branch 0 is the root at −√8 along the line's direction.
      final x = math.sqrt(8);
      expect(p.position!.closeTo(Vec2(-x, 0)), isTrue);

      var notified = 0;
      c.addListener(() => notified++);
      c.setIntersectionBranch('p', 1);
      expect(p.branchIndex, 1);
      expect(p.position!.closeTo(Vec2(x, 0)), isTrue);
      expect(m.position!.closeTo(Vec2((x - 10) / 2, 0)), isTrue);
      expect(notified, 1);
    });

    test('throws for unknown ids, other kinds, and out-of-range indices',
        () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final center = FreePoint(id: 'e', position: const Vec2(0, 1));
      final rim = FreePoint(id: 'f', position: const Vec2(3, 1));
      final k = CircleCenterPoint(id: 'k', center: center, onCircle: rim);
      final p = IntersectionPoint(id: 'p', curve1: l, curve2: k, branchIndex: 0);
      c
        ..add(a)
        ..add(b)
        ..add(l)
        ..add(center)
        ..add(rim)
        ..add(k)
        ..add(p);
      expect(() => c.setIntersectionBranch('nope', 0), throwsArgumentError);
      expect(() => c.setIntersectionBranch('a', 0), throwsArgumentError);
      expect(() => c.setIntersectionBranch('l', 0), throwsArgumentError);
      expect(() => c.setIntersectionBranch('p', -1), throwsArgumentError);
      expect(
        () => c.setIntersectionBranch('p', IntersectionPoint.maxBranchCount),
        throwsArgumentError,
      );
      expect(p.branchIndex, 0);
      // The bound is the *addressing space*, not the current candidate
      // count — which varies as the parents move, and which `recompute`
      // clamps to. It must match the constructor's, or a traced drag on
      // a conic pair adopts an index its own command then refuses: this
      // asserted `2` throws until Phase 120c, and that is what kept the
      // four crossings of two ellipses merging in the app after the
      // engine had stopped merging them.
      c.setIntersectionBranch('p', 2);
      expect(p.branchIndex, 2);
    });
  });

  group('Construction: dependents lookup', () {
    test('transitive dependents cover the whole downstream cone', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final l = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final m2 = Midpoint(id: 'm2', point1: m, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(l)
        ..add(m)
        ..add(m2);

      expect(c.transitiveDependentsOf('a'), {'l', 'm', 'm2'});
      expect(c.transitiveDependentsOf('m'), {'m2'});
      expect(c.transitiveDependentsOf('m2'), isEmpty);
    });
  });

  group('Construction: cascade delete & restore', () {
    test('removes the whole cone, returns it parents-first, restores', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      final m2 = Midpoint(id: 'm2', point1: m, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m)
        ..add(m2);

      final removed = c.removeWithDependents('m');
      expect(removed.map((o) => o.id), ['m', 'm2']);
      expect(c.objects.map((o) => o.id), ['a', 'b']);

      c.restore(removed);
      expect(c.contains('m'), isTrue);
      expect(c.contains('m2'), isTrue);
      // Restored objects recompute on entry, so they're consistent.
      expect(m2.position, const Vec2(1.5, 0));
    });

    test('deleting a root removes everything downstream of it only', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m);

      final removed = c.removeWithDependents('a');
      expect(removed.map((o) => o.id), ['a', 'm']);
      expect(c.objects.map((o) => o.id), ['b']);
    });

    test('delete after restore still cascades (dependents map rebuilt)', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(2, 0));
      final m = Midpoint(id: 'm', point1: a, point2: b);
      c
        ..add(a)
        ..add(b)
        ..add(m);

      c.restore(c.removeWithDependents('m'));
      final removed = c.removeWithDependents('a');
      expect(removed.map((o) => o.id), ['a', 'm']);
    });

    test('throws for an unknown id', () {
      expect(
        () => Construction().removeWithDependents('ghost'),
        throwsArgumentError,
      );
    });
  });

  group('Construction: setAttributes', () {
    test('replaces attributes without touching geometry, throws unknown', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(1, 2));
      c.add(a);

      c.setAttributes('a', const ObjectAttributes(name: 'A', visible: false));
      expect(a.attributes.name, 'A');
      expect(a.attributes.visible, isFalse);
      expect(a.position, const Vec2(1, 2));

      expect(
        () => c.setAttributes('nope', const ObjectAttributes()),
        throwsArgumentError,
      );
    });
  });

  group('Construction: listeners', () {
    test('notified once per mutation, removable', () {
      final c = Construction();
      var calls = 0;
      void listener() => calls++;
      c.addListener(listener);

      final a = FreePoint(id: 'a', position: Vec2.zero);
      c.add(a);
      expect(calls, 1);
      c.moveFreePoint('a', const Vec2(1, 1));
      expect(calls, 2);
      c.setAttributes('a', const ObjectAttributes(name: 'A'));
      expect(calls, 3);
      c.removeWithDependents('a');
      expect(calls, 4);

      c.removeListener(listener);
      c.add(FreePoint(id: 'b', position: Vec2.zero));
      expect(calls, 4);
    });
  });

  group('Construction: integration — compass perpendicular bisector', () {
    // Classic compass construction: circles around A through B and around
    // B through A intersect in X0/X1; line X0X1 is the perpendicular
    // bisector of AB; its intersection with line AB is AB's midpoint.
    // A 4-deep dependency chain — dragging A must keep the derived
    // "midpoint" exactly at (A+B)/2 and survive degeneracies.
    test('derived midpoint tracks (A+B)/2 under dragging', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final ka = CircleCenterPoint(id: 'ka', center: a, onCircle: b);
      final kb = CircleCenterPoint(id: 'kb', center: b, onCircle: a);
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: ka,
        curve2: kb,
        branchIndex: 0,
      );
      final x1 = IntersectionPoint(
        id: 'x1',
        curve1: ka,
        curve2: kb,
        branchIndex: 1,
      );
      final bisector = LineThroughTwoPoints(id: 'bi', point1: x0, point2: x1);
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final mid = IntersectionPoint(
        id: 'mid',
        curve1: bisector,
        curve2: ab,
        branchIndex: 0,
      );
      c
        ..add(a)
        ..add(b)
        ..add(ka)
        ..add(kb)
        ..add(x0)
        ..add(x1)
        ..add(bisector)
        ..add(ab)
        ..add(mid);

      expect(mid.position!.closeTo(const Vec2(2, 0)), isTrue);

      for (final target in const [Vec2(1, 3), Vec2(-2, -5), Vec2(10, 0.5)]) {
        c.moveFreePoint('a', target);
        final expected = target.lerp(b.position, 0.5);
        expect(
          mid.position!.closeTo(expected, 1e-9),
          isTrue,
          reason: 'midpoint must track (A+B)/2 for A = $target',
        );
      }
    });

    test('survives dragging A onto B and back', () {
      final c = Construction();
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final ka = CircleCenterPoint(id: 'ka', center: a, onCircle: b);
      final kb = CircleCenterPoint(id: 'kb', center: b, onCircle: a);
      final x0 = IntersectionPoint(
        id: 'x0',
        curve1: ka,
        curve2: kb,
        branchIndex: 0,
      );
      c
        ..add(a)
        ..add(b)
        ..add(ka)
        ..add(kb)
        ..add(x0);

      c.moveFreePoint('a', const Vec2(4, 0)); // onto B: concentric circles
      expect(x0.isDefined, isFalse);
      expect(ka.isDefined, isTrue, reason: 'zero-radius circle stays defined');

      c.moveFreePoint('a', Vec2.zero); // back: intersection reappears
      expect(x0.isDefined, isTrue);
      // Radius-4 circles centered (0,0) and (4,0) meet at (2, ±2√3).
      expect(x0.position!.closeTo(const Vec2(2, 3.4641016151377544)), isTrue);
    });
  });
}
