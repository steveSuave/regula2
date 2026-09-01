import '../math/rational.dart';

/// One linear relation between segment log-lengths:
/// `Σ cᵥ·lᵥ + Σ kₚ·ln p = 0`, where `lᵥ = log|v|` for a segment `v` and
/// `p` ranges over the primes the constant mentions.
///
/// **Logarithms are what make the vocabulary linear.** `cong` and
/// `eqratio` are multiplicative statements about lengths — `|ab| = |cd|`
/// and `|ab|/|cd| = |ef|/|gh|` — and taking logs turns both into
/// differences: `l_ab − l_cd = 0` and `l_ab − l_cd − l_ef + l_gh = 0`.
/// `midp(m,a,b)` contributes the equal halves, `l_ma − l_mb = 0`; the
/// 1:2 it also states is a constant-carrying row, [rconst]'s business.
///
/// **The [constant] column is a formal ℚ-vector over `{ln p : p prime}`,
/// never a rational number** (Phase 181, reversing Phase 165's
/// omission). A stated ratio or length — `|ab|/|cd| = 2`, `|ab|= 3/2` —
/// is not scale-invariant, so its row carries `ln` of the value; and
/// that constant must survive the ℚ-row-scaling this class exists to
/// allow. A rational *number* cannot: halving the row would turn `ln 2`
/// into `ln √2`, which is no rational's logarithm. As the exponent
/// vector `{2: 1}` it halves to `{2: ½}` exactly. Unique factorization
/// makes `{ln p}` linearly independent over ℚ, so a row whose variables
/// have all cancelled while its constant has not is a genuine `0 = k`,
/// `k ≠ 0` — [isContradictory] — and the system is inconsistency-capable
/// where its homogeneous predecessor was not.
///
/// **The coefficients are rationals, and that is the whole difference
/// from `AngleEquation`.** A log-length is a real number with no
/// modulus, so `2·l₁ = 2·l₂` says `|ab| = |cd|` and dividing a row by
/// its leading coefficient loses nothing. The angle system may not do
/// that — halving a relation read mod π turns a disjunction into a
/// theorem (PLAN §"AR is a ℤ-module, not a ℚ-vector space") — and the
/// two classes are separate files for exactly that reason. Nothing here
/// may be shared with the angle side, because a ℚ pivot reaching θ is a
/// soundness bug that no test on this side would see.
///
/// Canonical: zero coefficients are dropped and the variables are
/// ordered. So `==` is equality of relations up to spelling — though
/// *not* up to scale: `l₁ − l₂ = 0` and `2l₁ − 2l₂ = 0` are the same
/// statement and different values, and it is [LengthClosure] that knows
/// they are interderivable.
class LengthEquation {
  /// Drops zero coefficients and zero constant entries, and orders both.
  ///
  /// Takes the maps as given, so a caller building a row that mentions a
  /// variable twice wants [LengthEquation.fromTerms] instead.
  factory LengthEquation(
    Map<String, Rational> coefficients, {
    Map<BigInt, Rational> constant = const {},
  }) {
    final keys = [
      for (final entry in coefficients.entries)
        if (!entry.value.isZero) entry.key,
    ]..sort();
    final primes = [
      for (final entry in constant.entries)
        if (!entry.value.isZero) entry.key,
    ]..sort();
    return LengthEquation._(
      {for (final key in keys) key: coefficients[key]!},
      {for (final prime in primes) prime: constant[prime]!},
    );
  }

  const LengthEquation._(this.coefficients, this.constant);

  /// Sums [terms] by variable, so a repeated variable adds up rather
  /// than overwriting.
  ///
  /// The vocabulary needs this: `|ab|/|cd| = |ab|/|ef|` is a perfectly
  /// ordinary `eqratio` whose row is `−l_cd + l_ef = 0`, and a map
  /// literal would have silently kept one `l_ab` and dropped the other.
  factory LengthEquation.fromTerms(
    Iterable<(String, Rational)> terms, {
    Map<BigInt, Rational> constant = const {},
  }) {
    final sum = <String, Rational>{};
    for (final (variable, coefficient) in terms) {
      sum[variable] = (sum[variable] ?? Rational.zero) + coefficient;
    }
    return LengthEquation(sum, constant: constant);
  }

