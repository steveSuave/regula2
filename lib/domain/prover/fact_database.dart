import 'fact.dart';

/// Where a fact came from: a hypothesis read off the construction, or a
/// rule applied to premises already in the database.
///
/// The rule is a bare name the database never interprets. M-P2b brings
/// the rule set and may hand a richer reference in here; nothing in the
/// store depends on which, and a proof reads the name.
class Derivation {
  /// A given — something the diagram states rather than something the
  /// prover concluded.
  const Derivation.hypothesis() : rule = null, premises = const [];

  /// [rule] applied to [premises], each of which must already be in the
  /// database when this is recorded.
  Derivation(String this.rule, List<Fact> premises)
    : premises = List.unmodifiable(premises);

  /// Null exactly for a hypothesis.
  final String? rule;

  /// The facts the rule consumed; empty for a hypothesis.
  final List<Fact> premises;

  bool get isHypothesis => rule == null;

  @override
  String toString() => isHypothesis
      ? 'hypothesis'
      : '$rule(${premises.map((f) => '$f').join(', ')})';
}

/// The prover's fact database (PLAN §M-P2): the derived-so-far set that
/// forward chaining grows to quiescence, keyed on [Fact]'s canonical
/// forms so that one statement written two ways is stored once.
///
/// **Every entry carries its [Derivation], from day one**, which is what
/// PLAN means by the proof DAG being free: the edges are already here,
/// and M-P2c only has to walk them.
///
/// Two invariants make that walk safe, and both are enforced rather than
/// hoped for:
///
/// - **First insert wins.** A fact re-derived by a longer route keeps the
///   derivation it was discovered with. That is not a tie-break for
///   tidiness — it is the acyclicity argument. A derivation may only
///   cite facts that were already present, so every premise is strictly
///   older than its conclusion, and a cycle would need a fact older than
///   itself.
/// - **Premises must be present.** [add] throws on a premise the database
///   does not hold, so the DAG is closed by construction and a proof walk
///   can never reach a dangling edge.
///
/// Iteration is in insertion order, which keeps a run — and so a printed
/// proof — reproducible.
///
/// What is deliberately *not* here: an index by kind (M-P2b's rule
/// matcher is the consumer that would justify one, and it does not exist
/// yet), any coupling to `DiagramFilter` (screening candidates is the
/// filter's job; this stores what a rule actually derived), and any way
/// to read hypotheses off a `Construction` (also M-P2b's).
class FactDatabase {
  final Map<Fact, Derivation> _derivations = {};

  /// Records [fact] with [derivation], returning whether it was new.
  ///
  /// A fact already present is left exactly as it was — same derivation,
  /// same position in the iteration order — and the answer is false,
  /// which is the signal forward chaining converges on: a round that
  /// adds nothing is quiescence.
  ///
  /// Throws [StateError] when [derivation] cites a premise the database
  /// does not hold.
  bool add(Fact fact, Derivation derivation) {
    for (final premise in derivation.premises) {
      if (!_derivations.containsKey(premise)) {
        throw StateError(
          'derivation of $fact cites $premise, which is not in the database',
        );
      }
    }
    if (_derivations.containsKey(fact)) {
      return false;
    }
    _derivations[fact] = derivation;
    return true;
  }

  /// Records [fact] as a given.
  bool addHypothesis(Fact fact) => add(fact, const Derivation.hypothesis());

  bool contains(Fact fact) => _derivations.containsKey(fact);

  /// How [fact] was arrived at, or null when it is not in the database.
  Derivation? derivationOf(Fact fact) => _derivations[fact];

  /// Every fact, in the order it was first recorded.
  Iterable<Fact> get facts => _derivations.keys;

  int get length => _derivations.length;

  bool get isEmpty => _derivations.isEmpty;

  bool get isNotEmpty => _derivations.isNotEmpty;
}
