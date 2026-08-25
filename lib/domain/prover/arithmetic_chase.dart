import 'fact.dart';

/// What an AR step's explanation must be able to do, whichever algebra
/// produced it.
///
/// A DD step's rule name *is* its explanation; an AR step's is a label
/// for a sum, so the sum is what reads (PLAN §"Proofs must read"). There
/// are two such algebras — directions and lengths — and a proof holds
/// one explanation per step without caring which, so this is the type
/// `ProofStep.chase` is written in.
///
/// It is an interface and not a base class deliberately. The two chases
/// share a *shape* — scaled input rows, in citation order, summing to
/// the conclusion — and share no arithmetic: one is a ℤ-module over
/// values read mod π, the other a ℚ-vector space over log-lengths, and
/// a common superclass is one refactor away from a common closure.
abstract interface class ArithmeticChase {
  /// The relations added up, as lines of text, conclusion last.
  ///
  /// [cite] turns a premise fact into the step number a proof gives it;
  /// where it answers null the line carries no citation rather than an
  /// invented one.
  List<String> render({int? Function(Fact)? cite});

  /// The relation proved, written for a reader.
  String get conclusionText;

  /// Whether the lines really do sum to the conclusion — true by
  /// construction, and worth asserting because a rendering that quietly
  /// dropped or rescaled a line would still look like a proof.
  bool get isSound;
}
