import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/transform_equivalence.dart';

void main() {
  final a = FreePoint(id: 'a', position: const Vec2(0, 0));
  final b = FreePoint(id: 'b', position: const Vec2(4, 0));
  final c = FreePoint(id: 'c', position: const Vec2(2, 3));

  test('finds an existing image with identical parents and equal angle', () {
    final existing = RotatedPoint(id: 'r', point: a, center: b, angle: 1.25);
    final candidate = RotatedPoint(id: 'n0', point: a, center: b, angle: 1.25);

    expect(equivalentExisting([b, a, existing], candidate), same(existing));
  });

  test('a different angle is not equivalent', () {
    final existing = RotatedPoint(id: 'r', point: a, center: b, angle: 1.25);
    final candidate = RotatedPoint(
      id: 'n0',
      point: a,
      center: b,
      angle: 1.25 + 1e-9,
    );

    expect(equivalentExisting([existing], candidate), isNull);
  });

  test('homothetic points compare their ratio exactly (Phase 68)', () {
    final existing = HomotheticPoint(id: 'h', point: a, center: b, ratio: 2);
    final matching = HomotheticPoint(id: 'n0', point: a, center: b, ratio: 2);
    final other = HomotheticPoint(
      id: 'n1',
      point: a,
      center: b,
      ratio: 2 + 1e-9,
    );

    expect(equivalentExisting([b, a, existing], matching), same(existing));
    expect(equivalentExisting([existing], other), isNull);
  });

  test('identical parents means instances, not positions', () {
    // b2 coincides with b: the images are numerically identical today but
    // diverge the moment either free point is dragged.
    final b2 = FreePoint(id: 'b2', position: b.position);
    final existing = CentralReflectionPoint(id: 'r', point: a, center: b);
    final candidate = CentralReflectionPoint(id: 'n0', point: a, center: b2);

    expect(equivalentExisting([existing], candidate), isNull);
  });

  test('parent slots are positional', () {
    final existing = Segment(id: 's', point1: a, point2: b);
    final swapped = Segment(id: 'n0', point1: b, point2: a);
    final matching = Segment(id: 'n1', point1: a, point2: b);

    expect(equivalentExisting([existing], swapped), isNull);
    expect(equivalentExisting([existing], matching), same(existing));
  });

  test('a different concrete kind over the same parents is not equivalent', () {
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final candidate = Segment(id: 'n0', point1: a, point2: b);

    expect(equivalentExisting([line], candidate), isNull);
  });

  test('an uncovered candidate kind finds nothing', () {
    final existing = Midpoint(id: 'm', point1: a, point2: b);
    final candidate = Midpoint(id: 'n0', point1: a, point2: b);

    expect(
      equivalentExisting([existing], candidate),
      isNull,
      reason: 'only transform-image kinds participate',
    );
  });

  test('first equivalent in iteration order wins', () {
    final first = ReflectedPoint(
      id: 'r1',
      point: c,
      mirror: LineThroughTwoPoints(id: 'l', point1: a, point2: b),
    );
    final mirror = first.mirror;
    final second = ReflectedPoint(id: 'r2', point: c, mirror: mirror);
    final candidate = ReflectedPoint(id: 'n0', point: c, mirror: mirror);

    expect(equivalentExisting([first, second], candidate), same(first));
  });
}
