import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/question_draft.dart';
import 'package:regula/domain/prover/question_template.dart';
import 'package:regula/domain/prover/questions.dart';

void main() {
  FreePoint free(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  /// A rectangle A B D C with segments AB, CD, a line through C and D
  /// carrying a third point X, and the diagonals as segments.
  ({Construction construction, Map<String, GeoObject> o}) rig() {
    final construction = Construction();
    final a = free('a', 0, 0);
    final b = free('b', 4, 0);
    final c = free('c', 0, 3);
    final d = free('d', 4, 3);
    final ab = Segment(id: 'ab', point1: a, point2: b);
    final cd = Segment(id: 'cd', point1: c, point2: d);
    final l = LineThroughTwoPoints(id: 'l', point1: c, point2: d);
    final x = PointOnObject(id: 'x', curve: l, parameter: 2);
    final ad = Segment(id: 'ad', point1: a, point2: d);
    final bc = Segment(id: 'bc', point1: b, point2: c);
    final ac = Segment(id: 'ac', point1: a, point2: c);
    for (final object in [a, b, c, d, ab, cd, l, x, ad, bc, ac]) {
      construction.add(object);
    }
    return (
      construction: construction,
      o: {for (final object in construction.objects) object.id: object},
    );
  }

  QuestionDraft fill(QuestionTemplate template, List<GeoObject> taps) {
    var draft = QuestionDraft(template);
    for (final object in taps) {
      final next = draft.tap(object);
      if (identical(next, draft)) {
        fail('${object.id} refused at slot ${draft.current} of $draft');
      }
      draft = next;
    }
    return draft;
  }

  List<String> spelled(ProverQuestion? question) => [
    for (final s in question!.spellings) s.toString(),
  ];

  group('the templates', () {
    test('every kind in the vocabulary has a template that produces it', () {
      expect(
        {for (final t in QuestionTemplate.values) t.kind},
        containsAll(PredicateKind.values),
        reason: 'any question can be asked with no selection at all',
      );
    });

    test('slots flatten in group order and know their group', () {
      const t = QuestionTemplate.eqangle;
      expect(t.slots, hasLength(4));
      expect(t.slots.every((s) => s.type == SlotType.line), isTrue);
      expect([for (var i = 0; i < 4; i++) t.groupOf(i)], [0, 0, 1, 1]);
      expect(() => t.groupOf(4), throwsRangeError);
      expect(QuestionTemplate.midp.slots.map((s) => s.type), [
        SlotType.point,
        SlotType.segment,
      ]);
    });
  });

  group('a filled template is a ProverQuestion, spelled as the chips '
      'spell it', () {
    test('two carriers relate, reading every witness pair', () {
      final r = rig();
      final perp = fill(QuestionTemplate.perp, [r.o['ab']!, r.o['l']!]);

      expect(perp.isComplete, isTrue);
      expect(spelled(perp.question(r.construction.objects)), [
        'perp(a, b, c, d)',
        'perp(a, b, c, x)',
        'perp(a, b, d, x)',
      ]);
    });

    test('a line slot takes two points instead of a carrier', () {
      final r = rig();
      final draft = fill(QuestionTemplate.para, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
        r.o['d']!,
      ]);

      expect(draft.values[0], isA<PairValue>());
      expect(spelled(draft.question(r.construction.objects)), [
        'para(a, b, c, d)',
      ]);
    });

    test('a segment slot refuses a plain line, takes a segment or points', () {
      final r = rig();
      final empty = QuestionDraft(QuestionTemplate.cong);
      expect(identical(empty.tap(r.o['l']!), empty), isTrue);
      final cong = fill(QuestionTemplate.cong, [
        r.o['ab']!,
        r.o['c']!,
        r.o['d']!,
      ]);
      expect(spelled(cong.question(r.construction.objects)), [
        'cong(a, b, c, d)',
      ]);
    });

    test('three points are collinear; four are concyclic', () {
      final r = rig();
      final coll = fill(QuestionTemplate.coll, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
      ]);
      expect(spelled(coll.question(r.construction.objects)), ['coll(a, b, c)']);
      final cyclic = fill(QuestionTemplate.cyclic, [
        r.o['a']!,
        r.o['b']!,
        r.o['d']!,
        r.o['c']!,
      ]);
      expect(spelled(cyclic.question(r.construction.objects)), [
        'cyclic(a, b, d, c)',
      ]);
    });

    test('a midpoint is a point and a segment, and not one of its ends', () {
      final r = rig();
      final midp = fill(QuestionTemplate.midp, [r.o['x']!, r.o['cd']!]);
      expect(spelled(midp.question(r.construction.objects)), ['midp(x, c, d)']);
      final own = fill(QuestionTemplate.midp, [r.o['c']!, r.o['cd']!]);
      expect(own.isComplete, isTrue);
      expect(own.question(r.construction.objects), isNull);
    });

    test('equal angles are spelled in slot order — the order is the '
        'user\'s, not a chosen orientation', () {
      final r = rig();
      // ∠(AB, BC) = ∠(AD, DC): slots, not the chips' scoring.
      final draft = fill(QuestionTemplate.eqangle, [
        r.o['ab']!,
        r.o['bc']!,
        r.o['ad']!,
        r.o['cd']!,
      ]);
      final question = draft.question(r.construction.objects)!;
      expect(question.kind, PredicateKind.eqangle);
      expect(question.canonical.toString(), 'eqangle(a, b, b, c, a, d, c, d)');
      expect(
        question.spellings.map((s) => s.toString()),
        [
          'eqangle(a, b, b, c, a, d, c, d)',
          'eqangle(a, b, b, c, a, d, c, x)',
          'eqangle(a, b, b, c, a, d, d, x)',
        ],
        reason:
            'the segment cd is the line l by construction (Phase 164), so '
            'it borrows x — and every side reads every witness pair',
      );
    });

    test('equal ratios take four lengths and refuse 1 = 1', () {
      final r = rig();
      final ratio = fill(QuestionTemplate.eqratio, [
        r.o['ab']!,
        r.o['ac']!,
        r.o['cd']!,
        r.o['bc']!,
      ]);
      expect(spelled(ratio.question(r.construction.objects)), [
        'eqratio(a, b, a, c, c, d, b, c)',
      ]);
      final trivial = fill(QuestionTemplate.eqratio, [
        r.o['ab']!,
        r.o['ab']!,
        r.o['cd']!,
        r.o['cd']!,
      ]);
      expect(trivial.question(r.construction.objects), isNull);
    });

    test('three lines are concurrent, read as the chips read it', () {
      final r = rig();
      final draft = fill(QuestionTemplate.concurrent, [
        r.o['ac']!,
        r.o['ab']!,
        r.o['cd']!,
      ]);
      final question = draft.question(r.construction.objects)!;
      expect(question.kind, PredicateKind.coll);
      expect(question.reading, 'ac, ab and cd are concurrent');
      expect(question.canonical.toString(), 'coll(a, c, d)');
    });

    test('a line and a circle ask tangency', () {
      final construction = Construction();
      final o = free('o', 0, 0);
      final x = free('x', 5, 0);
      final k = CircleCenterPoint(id: 'k', center: o, onCircle: x);
      final q = free('q', 5, 3);
      final t = LineThroughTwoPoints(id: 't', point1: x, point2: q);
      for (final object in [o, x, k, q, t]) {
        construction.add(object);
      }
      final draft = fill(QuestionTemplate.tangent, [t, k]);
      final question = draft.question(construction.objects)!;
      expect(question.reading, 'xq is tangent to the circle at x');
      expect(question.canonical.toString(), 'perp(o, x, x, q)');
      expect(
        identical(QuestionDraft(QuestionTemplate.tangent).tap(k), null),
        isFalse,
      );
      expect(
        QuestionDraft(QuestionTemplate.tangent).tap(k).current,
        0,
        reason: 'a circle does not fit the line slot',
      );
    });

    test('a carrier with no named points completes the draft but names '
        'nothing', () {
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 0, 3);
      final d = free('d', 4, 3);
      final ab = Segment(id: 'ab', point1: a, point2: b);
      final l = LineThroughTwoPoints(id: 'l', point1: c, point2: d);
      final draft = fill(QuestionTemplate.perp, [ab, l]);
      // Only `ab`'s ends are in the objects handed over, so nothing the
      // construction knows names `l`. (A segment always names itself.)
      expect(draft.isComplete, isTrue);
      expect(draft.question([a, b, ab, l]), isNull);
      expect(draft.question([a, b, c, d, ab, l]), isNotNull);
    });
  });

  group('the correspondence is the slot', () {
    /// A scalene ABC and its medial triangle: D the midpoint of BC, E of
    /// CA, F of AB. DEF is similar to ABC with D ↔ A, E ↔ B, F ↔ C — a
    /// theorem, so it survives the filter's perturbation. The other
    /// correspondence, E ↔ A, D ↔ B, is a different statement and false.
    ({Construction construction, Map<String, GeoObject> o}) triangles() {
      final construction = Construction();
      final a = free('a', 0, 0);
      final b = free('b', 4, 0);
      final c = free('c', 1, 3);
      final d = Midpoint(id: 'd', point1: b, point2: c);
      final e = Midpoint(id: 'e', point1: c, point2: a);
      final f = Midpoint(id: 'f', point1: a, point2: b);
      final points = [a, b, c, d, e, f];
      for (final point in points) {
        construction.add(point);
      }
      return (construction: construction, o: {for (final p in points) p.id: p});
    }

    test('simtri asks the correspondence the rows state, and the wrong '
        'one is refuted before any run', () {
      final r = triangles();
      final right = fill(QuestionTemplate.simtri, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
        r.o['d']!,
        r.o['e']!,
        r.o['f']!,
      ]).question(r.construction.objects)!;
      final wrong = fill(QuestionTemplate.simtri, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
        r.o['e']!,
        r.o['d']!,
        r.o['f']!,
      ]).question(r.construction.objects)!;

      expect(right.canonical.toString(), 'simtri(a, b, c, d, e, f)');
      expect(wrong.canonical.toString(), 'simtri(a, b, c, e, d, f)');
      // Refute-before-OK: the filter alone, no prover.
      final filter = DiagramFilter.probe(r.construction.objects);
      expect(filter.holds(right.canonical), isTrue);
      expect(filter.holds(wrong.canonical), isFalse);
    });

    test('contri has the same shape', () {
      final r = triangles();
      final draft = fill(QuestionTemplate.contri, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
        r.o['d']!,
        r.o['e']!,
        r.o['f']!,
      ]);
      expect(
        draft.question(r.construction.objects)!.canonical.toString(),
        'contri(a, b, c, d, e, f)',
      );
    });

    test('a vertex twice in one triangle is refused; two triangles may '
        'share one', () {
      final r = triangles();
      final once = fill(QuestionTemplate.simtri, [r.o['a']!]);
      expect(identical(once.tap(r.o['a']!), once), isTrue);
      final shared = fill(QuestionTemplate.simtri, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
        r.o['a']!,
      ]);
      expect(shared.current, 4);
    });
  });

  group('the draft', () {
    test('advances slot by slot, and a complete draft ignores taps', () {
      final r = rig();
      var draft = QuestionDraft(QuestionTemplate.coll);
      expect(draft.current, 0);
      expect(draft.isComplete, isFalse);
      expect(draft.question(r.construction.objects), isNull);
      draft = draft.tap(r.o['a']!);
      expect(draft.current, 1);
      draft = draft.tap(r.o['b']!).tap(r.o['c']!);
      expect(draft.current, isNull);
      expect(identical(draft.tap(r.o['d']!), draft), isTrue);
    });

    test('a half pair holds its slot until the second point', () {
      final r = rig();
      final half = QuestionDraft(QuestionTemplate.perp).tap(r.o['a']!);
      expect(half.current, 0);
      expect(half.values[0], isA<PairValue>());
      expect((half.values[0]! as PairValue).isComplete, isFalse);
      expect(half.tap(r.o['b']!).current, 1);
      // A carrier tapped onto a half pair replaces it.
      final replaced = half.tap(r.o['cd']!);
      expect(replaced.values[0], isA<CarrierValue>());
      expect(replaced.current, 1);
    });

    test('put corrects one slot without clearing the rest; clear '
        'reopens one', () {
      final r = rig();
      final full = fill(QuestionTemplate.coll, [
        r.o['a']!,
        r.o['b']!,
        r.o['c']!,
      ]);
      final corrected = full.put(1, r.o['d']!)!;
      expect(spelled(corrected.question(r.construction.objects)), [
        'coll(a, d, c)',
      ]);
      expect(full.put(1, r.o['ab']!), isNull, reason: 'not a point');
      final reopened = corrected.clear(0);
      expect(reopened.current, 0);
      expect(reopened.values[1], isNotNull);
      expect(reopened.values[2], isNotNull);
      expect(reopened.tap(r.o['b']!).isComplete, isTrue);
    });

    test('a draft is immutable', () {
      final r = rig();
      final draft = QuestionDraft(QuestionTemplate.coll);
      draft.tap(r.o['a']!);
      expect(draft.current, 0);
      expect(() => draft.values[0] = null, throwsUnsupportedError);
    });
  });
}
