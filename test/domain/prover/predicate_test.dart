import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/predicate.dart';

void main() {
  FreePoint free(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  test('arity is enforced as a programmer-error contract', () {
    final a = free('a', 0, 0);
    final b = free('b', 1, 0);
    expect(() => Predicate(PredicateKind.coll, [a, b]), throwsArgumentError);
    expect(
      () => Predicate(PredicateKind.midp, [a, b, a, b]),
      throwsArgumentError,
    );
  });

  test('every kind dispatches to its evaluator', () {
    final o = free('o', 0, 0);
    final x2 = free('x2', 2, 0);
    final x4 = free('x4', 4, 0);
    final y3 = free('y3', 0, 3);
    final d44 = free('d', 4, 4);

    bool holds(PredicateKind kind, List<FreePoint> points) =>
        Predicate(kind, points).holdsNow;

    expect(holds(PredicateKind.coll, [o, x2, x4]), isTrue);
    expect(holds(PredicateKind.coll, [o, x2, y3]), isFalse);
    expect(holds(PredicateKind.para, [o, x2, y3, d44]), isFalse);
    expect(holds(PredicateKind.perp, [o, x2, o, y3]), isTrue);
    expect(holds(PredicateKind.cong, [o, y3, o, y3]), isTrue);
    expect(holds(PredicateKind.cong, [o, x2, o, y3]), isFalse);
    expect(holds(PredicateKind.midp, [x2, o, x4]), isTrue);
    expect(holds(PredicateKind.midp, [x2, o, y3]), isFalse);
    // (0,0) (2,0) (0,3) (4,4): generic four points, no circle claimed;
    // the true cyclic case is covered in numeric_checks_test.
    expect(holds(PredicateKind.cyclic, [o, x2, y3, d44]), isFalse);
    expect(holds(PredicateKind.eqangle, [o, x2, o, y3, o, y3, o, x2]), isTrue);
    expect(holds(PredicateKind.eqratio, [o, x2, o, x4, o, x2, o, x4]), isTrue);
    expect(
      holds(PredicateKind.simtri, [o, x2, y3, o, x4, free('t', 0, 6)]),
      isTrue,
    );
    expect(holds(PredicateKind.contri, [o, x2, y3, o, x2, y3]), isTrue);
  });

  test('an undefined point makes every predicate false', () {
    final a = free('a', 0, 0);
    final b = free('b', 4, 0);
    final c = free('c', 0, 2);
    final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
    // Two distinct parallels to one reference never meet in the chart:
    // their intersection projects to a point at infinity, position null.
    final p1 = ParallelLine(id: 'p1', through: c, reference: ab);
    final p2 = ParallelLine(id: 'p2', through: free('d', 0, 5), reference: ab);
    final never = IntersectionPoint(
      id: 'x',
      curve1: p1,
      curve2: p2,
      branchIndex: 0,
    );
    for (final object in [ab, p1, p2, never]) {
      object.recompute();
    }
    expect(never.position, isNull);

    expect(Predicate(PredicateKind.coll, [a, b, never]).holdsNow, isFalse);
  });

  test('toString names the kind and the points', () {
    final a = free('a', 0, 0);
    final b = free('b', 1, 0);
    final c = free('c', 2, 0);
    expect(
      Predicate(PredicateKind.coll, [a, b, c]).toString(),
      'coll(a, b, c)',
    );
  });
}
