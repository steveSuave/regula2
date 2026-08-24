import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/fact_naming.dart';
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

    test('four segments give the three equal-angle statements, and only '
        'three', () {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 5, 3);
      final d = free('d', 1, 3);
      final sides = [
        Segment(id: 's0', point1: a, point2: b),
        Segment(id: 's1', point1: b, point2: c),
        Segment(id: 's2', point1: c, point2: d),
        Segment(id: 's3', point1: d, point2: a),
      ];
      for (final object in [a, b, c, d, ...sides]) {
        construction.add(object);
      }

      final questions = ask(construction, {'s0', 's1', 's2', 's3'});

      expect(questions, hasLength(3));
      expect(kinds(questions), {PredicateKind.eqangle});
      final offered = {for (final q in questions) Fact.of(q.canonical)};
      expect(offered, hasLength(3), reason: 'three distinct statements');

      // The check that the three are the *right* three: every way of
      // reading four lines as ∠(x,y) = ∠(z,w) — 24 orderings, of which
      // the 6 below cover every orbit once the first side is anchored on
      // s0 — canonicalizes onto one of the offered facts. So nothing a
      // user could mean is missing, and (with three offered) nothing is
      // offered twice. The naive side-pairings (01|23, 02|13, 03|12)
      // fail this: the first two are one fact under the transpose.
      Fact reading(List<int> order) {
        final points = [
          for (final i in order) ...[sides[i].point1, sides[i].point2],
        ];
        return Fact.of(Predicate(PredicateKind.eqangle, points));
      }

      const orientations = [
        [0, 1, 2, 3],
        [0, 1, 3, 2],
        [0, 2, 1, 3],
        [0, 2, 3, 1],
        [0, 3, 1, 2],
        [0, 3, 2, 1],
      ];
      final covered = {for (final o in orientations) reading(o)};
      expect(covered, hasLength(3), reason: 'D4 leaves exactly three orbits');
      expect(covered, offered);

      // The naive pairing really is a duplicate — pinned so the comment
      // above stays true of the symmetry group, not just of this rig.
      expect(reading([0, 1, 2, 3]), reading([0, 2, 1, 3]));
    });

    test('four carriers phrase every witness pair, and refuse a line '
        'against itself', () {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 5, 3);
      final d = free('d', 1, 3);
      final ab = LineThroughTwoPoints(id: 'ab', point1: a, point2: b);
      final bc = Segment(id: 'bc', point1: b, point2: c);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      final da = Segment(id: 'da', point1: d, point2: a);
      for (final object in [a, b, c, d, ab, bc, cd, da]) {
        construction.add(object);
      }
      // A third point on the line: it now has three names.
      construction.add(PointOnObject(id: 'x', curve: ab, parameter: 2));

      final questions = ask(construction, {'ab', 'bc', 'cd', 'da'});

      expect(questions, hasLength(3));
      for (final question in questions) {
        expect(
          question.spellings,
          hasLength(3),
          reason: 'three names for the line, one for each segment',
        );
        expect(
          {for (final s in question.spellings) Fact.of(s)},
          hasLength(3),
          reason: 'different witness pairs are different spellings',
        );
      }

      // Two lines each named twice: every reading is the same two lines
      // on both sides of the equation (`θ = θ`) or one line against
      // itself (`0 = …`), and nothing is offered — the four-carrier form
      // of 'two carriers naming the same two points relate nothing'.
      construction.add(Segment(id: 'bc2', point1: b, point2: c));
      construction.add(Segment(id: 'cd2', point1: c, point2: d));
      expect(ask(construction, {'bc', 'cd', 'bc2', 'cd2'}), isEmpty);
    });

    test('the offered spelling reads three-point and true as magnitudes '
        '(Phase 162, the tangent–chord report)', () {
      // Circle about A through B; C, D on it; chords BC, BD, DC; the
      // tangent at C with E on it. The user selects the four segments
      // of "∠ECB = ∠CDB" and must see that sentence, not its transpose.
      final construction = decodeDocument(
        jsonDecode(File('test/fixtures/tangent-chord.rgl').readAsStringSync())
            as Map<String, dynamic>,
      ).construction;
      final byName = {
        for (final o in construction.objects) o.attributes.name: o.id,
      };
      final questions = ask(construction, {
        byName['b']!,
        byName['d']!,
        byName['e']!,
        byName['f']!,
      });

      expect(questions, hasLength(3));
      final readings = questions
          .map((q) => readPredicate(q.canonical))
          .toList();
      expect(
        readings,
        contains('angles BCE and BDC are equal'),
        reason: 'the theorem, as the user would state it',
      );
      expect(
        readings,
        isNot(contains('angles ECD and CBD are equal')),
        reason: 'its transpose is the same fact and a false-looking sentence',
      );
      for (final reading in readings) {
        expect(
          reading,
          startsWith('angles '),
          reason: 'every side shares a vertex here, so no "the angle from"',
        );
      }
    });

    test('the magnitude preference beats construction order', () {
      // The same figure with the carriers added as BC, BD, CE, DC: now
      // the first three-point orientation the enumeration meets is the
      // transpose, "angles CBD and ECD are equal" (107° vs 73°), and
      // only the magnitude check picks "BCE and BDC" (47° = 47°) over
      // it. The fixture test above passes without that check, because
      // its order happens to list the true reading first.
      final construction = Construction();
      final b = free('b', 545, -647.5);
      final c = free('c', 725.6807082866486, -61.51607625972173);
      final d = free('d', 845.2908907717656, -849.6098535395618);
      final e = free('e', 208.57068851405248, -307.4554255448492);
      for (final object in [
        b,
        c,
        d,
        e,
        Segment(id: 'bc', point1: b, point2: c),
        Segment(id: 'bd', point1: b, point2: d),
        Segment(id: 'ce', point1: c, point2: e),
        Segment(id: 'dc', point1: d, point2: c),
      ]) {
        construction.add(object);
      }
      final readings = ask(construction, {
        'bc',
        'bd',
        'ce',
        'dc',
      }).map((q) => readPredicate(q.canonical)).toList();
      // Any spelling whose magnitudes agree will do — which of the
      // four the tie-break lands on is enumeration order, not meaning.
      const trueReadings = {
        'angles bce and bdc are equal',
        'angles bdc and bce are equal',
        'angles ecb and cdb are equal',
        'angles cdb and ecb are equal',
      };
      expect(
        readings.where(trueReadings.contains),
        hasLength(1),
        reason: 'the theorem, read as magnitudes: $readings',
      );
      expect(readings, isNot(contains('angles cbd and ecd are equal')));
      expect(readings, isNot(contains('angles ecd and cbd are equal')));
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
      r.construction.add(
        Segment(
          id: 'ad',
          point1: r.byName['a']! as GeoPoint,
          point2: r.byName['d']! as GeoPoint,
        ),
      );
      // Three carriers phrase concurrency now (Phase 159, the sugar group
      // below); what stays refused is anything with a leftover.
      expect(
        ask(r.construction, {'ab', 'cd', 'ad', 'a'}),
        isEmpty,
        reason: 'four line-shaped things and a stray point is not four lines',
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

  group('sugar: what the vocabulary has no word for', () {
    /// P with three lines through it and one more named point on the
    /// third — the shape concurrency needs: a meeting point, and a pair
    /// naming the third line that the meeting point is not part of.
    ({Construction construction, List<GeoObject> lines}) pencil({
      bool witness = true,
    }) {
      final construction = Construction();
      final p = free('p', 0, 0);
      final a = free('a', 4, 0);
      final b = free('b', 0, 4);
      final c = free('c', 3, 3);
      final la = LineThroughTwoPoints(id: 'la', point1: p, point2: a);
      final lb = LineThroughTwoPoints(id: 'lb', point1: p, point2: b);
      final lc = LineThroughTwoPoints(id: 'lc', point1: p, point2: c);
      for (final object in [p, a, b, c, la, lb, lc]) {
        construction.add(object);
      }
      if (witness) {
        construction.add(PointOnObject(id: 'z', curve: lc, parameter: 2));
      }
      return (construction: construction, lines: [la, lb, lc]);
    }

    test('three lines through a named point ask coll about the third', () {
      final r = pencil();
      final questions = ask(r.construction, {'la', 'lb', 'lc'});

      expect(questions, hasLength(1));
      final question = questions.single;
      expect(question.kind, PredicateKind.coll);
      expect(question.reading, 'pa, pb and pc are concurrent');
      // The meeting point P against the one pair on lc it is not part
      // of: (c, z). Pairs (p, c) and (p, z) would say "P, P, C are
      // collinear" — refused. Same on la and lb, whose only other pairs
      // contain P, so the other two carrier pairs contribute nothing.
      expect(question.spellings.map((s) => s.points.map((p) => p.id).join()), [
        'pcz',
      ]);
    });

    test('no named meeting point, no chip', () {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 0, 3);
      final d = free('d', 4, 3);
      final e = free('e', 1, 1);
      final f = free('f', 5, 2);
      for (final object in [
        a,
        b,
        c,
        d,
        e,
        f,
        LineThroughTwoPoints(id: 'ab', point1: a, point2: b),
        LineThroughTwoPoints(id: 'cd', point1: c, point2: d),
        LineThroughTwoPoints(id: 'ef', point1: e, point2: f),
      ]) {
        construction.add(object);
      }
      expect(ask(construction, {'ab', 'cd', 'ef'}), isEmpty);
    });

    test('a meeting point on all three, and no other name: nothing', () {
      // Every pair on every third line contains P, so every spelling is
      // degenerate; the question needs a name P is not part of.
      final r = pencil(witness: false);
      expect(ask(r.construction, {'la', 'lb', 'lc'}), isEmpty);
    });

    test('a concurrency the figure denies is still asked, and refuted '
        'later', () {
      // P on la and lb, and a third line nowhere near: coll(P, C, D) is
      // the question; that it is false is the filter's finding.
      final construction = Construction();
      final p = free('p', 0, 0);
      final a = free('a', 4, 0);
      final b = free('b', 0, 4);
      final c = free('c', 3, 3);
      final d = free('d', 5, 1);
      for (final object in [
        p,
        a,
        b,
        c,
        d,
        LineThroughTwoPoints(id: 'la', point1: p, point2: a),
        LineThroughTwoPoints(id: 'lb', point1: p, point2: b),
        LineThroughTwoPoints(id: 'cd', point1: c, point2: d),
      ]) {
        construction.add(object);
      }
      final question = ask(construction, {'la', 'lb', 'cd'}).single;
      expect(question.spellings.map((s) => s.points.map((p) => p.id).join()), [
        'pcd',
      ]);
    });

    /// Phase 155's tangency figure: a circle with a structural centre, a
    /// tangent from an external pole, and the touch point drawn as the
    /// intersection of the two.
    ({Construction construction, GeoCircle circle, GeoLine tangent}) tangency({
      bool touch = true,
    }) {
      final construction = Construction();
      final o = free('o', 0, 0);
      final rim = free('r', 3, 0);
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: rim);
      final q = free('q', 9, 0);
      final tangent = TangentLine(id: 't', point: q, circle: circle, branch: 0);
      for (final object in [o, rim, circle, q, tangent]) {
        construction.add(object);
      }
      if (touch) {
        construction.add(
          IntersectionPoint(
            id: 'x',
            curve1: tangent,
            curve2: circle,
            branchIndex: 0,
          ),
        );
      }
      return (construction: construction, circle: circle, tangent: tangent);
    }

    test('a line and a circle ask whether the line is tangent', () {
      final r = tangency();
      final questions = ask(r.construction, {'t', 'k'});

      expect(questions, hasLength(1));
      final question = questions.single;
      expect(question.kind, PredicateKind.perp);
      expect(question.reading, 'qx is tangent to the circle at x');
      // perp(O, X, X, Q): the radius to the touch point against the line.
      expect(question.spellings.map((s) => s.points.map((p) => p.id).join()), [
        'oxxq',
      ]);
    });

    test('no named touch point, no chip — the same silence as the '
        'hypothesis', () {
      final r = tangency(touch: false);
      expect(ask(r.construction, {'t', 'k'}), isEmpty);
    });

    test('a circle with no named centre says nothing; drawing one is '
        'enough', () {
      final construction = Construction();
      final a = free('a', 3, 0);
      final b = free('b', 0, 3);
      final c = free('c', -3, 0);
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      final q = free('q', 9, 0);
      final tangent = TangentLine(id: 't', point: q, circle: circle, branch: 0);
      final touch = IntersectionPoint(
        id: 'x',
        curve1: tangent,
        curve2: circle,
        branchIndex: 0,
      );
      for (final object in [a, b, c, circle, q, tangent, touch]) {
        construction.add(object);
      }
      expect(ask(construction, {'t', 'k'}), isEmpty);

      construction.add(CircleCenter(id: 'o', circle: circle));
      final question = ask(construction, {'t', 'k'}).single;
      expect(question.spellings.map((s) => s.points.map((p) => p.id).join()), [
        'oxxq',
      ]);
    });

    test('a conic that looks round is not a circle, and is not asked', () {
      final construction = Construction();
      final points = [
        free('a', 4, 0),
        free('b', 0, 4),
        free('c', -4, 0),
        free('d', 0, -4),
        free('e', 3, 2.6457513110645907),
      ];
      final conic = FivePointConic(id: 'k', points: points);
      final o = CircleCenter(id: 'o', circle: conic);
      final q = free('q', 9, 5);
      final tangent = TangentLine(id: 't', point: q, circle: conic, branch: 0);
      final touch = IntersectionPoint(
        id: 'x',
        curve1: tangent,
        curve2: conic,
        branchIndex: 0,
      );
      for (final object in [...points, conic, o, q, tangent, touch]) {
        construction.add(object);
      }
      expect(ask(construction, {'t', 'k'}), isEmpty);
    });

    test('a secant asks about both crossings, and drops the "at"', () {
      final construction = Construction();
      final o = free('o', 0, 0);
      final rim = free('r', 3, 0);
      final circle = CircleCenterPoint(id: 'k', center: o, onCircle: rim);
      final s = free('s', 0, 9);
      // Through the rim point and a point above: the rim is one crossing
      // by construction, the other is drawn.
      final secant = LineThroughTwoPoints(id: 'l', point1: rim, point2: s);
      final other = IntersectionPoint(
        id: 'y',
        curve1: secant,
        curve2: circle,
        branchIndex: 1,
      );
      for (final object in [o, rim, circle, s, secant, other]) {
        construction.add(object);
      }
      final question = ask(construction, {'l', 'k'}).single;
      expect(question.reading, 'rs is tangent to the circle');
      expect(
        {for (final p in question.spellings) p.points.map((p) => p.id).join()},
        {'orrs', 'orry', 'oyyr', 'oyys'},
      );
    });

    test('a circle with anything but one line phrases nothing', () {
      final r = tangency();
      expect(ask(r.construction, {'k'}), isEmpty);
      expect(ask(r.construction, {'k', 'o'}), isEmpty);
      expect(ask(r.construction, {'k', 't', 'q'}), isEmpty);
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

    test('a length is named by its bounding pair only — a witness pair on '
        'a segment spells a different statement', () {
      // |AB| = |CD| is about A and B. With X a third point on segment AB,
      // cong(A,X,C,D) is a *different* statement, not a spelling of it —
      // answering the question proved on that fact would be unsound. The
      // direction questions still read every witness pair.
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
      final x = PointOnObject(id: 'x', curve: ab, parameter: 0.5);
      construction.add(x);

      final questions = ask(construction, {'ab', 'cd'});
      final cong = questions.singleWhere((q) => q.kind == PredicateKind.cong);
      final para = questions.singleWhere((q) => q.kind == PredicateKind.para);

      expect(cong.spellings.map((s) => s.toString()), ['cong(a, b, c, d)']);
      expect(para.spellings, hasLength(3));
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

  group('one line under two objects (Phase 164)', () {
    Construction load(String name) => decodeDocument(
      jsonDecode(File('test/fixtures/$name').readAsStringSync())
          as Map<String, dynamic>,
    ).construction;

    test('the tangent-chord fixture reads the same whichever tangent is '
        'clicked', () {
      // `c` and `d` are both the tangent at C; E was glued to `d`. A
      // canvas click lands on either by a last-bit margin, so the
      // question set must not depend on which.
      final construction = load('tangent-chord.rgl');
      final byName = {
        for (final o in construction.objects) o.attributes.name: o.id,
      };
      List<String> canon(Set<String> ids) => [
        for (final q in ask(construction, ids)) '${q.kind.name} ${q.canonical}',
      ];
      final viaD = canon({
        byName['b']!,
        byName['d']!,
        byName['e']!,
        byName['f']!,
      });
      final viaC = canon({
        byName['b']!,
        byName['c']!,
        byName['e']!,
        byName['f']!,
      });

      expect(viaD, hasLength(3), reason: 'the three angle readings');
      expect(viaC, viaD);
    });

    test('a segment beside a line through its ends borrows the line\'s '
        'points', () {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 0, 3);
      final d = free('d', 4, 3);
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final x = PointOnObject(id: 'x', curve: line, parameter: 8);
      final cd = Segment(id: 'cd', point1: c, point2: d);
      for (final object in [a, b, c, d, ab, line, x, cd]) {
        construction.add(object);
      }

      final para = ask(construction, {
        'ab',
        'cd',
      }).firstWhere((q) => q.kind == PredicateKind.para);
      final firstPairs = {
        for (final s in para.spellings)
          s.points.take(2).map((p) => p.id).join(),
      };
      expect(firstPairs, {'ab', 'ax', 'bx'});
    });
  });
}
