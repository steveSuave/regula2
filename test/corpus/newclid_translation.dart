/// A parsed Newclid problem, built as a regula2 [Construction] (Phase 167).
///
/// The mapping is not guessed from macro names: every construction's
/// meaning was read off `newclid/src/newclid/jgex/constructions/*.py`,
/// where each `JGEXDefinition` states the predicates it asserts. So
/// `on_tline x a b c` is `perp x a b c` — *x on the perpendicular to
/// `bc` through `a`* — and `eqdistance x a b c` is `cong x a b c`, x on
/// the circle about `a` of radius `|bc|`. Two of them read better than
/// their names suggest and are worth naming here: `lc_tangent x a o` is
/// only `perp a x a o`, so it needs no `TangentLine` at all, and both
/// circle intersections carry a point already **on** both curves in
/// their own arguments (`intersection_lc x a o b` passes `b`;
/// `intersection_cc x o w a` passes `a`), which makes the branch choice
/// determined rather than a guess.
///
/// **The shape of a clause is the whole translation.** A point
/// constrained by one call lies on one curve and is a [PointOnObject];
/// constrained by two it is the crossing and is an [IntersectionPoint].
/// Everything else is a named kind that exists already — `foot` is
/// `ProjectionPoint`, `circle` is `Circumcenter`, `mirror` is
/// `CentralReflectionPoint`. Nothing here adds a `GeoObject`.
///
/// **Refusals are typed and counted, never silent.** A translator that
/// quietly dropped the problems it could not read would make every
/// number taken off this corpus meaningless — the baseline would measure
/// the translator's taste. So an unsupported macro, an out-of-vocabulary
/// goal and a figure that comes out degenerate are three separate
/// [UntranslatableReason]s, and the benchmark reports each.
library;

import 'dart:math' as math;

import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/incenter.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/diagram_filter.dart';
import 'package:regula/domain/prover/hypotheses.dart';
import 'package:regula/domain/prover/question_draft.dart';
import 'package:regula/domain/prover/question_template.dart';
import 'package:regula/domain/prover/questions.dart';

import 'newclid_problem.dart';

/// Why a problem did not become a construction.
enum UntranslatableReason {
  /// A construction macro this translator does not implement.
  unknownMacro,

  /// A goal predicate outside regula2's ten, or at an arity it does not
  /// have (`cyclic` over five points is a conjunction, not a fact).
  unsupportedGoal,

  /// The clause shape is not one point on one or two curves — three
  /// simultaneous constraints, or a macro used with the wrong arity.
  unsupportedClause,

  /// Every sampled figure came out degenerate: a point undefined, two
  /// points coincident, or a hypothesis of the problem numerically false
  /// in the figure built for it.
  degenerate,

  /// The figure was generic and the goal was *false* in it.
  ///
  /// This is the translator's own tripwire rather than a fact about the
  /// corpus. Newclid rejects a problem whose goal is numerically false
  /// at setup, so a problem reaching this state almost always means the
  /// construction was built wrong — the wrong branch taken, or a macro's
  /// arguments read in the wrong order.
  goalFalseInFigure,
}

/// The result of translating one problem.
sealed class NewclidTranslation {
  const NewclidTranslation(this.problem);

  final NewclidProblem problem;
}

/// A problem that became a construction and a question.
class TranslatedProblem extends NewclidTranslation {
  const TranslatedProblem(
    super.problem, {
    required this.construction,
    required this.question,
    required this.points,
    required this.attempts,
  });

  final Construction construction;

  /// The goal, spelled the way the app's question builder spells it —
  /// through [QuestionDraft], so every witness pair on a named carrier
  /// is asked, not only the pair Newclid happened to write.
  final ProverQuestion question;

  /// The DSL's names, in construction order.
  final Map<String, GeoPoint> points;

  /// How many figures were sampled before one came out generic.
  final int attempts;
}

/// A problem that did not.
class UntranslatableProblem extends NewclidTranslation {
  const UntranslatableProblem(super.problem, this.reason, this.detail);

  final UntranslatableReason reason;
  final String detail;

