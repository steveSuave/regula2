import '../construction/geo_object.dart';
import 'arithmetic_chase.dart';
import 'fact.dart';
import 'fact_naming.dart';
import 'length_closure.dart';
import 'length_translation.dart';
import 'rational.dart';

/// A `length_arithmetic` step written out as the chase it is — the
/// length half of `AngleChase`, and its three decisions carried over
/// unchanged: citation order, one separator decided per chase, and a
/// scaled row shown already scaled.
///
/// **The rendering is multiplicative, and that decision is the one this
/// class had to make.** The rows are over log-lengths, so a reader shown
/// `log|AM| + log|AB| = 2·log|AO|` is being shown the implementation.
/// Exponentiating gives `|AM|·|AB| = |AO|^2`, which is the same
/// statement in the quantity a geometer actually has — the exact
/// counterpart of the angle side rendering in θ rather than in rows.
///
/// **Why not ratios, when `eqratio` is the input.** A stored
/// `|AB|/|CD| = |EF|/|GH|` reads more naturally as a ratio than as the
/// cross-multiplied `|AB|·|GH| = |CD|·|EF|`, and for that one shape it
/// would. But a chase line is an arbitrary ℚ-combination of rows —
/// `l_AM − 2·l_AO + l_AB = 0` is a real line from `provoleas2` — and a
/// row with three positive terms and one negative has no canonical split
/// into two ratios. A rendering that is a ratio when it can be and a
/// product when it cannot is two notations in one chase, which is the
/// mistake the separator decision exists to avoid. So: products
/// throughout, and `eqratio` reads cross-multiplied.
///
/// That settles the character question too. The spelling is `|`, `=`,
/// `^`, ASCII digits and `/` inside an exponent, plus `·` and the `⟹`
/// the angle chase already uses — **no fraction slash**, because there
/// are no fractions to slash. Pinned on the browser gate beside the
/// angle chase's glyphs.
///
/// **Re-derived, never carried**, exactly as next door: the chase is
/// rebuilt from the recorded premises, nothing is stored on the
/// derivation, the save format does not move, and a chase that cannot be
/// re-derived is [LengthChase.of] answering null rather than a proof
/// rendering a claim it cannot support.
class LengthChase implements ArithmeticChase {
  const LengthChase._(this.lines, this.conclusion, this._names);

  /// Rebuilds the chase for [conclusion] from [premises], or answers
  /// null when they do not entail it in the length algebra — which is a
  /// prover defect, and the same one `Proof.verify` reports.
  static LengthChase? of(Fact conclusion, List<Fact> premises) {
    final translation = LengthTranslation();
    for (final premise in premises) {
      translation.absorb(premise);
    }
    final target = translation.equationOf(conclusion);
    if (target == null || target.isTrivial) return null;
    final certificate = translation.closure.entails(target);
    if (certificate == null) return null;
    final indices = certificate.keys.toList()..sort();
    final lines = [
      for (final index in indices)
        LengthChaseLine._(
          translation.closure.inputs[index].scaled(certificate[index]!),
          certificate[index]!,
          translation.sources[index],
        ),
    ];
    final variables = <String>{
      ...target.variables,
      for (final line in lines) ...line.equation.variables,
    };
    return LengthChase._(
      List.unmodifiable(lines),
      target,
      _nameVariables(variables, translation),
    );
  }

  /// The relations multiplied together, in certificate order. Each is
  /// the input equation **already scaled** by the certificate's
  /// coefficient, so the lines sum to [conclusion] as they are read.
  final List<LengthChaseLine> lines;

  /// The relation proved — the row form of the step's fact.
  final LengthEquation conclusion;

  final Map<String, String> _names;

  /// [conclusion] written for a reader.
  @override
  String get conclusionText => renderLengthEquation(conclusion, _names);

