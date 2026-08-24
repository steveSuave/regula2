import 'angle_chase.dart';
import 'angle_translation.dart';
import 'derivation_check.dart';
import 'fact.dart';
import 'fact_database.dart';
import 'fact_naming.dart';
import 'rule.dart';

export 'fact_naming.dart'
    show
        describeFact,
        describePoint,
        factReadingConvention,
        predicateKindLabel,
        readFact,
        readPredicate;

/// One line of a proof: a fact, and the warrant for it.
///
/// [number] is the step's 1-based position in its [Proof], which is what
/// [premiseSteps] refer to — a proof reads as a numbered list where every
/// citation points *upwards*, and that property is not stylistic: it is
/// the premises-strictly-older invariant of `FactDatabase`, surfaced.
class ProofStep {
  ProofStep({
    required this.number,
    required this.fact,
    required this.rule,
    required List<int> premiseSteps,
    this.chase,
  }) : premiseSteps = List.unmodifiable(premiseSteps);

  final int number;
  final Fact fact;

  /// The rule that derived [fact], or null when it is a given.
  final String? rule;

  /// The steps this one cites, in the rule's premise-slot order — the
  /// order `derivation_check.dart` re-matches against.
  final List<int> premiseSteps;

  /// For an `angle_arithmetic` step, the relations it added up; null for
  /// every other step, where the rule's name is already the explanation.
  ///
  /// Null on an angle step too when the chase could not be re-derived —
  /// a defect, and one [Proof.verify] reports in the same breath. A step
  /// that cannot explain itself still states its premises rather than
  /// refusing to render.
  final AngleChase? chase;

  bool get isGiven => rule == null;
}

/// A proof of one goal fact, read out of a [FactDatabase] (PLAN §M-P2c).
///
/// The edges were stored as the prover ran — every fact carries its
/// [Derivation] from the moment it was inserted — so this is a walk, not
/// a search: the backward closure of the goal over those edges, which is
/// the sub-DAG that actually supports it and nothing else the run
/// happened to derive.
///
/// **Post-order, each fact once.** Steps are emitted so that every
/// premise stands above the step using it, and a fact reached by two
/// different routes is stated once and cited twice — a shared sub-proof
/// is shared in the reading too. The walk is iterative (a deep chain is
/// data, not a reason to grow the stack) and carries an explicit cycle
/// guard that throws: acyclicity here is structural — first-insert-wins
/// plus premises-must-be-present — and the guard is the same insurance
/// `FactDatabase.add`'s premise check is, not a doubt about the
/// argument.
///
/// What a proof does **not** do is vouch for itself. Reading edges out
/// faithfully says nothing about whether each edge is a sound
/// instantiation of the rule it names; that is [verify]'s question, and
/// the reason `derivation_check.dart` exists.
class Proof {
  Proof._(this.goal, List<ProofStep> steps) : steps = List.unmodifiable(steps);

  /// Extracts the proof of [goal] from [database].
  ///
  /// Throws [ArgumentError] when [database] does not hold [goal] — a
  /// proof of an underived fact is not an empty proof, it is a question
  /// the run did not answer.
  factory Proof.of(Fact goal, FactDatabase database) {
    if (!database.contains(goal)) {
      throw ArgumentError.value(goal, 'goal', 'not in the database');
    }
    final numberOf = <Fact, int>{};
    final order = <Fact>[];
    final onStack = <Fact>{goal};
    final stack = <_Frame>[_Frame(goal, _derivationOf(goal, database))];
    while (stack.isNotEmpty) {
      final frame = stack.last;
      if (frame.nextPremise < frame.derivation.premises.length) {
        final premise = frame.derivation.premises[frame.nextPremise++];
        if (numberOf.containsKey(premise)) continue;
        if (!onStack.add(premise)) {
          throw StateError('proof of $goal cycles through $premise');
        }
        stack.add(_Frame(premise, _derivationOf(premise, database)));
        continue;
      }
      stack.removeLast();
      onStack.remove(frame.fact);
      numberOf[frame.fact] = order.length + 1;
      order.add(frame.fact);
    }
    return Proof._(goal, [
      for (final fact in order)
        ProofStep(
          number: numberOf[fact]!,
          fact: fact,
          rule: database.derivationOf(fact)!.rule,
          premiseSteps: [
            for (final premise in database.derivationOf(fact)!.premises)
              numberOf[premise]!,
          ],
          chase: database.derivationOf(fact)!.rule == angleArithmeticRule
              ? AngleChase.of(fact, database.derivationOf(fact)!.premises)
              : null,
        ),
    ]);
  }

  static Derivation _derivationOf(Fact fact, FactDatabase database) {
    final derivation = database.derivationOf(fact);
    if (derivation == null) {
      throw StateError(
        '$fact has no derivation, so the database is not closed',
      );
    }
    return derivation;
  }

  final Fact goal;

  /// Every step, premises before conclusions; the last is [goal]'s.
  final List<ProofStep> steps;

  /// The hypotheses the proof rests on — what the construction gave it.
  Iterable<ProofStep> get givens => steps.where((step) => step.isGiven);

  /// The steps a rule produced.
  Iterable<ProofStep> get deductions => steps.where((step) => !step.isGiven);

  /// Every deduction re-matched against the rule it names, answering the
  /// reasons the failures failed — **empty exactly when the proof is a
  /// certificate** rather than a transcript. See
  /// [checkDerivation] for what is checked and why the numeric filter
  /// cannot check it.
  ///
  /// A non-empty answer is a prover defect, never a user-facing state,
  /// which is why the reasons are strings: they are read by a test or a
  /// developer, not rendered.
  List<String> verify({List<Rule>? rules}) => [
    for (final step in deductions)
      ...() {
        final check = checkDerivation(
          step.fact,
          Derivation(step.rule!, [
            for (final number in step.premiseSteps) steps[number - 1].fact,
          ]),
          rules: rules,
        );
        return check.isValid
            ? const <String>[]
            : ['step ${step.number}: ${check.reason}'];
      }(),
  ];

  /// The step each fact is stated at, which is what a citation is.
  Map<Fact, int> get numbering => {
    for (final step in steps) step.fact: step.number,
  };

  /// The proof as a numbered statement/reason list, points named the way
  /// the figure names them.
  ///
  /// An `angle_arithmetic` step is followed by its chase, indented: the
  /// rule name is the explanation everywhere else, and there it is a
  /// label for a sum the reader cannot see. See [AngleChase].
  String render() {
    final lines = <String>[];
    final statements = [for (final step in steps) describeFact(step.fact)];
    final width = statements.fold(0, (w, s) => s.length > w ? s.length : w);
    final numberOf = numbering;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final reason = step.isGiven
          ? 'given'
          : '${step.rule} from '
                '${step.premiseSteps.map((n) => '[$n]').join(', ')}';
      lines.add('  [${step.number}] ${statements[i].padRight(width)}  $reason');
      final chase = step.chase;
      if (chase != null) {
        for (final line in chase.render(cite: (fact) => numberOf[fact])) {
          lines.add('        $line');
        }
      }
    }
    final givenCount = givens.length;
    final derivedCount = steps.length - givenCount;
    return [
      'Proof of ${describeFact(goal)} — '
          '$givenCount given, '
          '$derivedCount ${derivedCount == 1 ? 'deduction' : 'deductions'}',
      ...lines,
    ].join('\n');
  }

  @override
  String toString() => render();
}

class _Frame {
  _Frame(this.fact, this.derivation);

  final Fact fact;
  final Derivation derivation;
  int nextPremise = 0;
}
