/// The corpus translator, pinned on a subset small enough to run in the
/// gate (Phase 167).
///
/// **Why a subset.** The whole corpus is 928 goals and two minutes of
/// prover time; `CLAUDE.md`'s CI gate is `flutter analyze && flutter
/// test && flutter test --platform chrome test/web`, and a two-minute
/// addition to it would turn a prover slowdown into a CI timeout rather
/// than a number. The full run lives in `benchmark/corpus_bench.dart`,
/// which is informational like every other benchmark. What runs here is
/// fifteen problems, inlined verbatim so the gate needs no checkout of
/// somebody else's repository.
///
/// **What is actually being tested is the translator**, not the prover.
/// The prover has its own suite. A translation can be wrong in a way no
/// verdict would reveal — build the parallelogram where the problem
/// meant the trapezoid, read a macro's arguments in the wrong order —
/// and the baseline would then measure the translator's mistakes and
/// call them the engine's limits. Three checks stand against that, and
/// the second is the one that matters:
///
/// 1. hand-checked problems translate to exactly the objects expected;
/// 2. **every hypothesis of every translated problem holds under
///    `DiagramFilter`**, which is a real assertion rather than a
///    tautology: `hypotheses()` reads the *parent ties*, so a statement
///    it emits must be true in any figure those ties produce, and one
///    that fails means the construction is not what the clause said;
/// 3. the goal holds in the figure built for it, for the same reason.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/fixed_angle_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/ratio_apollonius_circle.dart';
import 'package:regula/domain/construction/objects/scaled_compass_circle.dart';
import 'package:regula/domain/construction/objects/stated_radius_circle.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/fact.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/predicate.dart';
import 'package:regula/domain/prover/question_template.dart';

import 'newclid_problem.dart';
import 'newclid_translation.dart';

/// Fifteen problems, copied verbatim from Newclid's corpus.
///
/// Chosen to cover every shape the translator has: a point on one
/// curve and a point on two, each family of carrier, the direct kinds,
/// the two-branch circle crossings, a clause naming several points, a
/// goal of every arity, and the two configurations resampling exists
/// for.
const List<(String, String, String)> corpusSubset = [
  (
    'examples',
    'orthocenter',
    'a b c = triangle a b c; h = on_tline h b a c, on_tline h c a b '
        '? perp a h b c',
  ),
  (
    'examples',
    'orthocenter_aux',
    'a b c = triangle a b c; d = on_tline d b a c, on_tline d c a b; '
        'e = on_line e a c, on_line e b d ? perp a d b c',
  ),
  (
    'examples',
    'not_always_good',
    'a b c = triangle a b c; o = free o; m = on_circle m o b, on_line m a b; '
        'n = on_circle n o b, on_line n a c; r = angle_bisector r b a c, '
        'angle_bisector r m o n ? perp n m o r',
  ),
  (
    'minimal',
    'r03',
    'a = free a; b = free b; p = free p; q = on_circum q a b p '
        '? eqangle p a p b q a q b',
  ),
  (
    'minimal',
    'r22',
    'a = free a; b = free b; m = midpoint m a b; o = on_tline o m a b '
        '? cong o a o b',
  ),
  (
    'minimal',
    'r54',
    'a b = segment a b; m = on_line m a b, on_bline m a b ? midp m a b',
  ),
  (
    'minimal',
    'r91',
    'a b = segment a b; c = free a; d = on_pline d a b c, '
        'eqdistance d c a b ? eqangle c a c b b c b d',
  ),
  ('minimal', 'r56', 'a b = segment a b; m = midpoint m a b ? coll m a b'),
  (
    'minimal',
    'r19',
    'a b c = triangle a b c; d = on_dia d a c; m = midpoint m a c '
        '? cong a m d m',
  ),
  (
    'minimal',
    'r43',
    'a b c = triangle a b c; d = on_tline d b a c, on_tline d c a b '
        '? perp a d b c',
  ),
  (
    'examples',
    'incenter_a',
    'a b c = triangle a b c; i = incenter i a b c; '
        'f = foot f i b c ? perp i f b c',
  ),
  (
    'examples',
    'circumcentre',
    'a b c = triangle a b c; o = circle o a b c ? cong o a o b',
  ),
  (
    'examples',
    'midline',
    'a b c = triangle a b c; m = midpoint m a b; n = midpoint n a c '
        '? para m n b c',
  ),
  (
    'examples',
    'test_get_two_intersections',
    'a b = segment a b; c = eqdistance c a a b, eqdistance c b a b; '
        'd = eqdistance d a a b, eqdistance d b a b ? perp c d a b',
  ),
  (
    'examples',
    'reflection',
    'a b = segment a b; c = free c; d = mirror d c b ? coll c b d',
  ),
  (
    'examples',
    'centroid',
    'a b c = triangle a b c; m = midpoint m a b; n = midpoint n a c; '
        'k = midpoint k b c; p = intersection_ll p b n c m ? coll a p k',
  ),
];