  /// The chase as lines of text, conclusion last.
  ///
  /// Given [cite], the lines are read out in **citation order**, on
  /// `AngleChase.render`'s reasoning: a proof is a numbered list whose
  /// citations point upwards, and a chase read against it should not
  /// make the eye jump back. Ties keep their certificate order.
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
            '${renderLengthEquation(lines[index].equation, _names)}'
                '  [$number]',
          null => renderLengthEquation(lines[index].equation, _names),
        },
      '⟹ $conclusionText',
    ];
  }

  /// Whether the lines really do sum to [conclusion].
  @override
  bool get isSound {
    var total = LengthEquation(const {});
    for (final line in lines) {
      total = total + line.equation;
    }
    return total == conclusion;
  }

  @override
  String toString() => render().join('\n');

  /// Variable → the pair of point names to write inside `|…|`.
  ///
  /// The separator is decided once per chase rather than per pair, the
  /// angle chase's rule and for its reason: with every point a single
  /// letter `|AB|` is what a reader expects, and with ids like `mab` in
  /// play it would run two names together into a third.
  static Map<String, String> _nameVariables(
    Set<String> variables,
    LengthTranslation translation,
  ) {
    final pairs = <String, (GeoPoint, GeoPoint)>{};
    for (final variable in variables) {
      final ends = translation.endsOf(variable);
      if (ends != null) pairs[variable] = ends;
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
class LengthChaseLine {
  const LengthChaseLine._(this.equation, this.multiple, this.source);

  /// The addend — the source's equation times [multiple].
  final LengthEquation equation;

  /// How many times the step took the source relation. Negative reads as
  /// the relation used backwards, which is what a swapped side is; a
  /// fraction is the ℚ elimination's own, and has no counterpart on the
  /// angle side, where the multiple is an integer by construction.
  final Rational multiple;

  /// The fact the equation came from.
  final Fact source;

  @override
  String toString() => '$multiple × $equation from $source';
}

/// `Σ cᵥ·lᵥ + Σ kₚ·ln p = 0` as a reader would write it: exponentiated,
/// so that everything with a positive coefficient multiplies out on the
/// left and everything else on the right.
///
/// So `l₁ − l₂ = 0` reads `|AB| = |CD|`, an `eqratio`'s four terms read
/// cross-multiplied as `|AB|·|GH| = |CD|·|EF|`, and a coefficient other
/// than 1 becomes an exponent: `|AO|^2`, or `|AO|^1/2` where the
/// elimination halved a row.
///
/// The constant column exponentiates to a plain number and leads its
/// side — `l_ab − l_ma − ln 2 = 0` reads `|AB| = 2·|MA|`, the way a
/// geometer writes a stated ratio. Whole prime exponents multiply out
/// into one number per side; a fractional exponent — a ℚ-scaled row —
/// stays symbolic as `2^1/2`, exactly like a segment's.
///
/// A side with no factor at all renders as `1`, the empty product —
/// unreachable from the homogeneous vocabulary, whose coefficients sum
/// to zero, but exactly right for a stated length: `lconst`'s
/// `|AB| = 3/2` has row `l_ab − ln 3 + ln 2 = 0` and reads
/// `2·|AB| = 3`, and at value 1 the row is `l_ab = 0`, read `|AB| = 1`.
String renderLengthEquation(
  LengthEquation equation,
  Map<String, String> names,
) {
  final left = <String>[];
  final right = <String>[];
  var leftNumber = BigInt.one;
  var rightNumber = BigInt.one;
  final cap = BigInt.from(64);
  for (final entry in equation.constant.entries) {
    final exponent = entry.value.abs;
    if (exponent.denominator == BigInt.one && exponent.numerator <= cap) {
      final power = entry.key.pow(exponent.numerator.toInt());
      if (entry.value.isNegative) {
        rightNumber *= power;
      } else {
        leftNumber *= power;
      }
    } else {
      (entry.value.isNegative ? right : left).add('${entry.key}^$exponent');
    }
  }
  if (leftNumber != BigInt.one) left.insert(0, '$leftNumber');
  if (rightNumber != BigInt.one) right.insert(0, '$rightNumber');
  for (final entry in equation.coefficients.entries) {
    final term = _factor(entry.value.abs, names[entry.key] ?? entry.key);
    (entry.value.isNegative ? right : left).add(term);
  }
  return '${left.isEmpty ? '1' : left.join('·')} = '
      '${right.isEmpty ? '1' : right.join('·')}';
}

String _factor(Rational exponent, String name) =>
    exponent == Rational.one ? '|$name|' : '|$name|^$exponent';