  /// `l[first] − l[second] = 0` — what both `cong` and the equal halves
  /// of a `midp` reduce to.
  factory LengthEquation.difference(String first, String second) =>
      LengthEquation.fromTerms([
        (first, Rational.one),
        (second, -Rational.one),
      ]);

  /// `|first|/|second| = |third|/|fourth|`, i.e.
  /// `l₁ − l₂ − l₃ + l₄ = 0`.
  factory LengthEquation.eqratio(
    String first,
    String second,
    String third,
    String fourth,
  ) => LengthEquation.fromTerms([
    (first, Rational.one),
    (second, -Rational.one),
    (third, -Rational.one),
    (fourth, Rational.one),
  ]);

  /// `|first|/|second| = ratio`, i.e. `l₁ − l₂ − ln(ratio) = 0` — the
  /// row an `rconst` states. Throws [ArgumentError] unless [ratio] is
  /// positive.
  ///
  /// The same segment on both sides is allowed and means what it says:
  /// `|ab|/|ab| = q` is trivial at `q = 1` and [isContradictory] at any
  /// other value.
  factory LengthEquation.rconst(String first, String second, Rational ratio) =>
      LengthEquation.fromTerms([
        (first, Rational.one),
        (second, -Rational.one),
      ], constant: _negated(logOf(ratio)));

  /// `|segment| = value`, i.e. `l − ln(value) = 0` — the row an `lconst`
  /// states. Throws [ArgumentError] unless [value] is positive.
  factory LengthEquation.lconst(String segment, Rational value) =>
      LengthEquation.fromTerms([
        (segment, Rational.one),
      ], constant: _negated(logOf(value)));

  /// The formal `ln` of a positive rational, as prime → exponent:
  /// `12/5 → {2: 2, 3: 1, 5: −1}`, and `1 → {}` since `ln 1 = 0`.
  ///
  /// Exact by unique factorization, which is also what makes the vectors
  /// ℚ-linearly independent across primes. Throws [ArgumentError] on
  /// zero or a negative — a length or ratio has no logarithm there, and
  /// the caller screening its input is the same contract
  /// `LengthTranslation` already applies to zero-length segments.
  static Map<BigInt, Rational> logOf(Rational value) {
    if (value.isZero || value.isNegative) {
      throw ArgumentError.value(value, 'value', 'ln needs a positive value');
    }
    final exponents = <BigInt, int>{};
    void factor(BigInt n, int sign) {
      var remaining = n;
      var prime = BigInt.two;
      while (prime * prime <= remaining) {
        while (remaining % prime == BigInt.zero) {
          exponents[prime] = (exponents[prime] ?? 0) + sign;
          remaining ~/= prime;
        }
        prime += prime == BigInt.two ? BigInt.one : BigInt.two;
      }
      if (remaining > BigInt.one) {
        exponents[remaining] = (exponents[remaining] ?? 0) + sign;
      }
    }

    factor(value.numerator, 1);
    factor(value.denominator, -1);
    final primes = [
      for (final entry in exponents.entries)
        if (entry.value != 0) entry.key,
    ]..sort();
    return {
      for (final prime in primes) prime: Rational.whole(exponents[prime]!),
    };
  }

  static Map<BigInt, Rational> _negated(Map<BigInt, Rational> constant) => {
    for (final entry in constant.entries) entry.key: -entry.value,
  };

  /// Non-zero coefficients only, in variable order.
  final Map<String, Rational> coefficients;

  /// The constant column: non-zero coefficients of `ln p` only, in
  /// prime order. Empty on every row the homogeneous vocabulary states.
  final Map<BigInt, Rational> constant;

  /// The variable this equation leads with — null exactly when it is
  /// [isTrivial].
  String? get leading => coefficients.isEmpty ? null : coefficients.keys.first;

  /// `0 = 0` — says nothing, and is what a fully reduced entailment
  /// arrives at. An empty row that kept a constant is [isContradictory]
  /// instead, never this.
  bool get isTrivial => coefficients.isEmpty && constant.isEmpty;

  /// `0 = k` for a non-zero `k` — every variable cancelled and a
  /// constant survived. `{ln p}` being ℚ-linearly independent (unique
  /// factorization), a non-empty constant is a non-zero real, so this
  /// relation is satisfied by nothing.
  bool get isContradictory => coefficients.isEmpty && constant.isNotEmpty;

