import 'rational.dart';

/// One linear relation between line directions:
/// `Σ cᵥ·θᵥ ≡ constant (mod π)`, with the constant measured **in units
/// of π** so that "mod π" is [Rational.modOne].
///
/// The vocabulary maps onto this and nothing else (PLAN §M-P3):
/// `para(l₁,l₂)` is `θ₁ − θ₂ ≡ 0`, `perp(l₁,l₂)` is `θ₁ − θ₂ ≡ ½`, and
/// `eqangle` on four lines is `−θ_ab + θ_cd + θ_ef − θ_gh ≡ 0`. Chasles
/// needs no statement at all: it is what addition of these rows *is*.
///
/// **The coefficients are integers, and that is a soundness requirement
/// rather than a convenience.** Each θ is defined only modulo π, so a
/// form `Σ cᵥ·θᵥ` denotes anything at all only when every `cᵥ` is a
/// whole number — a coefficient of ½ turns an ambiguity of π into an
/// ambiguity of π/2, which is not the same statement written twice but
/// two different statements. See [AngleClosure] for what that costs the
/// elimination.
///
/// Canonical: zero coefficients are dropped, the variables are ordered,
/// and the constant is reduced into `[0, 1)`. So `==` is equality of
/// statements and two spellings of one relation are one value.
class AngleEquation {
  /// Drops zero coefficients, orders the variables and reduces the
  /// constant mod 1.
  factory AngleEquation(Map<String, BigInt> coefficients, Rational constant) {
    final keys = [
      for (final entry in coefficients.entries)
        if (entry.value != BigInt.zero) entry.key,
    ]..sort();
    return AngleEquation._({
      for (final key in keys) key: coefficients[key]!,
    }, constant.modOne());
  }

  const AngleEquation._(this.coefficients, this.constant);

  /// `θ[first] − θ[second] ≡ constant`, the shape every predicate in the
  /// angle vocabulary reduces to pairwise.
  factory AngleEquation.difference(
    String first,
    String second,
    Rational constant,
  ) => AngleEquation({first: BigInt.one, second: -BigInt.one}, constant);

  /// Non-zero coefficients only, in variable order.
  final Map<String, BigInt> coefficients;

  /// In units of π, always in `[0, 1)`.
  final Rational constant;

  /// The variable this equation leads with — null when it has none left,
  /// which is either [isTrivial] or [isContradiction].
  String? get leading => coefficients.isEmpty ? null : coefficients.keys.first;

  /// `0 ≡ 0` — says nothing, and is what a fully reduced entailment
  /// arrives at.
  bool get isTrivial => coefficients.isEmpty && constant.isZero;

  /// `0 ≡ k` for non-zero `k`. Not a statement about any line: the
  /// premises that produced it are inconsistent.
  bool get isContradiction => coefficients.isEmpty && !constant.isZero;

  AngleEquation operator +(AngleEquation other) {
    final sum = <String, BigInt>{...coefficients};
    for (final entry in other.coefficients.entries) {
      sum[entry.key] = (sum[entry.key] ?? BigInt.zero) + entry.value;
    }
    return AngleEquation(sum, constant + other.constant);
  }

  AngleEquation operator -(AngleEquation other) => this + -other;

  AngleEquation operator -() => scaled(-BigInt.one);

  /// This relation taken [factor] times over. Integer only — see the
  /// class comment, and [AngleClosure] for why there is no `/`.
  AngleEquation scaled(BigInt factor) => AngleEquation({
    for (final entry in coefficients.entries) entry.key: entry.value * factor,
  }, constant.scaled(factor));

