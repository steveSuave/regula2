import 'dart:math' as math;

import '../construction/geo_object.dart';
import 'diagram_filter.dart';
import 'event_loop_yield.dart';
import 'fact.dart';
import 'fact_database.dart';
import 'predicate.dart';
import 'rule.dart';

/// Seeds [database] with the [hypotheses] that survive [filter],
/// answering how many were new.
///
/// A hypothesis the filter refuses is dropped, conservatively: the
/// extraction only emits theorems of the construction, so a refusal
/// means the diagram is degenerate right now (a reflection with its
/// point on the mirror, a collapsed triangle) and nothing should be
/// deduced from that statement.
int seedHypotheses(
  FactDatabase database,
  Iterable<Predicate> hypotheses,
  DiagramFilter filter,
) {
  var added = 0;
  for (final hypothesis in hypotheses) {
    if (!filter.holds(hypothesis)) continue;
    if (database.addHypothesis(Fact.of(hypothesis))) added++;
  }
  return added;
}

/// DD forward chaining to quiescence, in the Phase 140 resumable shape:
/// an explicit cursor over the fact list, driven by [step] under a
/// budget counted in **rule applications** — one fully-bound premise
/// combination considered — never milliseconds, so a run's outcome is a
/// deterministic function of its input on every target (the Phase 139
/// argument, applied verbatim).
///
/// The loop is semi-naive: each fact, in insertion order, serves once as
/// the *pivot* — bound into every premise slot its kind fits, with the
/// remaining premises joined over the facts already stored when the
/// pivot's turn began. A combination of two facts is enumerated when the
/// younger of them pivots, so nothing is missed and nothing waits.
/// Matching binds against every spelling of a stored fact
/// ([orbitArguments]) because a pattern with a repeated variable —
/// `cong(o,a,o,b)` — has to see the spelling the canonical order sorted
/// away. The per-kind index lives here, not in `FactDatabase`: the
/// matcher is the consumer that justifies it (the M-P2a deferral), and
/// the store stays a store.
///
/// Every candidate conclusion is screened through the [filter] before
/// insertion — never derive a fact that is not numerically true in the
/// diagram — which also carries the DD sources' implicit non-degeneracy
/// side conditions (see [ddCoreRules]). Structural degeneracy (a
/// zero-length segment, a repeated `coll` point, an identical triangle
/// pair) is refused at binding time without spending budget: it is a
/// property of the tuple, not of any configuration.
class ProverEngine {
  ProverEngine({
    required this.database,
    required this.filter,
    List<Rule>? rules,
  }) : rules = List.unmodifiable(rules ?? ddCoreRules) {
    for (final fact in database.facts) {
      _append(fact);
    }
  }

  final FactDatabase database;
  final DiagramFilter filter;
  final List<Rule> rules;

  /// Mirror of [database]'s facts in insertion order — the pivot queue.
  final List<Fact> _facts = [];
  final Map<PredicateKind, List<Fact>> _byKind = {
    for (final kind in PredicateKind.values) kind: [],
  };

  int _nextPivot = 0;
  Iterator<_Candidate>? _current;
  int _applications = 0;

  /// Rule applications performed so far, across all [step] calls.
  int get applications => _applications;

  /// Whether the fixpoint is reached: every fact has served as pivot and
  /// no candidate remains. A completed engine's [step] answers 0.
  bool get isComplete => _current == null && _nextPivot >= _facts.length;

  void _append(Fact fact) {
    _facts.add(fact);
    _byKind[fact.kind]!.add(fact);
  }

  /// Takes into the pivot queue any fact added to [database] by someone
  /// else — a peer engine publishing into the same store (PLAN §M-P3's
  /// facade).
  ///
  /// Sound because [_facts] is exactly [database]'s list: the engine is
  /// seeded from it and appends precisely when [database.add] answers
  /// true, so what it has not seen is the tail. A fact that arrives this
  /// way pivots like any other, which is what makes the exchange run
  /// both ways — an angle conclusion is a premise for the next rule.
  int absorbExternal() {
    var taken = 0;
    for (final fact in database.facts.skip(_facts.length).toList()) {
      _append(fact);
      taken++;
    }
    return taken;
  }