  /// The variables this relation mentions, in order.
  Iterable<String> get variables => coefficients.keys;

  LengthEquation operator +(LengthEquation other) {
    final sum = <String, Rational>{...coefficients};
    for (final entry in other.coefficients.entries) {
      sum[entry.key] = (sum[entry.key] ?? Rational.zero) + entry.value;
    }
    final constantSum = <BigInt, Rational>{...constant};
    for (final entry in other.constant.entries) {
      constantSum[entry.key] =
          (constantSum[entry.key] ?? Rational.zero) + entry.value;
    }
    return LengthEquation(sum, constant: constantSum);
  }

  LengthEquation operator -(LengthEquation other) => this + -other;

  LengthEquation operator -() => scaled(-Rational.one);

  /// This relation taken [factor] times over — constant included, which
  /// is exact because the constant is an exponent vector: half of `ln 2`
  /// is `{2: ½}`, not an approximation of `ln √2`. Rational, unlike the
  /// angle system's integer-only scaling — see the class comment.
  LengthEquation scaled(Rational factor) => LengthEquation(
    {for (final entry in coefficients.entries) entry.key: entry.value * factor},
    constant: {
      for (final entry in constant.entries) entry.key: entry.value * factor,
    },
  );

  /// This relation with its leading coefficient brought to 1, or the
  /// trivial relation unchanged.
  LengthEquation get normalized {
    final variable = leading;
    if (variable == null) return this;
    return scaled(Rational.one / coefficients[variable]!);
  }

  /// The value of `Σ cᵥ·lᵥ` under an [assignment] of log-lengths —
  /// **the variable part only**: a formal `ln p` has no rational value,
  /// so the constant column is not summed in.
  ///
  /// A constant-free relation *holds* under an assignment when this is
  /// zero, which is what makes an assignment an evaluator the closure
  /// can be checked against. A constant-carrying relation holds under a
  /// *formal* assignment — each variable a rational plus a ℚ-vector of
  /// prime logs — exactly when every component vanishes: this method on
  /// the rational components, and per prime `p` this method on the `p`
  /// components plus `constant[p]`. The evaluator tests run that
  /// componentwise check; nothing in `lib/` needs it. A variable the
  /// assignment omits is read as zero.
  Rational evaluate(Map<String, Rational> assignment) {
    var total = Rational.zero;
    for (final entry in coefficients.entries) {
      total = total + entry.value * (assignment[entry.key] ?? Rational.zero);
    }
    return total;
  }

  @override
  bool operator ==(Object other) {
    if (other is! LengthEquation ||
        other.coefficients.length != coefficients.length ||
        other.constant.length != constant.length) {
      return false;
    }
    for (final entry in coefficients.entries) {
      if (other.coefficients[entry.key] != entry.value) return false;
    }
    for (final entry in constant.entries) {
      if (other.constant[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    for (final entry in coefficients.entries) ...[entry.key, entry.value],
    for (final entry in constant.entries) ...[entry.key, entry.value],
  ]);

  /// The variable part on the left, the constant moved to the right and
  /// negated — `l_ab − l_cd − ln 2 = 0` prints as `ab + -cd = ln 2`.
  @override
  String toString() {
    final terms = [
      for (final entry in coefficients.entries)
        '${entry.value == Rational.one
            ? ''
            : entry.value == -Rational.one
            ? '-'
            : entry.value}${entry.key}',
    ];
    final left = terms.isEmpty ? '0' : terms.join(' + ');
    if (constant.isEmpty) return '$left = 0';
    final right = [
      for (final entry in constant.entries)
        '${entry.value == -Rational.one
            ? ''
            : entry.value == Rational.one
            ? '-'
            : '${-entry.value}·'}ln ${entry.key}',
    ];
    return '$left = ${right.join(' + ')}';
  }
}

/// What [LengthClosure.add] did with an equation.
enum LengthAddOutcome {
  /// Already entailed — the closure learned nothing.
  redundant,

  /// New information; the closure grew.
  added,

  /// Together with what was already here, this says `0 = k` for a
  /// non-zero `k`. Unlike the angle side, where a screened diagram makes
  /// this a bug upstream, inconsistent premises are a *sayable* state
  /// here: two stated constants — `|ab| = 2` and `|ab| = 3` — disagree
  /// without either being ill-formed.
  contradiction,
}