  @override
  String toString() => '$problem: ${reason.name} ($detail)';
}

/// Goal predicate name to the template that phrases it.
///
/// The argument orders line up slot for slot with no special casing,
/// which is not luck: both vocabularies name a line by two points and an
/// angle by two lines, in that order. `perp a h b c` fills the two line
/// slots `(a,h)` and `(b,c)`; `midp m a b` fills a point slot and a
/// segment slot; `eqangle` fills four line slots.
const Map<String, QuestionTemplate> goalTemplates = {
  'coll': QuestionTemplate.coll,
  'para': QuestionTemplate.para,
  'perp': QuestionTemplate.perp,
  'cong': QuestionTemplate.cong,
  'cyclic': QuestionTemplate.cyclic,
  'eqangle': QuestionTemplate.eqangle,
  'eqratio': QuestionTemplate.eqratio,
  'midp': QuestionTemplate.midp,
  'simtri': QuestionTemplate.simtri,
  'contri': QuestionTemplate.contri,
};

/// How many points fill [template] — one per point slot and **two** per
/// line or segment slot, since a line is named by a pair.
///
/// Not `template.slots.length`: that counts slots, and the corpus counts
/// taps. The two agree only for the all-point templates, which is why
/// getting it wrong refused every `perp` goal in the corpus and none of
/// the `coll` ones.
int tapsFor(QuestionTemplate template) => template.slots.fold(
  0,
  (sum, slot) => sum + (slot.type == SlotType.point ? 1 : 2),
);

/// How many figures to sample before giving up on a problem.
///
/// Newclid resamples the whole problem up to **100** times until the
/// goals hold numerically (`problem_builder.py`'s
/// `max_attempts_to_satisfy_goals_numerically`), on top of five retries
/// per degenerate clause. Twenty-five is the same policy at a fraction
/// of the cost: a sample is one figure plus one filter probe, which is
/// three orders below the prover run it feeds.
const int defaultSampleAttempts = 25;

/// Builds [problem] as a construction, resampling the free positions
/// until the figure is generic or [attempts] is spent.
NewclidTranslation translateNewclidProblem(
  NewclidProblem problem, {
  int seed = 0,
  int attempts = defaultSampleAttempts,
}) {
  var lastDegeneracy = 'no attempt ran';
  var lastReason = UntranslatableReason.degenerate;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    final builder = _Builder(problem, math.Random(seed + attempt * 7919));
    final failure = builder.run();
    if (failure != null) {
      // A macro or goal this translator cannot *read* fails the same way
      // on every sample, so there is nothing to retry. A figure that
      // came out degenerate, or on which the goal is false, is a
      // property of this sample and not of the problem — and resampling
      // it is the reference implementation's own policy, not a way of
      // choosing the answer: Newclid rebuilds the whole problem until
      // its goals hold numerically and refuses it after a hundred
      // failures. A clause like `d = on_pline d a b c, eqdistance d c a
      // b` meets its two curves at the isosceles trapezoid *and* at the
      // parallelogram, and nothing in a point-tuple vocabulary without
      // `sameside` says which one the problem meant.
      if (!_resamplable.contains(failure.reason)) return failure;
      lastDegeneracy = failure.detail;
      lastReason = failure.reason;
      continue;
    }
    return TranslatedProblem(
      problem,
      construction: builder.construction,
      question: builder.question!,
      points: builder.points,
      attempts: attempt,
    );
  }
  return UntranslatableProblem(
    problem,
    lastReason,
    'no usable figure in $attempts samples; last: $lastDegeneracy',
  );
}

/// The two refusals that are about the *sample* rather than the problem.
const Set<UntranslatableReason> _resamplable = {
  UntranslatableReason.degenerate,
  UntranslatableReason.goalFalseInFigure,
};

class _Builder {
  _Builder(this.problem, this.random);

  final NewclidProblem problem;
  final math.Random random;

  final Construction construction = Construction();
  final Map<String, GeoPoint> points = {};
  final Map<String, GeoObject> _carriers = {};
  ProverQuestion? question;
  var _nextId = 0;

