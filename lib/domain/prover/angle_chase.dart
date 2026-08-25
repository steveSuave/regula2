import '../construction/geo_object.dart';
import 'angle_closure.dart';
import 'angle_translation.dart';
import 'arithmetic_chase.dart';
import 'fact.dart';
import 'fact_naming.dart';
import 'rational.dart';

/// An `angle_arithmetic` step written out as the angle chase it is
/// (PLAN §M-P3, and §"Proofs must read" — the reason Wu and Gröbner were
/// refused).
///
/// **The problem this exists to fix.** A DD step reads:
/// `[6] para(E, D, A, D)  midline_para from [3], [5]`, and the rule name
/// is the explanation. An AR step read
/// `[9] perp(E, A, F, C)  angle_arithmetic from [1], [2], [4], [6], [8]`,
/// which names what it used and explains nothing. The step *is* a sum of
/// relations, so what reads is the sum: one line per relation, in the
/// direction language the algebra actually works in.
///
/// **Per input, not per premise fact.** The obvious spelling — a
/// multiple beside each cited fact — cannot be written down: a `coll`
/// contributes two equations to the closure and a certificate may weight
/// them differently, so "the coefficient of step [4]" is not a number.
/// A certificate indexes *equations*, and each equation has exactly one
/// source fact, so a chase line is one equation and cites one step. Two
/// lines citing the same step is the honest rendering of that, not a
/// duplicate.
///
/// **Re-derived, never carried.** The chase is rebuilt from the recorded
/// premises the way `derivation_check.dart` rebuilds the entailment, so
/// nothing is stored on the derivation, the save format does not move,
/// and a chase that cannot be re-derived is [AngleChase.of] answering
/// null rather than a proof rendering a claim it cannot support.
class AngleChase implements ArithmeticChase {
  const AngleChase._(this.lines, this.conclusion, this._names);

  /// Rebuilds the chase for [conclusion] from [premises], or answers
  /// null when they do not entail it in the angle algebra — which is a
  /// prover defect, and the same one `Proof.verify` reports.
  static AngleChase? of(Fact conclusion, List<Fact> premises) {
    final translation = AngleTranslation();
    for (final premise in premises) {
      translation.absorb(premise);
    }
    final target = translation.equationOf(conclusion);
    if (target == null) return null;
    final certificate = translation.closure.entails(target);
    if (certificate == null) return null;
    final indices = certificate.keys.toList()..sort();
    final lines = [
      for (final index in indices)
        AngleChaseLine._(
          translation.closure.inputs[index].scaled(certificate[index]!),
          certificate[index]!,
          translation.sources[index],
        ),
    ];
    final variables = <String>{
      ...target.coefficients.keys,
      for (final line in lines) ...line.equation.coefficients.keys,
    };
    return AngleChase._(
      List.unmodifiable(lines),
      target,
      _nameVariables(variables, translation),
    );
  }

  /// The relations added up, in certificate order. Each is the input
  /// equation **already multiplied** by the certificate's coefficient,
  /// so the lines sum to [conclusion] as they are read.
  final List<AngleChaseLine> lines;

  /// The relation proved — the row form of the step's fact.
  final AngleEquation conclusion;

  final Map<String, String> _names;

  /// [conclusion] written for a reader.
  @override
  String get conclusionText => renderAngleEquation(conclusion, _names);

  /// The chase as lines of text, conclusion last.
  ///
  /// [cite] turns a premise fact into the step number a proof gives it;
  /// without it — or where it answers null, which no well-formed proof
  /// should reach — the line carries no citation rather than an invented
  /// one.
  ///
  /// Given [cite], the lines are read out in **citation order**. A proof
  /// is a numbered list whose citations point upwards, and a chase read
  /// against it should not make the eye jump back; certificate order is
  /// insertion order, which is nearly that and not reliably that. Ties
  /// keep their certificate order, which is what makes the two lines a
  /// single `coll` contributes come out in the order it states them.
  @override
  List<String> render({int? Function(Fact)? cite}) {
    final ordered = [for (var i = 0; i < lines.length; i++) i];
    if (cite != null) {
      final at = [for (final line in lines) cite(line.source)];
      ordered.sort((a, b) {
        final byStep = (at[a] ?? 1 << 30).compareTo(at[b] ?? 1 << 30);
        return byStep != 0 ? byStep : a.compareTo(b);
      });
    }
    return [
      for (final index in ordered)
        switch (cite?.call(lines[index].source)) {
          final int number =>
            '${renderAngleEquation(lines[index].equation, _names)}  [$number]',
          null => renderAngleEquation(lines[index].equation, _names),
        },
      '⟹ $conclusionText',
    ];
  }