/// The closure of a set of [LengthEquation]s under **rational** linear
/// combination — the AR half of DDAR for lengths (PLAN §M-P3).
///
/// This *is* a Gaussian elimination, and saying so is the point: the
/// angle side next door is deliberately not one. Log-lengths are real
/// numbers with no modulus, so the ℚ-span of the input rows is exactly
/// the set of relations they entail, and a pivot may be divided by its
/// own leading coefficient. Session 174 measured what that buys over a
/// union-find on the same facts: on `provoleas2.json` the combination
/// that yields `|AB| = |LO|` carries a coefficient 2 on `l_AO`, so no
/// amount of merging equivalence classes reaches it.
///
/// The basis is kept **fully** reduced — a new pivot is back-substituted
/// into every row that mentions it — so each pivot variable appears in
/// its own row and nowhere else. That is not tidiness: it is what makes
/// [residual] a *canonical* representative of a relation's coset, and
/// the enumeration that reads entailed `eqratio`s off matching residuals
/// is wrong without it (it would bucket by an arbitrary partial
/// reduction and miss pairs that agree).
///
/// **Two stated constants can disagree, so this closure can be
/// inconsistent** — `|ab| = 2` and `|ab| = 3` reduce against each other
/// to `0 = ln(2/3)` — and [add] answers
/// [LengthAddOutcome.contradiction] and latches [isInconsistent], the
/// angle side's arrangement. The contradictory row is not stored: it
/// has no pivot to live under, and entailment stays conservative — an
/// inconsistent closure refuses what its rows do not reach, rather than
/// proving everything ex falso, exactly as `AngleClosure` does.
///
/// **Every row carries its provenance**, on the `AngleClosure`
/// precedent and for the same reason: a proof must be able to name what
/// a step came from, and retrofitting that is a rewrite. [entails]
/// answers *how* — the rational combination of input equations that
/// yields the target — and [recombine] re-multiplies it, so verifying an
/// AR step is arithmetic rather than search.
class LengthClosure {
  /// The equations as they were given, in order. A certificate indexes
  /// into this list.
  final List<LengthEquation> inputs = [];

  /// Pivot variable → the row that leads with it, normalized to a
  /// leading coefficient of 1 and reduced against every other row.
  final Map<String, _Row> _rows = {};

  /// The rows in echelon order — the closure's own basis, which is not
  /// the input set and is usually smaller.
  Iterable<LengthEquation> get rows {
    final keys = _rows.keys.toList()..sort();
    return [for (final key in keys) _rows[key]!.equation];
  }

  int get rank => _rows.length;

  /// Whether an inconsistency has been recorded.
  bool get isInconsistent => _inconsistent;
  bool _inconsistent = false;

  /// Every variable the closure constrains, in order.
  ///
  /// A variable an input mentions but that no row does is one every
  /// relation in the span gives coefficient zero — it is not constrained
  /// and nothing can be concluded about it, so it is not here.
  List<String> get variables {
    final seen = <String>{};
    for (final row in _rows.values) {
      seen.addAll(row.equation.variables);
    }
    return seen.toList()..sort();
  }

  /// Records [equation] and answers what it did.
  ///
  /// The equation joins [inputs] whatever the outcome — a certificate
  /// names inputs by position, so positions must not shift, and a
  /// redundant premise is still a premise the caller supplied.
  LengthAddOutcome add(LengthEquation equation) {
    final index = inputs.length;
    inputs.add(equation);
    final (reduced, support) = _reduce(equation, {index: Rational.one});
    if (reduced.isTrivial) return LengthAddOutcome.redundant;
    if (reduced.isContradictory) {
      _inconsistent = true;
      return LengthAddOutcome.contradiction;
    }

    final pivot = reduced.leading!;
    final scale = Rational.one / reduced.coefficients[pivot]!;
    final row = _Row(reduced.scaled(scale), _scale(support, scale));
    // Back-substitute, so the pivot lives in this row alone. The rows
    // being already reduced against each other, `row` mentions no other
    // pivot, so subtracting a multiple of it introduces none.
    for (final key in _rows.keys.toList()) {
      final existing = _rows[key]!;
      final coefficient = existing.equation.coefficients[pivot];
      if (coefficient == null) continue;
      _rows[key] = _Row(
        existing.equation - row.equation.scaled(coefficient),
        _combine(existing.support, row.support, -coefficient),
      );
    }
    _rows[pivot] = row;
    return LengthAddOutcome.added;
  }