  /// Half-width of the box free points are sampled in, and the scale a
  /// glued point's parameter is sampled against.
  static const double _scale = 300;

  String _id(String prefix) => '$prefix${_nextId++}';

  UntranslatableProblem? _fail(UntranslatableReason reason, String detail) =>
      UntranslatableProblem(problem, reason, detail);

  UntranslatableProblem? run() {
    for (final clause in problem.clauses) {
      final failure = _clause(clause);
      if (failure != null) return failure;
    }
    final degenerate = _checkGeneric();
    if (degenerate != null) {
      return _fail(UntranslatableReason.degenerate, degenerate);
    }
    return _goal();
  }

  // ---------------------------------------------------------------- points

  GeoPoint _free(String name) {
    final point = FreePoint(
      id: _id('p'),
      position: Vec2(
        (random.nextDouble() * 2 - 1) * _scale,
        (random.nextDouble() * 2 - 1) * _scale,
      ),
      attributes: ObjectAttributes(name: name),
    );
    construction.add(point);
    return points[name] = point;
  }

  GeoPoint? _known(String name) => points[name];

  /// The line through two named points, built once and reused — so two
  /// clauses that mention `line ab` name one carrier, which is what
  /// makes the incidence closure see them as one.
  GeoObject? _lineThrough(String a, String b) {
    final key = 'line:${_orderKey(a, b)}';
    final held = _carriers[key];
    if (held != null) return held;
    final pa = _known(a);
    final pb = _known(b);
    if (pa == null || pb == null) return null;
    final line = LineThroughTwoPoints(id: _id('l'), point1: pa, point2: pb);
    construction.add(line);
    return _carriers[key] = line;
  }

  /// The circle about [centre] through [through].
  GeoObject? _circleAbout(String centre, String through) {
    final key = 'circ:$centre:$through';
    final held = _carriers[key];
    if (held != null) return held;
    final o = _known(centre);
    final a = _known(through);
    if (o == null || a == null) return null;
    final circle = CompassCircle(
      id: _id('c'),
      center: o,
      radiusPoint1: o,
      radiusPoint2: a,
    );
    construction.add(circle);
    return _carriers[key] = circle;
  }

  static String _orderKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  double _parameterOn(GeoObject curve) => curve is GeoCircle
      ? random.nextDouble() * 2 * math.pi
      : (random.nextDouble() * 2 - 1) * _scale;

  // --------------------------------------------------------------- clauses

  /// Macros that introduce unconstrained points: the name maps to how
  /// many the clause names.
  static const Map<String, int> _freeShapes = {
    'free': 1,
    'segment': 2,
    'triangle': 3,
    'quadrangle': 4,
    'pentagon': 5,
  };

  /// Macros that name one point directly, as a kind that already exists.
  static const Set<String> _directMacros = {
    'midpoint',
    'foot',
    'circle',
    'circumcenter',
    'incenter',
    'orthocenter',
    'mirror',
    'reflect',
    'parallelogram',
  };

  UntranslatableProblem? _clause(NewclidClause clause) {
    if (clause.calls.length == 1) {
      final call = clause.calls.single;
      final freeCount = _freeShapes[call.macro];
      if (freeCount != null) {
        if (clause.outputs.length != freeCount) {
          return _fail(
            UntranslatableReason.unsupportedClause,
            '${call.macro} names ${clause.outputs.length} points, '
            'expected $freeCount',
          );
        }
        for (final name in clause.outputs) {
          _free(name);
        }
        return null;
      }
      final shaped = _shapedClause(clause, call);
      if (shaped != null) {
        return shaped.failure;
      }
    }

    if (clause.outputs.length != 1) {
      return _fail(
        UntranslatableReason.unsupportedClause,
        'a clause naming ${clause.outputs.length} points must be a shape '
        'macro, got $clause',
      );
    }
    final name = clause.outputs.single;

    if (clause.calls.length == 1 &&
        _directMacros.contains(clause.calls.single.macro)) {
      return _direct(name, clause.calls.single);
    }

    final constraints = <_Constraint>[];
    for (final call in clause.calls) {
      if (_directMacros.contains(call.macro) ||
          _freeShapes.containsKey(call.macro)) {
        return _fail(
          UntranslatableReason.unsupportedClause,
          '${call.macro} cannot be combined with another constraint',
        );
      }
      final found = _constraints(call);
      if (found == null) {
        return _fail(UntranslatableReason.unknownMacro, call.macro);
      }
      constraints.addAll(found);
    }
    if (constraints.isEmpty) {
      return _fail(UntranslatableReason.unsupportedClause, 'no constraint');
    }
    if (constraints.length == 1) {
      final curve = constraints.single.curve;
      final glued = PointOnObject(
        id: _id('p'),
        curve: curve,
        parameter: _parameterOn(curve),
        attributes: ObjectAttributes(name: name),
      );
      construction.add(glued);
      points[name] = glued;
      return null;
    }
    if (constraints.length > 2) {
      return _fail(
        UntranslatableReason.unsupportedClause,
        '${constraints.length} simultaneous constraints on $name',
      );
    }
    return _cross(name, constraints[0], constraints[1]);
  }