  /// Performs up to [budget] rule applications, answering how many were
  /// actually performed — fewer exactly when quiescence arrived first.
  /// Resumable at any granularity: `step(1)` many times and one
  /// `step(1 << 30)` reach the identical database (pinned by test).
  int step(int budget) {
    if (budget < 0) {
      throw ArgumentError.value(budget, 'budget', 'must be non-negative');
    }
    var performed = 0;
    while (performed < budget) {
      final current = _current ??= _startNextPivot();
      if (current == null) break;
      if (!current.moveNext()) {
        _current = null;
        continue;
      }
      performed++;
      _applications++;
      final candidate = current.current;
      if (!filter.holds(candidate.statement)) continue;
      final fact = Fact.of(candidate.statement);
      if (database.add(
        fact,
        Derivation(candidate.rule.name, candidate.premises),
      )) {
        _append(fact);
      }
    }
    return performed;
  }

  /// Drives to quiescence in one call and answers the total number of
  /// applications it took. The chunked entry point is [step]; this is
  /// the native-friendly straight line over the same machinery.
  int run() {
    var total = 0;
    while (!isComplete) {
      total += step(1 << 30);
    }
    return total;
  }

  /// Drives to quiescence [chunkBudget] applications at a time, yielding
  /// to the event loop between chunks ([yieldToEventLoop] — the
  /// MessageChannel on web, a zero timer natively), so a long fixpoint
  /// never holds a frame hostage. Same machinery, same result: chunking
  /// changes when the work happens, never what it derives (pinned).
  ///
  /// [stopWhen] is checked between chunks and ends the call early when
  /// it answers true — a goal-directed caller wants one fact, not
  /// quiescence, and asking is therefore *cheaper* than deriving rather
  /// than more expensive: a document whose fixpoint never lands can
  /// still answer a question in the first chunk. The check granularity
  /// is the chunk, so a stopped run has overshot by less than
  /// [chunkBudget] — the answer is unaffected (the engine only ever adds
  /// facts) and the overshoot is what buys one predicate evaluation per
  /// chunk instead of per application.
  ///
  /// [maxApplications] caps *this call*, answering early with
  /// [isComplete] still false — quiescence is not something an arbitrary
  /// document owes, and a caller with a frame to keep needs a ceiling
  /// rather than a promise. Everything derived up to the cap stands: the
  /// database is a fixpoint prefix, not a partial result to discard, and
  /// a further call resumes exactly where this one stopped (the Phase
  /// 140 resumable shape, used for what it is for).
  Future<int> runChunked({
    required int chunkBudget,
    int? maxApplications,
    bool Function()? stopWhen,
  }) async {
    if (chunkBudget <= 0) {
      throw ArgumentError.value(chunkBudget, 'chunkBudget', 'must be positive');
    }
    if (maxApplications != null && maxApplications < 0) {
      throw ArgumentError.value(
        maxApplications,
        'maxApplications',
        'must be non-negative',
      );
    }
    var total = 0;
    if (stopWhen != null && stopWhen()) return 0;
    while (!isComplete) {
      final budget = maxApplications == null
          ? chunkBudget
          : math.min(chunkBudget, maxApplications - total);
      if (budget <= 0) break;
      total += step(budget);
      if (isComplete) break;
      if (stopWhen != null && stopWhen()) break;
      if (maxApplications != null && total >= maxApplications) break;
      await yieldToEventLoop();
    }
    return total;
  }

  Iterator<_Candidate>? _startNextPivot() {
    if (_nextPivot >= _facts.length) return null;
    final pivotIndex = _nextPivot++;
    // The join set is frozen as of this pivot's turn: combinations with
    // younger facts are enumerated when those facts pivot. Per-kind
    // counts are captured eagerly so insertions during this pivot's own
    // consumption cannot shift its iteration.
    final snapshot = {
      for (final kind in PredicateKind.values) kind: _byKind[kind]!.length,
    };
    return _pivotCandidates(_facts[pivotIndex], snapshot).iterator;
  }

  Iterable<_Candidate> _pivotCandidates(
    Fact pivot,
    Map<PredicateKind, int> snapshot,
  ) sync* {
    for (final rule in rules) {
      for (var slot = 0; slot < rule.premises.length; slot++) {
        if (rule.premises[slot].kind != pivot.kind) continue;
        for (final form in orbitArguments(pivot.kind, pivot.points)) {
          final binding = <String, GeoPoint>{};
          if (!_bind(rule.premises[slot], form, binding)) continue;
          yield* _joinRemaining(rule, slot, 0, binding, {
            slot: pivot,
          }, snapshot);
        }
      }
    }
  }

