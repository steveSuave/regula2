import '../construction/geo_object.dart';
import '../math/rational.dart';
import 'angle_translation.dart';
import 'carriers.dart';
import 'diagram_filter.dart';
import 'event_loop_yield.dart';
import 'fact.dart';
import 'fact_database.dart';
import 'length_translation.dart';
import 'predicate.dart';
import 'rule.dart';
import 'rule_engine.dart';

/// What one exchange between the two engines did.
class ProverPass {
  const ProverPass({
    required this.applications,
    required this.published,
    required this.absorbed,
  });

  /// Rule applications DD spent in this pass.
  final int applications;

  /// Facts AR published into the database in this pass.
  final int published;

  /// Facts AR took *from* DD in this pass — the other direction.
  final int absorbed;

  bool get isQuiet => published == 0 && applications == 0;

  @override
  String toString() =>
      'pass(dd $applications, ar +$published, ar <- $absorbed)';
}

/// DD and AR as peers over one fact database (PLAN §M-P3).
///
/// **The exchange is the point, and Phase 152b measured why.** AR run on
/// a document's hypotheses alone reaches almost nothing — it misses
/// twenty of DD's twenty-one `para`/`perp` on `perp-true-unproved.rgl`,
/// because those come from `midline_para`, `perp_bisector` and the
/// inscribed pair, whose premises are `midp`, `cong` and `cyclic` and so
/// are invisible to an algebra of directions. Fed DD's fixpoint the same
/// closure *doubles* the angle facts in two milliseconds. Neither engine
/// is the prover; the loop between them is.
///
/// And it runs both ways, which is what makes this a loop rather than a
/// pipeline: a `para` AR published is a premise DD can pivot on, whose
/// conclusions AR then reads. So a pass ends only when DD is quiescent
/// **and** AR published nothing, and the budget bounds the whole thing
/// rather than either half.
///
/// Facts AR publishes are screened by the same [filter] DD screens with,
/// for the same reason and with no exception made: the algebra is
/// believed, but a conclusion that is not numerically true in the
/// diagram means something upstream is wrong, and letting it in would
/// hide that.
class Prover {
  Prover({required this.database, required this.filter, List<Rule>? rules})
    : _dd = ProverEngine(database: database, filter: filter, rules: rules) {
    _absorb();
  }

  final FactDatabase database;
  final DiagramFilter filter;

  final ProverEngine _dd;
  final AngleTranslation angles = AngleTranslation();

  /// The other half of AR (Phase 165). It publishes `cong` and answers
  /// `eqratio` on ask — the opposite split from [angles], which
  /// publishes `para`/`perp` and answers `eqangle`, and by the same
  /// rule: publish what has a consumer, and only what the enumeration
  /// can afford.
  final LengthTranslation lengths = LengthTranslation();

  /// The incidence closure, which tells [AngleTranslation.conclusions] a
  /// parallel from a line and itself.
  final CarrierIndex incidence = CarrierIndex();

  /// How far into [database] the angle side has read.
  int _read = 0;

  /// Every pass so far, oldest first — the exchange's own record, and
  /// what a measurement reads.
  final List<ProverPass> passes = [];

  int get applications => _dd.applications;

  /// DD's per-rule work so far, keyed by rule name — what a pass cost
  /// in visits as well as in applications ([ProverEngine.tallies]).
  Map<String, RuleTally> get tallies => _dd.tallies;

  /// Whether both halves have nothing left: DD quiescent and the last
  /// pass silent.
  bool get isComplete =>
      _dd.isComplete && passes.isNotEmpty && passes.last.published == 0;

  /// Runs the exchange to a joint fixpoint, or until [maxApplications]
  /// rule applications have been spent, answering the passes it took.
  ///
  /// The cap counts DD's applications only. AR's cost is not in the same
  /// currency — a pass of it is a bounded elimination over the facts
  /// present, measured in single-digit milliseconds on every fixture —
  /// and pretending otherwise would put two incomparable things behind
  /// one number.
  int run({int? maxApplications}) {
    final spentBefore = _dd.applications;
    while (!isComplete) {
      final budget = _budgetLeft(maxApplications, spentBefore);
      if (budget <= 0) break;
      final pass = _pass(budget);
      passes.add(pass);
      if (pass.isQuiet) break;
    }
    return passes.length;
  }

  /// What this *call* may still spend.
  ///
  /// Per call and not per lifetime, which is `ProverEngine.runChunked`'s
  /// contract and the one a resumed run depends on: a second call with
  /// the same budget must be able to spend it, or *Keep going* keeps
  /// nothing going.
  int _budgetLeft(int? maxApplications, int spentBefore) {
    if (maxApplications == null) return 1 << 30;
    return maxApplications - (_dd.applications - spentBefore);
  }