  @override
  bool operator ==(Object other) {
    if (other is! AngleEquation ||
        other.constant != constant ||
        other.coefficients.length != coefficients.length) {
      return false;
    }
    for (final entry in coefficients.entries) {
      if (other.coefficients[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    constant,
    Object.hashAll([
      for (final entry in coefficients.entries) ...[entry.key, entry.value],
    ]),
  );

  @override
  String toString() {
    if (coefficients.isEmpty) return '0 = $constant';
    final terms = [
      for (final entry in coefficients.entries)
        '${entry.value == BigInt.one
            ? ''
            : entry.value == -BigInt.one
            ? '-'
            : entry.value}${entry.key}',
    ];
    return '${terms.join(' + ')} = $constant';
  }
}

/// What [AngleClosure.add] did with an equation.
enum AngleAddOutcome {
  /// Already entailed — the closure learned nothing.
  redundant,

  /// New information; the closure grew.
  added,

  /// Together with what was already here, this says `0 ≡ k` for a
  /// non-zero `k`. The premises are inconsistent, which for a screened
  /// diagram means a bug upstream rather than a document.
  contradiction,
}

/// The closure of a set of [AngleEquation]s under **integer** linear
/// combination (PLAN §"AR is a ℤ-module, not a ℚ-vector space").
///
/// This is the AR half of DDAR for angles, and the thing it is not is a
/// Gaussian elimination. Rows are kept in echelon form by *lattice*
/// reduction: a row is never divided by its own leading coefficient, and
/// two rows are combined through the extended gcd instead. Entailment is
/// membership in the ℤ-span of the inputs, not in their ℚ-span.
///
/// **The difference is a wrong answer, and it is two facts deep.** Take
/// `eqangle` saying `∠(l₁,l₂) = ∠(l₃,l₄)` and another saying
/// `∠(l₁,l₂) = ∠(l₄,l₃)`. As rows those are `−θ₁ + θ₂ + θ₃ − θ₄ ≡ 0`
/// and `−θ₁ + θ₂ − θ₃ + θ₄ ≡ 0`, and their sum is `2θ₂ − 2θ₁ ≡ 0`. Over
/// ℚ the pivot divides by two and concludes `para(l₁,l₂)`. What the
/// relation actually says is `2·∠(l₁,l₂) ≡ 0 (mod π)`, so `∠(l₁,l₂)` is
/// `0` **or** `π/2`: the lines are parallel or perpendicular, and a real
/// figure can be either. Rational elimination turns a disjunction into a
/// theorem, and the numeric screen would pass it on any diagram that
/// happens to sit on the parallel branch.
///
/// So a `2θ` row is kept — it is perfectly good input for further
/// combination — and nothing is published from it. Reading the branch
/// off the diagram is deliberately not done: DD's filter screens a
/// conclusion that is *already entailed*, and using it to choose between
/// two possible worlds is a weaker act wearing the same clothes. The
/// disjunction is a known incompleteness, not a shortcut taken.
///
/// **Every row carries its provenance**, on the `FactDatabase`
/// precedent and for the same reason: a proof must be able to name what
/// a step came from, and retrofitting that is a rewrite. [entails]
/// answers *how* — the integer combination of input equations that
/// yields the target — and [recombine] re-multiplies it, so verifying an
/// AR step is arithmetic rather than search.
class AngleClosure {
  /// The equations as they were given, in order. A certificate indexes
  /// into this list.
  final List<AngleEquation> inputs = [];

  /// Pivot variable → the row that leads with it. Every row contains
  /// only variables at or after its pivot, and its pivot coefficient is
  /// positive; that invariant is what makes [entails] a single downward
  /// pass.
  final Map<String, _Row> _rows = {};

  /// The rows in echelon order — the closure's own basis, which is not
  /// the input set and is usually smaller.
  Iterable<AngleEquation> get rows {
    final keys = _rows.keys.toList()..sort();
    return [for (final key in keys) _rows[key]!.equation];
  }

  int get rank => _rows.length;

  /// Whether an inconsistency has been recorded.
  bool get isInconsistent => _inconsistent;
  bool _inconsistent = false;

  /// Records [equation] and answers what it did.
  ///
  /// The equation joins [inputs] whatever the outcome — a certificate
  /// names inputs by position, so positions must not shift, and a
  /// redundant premise is still a premise the caller supplied.
  AngleAddOutcome add(AngleEquation equation) {
    final index = inputs.length;
    inputs.add(equation);
    var current = equation;
    var support = <int, BigInt>{index: BigInt.one};

    while (true) {
      final variable = current.leading;
      if (variable == null) {
        if (current.constant.isZero) return AngleAddOutcome.redundant;
        _inconsistent = true;
        return AngleAddOutcome.contradiction;
      }
      final row = _rows[variable];
      if (row == null) {
        _rows[variable] = _Row(
          _madePositive(current),
          _sign(current) < 0 ? _negate(support) : support,
        );
        return AngleAddOutcome.added;
      }
      final mine = current.coefficients[variable]!;
      final theirs = row.equation.coefficients[variable]!;
      if (mine % theirs == BigInt.zero) {
        final factor = mine ~/ theirs;
        current = current - row.equation.scaled(factor);
        support = _combine(support, row.support, -factor);
        continue;
      }
      // Neither divides the other: the lattice's generator at this
      // variable is their gcd, and Bézout says which combination
      // reaches it. This is the step Gaussian elimination replaces with
      // a division, and the step that keeps every coefficient whole.
      //
      // The continuation must be the *complement* — `(theirs/g)·current
      // − (mine/g)·old` — so that the pair (replacement, complement)
      // is a determinant −1 transformation of (current, old) and the
      // rows keep generating the whole input lattice. Continuing with
      // `current − (mine/g)·replacement` instead has determinant −y:
      // the basis silently shrinks to a sublattice, later [entails]
      // calls answer false noes for combinations that exist over the
      // inputs, and the verifier reports sound angle steps as unsound
      // (found on `regular_hexagon`, Phase 179 — the certificate
      // scaled two perps by 4 and 2, wiping their halves mod 1).
      final (x, y) = _extendedGcd(mine, theirs);
      final gcd = x * mine + y * theirs;
      final replacement = current.scaled(x) + row.equation.scaled(y);
      final replacementSupport = _combine(_scale(support, x), row.support, y);
      _rows[variable] = _Row(replacement, replacementSupport);
      current =
          current.scaled(theirs ~/ gcd) - row.equation.scaled(mine ~/ gcd);
      support = _combine(
        _scale(support, theirs ~/ gcd),
        row.support,
        -(mine ~/ gcd),
      );
    }
  }

  /// The integer combination of [inputs] that yields [equation], or null
  /// when it is not in their ℤ-span.
  ///
  /// An empty map is a valid answer and means `0 ≡ 0` — the trivial
  /// equation follows from nothing. Nothing here mutates the closure: a
  /// question is not an assertion, and a target that *cannot* be reduced
  /// must not quietly extend the basis on its way to being refused.
  Map<int, BigInt>? entails(AngleEquation equation) {
    var current = equation;
    var used = <int, BigInt>{};
    while (true) {
      final variable = current.leading;
      if (variable == null) {
        return current.constant.isZero ? used : null;
      }
      final row = _rows[variable];
      if (row == null) return null;
      final mine = current.coefficients[variable]!;
      final theirs = row.equation.coefficients[variable]!;
      // The divisibility test *is* the ℤ/ℚ distinction: `θ₁ − θ₂` is not
      // a consequence of `2θ₁ − 2θ₂`, and this is where it is refused.
      if (mine % theirs != BigInt.zero) return null;
      final factor = mine ~/ theirs;
      current = current - row.equation.scaled(factor);
      used = _combine(used, row.support, factor);
    }
  }

  /// Whether [equation] follows — [entails] without the certificate.
  bool proves(AngleEquation equation) => entails(equation) != null;

  /// The equation a [certificate] denotes: `Σ cᵢ·inputs[i]`.
  ///
  /// The other half of the proof obligation. `recombine(entails(e))`
  /// equals `e` whenever `entails` answered, so re-checking an AR step
  /// is a multiplication and not a search — which is what earns AR a
  /// place where Wu and Gröbner were refused for unreadable proofs.
  ///
  /// Throws [RangeError] on an index no input holds.
  AngleEquation recombine(Map<int, BigInt> certificate) {
    var total = AngleEquation(const {}, Rational.zero);
    for (final entry in certificate.entries) {
      if (entry.key < 0 || entry.key >= inputs.length) {
        throw RangeError.index(entry.key, inputs, 'certificate');
      }
      total = total + inputs[entry.key].scaled(entry.value);
    }
    return total;
  }

  static int _sign(AngleEquation equation) =>
      equation.coefficients[equation.leading]!.sign;

  static AngleEquation _madePositive(AngleEquation equation) =>
      _sign(equation) < 0 ? -equation : equation;

  static Map<int, BigInt> _negate(Map<int, BigInt> support) =>
      _scale(support, -BigInt.one);

  static Map<int, BigInt> _scale(Map<int, BigInt> support, BigInt factor) => {
    for (final entry in support.entries)
      if (entry.value * factor != BigInt.zero) entry.key: entry.value * factor,
  };

  /// `into + factor · addend`, dropping cancelled terms so a certificate
  /// never cites an input with coefficient zero.
  static Map<int, BigInt> _combine(
    Map<int, BigInt> into,
    Map<int, BigInt> addend,
    BigInt factor,
  ) {
    final out = <int, BigInt>{...into};
    for (final entry in addend.entries) {
      final value = (out[entry.key] ?? BigInt.zero) + entry.value * factor;
      if (value == BigInt.zero) {
        out.remove(entry.key);
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

  /// `(x, y)` with `x·a + y·b = gcd(a, b) > 0`.
  static (BigInt, BigInt) _extendedGcd(BigInt a, BigInt b) {
    var oldR = a;
    var r = b;
    var oldS = BigInt.one;
    var s = BigInt.zero;
    var oldT = BigInt.zero;
    var t = BigInt.one;
    while (r != BigInt.zero) {
      final quotient = oldR ~/ r;
      (oldR, r) = (r, oldR - quotient * r);
      (oldS, s) = (s, oldS - quotient * s);
      (oldT, t) = (t, oldT - quotient * t);
    }
    return oldR.isNegative ? (-oldS, -oldT) : (oldS, oldT);
  }
}

class _Row {
  _Row(this.equation, this.support);

  final AngleEquation equation;

  /// The integer combination of `AngleClosure.inputs` this row is.
  final Map<int, BigInt> support;
}