void main() {
  NewclidProblem only(String name, String body, {String source = 'test'}) {
    final problems = parseNewclidBody(name, body, source: source);
    expect(problems, hasLength(1), reason: 'expected a single goal');
    return problems.single;
  }

  TranslatedProblem built(String name, String body) {
    final translation = translateNewclidProblem(only(name, body));
    expect(
      translation,
      isA<TranslatedProblem>(),
      reason: translation is UntranslatableProblem ? '$translation' : '',
    );
    return translation as TranslatedProblem;
  }

  group('the grammar', () {
    test(
      'a clause names its points on the left and its calls on the right',
      () {
        final problem = only(
          'two',
          'a b c = triangle a b c; h = on_tline h b a c, on_tline h c a b '
              '? perp a h b c',
        );
        expect(problem.clauses, hasLength(2));
        expect(problem.clauses[0].outputs, ['a', 'b', 'c']);
        expect(problem.clauses[0].calls.single.macro, 'triangle');
        expect(problem.clauses[1].outputs, ['h']);
        expect(problem.clauses[1].calls, hasLength(2));
        expect(problem.clauses[1].calls[1].arguments, ['h', 'c', 'a', 'b']);
        expect(problem.goal.predicate, 'perp');
        expect(problem.goal.arguments, ['a', 'h', 'b', 'c']);
      },
    );

    test('several goals after one "?" are several problems', () {
      final problems = parseNewclidBody(
        'pair',
        'a b = segment a b; m = midpoint m a b ? coll m a b; cong m a m b',
        source: 'test',
      );
      expect(problems.map((p) => p.name), ['pair', 'pair#2']);
      expect(problems[0].goal.predicate, 'coll');
      expect(problems[1].goal.predicate, 'cong');
      // One construction, read twice.
      expect(problems[0].clauses.length, problems[1].clauses.length);
    });

    test('the auxiliary section is parsed and kept out of the clauses', () {
      final problem = only(
        'aux',
        'a b = segment a b; m = midpoint m a b | q = midpoint q a m '
            '? coll m a b',
      );
      expect(problem.clauses, hasLength(2));
      expect(problem.auxiliary, hasLength(1));
      expect(problem.auxiliary.single.outputs, ['q']);
    });

    test('the auxiliary section is built only when a caller asks '
        '(Phase 174)', () {
      final problem = only(
        'aux',
        'a b = segment a b; m = midpoint m a b | q = midpoint q a m '
            '? coll m a b',
      );

      final without = translateNewclidProblem(problem) as TranslatedProblem;
      final with_ =
          translateNewclidProblem(problem, withAuxiliary: true)
              as TranslatedProblem;

      // Off by default, which is the benchmark's contract: handing the
      // prover the construction it was supposed to find would measure
      // the corpus's authors. The flag exists for the one question
      // where that is the point — what a perfect auxiliary search would
      // reach (Phase 174's ceiling), which came back zero.
      expect(without.points.keys, isNot(contains('q')));
      expect(with_.points.keys, contains('q'));
      expect(with_.points.length, without.points.length + 1);
      // And the extra point brings its own hypotheses, which is what
      // makes the ceiling measurement mean anything.
      expect(
        hypotheses(with_.construction.objects).length,
        greaterThan(hypotheses(without.construction.objects).length),
      );
    });

    test('a malformed body is reported, and costs only that body', () {
      final file = parseNewclidProblems(
        'good\na b = segment a b; m = midpoint m a b ? coll m a b\n'
        'bad\na b = segment a b ? coll a b ? coll b a\n'
        'good2\na b = segment a b; n = midpoint n a b ? coll n a b\n',
        source: 'test',
      );
      expect(file.problems.map((p) => p.name), ['good', 'good2']);
      expect(file.errors, hasLength(1));
      expect(file.errors.single.name, 'bad');
      expect(file.errors.single.reason, contains('"?"'));
    });

    test('a clause without an "=" is refused', () {
      expect(
        () =>
            parseNewclidBody('x', 'a b segment a b ? coll a b a', source: 't'),
        throwsA(isA<NewclidParseError>()),
      );
    });
  });

  group('a clause becomes the objects it says', () {
    test('one constraint is a glued point, two are a crossing', () {
      final problem = built(
        'orthocenter',
        'a b c = triangle a b c; h = on_tline h b a c, on_tline h c a b '
            '? perp a h b c',
      );
      expect(problem.points.keys, containsAll(<String>['a', 'b', 'c', 'h']));
      for (final name in ['a', 'b', 'c']) {
        expect(problem.points[name], isA<FreePoint>(), reason: name);
      }
      // Two `on_tline` calls on one point are two perpendiculars, and
      // the point is where they meet.
      final h = problem.points['h']!;
      expect(h, isA<IntersectionPoint>());
      expect(
        (h as IntersectionPoint).parents.whereType<PerpendicularLine>(),
        hasLength(2),
      );
    });

    test('a single constraint glues the point to that one carrier', () {
      final problem = built(
        'r03',
        'a = free a; b = free b; p = free p; q = on_circum q a b p '
            '? eqangle p a p b q a q b',
      );
      final q = problem.points['q']!;
      expect(q, isA<PointOnObject>());
      expect((q as PointOnObject).curve, isA<GeoCircle>());
    });

    test('the direct kinds are the kinds, not a crossing', () {
      final problem = built(
        'r22',
        'a = free a; b = free b; m = midpoint m a b; o = on_tline o m a b '
            '? cong o a o b',
      );
      expect(problem.points['m'], isA<Midpoint>());
    });

    test('angle_bisector is a bisector carrier, taken twice', () {
      final problem = built(
        'not_always_good',
        'a b c = triangle a b c; o = free o; '
            'm = on_circle m o b, on_line m a b; '
            'n = on_circle n o b, on_line n a c; '
            'r = angle_bisector r b a c, angle_bisector r m o n '
            '? perp n m o r',
      );
      final r = problem.points['r']!;
      expect(r, isA<IntersectionPoint>());
      expect(
        (r as IntersectionPoint).parents.whereType<AngleBisectorLine>(),
        hasLength(2),
      );
    });

    test('the same two curves, taken twice, give the two points', () {
      // The corpus problem that pins the branch rule, and the only
      // shape that pins it *hard*: `c` and `d` are the two crossings of
      // one pair of circles, so a translator that took branch 0 both
      // times would build one point twice and never produce a figure at
      // all. Measured on the whole corpus, the rule is worth 86 of the
      // 470 problems that build.
      final problem = built(
        'test_get_two_intersections',
        'a b = segment a b; c = eqdistance c a a b, eqdistance c b a b; '
            'd = eqdistance d a a b, eqdistance d b a b ? perp c d a b',
      );
      final c = problem.points['c']!;
      final d = problem.points['d']!;
      expect(c, isA<IntersectionPoint>());
      expect(d, isA<IntersectionPoint>());
      expect(
        (c as IntersectionPoint).branchIndex,
        isNot((d as IntersectionPoint).branchIndex),
      );
      expect(c.position!.distanceTo(d.position!), greaterThan(1));
    });

    test('a new point never lands on a point the figure already names', () {
      // `on_circle m o b` and `on_line m a b` meet at `b` and at one
      // other point. `m` is the other one — the rule that reading only
      // the two macros which *say* so got wrong.
      final problem = built(
        'not_always_good',
        'a b c = triangle a b c; o = free o; '
            'm = on_circle m o b, on_line m a b; '
            'n = on_circle n o b, on_line n a c; '
            'r = angle_bisector r b a c, angle_bisector r m o n '
            '? perp n m o r',
      );
      final b = problem.points['b']!.position!;
      for (final name in ['m', 'n']) {
        expect(
          problem.points[name]!.position!.distanceTo(b),
          greaterThan(1e-3),
          reason: '$name landed on b',
        );
      }
    });
  });

  group('what the translator refuses, it refuses by name', () {
    test('a macro it does not implement', () {
      final translation = translateNewclidProblem(
        only(
          'aline',
          'a b c = triangle a b c; '
              'd = on_aline d a b c a b ? coll a b d',
        ),
      );
      expect(translation, isA<UntranslatableProblem>());
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.unknownMacro,
      );
      expect(translation.detail, 'on_aline');
    });

    test('a goal predicate outside the vocabulary', () {
      final translation = translateNewclidProblem(
        only('clock', 'a b c = triangle a b c ? sameclock a b c a b c'),
      );
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.unsupportedGoal,
      );
    });

    test('a goal at an arity the vocabulary does not have', () {
      // `cyclic` over five points is a conjunction of facts, not one.
      final translation = translateNewclidProblem(
        only(
          'five',
          'a b c = triangle a b c; d = on_circum d a b c; '
              'e = on_circum e a b c ? cyclic a b c d e',
        ),
      );
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.unsupportedGoal,
      );
      expect(translation.detail, contains('conjunction'));
    });

    test('a line slot counts two points, not one', () {
      // The check that refused every `perp` goal in the corpus when it
      // compared the corpus's points against the template's *slots*.
      expect(tapsFor(QuestionTemplate.perp), 4);
      expect(tapsFor(QuestionTemplate.coll), 3);
      expect(tapsFor(QuestionTemplate.eqangle), 8);
      expect(tapsFor(QuestionTemplate.midp), 3);
    });
  });

  group('the constant-stating macros (Phase 182)', () {
    // Each macro is a point on a carrier that embodies its constant, so
    // the pin is threefold: the carrier kind exists in the construction,
    // `hypotheses()` states the constant, and the goal phrases. Proving
    // is the corpus benchmark's business, not this suite's (see the
    // file header).
    Matcher statesFact(Predicate expected) =>
        contains(predicate((Predicate p) => Fact.of(p) == Fact.of(expected)));

    test('s_angle: a point on the fixed-angle carrier through the '
        'vertex, stating aconst a b b x', () {
      final problem = built(
        'turned',
        'a b = segment a b; c = s_angle a b c 108o ? aconst a b b c 108o',
      );
      final points = problem.points;
      expect(
        problem.construction.objects.whereType<FixedAngleLine>(),
        hasLength(1),
      );
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.aconst, [
            points['a']!,
            points['b']!,
            points['b']!,
            points['c']!,
          ], value: Rational.fromInts(3, 5)),
        ),
      );
      expect(problem.question.canonical.kind, PredicateKind.aconst);
      expect(problem.question.canonical.value, Rational.fromInts(3, 5));
    });

    test('the aconst macro: the same carrier through its own vertex '
        'point', () {
      final problem = built(
        'turned_far',
        'a b = segment a b; c = free c; x = aconst a b c x 2pi/3 '
            '? aconst a b c x 2pi/3',
      );
      final points = problem.points;
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.aconst, [
            points['a']!,
            points['b']!,
            points['c']!,
            points['x']!,
          ], value: Rational.fromInts(2, 3)),
        ),
      );
    });

    test('lconst: a point on the stated-radius circle', () {
      final problem = built('measured', 'a = free a; b = lconst b a 4 '
          '? lconst a b 4');
      final points = problem.points;
      expect(
        problem.construction.objects.whereType<StatedRadiusCircle>(),
        hasLength(1),
      );
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.lconst, [
            points['b']!,
            points['a']!,
          ], value: Rational.fromInts(4, 1)),
        ),
      );
    });

    test('l2const states the square: a perfect square works, anything '
        'else refuses', () {
      // The corpus's one use, verbatim: |ba|² = 4 is |ba| = 2.
      final problem = built(
        'test_l2const',
        'a = free a; b = l2const b a 4 ? lconst a b 2',
      );
      final points = problem.points;
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.lconst, [
            points['b']!,
            points['a']!,
          ], value: Rational.fromInts(2, 1)),
        ),
      );
      // √2 is not rational, and lconst states a rational — refused
      // rather than rounded.
      final irrational = translateNewclidProblem(
        only('root_two', 'a = free a; b = l2const b a 2 ? lconst a b 2'),
      );
      expect(irrational, isA<UntranslatableProblem>());
    });

    test('rconst: the scaled compass circle, and 1/1 is the plain '
        'compass', () {
      final problem = built(
        'scaled',
        'a b = segment a b; c = free c; d = rconst a b c d 2/1 '
            '? rconst a b c d 2/1',
      );
      final points = problem.points;
      expect(
        problem.construction.objects.whereType<ScaledCompassCircle>(),
        hasLength(1),
      );
      // |ab|/|cd| = 2 and the emitted |dc|/|ab| = ½ are one fact.
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.rconst, [
            points['a']!,
            points['b']!,
            points['c']!,
            points['d']!,
          ], value: Rational.fromInts(2, 1)),
        ),
      );

      final unit = built(
        'unit_ratio',
        'a b = segment a b; c = free c; d = rconst a b c d 1/1 '
            '? cong a b c d',
      );
      expect(
        unit.construction.objects.whereType<ScaledCompassCircle>(),
        isEmpty,
      );
      expect(
        unit.construction.objects.whereType<CompassCircle>(),
        hasLength(1),
      );
    });

    test('rconst2: the stated-ratio Apollonius circle, and 1/1 is the '
        'perpendicular bisector', () {
      final problem = built(
        'apollo',
        'a b = segment a b; f = rconst2 f a b 1/2 ? rconst f a f b 1/2',
      );
      final points = problem.points;
      expect(
        problem.construction.objects.whereType<RatioApolloniusCircle>(),
        hasLength(1),
      );
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.rconst, [
            points['f']!,
            points['a']!,
            points['f']!,
            points['b']!,
          ], value: Rational.fromInts(1, 2)),
        ),
      );

      final unit = built(
        'equidistant',
        'a b = segment a b; f = rconst2 f a b 1/1 ? cong f a f b',
      );
      expect(
        unit.construction.objects.whereType<RatioApolloniusCircle>(),
        isEmpty,
      );
      expect(
        hypotheses(unit.construction.objects),
        statesFact(
          Predicate(PredicateKind.cong, [
            unit.points['f']!,
            unit.points['a']!,
            unit.points['f']!,
            unit.points['b']!,
          ]),
        ),
      );
    });

    test('triangle12: two free points and the third at twice the base', () {
      // A corpus problem verbatim (examples.txt).
      final problem = built(
        'triangle12',
        'a b c = triangle12 a b c; m = midpoint m a c ? cong a m a b',
      );
      final points = problem.points;
      expect(
        hypotheses(problem.construction.objects),
        statesFact(
          Predicate(PredicateKind.rconst, [
            points['a']!,
            points['b']!,
            points['a']!,
            points['c']!,
          ], value: Rational.fromInts(1, 2)),
        ),
      );
      expect(problem.question.canonical.kind, PredicateKind.cong);
    });
  });

  group('a constant goal the vocabulary already states is respelled', () {
    // Phase 177: `aconst` at π/2 *is* perp and `rconst` at 1 *is* cong —
    // biconditionals, not approximations — and refusing them as
    // `unsupportedGoal` misreported three corpus goals the prover
    // proves. A genuinely constant value phrases with its value since
    // Phases 181–182; the plainer spelling still wins where one exists.
    const square =
        'a b = segment a b; c = on_tline c b a b, eqdistance c b a b; '
        'd = on_circum d a b c, eqdistance d c a b';

    test('aconst at a right angle is perp', () {
      final problem = built('square_turn', '$square ? aconst d a a b 1pi/2');
      expect(problem.question.canonical.kind, PredicateKind.perp);
    });

    test('aconst at 90 degrees is the same right angle', () {
      final problem = built('square_turn_o', '$square ? aconst d a a b 90o');
      expect(problem.question.canonical.kind, PredicateKind.perp);
    });

    test('aconst at zero is para', () {
      // Opposite sides of the square: a zero angle between two named
      // lines is parallelism wearing the constant spelling.
      final problem = built('square_para', '$square ? aconst d c a b 0pi/1');
      expect(problem.question.canonical.kind, PredicateKind.para);
    });

    test('rconst at one is cong', () {
      final problem = built(
        'halves',
        'a b = segment a b; m = midpoint m a b ? rconst a m b m 1/1',
      );
      expect(problem.question.canonical.kind, PredicateKind.cong);
    });
  });

  group('a genuinely constant angle, ratio or length is phrased with '
      'its value', () {
    // Phases 181–182: `rconst`/`lconst`/`aconst` goals stop refusing —
    // the fact kinds exist, so the goal is one value-carrying spelling
    // over the corpus's own points (a length is named by the pair that
    // bounds it), resolved through the matching closure's entailment.
    test('aconst at a real angle carries the residue', () {
      // The eq_triangle threefold-root problem of Phase 177: it now
      // phrases and builds; proving it stays a named incompleteness
      // (the closure pins 3·Δθ, and mod-1 algebra cannot divide).
      final problem = built(
        'sixty',
        'b c = segment b c; a = eq_triangle a b c ? aconst a b a c 1pi/3',
      );
      final canonical = problem.question.canonical;
      expect(canonical.kind, PredicateKind.aconst);
      expect(canonical.value, Rational.fromInts(1, 3));
    });

    test('an aconst value in a ratio spelling is not an angle', () {
      final translation = translateNewclidProblem(
        only(
          'unitless',
          'b c = segment b c; a = eq_triangle a b c ? aconst a b a c 1/3',
        ),
      );
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.unsupportedGoal,
      );
      expect(translation.detail, contains('angle value'));
    });

    test('a false stated angle is the figure\'s refusal', () {
      final translation = translateNewclidProblem(
        only(
          'wrong_angle',
          'b c = segment b c; a = eq_triangle a b c ? aconst a b a c 1pi/5',
        ),
      );
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.goalFalseInFigure,
      );
    });

    test('rconst at a real ratio carries the value', () {
      final problem = built(
        'halved',
        'a b = segment a b; m = midpoint m a b ? rconst a b a m 2/1',
      );
      final canonical = problem.question.canonical;
      expect(canonical.kind, PredicateKind.rconst);
      expect(canonical.value, Rational.fromInts(2, 1));
      expect(problem.question.spellings, hasLength(1));
    });

    test('an lconst goal reaches the filter, which answers for the '
        'figure', () {
      // No supported macro can state an absolute length yet (Phase
      // 182's `lconst` construction), so a generic segment refuses as
      // false-in-figure — the parse and the phrasing worked, and the
      // refusal is the figure's, not the vocabulary's.
      final translation = translateNewclidProblem(
        only('measured', 'a b = segment a b ? lconst a b 2'),
      );
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.goalFalseInFigure,
      );
    });

    test('a malformed or non-positive value refuses by name', () {
      final zero = translateNewclidProblem(
        only(
          'zeroed',
          'a b = segment a b; m = midpoint m a b ? rconst a b a m 0/1',
        ),
      );
      expect(
        (zero as UntranslatableProblem).reason,
        UntranslatableReason.unsupportedGoal,
      );
      expect(zero.detail, contains('positive rational'));
      final garbled = translateNewclidProblem(
        only(
          'garbled',
          'a b = segment a b; m = midpoint m a b ? rconst a b a m 2pi/3',
        ),
      );
      expect(
        (garbled as UntranslatableProblem).reason,
        UntranslatableReason.unsupportedGoal,
      );
    });

    test('a false stated ratio is the figure\'s refusal', () {
      final translation = translateNewclidProblem(
        only(
          'wrong_ratio',
          'a b = segment a b; m = midpoint m a b ? rconst a b a m 3/1',
        ),
      );
      expect(
        (translation as UntranslatableProblem).reason,
        UntranslatableReason.goalFalseInFigure,
      );
    });
  });

  group('the subset translates, and the figures are honest', () {
    for (final (source, name, body) in corpusSubset) {
      test('$source:$name', () {
        final problem = built(name, body);
        final objects = problem.construction.objects.toList();
        final filter = DiagramFilter.probe(objects);

        // The assertion that makes the corpus usable as a baseline:
        // every statement read off the parent ties is true in the
        // figure those ties produced.
        final given = hypotheses(objects);
        expect(given, isNotEmpty, reason: 'a figure that says nothing');
        for (final hypothesis in given) {
          expect(
            filter.holds(hypothesis),
            isTrue,
            reason: '$hypothesis is false in the figure built for $name',
          );
        }

        // And the goal itself, which is what Newclid resamples for.
        expect(
          filter.holds(problem.question.canonical),
          isTrue,
          reason: 'the goal of $name is false in its own figure',
        );

        // Every point the DSL named exists and is distinct.
        final positions = problem.points.values.map((p) => p.position).toList();
        expect(positions, everyElement(isNotNull));
      });
    }
  });
}
