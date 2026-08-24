import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/question_spellings.dart';

void main() {
  FreePoint free(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  List<String> ids(Iterable<Predicate> spellings) => [
    for (final s in spellings) s.points.map((p) => p.id).join(),
  ];

  group('CarrierGroup', () {
    test('a segment names its length first, then every witness pair', () {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final ab = Segment(id: 'ab', point1: a, point2: b);
      construction.add(a);
      construction.add(b);
      construction.add(ab);
      final x = PointOnObject(id: 'x', curve: ab, parameter: 0.5);
      construction.add(x);

      final group = CarrierGroup.ofCarrier(construction.objects, ab)!;

      expect(group.boundsLength, isTrue);
      expect(group.pairs.map((p) => '${p.a.id}${p.b.id}:${p.boundsLength}'), [
        'ab:true',
        'ax:false',
        'bx:false',
      ]);
      expect(group.lengthPairs, hasLength(1));
      expect(group.points.map((p) => p.id), ['a', 'b', 'x']);
      expect(group.name, 'ab');
    });

    test('a ray bounds a length from its origin; a line bounds none', () {
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final ray = Ray(id: 'r', origin: a, through: b);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final all = [a, b, ray, line];

      expect(CarrierGroup.ofCarrier(all, ray)!.boundsLength, isTrue);
      final onLine = CarrierGroup.ofCarrier(all, line)!;
      expect(onLine.boundsLength, isFalse);
      expect(onLine.lengthPairs, isEmpty);
    });

    test('a carrier with fewer than two named points has no group', () {
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      // Only `a` is in the construction the group reads over.
      expect(CarrierGroup.ofCarrier([a, line], line), isNull);
    });

    test('two points the user picked bound a length', () {
      final group = CarrierGroup.ofPoints(free('p', 0, 0), free('q', 1, 1));
      expect(group.boundsLength, isTrue);
      expect(group.pairs, hasLength(1));
      expect(group.name, 'pq');
    });

    test('a group needs at least one pair', () {
      expect(() => CarrierGroup(const [], const []), throwsArgumentError);
    });
  });

  group('relationQuestion', () {
    final a = free('a', 0, 0);
    final b = free('b', 4, 0);
    final c = free('c', 0, 3);
    final d = free('d', 4, 3);

    test('cong reads through length pairs only, and needs a length', () {
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final all = [a, b, c, d, ab];
      final x = PointOnObject(id: 'x', curve: ab, parameter: 0.5);
      all.add(x);
      final line = LineThroughTwoPoints(id: 'l', point1: c, point2: d);
      all.add(line);
      final segment = CarrierGroup.ofCarrier(all, ab)!;
      final onLine = CarrierGroup.ofCarrier(all, line)!;
      final picked = CarrierGroup.ofPoints(c, d);

      expect(relationQuestion(PredicateKind.cong, segment, onLine), isNull);
      final cong = relationQuestion(PredicateKind.cong, segment, picked)!;
      expect(ids(cong.spellings), ['abcd']);
      final para = relationQuestion(PredicateKind.para, segment, onLine)!;
      expect(ids(para.spellings), ['abcd', 'axcd', 'bxcd']);
    });

    test('a pairing that names no two lines is refused', () {
      final first = CarrierGroup.ofPoints(a, b);
      final second = CarrierGroup.ofPoints(b, a);
      expect(relationQuestion(PredicateKind.perp, first, second), isNull);
      expect(degeneratePairs(first.pairs.single, second.pairs.single), isTrue);
      expect(
        degeneratePairs(
          WitnessPair(a, a, boundsLength: false),
          second.pairs.single,
        ),
        isTrue,
        reason: 'a pair of one point names no line',
      );
      expect(
        degeneratePairs(
          first.pairs.single,
          CarrierGroup.ofPoints(c, d).pairs.single,
        ),
        isFalse,
      );
    });

    test('only the three two-line relations are relations', () {
      expect(
        () => relationQuestion(
          PredicateKind.coll,
          CarrierGroup.ofPoints(a, b),
          CarrierGroup.ofPoints(c, d),
        ),
        throwsArgumentError,
      );
    });
  });

  group('concurrencyQuestion', () {
    test('a meeting point is any point two of the groups both name', () {
      final p = free('p', 0, 0);
      final x = free('x', 1, 0);
      final y = free('y', 0, 1);
      final u = free('u', 2, 2);
      final v = free('v', 3, 3);
      // Lines PX and PY meet at P by name alone; UV is the third.
      final question = concurrencyQuestion([
        CarrierGroup.ofPoints(p, x),
        CarrierGroup.ofPoints(p, y),
        CarrierGroup.ofPoints(u, v),
      ])!;

      expect(question.kind, PredicateKind.coll);
      expect(ids(question.spellings), ['puv']);
      expect(question.reading, 'px, py and uv are concurrent');
    });

    test('no named meeting point, no question', () {
      final points = [for (var i = 0; i < 6; i++) free('p$i', i.toDouble(), 0)];
      expect(
        concurrencyQuestion([
          CarrierGroup.ofPoints(points[0], points[1]),
          CarrierGroup.ofPoints(points[2], points[3]),
          CarrierGroup.ofPoints(points[4], points[5]),
        ]),
        isNull,
      );
    });

    test('concurrency is of exactly three', () {
      final p = free('p', 0, 0);
      final q = free('q', 1, 1);
      expect(
        () => concurrencyQuestion([CarrierGroup.ofPoints(p, q)]),
        throwsArgumentError,
      );
    });
  });

  group('tangencyQuestion', () {
    test('reads the radius against every other point on the line', () {
      final construction = Construction();
      final o = free('o', 0, 0);
      final x = free('x', 5, 0);
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: x);
      final q = free('q', 5, 3);
      final line = LineThroughTwoPoints(id: 't', point1: x, point2: q);
      for (final object in [o, x, circle, q, line]) {
        construction.add(object);
      }
      final onLine = PointOnObject(id: 's', curve: line, parameter: 2);
      construction.add(onLine);
      final all = construction.objects;
      final group = CarrierGroup.ofCarrier(all, line)!;

      final question = tangencyQuestion(all, group, circle)!;

      expect(question.reading, 'xq is tangent to the circle at x');
      expect(ids(question.spellings), ['oxxq', 'oxxs']);
    });
  });

  group('eqangleQuestion', () {
    test('the spelling is the caller\'s order, and θ = θ is dropped', () {
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 0, 3);
      final d = free('d', 4, 3);
      final ab = CarrierGroup.ofPoints(a, b);
      final cd = CarrierGroup.ofPoints(c, d);
      final ac = CarrierGroup.ofPoints(a, c);
      final bd = CarrierGroup.ofPoints(b, d);

      final question = eqangleQuestion([ab, cd, ac, bd])!;
      expect(ids(question.spellings), ['abcdacbd']);

      expect(eqangleQuestion([ab, cd, cd, ab]), isNull, reason: 'θ = θ');
      expect(() => eqangleQuestion([ab, cd]), throwsArgumentError);
    });
  });
}
