import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/questions.dart';

void main() {
  FreePoint free(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  /// Square-ish rig: A B C D free, segments AB and CD, plus a line
  /// through A and B carrying a third point.
  ({Construction construction, Map<String, GeoObject> byName}) rig() {
    final construction = Construction();
    final a = free('a', 0, 0);
    final b = free('b', 4, 0);
    final c = free('c', 0, 3);
    final d = free('d', 4, 3);
    final ab = Segment(id: 'ab', point1: a, point2: b);
    final cd = Segment(id: 'cd', point1: c, point2: d);
    for (final object in [a, b, c, d, ab, cd]) {
      construction.add(object);
    }
    return (
      construction: construction,
      byName: {'a': a, 'b': b, 'c': c, 'd': d, 'ab': ab, 'cd': cd},
    );
  }

  List<ProverQuestion> ask(Construction construction, Set<String> ids) =>
      askableQuestions(construction.objects, selectedIds: ids);

  Set<PredicateKind> kinds(List<ProverQuestion> questions) => {
    for (final question in questions) question.kind,
  };

  group('what a selection phrases', () {
    test('two segments give perpendicular, parallel and congruent', () {
      final r = rig();
      final questions = ask(r.construction, {'ab', 'cd'});

      expect(kinds(questions), {
        PredicateKind.perp,
        PredicateKind.para,
        PredicateKind.cong,
      });
      expect(
        questions.first.kind,
        PredicateKind.perp,
        reason: 'the relation most selections mean comes first',
      );
      expect(
        questions.every((q) => q.spellings.isNotEmpty),
        isTrue,
        reason: 'a question with no phrasing is not a question',
      );
    });

    test('a plain line has no length, so cong is not offered', () {
      final r = rig();
      final line = LineThroughTwoPoints(
        id: 'l',
        point1: r.byName['c']! as GeoPoint,
        point2: r.byName['d']! as GeoPoint,
      );
      r.construction.add(line);

      expect(kinds(ask(r.construction, {'ab', 'l'})), {
        PredicateKind.perp,
        PredicateKind.para,
      });
    });

    test('two selected points act as a pair against a carrier', () {
      final r = rig();

      final questions = ask(r.construction, {'ab', 'c', 'd'});

      expect(kinds(questions), {
        PredicateKind.perp,
        PredicateKind.para,
        PredicateKind.cong,
      });
      expect(questions.first.canonical.points.map((p) => p.id), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('three points give collinear and all three midpoint readings', () {
      final r = rig();

      final questions = ask(r.construction, {'a', 'b', 'c'});

      expect(questions.map((q) => q.kind).toList(), [
        PredicateKind.coll,
        PredicateKind.midp,
        PredicateKind.midp,
        PredicateKind.midp,
      ]);
      expect(
        {for (final q in questions.skip(1)) q.canonical.points.first.id},
        {'a', 'b', 'c'},
        reason: 'each point gets its turn as the midpoint',
      );
    });

    test('four points give cyclic and the three pairings', () {
      final r = rig();

      final questions = ask(r.construction, {'a', 'b', 'c', 'd'});

      expect(questions.first.kind, PredicateKind.cyclic);
      expect(questions, hasLength(1 + 3 * 3));
      final perpPairings = {
        for (final q in questions)
          if (q.kind == PredicateKind.perp)
            q.canonical.points.map((p) => p.id).join(),
      };
      expect(perpPairings, {'abcd', 'acbd', 'adbc'});
    });

    test('selections that phrase nothing phrase nothing', () {
      final r = rig();

      expect(ask(r.construction, const {}), isEmpty);
      expect(ask(r.construction, {'a'}), isEmpty, reason: 'a lone point');
      expect(
        ask(r.construction, {'a', 'b', 'c', 'd', 'ab'}),
        isEmpty,
        reason: 'four points and a carrier is not a statement',
      );
      expect(
        ask(r.construction, {'ab'}),
        isEmpty,
        reason: 'one carrier relates to nothing',
      );
      expect(
        ask(r.construction, {'ab', 'cd', 'a'}),
        isEmpty,
        reason: 'two carriers plus a stray point is ambiguous',
      );
    });

    test('a circle phrases nothing — cyclic is about four points', () {
      final r = rig();
      r.construction.add(
        CircleCenterPoint(
          id: 'k',
          center: r.byName['a']! as GeoPoint,
          onCircle: r.byName['b']! as GeoPoint,
        ),
      );

      expect(ask(r.construction, {'k'}), isEmpty);
      expect(ask(r.construction, {'k', 'ab'}), isEmpty);
    });

    test('a carrier with fewer than two known points phrases nothing', () {
      // A `PerpendicularLine` names one point (the one it passes
      // through) and nothing else sits on it, so there is no pair to
      // witness its direction with. Honest rather than approximated —
      // DD could do nothing with an unnamed line either.
      final r = rig();
      r.construction.add(
        PerpendicularLine(
          id: 'p',
          through: r.byName['c']! as GeoPoint,
          reference: r.byName['ab']! as GeoLine,
        ),
      );

      expect(ask(r.construction, {'ab', 'p'}), isEmpty);

      // Glue a second point to it and the same selection speaks.
      r.construction.add(
        PointOnObject(id: 'g', curve: r.construction.byId('p')!, parameter: 2),
      );
      expect(ask(r.construction, {'ab', 'p'}), isNotEmpty);
    });

    test('two carriers naming the same two points relate nothing', () {
      // A segment and a line through the same pair are one line, and
      // "is this line perpendicular to itself?" is not a question. It is
      // a property of the tuple, so it is refused here rather than left
      // to the filter.
      final r = rig();
      r.construction.add(
        LineThroughTwoPoints(
          id: 'l',
          point1: r.byName['a']! as GeoPoint,
          point2: r.byName['b']! as GeoPoint,
        ),
      );

      expect(ask(r.construction, {'ab', 'l'}), isEmpty);
    });
  });

  group('a question is a statement, not a spelling', () {
    test('a carrier with a third point on it phrases every witness pair', () {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 0, 3);
      final d = free('d', 4, 3);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      for (final object in [a, b, c, d, line, cd]) {
        construction.add(object);
      }
      // A third point structurally on the line: now AB, AX and BX all
      // name it, and a derived fact may be spelled with any of them.
      final x = PointOnObject(id: 'x', curve: line, parameter: 2);
      construction.add(x);

      final perp = ask(construction, {
        'l',
        'cd',
      }).singleWhere((q) => q.kind == PredicateKind.perp);

      expect(
        perp.spellings,
        hasLength(3),
        reason: 'three pairs on the line, one pair on the segment',
      );
      expect(
        {
          for (final s in perp.spellings)
            s.points.take(2).map((p) => p.id).join(),
        },
        {'ab', 'ax', 'bx'},
      );
      expect(
        perp.spellings.every(
          (s) => s.points.skip(2).map((p) => p.id).join() == 'cd',
        ),
        isTrue,
      );
    });

    test('a degenerate pairing is refused before it is asked', () {
      // Two segments sharing both endpoints would phrase perp(a,b,a,b),
      // which names no pair of lines. It is a property of the tuple, so
      // it is refused here rather than left to the filter.
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final first = Segment(id: 's1', point1: a, point2: b);
      final second = Segment(id: 's2', point1: a, point2: b);
      for (final object in [a, b, first, second]) {
        construction.add(object);
      }

      final questions = ask(construction, {'s1', 's2'});

      expect(
        questions,
        isEmpty,
        reason: 'the only phrasing was degenerate, so there is no question',
      );
    });

    test('ProverQuestion refuses to exist without a spelling', () {
      expect(
        () => ProverQuestion(PredicateKind.coll, const []),
        throwsArgumentError,
      );
    });
  });
}