  Iterable<_Candidate> _joinRemaining(
    Rule rule,
    int pivotSlot,
    int position,
    Map<String, GeoPoint> binding,
    Map<int, Fact> bound,
    Map<PredicateKind, int> snapshot,
  ) sync* {
    if (position == rule.premises.length) {
      final points = [
        for (final variable in rule.conclusion.variables) binding[variable]!,
      ];
      if (!_admissibleConclusion(rule.conclusion.kind, points)) return;
      yield _Candidate(rule, [
        for (var i = 0; i < rule.premises.length; i++) bound[i]!,
      ], Predicate(rule.conclusion.kind, points));
      return;
    }
    if (position == pivotSlot) {
      yield* _joinRemaining(
        rule,
        pivotSlot,
        position + 1,
        binding,
        bound,
        snapshot,
      );
      return;
    }
    final premise = rule.premises[position];
    final candidates = _byKind[premise.kind]!;
    final limit = snapshot[premise.kind]!;
    for (var i = 0; i < limit; i++) {
      final fact = candidates[i];
      for (final form in orbitArguments(fact.kind, fact.points)) {
        final extended = Map.of(binding);
        if (!_bind(premise, form, extended)) continue;
        yield* _joinRemaining(rule, pivotSlot, position + 1, extended, {
          ...bound,
          position: fact,
        }, snapshot);
      }
    }
  }

  /// Unifies [points] with [pattern] into [binding] (mutated), false on
  /// a clash — a variable already bound to a different point, or one
  /// spelling binding two slots of a repeated variable differently.
  bool _bind(
    RulePattern pattern,
    List<GeoPoint> points,
    Map<String, GeoPoint> binding,
  ) {
    for (var i = 0; i < points.length; i++) {
      final variable = pattern.variables[i];
      final existing = binding[variable];
      if (existing == null) {
        binding[variable] = points[i];
      } else if (!identical(existing, points[i])) {
        return false;
      }
    }
    return true;
  }
}

/// A conclusion tuple worth spending budget on: structurally
/// non-degenerate and not trivially self-referential. Everything here is
/// a property of the tuple alone; configuration questions belong to the
/// filter.
bool _admissibleConclusion(PredicateKind kind, List<GeoPoint> points) {
  bool distinct(Iterable<int> indices) {
    final seen = <GeoPoint>[];
    for (final i in indices) {
      if (seen.any((p) => identical(p, points[i]))) return false;
      seen.add(points[i]);
    }
    return true;
  }

  bool sameSegment(int a, int b) =>
      (identical(points[a * 2], points[b * 2]) &&
          identical(points[a * 2 + 1], points[b * 2 + 1])) ||
      (identical(points[a * 2], points[b * 2 + 1]) &&
          identical(points[a * 2 + 1], points[b * 2]));

  switch (kind) {
    case PredicateKind.coll:
    case PredicateKind.midp:
      return distinct([0, 1, 2]);
    case PredicateKind.cyclic:
      return distinct([0, 1, 2, 3]);
    case PredicateKind.para:
    case PredicateKind.perp:
    case PredicateKind.cong:
      return distinct([0, 1]) && distinct([2, 3]) && !sameSegment(0, 1);
    case PredicateKind.eqangle:
    case PredicateKind.eqratio:
      for (var segment = 0; segment < 4; segment++) {
        if (!distinct([segment * 2, segment * 2 + 1])) return false;
      }
      // ∠(s,t) = ∠(s,t) and ∠(s,s) = ∠(t,t) say nothing; likewise the
      // ratios.
      if (sameSegment(0, 2) && sameSegment(1, 3)) return false;
      if (sameSegment(0, 1) && sameSegment(2, 3)) return false;
      return true;
    case PredicateKind.simtri:
    case PredicateKind.contri:
      if (!distinct([0, 1, 2]) || !distinct([3, 4, 5])) return false;
      // A triangle is similar to itself in the identity correspondence.
      return !(identical(points[0], points[3]) &&
          identical(points[1], points[4]) &&
          identical(points[2], points[5]));
  }
}

class _Candidate {
  _Candidate(this.rule, this.premises, this.statement);

  final Rule rule;
  final List<Fact> premises;
  final Predicate statement;
}