  /// Whether the lines really do sum to [conclusion].
  ///
  /// True by construction — the certificate came from `entails` and
  /// `recombine` is its inverse — which is exactly why it is worth
  /// asserting: a rendering that quietly dropped or rescaled a line
  /// would still look like a proof.
  @override
  bool get isSound {
    var total = AngleEquation(const {}, Rational.zero);
    for (final line in lines) {
      total = total + line.equation;
    }
    return total == conclusion;
  }

  @override
  String toString() => render().join('\n');

  /// Variable → the pair of point names to write inside `θ(…)`.
  ///
  /// The separator is decided once per chase rather than per pair: with
  /// every point a single letter the geometric spelling `θ(AB)` is what
  /// a reader expects, and with ids like `mab` in play it would run two
  /// names together into a third. One rendering must not mix the two.
  static Map<String, String> _nameVariables(
    Set<String> variables,
    AngleTranslation translation,
  ) {
    final pairs = <String, (GeoPoint, GeoPoint)>{};
    for (final variable in variables) {
      final pair = translation.pairFor(variable);
      if (pair != null) pairs[variable] = pair;
    }
    final names = [
      for (final pair in pairs.values) ...[
        describePoint(pair.$1),
        describePoint(pair.$2),
      ],
    ];
    final separator = names.every((name) => name.length == 1) ? '' : ',';
    return {
      for (final variable in variables)
        variable: pairs.containsKey(variable)
            ? '${describePoint(pairs[variable]!.$1)}$separator'
                  '${describePoint(pairs[variable]!.$2)}'
            : variable,
    };
  }
}

/// One relation in a chase: the multiple of an input equation the step
/// used, and the fact that stated it.
class AngleChaseLine {
  const AngleChaseLine._(this.equation, this.multiple, this.source);

  /// The addend — the source's equation times [multiple].
  final AngleEquation equation;

  /// How many times the step took the source relation. Negative reads as
  /// the relation used backwards, which is what a swapped side is.
  final BigInt multiple;

  /// The fact the equation came from. Two lines may share one: a `coll`
  /// states more than one relation.
  final Fact source;

  @override
  String toString() => '$multiple × $equation from $source';
}

/// `Σ cᵥθᵥ ≡ k (mod π)` as a reader would write it: everything with a
/// positive coefficient on the left, everything else on the right, and
/// the constant in units of π.
///
/// So `θ₁ − θ₂ ≡ 0` reads `θ(AB) = θ(CD)`, `θ₁ − θ₂ ≡ ½` reads
/// `θ(AB) = θ(CD) + π/2`, and an `eqangle`'s four terms split two and
/// two. The mod-π qualifier is not repeated on every line — it is a
/// property of the whole algebra, stated once where the chase is
/// introduced.
String renderAngleEquation(AngleEquation equation, Map<String, String> names) {
  final left = <String>[];
  final right = <String>[];
  for (final entry in equation.coefficients.entries) {
    final term = _term(entry.value.abs(), names[entry.key] ?? entry.key);
    (entry.value.isNegative ? right : left).add(term);
  }
  final constant = _piMultiple(equation.constant);
  if (constant.isNotEmpty) right.add(constant);
  return '${left.isEmpty ? '0' : left.join(' + ')} = '
      '${right.isEmpty ? '0' : right.join(' + ')}';
}

String _term(BigInt magnitude, String name) =>
    [if (magnitude != BigInt.one) '$magnitude', 'θ($name)'].join();

/// A constant in `[0, 1)` units of π, written as an angle. Empty for
/// zero, which is a term a reader should not have to see.
String _piMultiple(Rational constant) {
  if (constant.isZero) return '';
  return [
    if (constant.numerator != BigInt.one) '${constant.numerator}',
    'π',
    if (constant.denominator != BigInt.one) '/${constant.denominator}',
  ].join();
}
