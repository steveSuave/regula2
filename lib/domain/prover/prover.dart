import 'angle_translation.dart';
import 'carriers.dart';
import 'diagram_filter.dart';
import 'event_loop_yield.dart';
import 'fact.dart';
import 'fact_database.dart';
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
  Prover({
    required this.database,
    required this.filter,
    List<Rule>? rules,
  }) : _dd = ProverEngine(database: database, filter: filter, rules: rules) {
    _absorb();
  }

  final FactDatabase database;
  final DiagramFilter filter;

  final ProverEngine _dd;
  final AngleTranslation angles = AngleTranslation();

  /// The incidence closure, which tells [AngleTranslation.conclusions] a
  /// parallel from a line and itself.
  final CarrierIndex incidence = CarrierIndex();

  /// How far into [database] the angle side has read.
  int _read = 0;

  /// Every pass so far, oldest first — the exchange's own record, and
  /// what a measurement reads.
  final List<ProverPass> passes = [];

  int get applications => _dd.applications;

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
    while (!isComplete) {
      if (maxApplications != null && _dd.applications >= maxApplications) break;
      final budget = maxApplications == null
          ? 1 << 30
          : maxApplications - _dd.applications;
      final pass = _pass(budget);
      passes.add(pass);
      if (pass.isQuiet) break;
    }
    return passes.length;
  }

  /// [run] with a yield between passes, so a long exchange never holds a
  /// frame hostage — `ProverEngine.runChunked`'s bargain at the pass
  /// granularity.
  Future<int> runChunked({
    required int chunkBudget,
    int? maxApplications,
    bool Function()? stopWhen,
  }) async {
    if (chunkBudget <= 0) {
      throw ArgumentError.value(chunkBudget, 'chunkBudget', 'must be positive');
    }
    if (stopWhen != null && stopWhen()) return 0;
    while (!isComplete) {
      if (maxApplications != null && _dd.applications >= maxApplications) break;
      var budget = chunkBudget;
      if (maxApplications != null) {
        final left = maxApplications - _dd.applications;
        if (left < budget) budget = left;
      }
      if (budget <= 0) break;
      final pass = _pass(budget);
      passes.add(pass);
      if (pass.isQuiet) break;
      if (stopWhen != null && stopWhen()) break;
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
    }
    return fresh.length;
  }

  int _publish() {
    var published = 0;
    for (final conclusion in angles.conclusions(incidence).toList()) {
      if (database.contains(conclusion.fact)) continue;
      if (!filter.holds(conclusion.fact.statement)) continue;
      final premises = angles.sourcesOf(conclusion.certificate);
      if (premises.any((premise) => !database.contains(premise))) continue;
      if (database.add(
        conclusion.fact,
        Derivation(angleArithmeticRule, premises),
      )) {
        published++;
      }
    }
    return published;
  }

  /// Whether the exchange holds [fact].
  bool holds(Fact fact) => database.contains(fact);
}