  /// The rational combination of [inputs] that yields [equation], or
  /// null when it is not in their ℚ-span.
  ///
  /// An empty map is a valid answer and means `0 = 0` — the trivial
  /// equation follows from nothing. Nothing here mutates the closure: a
  /// question is not an assertion, and a target that *cannot* be reduced
  /// must not quietly extend the basis on its way to being refused.
  Map<int, Rational>? entails(LengthEquation equation) {
    final (reduced, support) = _reduce(equation, {});
    return reduced.isTrivial ? _negate(support) : null;
  }

  /// Whether [equation] follows — [entails] without the certificate.
  bool proves(LengthEquation equation) => entails(equation) != null;

  /// A canonical representative of [equation]'s coset: two relations
  /// reduce to the same residual exactly when their difference is
  /// entailed, and the trivial residual is [proves].
  ///
  /// This is what lets entailed `eqratio`s be read off buckets of
  /// matching residuals — n² reductions where enumerating quadruples
  /// would be n⁴ — and it is canonical only because the basis is fully
  /// reduced, so every pivot is eliminated rather than only the leading
  /// one.
  LengthEquation residual(LengthEquation equation) =>
      _reduce(equation, const {}).$1;

  /// The equation a [certificate] denotes: `Σ cᵢ·inputs[i]`.
  ///
  /// The other half of the proof obligation. `recombine(entails(e))`
  /// equals `e` whenever `entails` answered, so re-checking an AR step
  /// is a multiplication and not a search — which is what earns AR a
  /// place where Wu and Gröbner were refused for unreadable proofs.
  ///
  /// Throws [RangeError] on an index no input holds.
  LengthEquation recombine(Map<int, Rational> certificate) {
    var total = LengthEquation(const {});
    for (final entry in certificate.entries) {
      if (entry.key < 0 || entry.key >= inputs.length) {
        throw RangeError.index(entry.key, inputs, 'certificate');
      }
      total = total + inputs[entry.key].scaled(entry.value);
    }
    return total;
  }

  /// Eliminates every pivot variable from [equation], carrying
  /// [support] with it.
  ///
  /// The invariant is that `current − Σ support[i]·inputs[i]` does not
  /// move: a caller starting from `{index: 1}` on its own input gets a
  /// row that *is* its support, and a caller starting from `{}` gets a
  /// support whose negation is the reduced equation's certificate.
  (LengthEquation, Map<int, Rational>) _reduce(
    LengthEquation equation,
    Map<int, Rational> support,
  ) {
    var current = equation;
    var used = support;
    while (true) {
      String? pivot;
      for (final variable in current.variables) {
        if (_rows.containsKey(variable)) {
          pivot = variable;
          break;
        }
      }
      if (pivot == null) return (current, used);
      final row = _rows[pivot]!;
      // The row's pivot coefficient is 1, so this is the multiplier.
      final scale = current.coefficients[pivot]!;
      current = current - row.equation.scaled(scale);
      used = _combine(used, row.support, -scale);
    }
  }

  static Map<int, Rational> _negate(Map<int, Rational> support) =>
      _scale(support, -Rational.one);

  static Map<int, Rational> _scale(
    Map<int, Rational> support,
    Rational factor,
  ) => {
    for (final entry in support.entries)
      if (!(entry.value * factor).isZero) entry.key: entry.value * factor,
  };

  /// `into + factor · addend`, dropping cancelled terms so a certificate
  /// never cites an input with coefficient zero.
  static Map<int, Rational> _combine(
    Map<int, Rational> into,
    Map<int, Rational> addend,
    Rational factor,
  ) {
    final out = <int, Rational>{...into};
    for (final entry in addend.entries) {
      final value = (out[entry.key] ?? Rational.zero) + entry.value * factor;
      if (value.isZero) {
        out.remove(entry.key);
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }
}

class _Row {
  _Row(this.equation, this.support);

  final LengthEquation equation;

  /// The rational combination of `LengthClosure.inputs` this row is.
  final Map<int, Rational> support;
}