  /// [run] with a yield between passes, so a long exchange never holds a
  /// frame hostage — `ProverEngine.runChunked`'s bargain at the pass
  /// granularity.
  ///
  /// [onPass] is called once per pass, right after it ran — the hook a
  /// caller that published "running" once and then hears nothing until
  /// the future completes uses to say how far the run has got. It fires
  /// for every pass, the final one included, and never fires when the
  /// entry checks return without a pass.
  Future<int> runChunked({
    required int chunkBudget,
    int? maxApplications,
    bool Function()? stopWhen,
    void Function()? onPass,
  }) async {
    if (chunkBudget <= 0) {
      throw ArgumentError.value(chunkBudget, 'chunkBudget', 'must be positive');
    }
    if (stopWhen != null && stopWhen()) return 0;
    final spentBefore = _dd.applications;
    while (!isComplete) {
      final left = _budgetLeft(maxApplications, spentBefore);
      if (left <= 0) break;
      final budget = left < chunkBudget ? left : chunkBudget;
      final pass = _pass(budget);
      passes.add(pass);
      onPass?.call();
      if (pass.isQuiet) break;
      if (stopWhen != null && stopWhen()) break;
      // Every exit is taken *before* the yield, deliberately. A yield
      // is a timer, and a caller that awaits this future without
      // pumping — `testWidgets`' fake async, and so every widget test
      // that drives the prover directly — would wait on a timer nobody
      // fires. `ProverEngine.runChunked` has the same shape for the same
      // reason; a run that has spent its budget must come back without
      // touching the event loop.
      if (_budgetLeft(maxApplications, spentBefore) <= 0) break;
      await yieldToEventLoop();
    }
    return passes.length;
  }

  ProverPass _pass(int budget) {
    final applications = _dd.step(budget);
    final absorbed = _absorb();
    final published = _publish();
    // What AR published must pivot, or the loop is a pipeline: an angle
    // conclusion is a premise for the next rule.
    _dd.absorbExternal();
    return ProverPass(
      applications: applications,
      published: published,
      absorbed: absorbed,
    );
  }

  /// Feeds the angle side everything the database has gained since last
  /// time, and answers how many facts it read.
  int _absorb() {
    final fresh = database.facts.skip(_read).toList();
    _read += fresh.length;
    for (final fact in fresh) {
      incidence.absorb(fact);
      angles.absorb(fact);
      lengths.absorb(fact);
    }
    return fresh.length;
  }

  int _publish() {
    var published = 0;
    for (final conclusion in angles.conclusions(incidence).toList()) {
      if (database.contains(conclusion.fact)) continue;
      if (_record(
        conclusion.fact,
        angleArithmeticRule,
        angles.sourcesOf(conclusion.certificate),
      )) {
        published++;
      }
    }
    for (final conclusion in lengths.conclusions().toList()) {
      if (database.contains(conclusion.fact)) continue;
      if (_record(
        conclusion.fact,
        lengthArithmeticRule,
        lengths.sourcesOf(conclusion.certificate),
      )) {
        published++;
      }
    }
    return published;
  }

  /// Records [fact] as an AR step under [rule], screened.
  ///
  /// The two screens are the same two whether the fact was enumerated or
  /// asked for: the diagram must agree, on the no-exception rule this
  /// class states, and every cited premise must still be present — a
  /// certificate over inputs the database has since lost would name a
  /// proof step that cannot be read back.
  bool _record(Fact fact, String rule, List<Fact> premises) {
    if (!filter.holds(fact.statement)) return false;
    if (premises.any((premise) => !database.contains(premise))) return false;
    return database.add(fact, Derivation(rule, premises));
  }

  /// Whether the exchange holds [fact].
  bool holds(Fact fact) => database.contains(fact);

  /// Whether the exchange holds [fact] *or can* — and if only the
  /// latter, holds it from now on (Phase 159).
  ///
  /// [_publish] enumerates `para`, `perp` and `cong`, and deliberately
  /// never `eqangle` or `eqratio`: quadruples of variables are quartic,
  /// and 152e measured 2 527 entailed `eqangle` on one fixture with no
  /// consumer for any, session 174 another 43 `eqratio`.
  /// An *ask* is the other direction — one membership query against
  /// each closure — and the one statement it lands on is recorded as an
  /// arithmetic step exactly as a published one would be, so
  /// that `Proof.of` has a derivation to read and `verify` a certificate
  /// to check. Screened through the filter like every publication, and
  /// **not** handed to DD's pivot queue: the fact was asked for, not
  /// derived toward, and waking a quiescent engine on it would make
  /// [isComplete] a function of what the user asked.
  bool resolve(Fact fact) {
    if (database.contains(fact)) return true;
    final angleCertificate = angles.entailmentOf(fact);
    if (angleCertificate != null &&
        _record(
          fact,
          angleArithmeticRule,
          angles.sourcesOf(angleCertificate),
        )) {
      return true;
    }
    final lengthCertificate = lengths.entailmentOf(fact);
    if (lengthCertificate != null &&
        _record(
          fact,
          lengthArithmeticRule,
          lengths.sourcesOf(lengthCertificate),
        )) {
      return true;
    }
    return false;
  }

  /// The value the closures entail for a value-carrying [kind] over
  /// [points] — the `aconst` residue, the `rconst` ratio, the `lconst`
  /// length — or null when they do not determine it (Phase 185, the
  /// "what is this angle?" reader). Nothing is recorded: a reading is a
  /// question about the closure, and [resolve] on the fact with the
  /// value read is what records the answer, certificate and all.
  ///
  /// Throws [ArgumentError] on a kind that carries no value, or the
  /// wrong number of points for it.
  Rational? readConstant(PredicateKind kind, List<GeoPoint> points) {
    if (!kind.carriesValue) {
      throw ArgumentError.value(kind, 'kind', 'carries no value to read');
    }
    if (points.length != kind.arity) {
      throw ArgumentError.value(points, 'points', 'arity is ${kind.arity}');
    }
    return switch (kind) {
      PredicateKind.aconst => angles.readAngle(
        points[0],
        points[1],
        points[2],
        points[3],
      ),
      PredicateKind.rconst => lengths.readRatio(
        points[0],
        points[1],
        points[2],
        points[3],
      ),
      PredicateKind.lconst => lengths.readLength(points[0], points[1]),
      _ => null,
    };
  }
}