  /// The crossing of two curves, on the branch the clause means.
  ///
  /// **A clause introduces a new point, so a branch sitting on a point
  /// that already has a name is the wrong branch.** That is the whole
  /// rule, and it is more general than the two macros that state it:
  /// `intersection_lc x a o b` passes `b`, which is on the line and on
  /// the circle, and `intersection_cc x o w a` passes `a` — but
  /// `m = on_circle m o b, on_line m a b` says exactly the same thing
  /// without naming it, and reading only the explicit form got the
  /// wrong point on the corpus problem called `not_always_good`. So
  /// every already-named point is excluded, and the macro's own shared
  /// argument survives as a tie-break for the rare figure where two
  /// branches are equally new.
  ///
  /// Where nothing is excluded — two lines cross once; `eq_triangle` may
  /// take either apex — branch 0 is canonical and either answer is a
  /// correct instance of the problem.
  UntranslatableProblem? _cross(String name, _Constraint a, _Constraint b) {
    final shared = a.shared ?? b.shared;
    IntersectionPoint? best;
    var bestDistance = -1.0;
    var met = false;
    var allTaken = true;
    for (var branch = 0; branch < IntersectionPoint.maxBranchCount; branch++) {
      final IntersectionPoint candidate;
      try {
        candidate = IntersectionPoint(
          id: _id('p'),
          curve1: a.curve,
          curve2: b.curve,
          branchIndex: branch,
          attributes: ObjectAttributes(name: name),
        );
      } on ArgumentError {
        break;
      }
      final here = candidate.position;
      if (here == null) continue;
      met = true;
      if (_alreadyNamed(here)) continue;
      allTaken = false;
      final away = shared?.position;
      final distance = away == null ? 0.0 : here.distanceTo(away);
      if (best == null || distance > bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
      if (away == null) break;
    }
    if (best == null) {
      return _fail(
        UntranslatableReason.degenerate,
        met && allTaken
            ? 'every branch for $name is a point the figure already names'
            : 'the two curves for $name do not meet in this figure',
      );
    }
    construction.add(best);
    points[name] = best;
    return null;
  }

  /// Whether [where] is one of the points the figure has already named.
  bool _alreadyNamed(Vec2 where) {
    for (final point in points.values) {
      final at = point.position;
      if (at != null && at.distanceTo(where) <= _coincident) return true;
    }
    return false;
  }

  UntranslatableProblem? _direct(String name, NewclidCall call) {
    final args = call.arguments;
    GeoPoint? at(int i) => i < args.length ? _known(args[i]) : null;

    UntranslatableProblem? missing() => _fail(
      UntranslatableReason.unsupportedClause,
      '${call.macro} names a point that does not exist yet: $call',
    );

    switch (call.macro) {
      case 'midpoint':
        final a = at(1);
        final b = at(2);
        if (a == null || b == null) return missing();
        return _place(
          name,
          Midpoint(
            id: _id('p'),
            point1: a,
            point2: b,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'foot':
        // foot x a b c: perp x a b c, coll x b c — the foot of the
        // perpendicular from a to line bc.
        final a = at(1);
        final line = _lineThrough(args[2], args[3]);
        if (a == null || line is! GeoLine) return missing();
        return _place(
          name,
          ProjectionPoint(
            id: _id('p'),
            point: a,
            line: line,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'circle':
      case 'circumcenter':
        // circle x a b c: x is the *centre* of the circle through a b c.
        final a = at(1);
        final b = at(2);
        final c = at(3);
        if (a == null || b == null || c == null) return missing();
        return _place(
          name,
          Circumcenter(
            id: _id('p'),
            vertex1: a,
            vertex2: b,
            vertex3: c,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'incenter':
        final a = at(1);
        final b = at(2);
        final c = at(3);
        if (a == null || b == null || c == null) return missing();
        return _place(
          name,
          Incenter(
            id: _id('p'),
            vertex1: a,
            vertex2: b,
            vertex3: c,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'orthocenter':
        final a = at(1);
        final b = at(2);
        final c = at(3);
        if (a == null || b == null || c == null) return missing();
        return _place(
          name,
          Orthocenter(
            id: _id('p'),
            vertex1: a,
            vertex2: b,
            vertex3: c,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'mirror':
        // mirror x a b: coll x a b, cong b a b x — a reflected through b.
        final a = at(1);
        final b = at(2);
        if (a == null || b == null) return missing();
        return _place(
          name,
          CentralReflectionPoint(
            id: _id('p'),
            point: a,
            center: b,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'reflect':
        // reflect x a b c: a reflected in line bc.
        final a = at(1);
        final line = _lineThrough(args[2], args[3]);
        if (a == null || line is! GeoLine) return missing();
        return _place(
          name,
          ReflectedPoint(
            id: _id('p'),
            point: a,
            mirror: line,
            attributes: ObjectAttributes(name: name),
          ),
        );
      case 'parallelogram':
        // parallelogram x a b c: para a b c x, para a x b c — so
        // x = c + (a - b), which is c translated along b -> a.
        final a = at(1);
        final b = at(2);
        final c = at(3);
        if (a == null || b == null || c == null) return missing();
        return _place(
          name,
          TranslatedPoint(
            id: _id('p'),
            point: c,
            vectorFrom: b,
            vectorTo: a,
            attributes: ObjectAttributes(name: name),
          ),
        );
      default:
        return _fail(UntranslatableReason.unknownMacro, call.macro);
    }
  }

  UntranslatableProblem? _place(String name, GeoPoint point) {
    construction.add(point);
    points[name] = point;
    return null;
  }

  // ------------------------------------------------------------- carriers

  /// The curves one call constrains its point to.
  ///
  /// Null for a macro this translator does not implement — which the
  /// caller reports as [UntranslatableReason.unknownMacro] rather than
  /// skipping, so the corpus's unread tail stays visible.
  List<_Constraint>? _constraints(NewclidCall call) {
    final args = call.arguments;
    GeoObject? line(int i, int j) => i < args.length && j < args.length
        ? _lineThrough(args[i], args[j])
        : null;
    GeoObject? circle(int centre, int through) =>
        centre < args.length && through < args.length
        ? _circleAbout(args[centre], args[through])
        : null;

    List<_Constraint>? on(GeoObject? curve, {GeoPoint? shared}) =>
        curve == null ? null : [_Constraint(curve, shared)];
    List<_Constraint>? both(GeoObject? a, GeoObject? b, {GeoPoint? shared}) =>
        a == null || b == null
        ? null
        : [_Constraint(a, shared), _Constraint(b, null)];

    GeoObject? parallelThrough(int through, int a, int b) {
      final point = _known(args[through]);
      final reference = line(a, b);
      if (point == null || reference is! GeoLine) return null;
      return _named('para:${args[through]}:${_orderKey(args[a], args[b])}', () {
        final built = ParallelLine(
          id: _id('l'),
          through: point,
          reference: reference,
        );
        construction.add(built);
        return built;
      });
    }

    GeoObject? perpendicularThrough(int through, int a, int b) {
      final point = _known(args[through]);
      final reference = line(a, b);
      if (point == null || reference is! GeoLine) return null;
      return _named('perp:${args[through]}:${_orderKey(args[a], args[b])}', () {
        final built = PerpendicularLine(
          id: _id('l'),
          through: point,
          reference: reference,
        );
        construction.add(built);
        return built;
      });
    }

    switch (call.macro) {
      // x on line ab.
      case 'on_line':
        return on(line(1, 2));
      // x with line xa parallel to line bc: the parallel through a.
      case 'on_pline':
      case 'on_pline0':
        return on(parallelThrough(1, 2, 3));
      // x with line xa perpendicular to line bc: the perpendicular
      // through a.
      case 'on_tline':
        return on(perpendicularThrough(1, 2, 3));
      // lc_tangent x a o: perp a x a o — the tangent at a is just the
      // perpendicular to the radius oa through a. No circle needed.
      case 'lc_tangent':
        return on(perpendicularThrough(1, 1, 2));
      // x on the perpendicular bisector of ab.
      case 'on_bline':
        final a = _known(args[1]);
        final b = _known(args[2]);
        if (a == null || b == null) return null;
        return on(
          _named('bline:${_orderKey(args[1], args[2])}', () {
            final built = PerpendicularBisectorLine(
              id: _id('l'),
              point1: a,
              point2: b,
            );
            construction.add(built);
            return built;
          }),
        );
      // x on the bisector of angle abc.
      case 'angle_bisector':
        final a = _known(args[1]);
        final b = _known(args[2]);
        final c = _known(args[3]);
        if (a == null || b == null || c == null) return null;
        return on(
          _named('bisect:${args[1]}:${args[2]}:${args[3]}', () {
            final built = AngleBisectorLine(
              id: _id('l'),
              arm1: a,
              vertex: b,
              arm2: c,
            );
            construction.add(built);
            return built;
          }),
        );
      // x on the circle about o through a.
      case 'on_circle':
        return on(circle(1, 2));
      // eqdistance x a b c: cong x a b c — the circle about a of radius
      // |bc|, which is a compass circle rather than one through a point.
      case 'on_rcircle':
      case 'eqdistance':
        final centre = _known(args[1]);
        final from = _known(args[2]);
        final to = _known(args[3]);
        if (centre == null || from == null || to == null) return null;
        return on(
          _named('compass:${args[1]}:${args[2]}:${args[3]}', () {
            final built = CompassCircle(
              id: _id('c'),
              center: centre,
              radiusPoint1: from,
              radiusPoint2: to,
            );
            construction.add(built);
            return built;
          }),
        );
      // x seeing ab at a right angle: the circle on ab as diameter.
      case 'on_dia':
        final a = _known(args[1]);
        final b = _known(args[2]);
        if (a == null || b == null) return null;
        return on(
          _named('dia:${_orderKey(args[1], args[2])}', () {
            final built = DiameterCircle(id: _id('c'), point1: a, point2: b);
            construction.add(built);
            return built;
          }),
        );
      // x on the circle through a, b, c.
      case 'on_circum':
        final a = _known(args[1]);
        final b = _known(args[2]);
        final c = _known(args[3]);
        if (a == null || b == null || c == null) return null;
        return on(
          _named('circum:${args[1]}:${args[2]}:${args[3]}', () {
            final built = ThreePointCircle(
              id: _id('c'),
              point1: a,
              point2: b,
              point3: c,
            );
            construction.add(built);
            return built;
          }),
        );
      // eq_triangle x b c: |xb| = |bc| = |cx| — the apex is where the
      // two circles of radius |bc| about b and about c meet, and either
      // meeting point is a correct equilateral triangle.
      case 'eq_triangle':
        return both(circle(1, 2), circle(2, 1));
      case 'intersection_ll':
        return both(line(1, 2), line(3, 4));
      case 'intersection_lp':
        return both(line(1, 2), parallelThrough(3, 4, 5));
      case 'intersection_lt':
        return both(line(1, 2), perpendicularThrough(3, 4, 5));
      case 'intersection_pp':
        return both(parallelThrough(1, 2, 3), parallelThrough(4, 5, 6));
      case 'intersection_tt':
        return both(
          perpendicularThrough(1, 2, 3),
          perpendicularThrough(4, 5, 6),
        );
      // intersection_lc x a o b: line ab meets the circle about o
      // through b — and b is on both, so it is the branch to avoid.
      case 'intersection_lc':
        return both(line(1, 3), circle(2, 3), shared: _known(args[3]));
      // intersection_cc x o w a: both circles pass through a.
      case 'intersection_cc':
        return both(circle(1, 3), circle(2, 3), shared: _known(args[3]));
      default:
        return null;
    }
  }

  GeoObject _named(String key, GeoObject Function() build) =>
      _carriers[key] ??= build();

  // --------------------------------------------------------------- shapes

  /// Clauses that name several points at once and constrain them
  /// against each other. Null when [call] is not one of them.
  _ShapeOutcome? _shapedClause(NewclidClause clause, NewclidCall call) {
    switch (call.macro) {
      // iso_triangle a b c: cong a b a c — c on the circle about a
      // through b.
      case 'iso_triangle':
        if (clause.outputs.length != 3) return _shapeArity(call, 3);
        _free(clause.outputs[0]);
        _free(clause.outputs[1]);
        final circle = _circleAbout(clause.outputs[0], clause.outputs[1]);
        if (circle == null) return _ShapeOutcome(_missing(call));
        final apex = PointOnObject(
          id: _id('p'),
          curve: circle,
          parameter: _parameterOn(circle),
          attributes: ObjectAttributes(name: clause.outputs[2]),
        );
        construction.add(apex);
        points[clause.outputs[2]] = apex;
        return const _ShapeOutcome(null);
      // r_triangle a b c: perp a b a c — c on the perpendicular to ab
      // at a.
      case 'r_triangle':
        if (clause.outputs.length != 3) return _shapeArity(call, 3);
        final a = _free(clause.outputs[0]);
        _free(clause.outputs[1]);
        final base = _lineThrough(clause.outputs[0], clause.outputs[1]);
        if (base is! GeoLine) return _ShapeOutcome(_missing(call));
        final leg = PerpendicularLine(
          id: _id('l'),
          through: a,
          reference: base,
        );
        construction.add(leg);
        final third = PointOnObject(
          id: _id('p'),
          curve: leg,
          parameter: _parameterOn(leg),
          attributes: ObjectAttributes(name: clause.outputs[2]),
        );
        construction.add(third);
        points[clause.outputs[2]] = third;
        return const _ShapeOutcome(null);
      // incenter2 x y z i a b c: the incentre and its three touch
      // points, which are the feet of the perpendiculars from it.
      case 'incenter2':
        if (clause.outputs.length != 4) return _shapeArity(call, 4);
        final args = call.arguments;
        if (args.length != 7) return _shapeArity(call, 4);
        final a = _known(args[4]);
        final b = _known(args[5]);
        final c = _known(args[6]);
        if (a == null || b == null || c == null) {
          return _ShapeOutcome(_missing(call));
        }
        final centre = Incenter(
          id: _id('p'),
          vertex1: a,
          vertex2: b,
          vertex3: c,
          attributes: ObjectAttributes(name: args[3]),
        );
        construction.add(centre);
        points[args[3]] = centre;
        const sides = [
          [5, 6],
          [6, 4],
          [4, 5],
        ];
        for (var i = 0; i < 3; i++) {
          final side = _lineThrough(args[sides[i][0]], args[sides[i][1]]);
          if (side is! GeoLine) return _ShapeOutcome(_missing(call));
          final foot = ProjectionPoint(
            id: _id('p'),
            point: centre,
            line: side,
            attributes: ObjectAttributes(name: args[i]),
          );
          construction.add(foot);
          points[args[i]] = foot;
        }
        return const _ShapeOutcome(null);
      default:
        return null;
    }
  }

  _ShapeOutcome _shapeArity(NewclidCall call, int expected) => _ShapeOutcome(
    _fail(
      UntranslatableReason.unsupportedClause,
      '${call.macro} should name $expected points',
    ),
  );

  UntranslatableProblem? _missing(NewclidCall call) => _fail(
    UntranslatableReason.unsupportedClause,
    '${call.macro} names a point that does not exist yet: $call',
  );

  // -------------------------------------------------------- the check

  /// How close two points may be before the figure counts as degenerate,
  /// relative to the sampling box.
  static const double _coincident = _scale * 1e-6;

  /// Whether the figure this sample produced is generic enough to
  /// measure on, and what is wrong when it is not.
  ///
  /// The hypothesis sweep is the part that earns its keep. Every
  /// statement `hypotheses()` reads off the construction is a structural
  /// truth of the *parent ties*, so it must also be true in any figure
  /// those ties produce. One that fails the filter therefore does not
  /// mean the diagram is unlucky — it means this translation built
  /// something other than what the clause said, and catching that here
  /// is why the corpus can be trusted as a baseline at all.
  String? _checkGeneric() {
    for (final entry in points.entries) {
      if (entry.value.position == null) {
        return '${entry.key} is undefined in this figure';
      }
    }
    final named = points.entries.toList();
    for (var i = 0; i < named.length; i++) {
      for (var j = i + 1; j < named.length; j++) {
        final a = named[i].value.position!;
        final b = named[j].value.position!;
        if (a.distanceTo(b) <= _coincident) {
          return '${named[i].key} and ${named[j].key} coincide';
        }
      }
    }
    final objects = construction.objects.toList();
    final filter = DiagramFilter.probe(objects, random: random);
    for (final hypothesis in hypotheses(objects)) {
      if (!filter.holds(hypothesis)) {
        return 'the hypothesis $hypothesis is false in the figure';
      }
    }
    _filter = filter;
    return null;
  }

  DiagramFilter? _filter;

  /// Phrases the goal the way the app's question builder would.
  ///
  /// [QuestionDraft.seeded] taps the goal's points into the template's
  /// slots in order, which is exactly the corpus's own argument order —
  /// so the question carries every witness-pair spelling of each named
  /// line, not only the pair Newclid wrote. Asking one spelling would
  /// under-report the prover: PLAN §M-P4 records that a run can hold the
  /// statement under a different name.
  UntranslatableProblem? _goal() {
    final template = goalTemplates[problem.goal.predicate];
    if (template == null) {
      return _fail(
        UntranslatableReason.unsupportedGoal,
        'no template for ${problem.goal.predicate}',
      );
    }
    final expected = tapsFor(template);
    if (problem.goal.arguments.length != expected) {
      return _fail(
        UntranslatableReason.unsupportedGoal,
        '${problem.goal.predicate} over ${problem.goal.arguments.length} '
        'points is not the $expected the template takes — an arity the '
        'vocabulary does not have is a conjunction, not one fact',
      );
    }
    final taps = <GeoObject>[];
    for (final name in problem.goal.arguments) {
      final point = _known(name);
      if (point == null) {
        return _fail(
          UntranslatableReason.unsupportedGoal,
          'the goal names $name, which the construction never builds',
        );
      }
      taps.add(point);
    }
    final draft = QuestionDraft.seeded(template, taps);
    final asked = draft.question(construction.objects);
    if (asked == null) {
      return _fail(
        UntranslatableReason.unsupportedGoal,
        'the template phrases nothing from ${problem.goal}',
      );
    }
    if (!_filter!.holds(asked.canonical)) {
      return _fail(
        UntranslatableReason.goalFalseInFigure,
        '${problem.goal} is false in the figure built for it',
      );
    }
    question = asked;
    return null;
  }
}

/// A curve a point is constrained to, and the point the macro already
/// names on it when it names one.
class _Constraint {
  const _Constraint(this.curve, this.shared);

  final GeoObject curve;

  /// A point known to lie on *both* curves of the crossing, and so the
  /// branch the clause does not mean.
  final GeoPoint? shared;
}

/// That a clause was a multi-point shape, and whether it worked.
class _ShapeOutcome {
  const _ShapeOutcome(this.failure);

  final UntranslatableProblem? failure;
}
