/// An exact rational number, for the prover's algebra (PLAN §"AR is a
/// ℤ-module, not a ℚ-vector space").
///
/// **`BigInt` and not `int`, deliberately.** `int` is not the same type
/// on every target this app ships to — 64-bit on the VM and under
/// dart2wasm, a double-backed 53-bit integer under dart2js — so a
/// coefficient large enough to overflow would overflow *differently* per
/// platform, and the browser gate would find it late and confusingly.
/// The systems AR builds are small; exactness is worth more than the
/// arithmetic is expensive, and this is a place where a silent wrong
/// answer is worse than a slow one.
///
/// Values are canonical: the denominator is positive and shares no
/// factor with the numerator, so `==` is value equality and [hashCode]
/// agrees with it. Zero is `0/1`.
///
/// Two consumers with different needs, both served here: the **length**
/// system is ℚ throughout (log-lengths have no modulus), while the
/// **angle** system uses rationals only for its constants, which live in
/// ℚ/ℤ — see [modOne]. The angle system's *coefficients* are integers
/// and are deliberately not rationals: a non-integer coefficient on a
/// variable defined mod π is not a statement at all.
class Rational implements Comparable<Rational> {
  /// Reduces [numerator] / [denominator] to canonical form.
  ///
  /// Throws [ArgumentError] on a zero denominator — a programmer-error
  /// contract, like a degenerate `LineEq`, never a value to propagate.
  factory Rational(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError.value(denominator, 'denominator', 'must not be zero');
    }
    if (numerator == BigInt.zero) {
      return Rational._(BigInt.zero, BigInt.one);
    }
    var n = numerator;
    var d = denominator;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final common = n.gcd(d);
    return Rational._(n ~/ common, d ~/ common);
  }

  const Rational._(this.numerator, this.denominator);

  /// The whole number [value].
  factory Rational.whole(int value) =>
      Rational._(BigInt.from(value), BigInt.one);

  /// [numerator] / [denominator] from machine ints — the spelling the
  /// vocabulary's own constants use (`perp` is one half of π).
  factory Rational.fromInts(int numerator, int denominator) =>
      Rational(BigInt.from(numerator), BigInt.from(denominator));

  /// Parses an exact rational from user text: an optionally signed
  /// integer (`3`, `-2`), a decimal (`2.5`, `.75` — exact, since a
  /// decimal *is* a fraction over a power of ten), or a fraction of
  /// integers (`1/3`, `-45/2`). Surrounding whitespace is ignored, and so
  /// is whitespace beside the slash. Null for anything else — `sqrt(2)`,
  /// `pi`, `1/0`, an empty string — which is the "garbage reads as
  /// cancel" convention the numeric dialogs already follow.
  ///
  /// Deliberately narrower than the expression parser the float dialogs
  /// use: what comes out of here is *stated* in a hypothesis a proof
  /// will cite, so it has to be a number the prover's arithmetic can
  /// carry exactly. An irrational is refused rather than rounded — the
  /// same line `l2const`'s translation draws at `√2`.
  static Rational? tryParse(String text) {
    final s = text.trim();
    final fraction = RegExp(r'^([+-]?\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (fraction != null) {
      final denominator = BigInt.parse(fraction.group(2)!);
      if (denominator == BigInt.zero) return null;
      return Rational(BigInt.parse(fraction.group(1)!), denominator);
    }
    final decimal = RegExp(r'^([+-]?)(\d*)(?:\.(\d+))?$').firstMatch(s);
    if (decimal == null) return null;
    final whole = decimal.group(2)!;
    final places = decimal.group(3) ?? '';
    if (whole.isEmpty && places.isEmpty) return null;
    final digits = BigInt.parse('${whole.isEmpty ? '0' : whole}$places');
    final value = Rational(digits, BigInt.from(10).pow(places.length));
    return decimal.group(1) == '-' ? -value : value;
  }

  /// Always coprime with [denominator]; carries the sign.
  final BigInt numerator;

  /// Always positive.
  final BigInt denominator;

  static final Rational zero = Rational._(BigInt.zero, BigInt.one);
  static final Rational one = Rational._(BigInt.one, BigInt.one);

  bool get isZero => numerator == BigInt.zero;

  bool get isInteger => denominator == BigInt.one;

  bool get isNegative => numerator.isNegative;

  /// −1, 0 or 1.
  int get sign => numerator.sign;

  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Rational operator -(Rational other) => this + (-other);

  Rational operator -() => Rational._(-numerator, denominator);

  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);

  /// Throws [ArgumentError] on division by zero, the same contract the
  /// constructor keeps.
  Rational operator /(Rational other) {
    if (other.isZero) {
      throw ArgumentError.value(other, 'other', 'division by zero');
    }
    return Rational(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }

  Rational get abs => isNegative ? -this : this;

  /// The nearest double — for handing a stated value to a numeric
  /// screen, never for the exact arithmetic everything else here is.
  double toDouble() => numerator.toDouble() / denominator.toDouble();

  /// This value scaled by the integer [factor] — the angle system's only
  /// multiplication, and the reason it never needs a general product.
  Rational scaled(BigInt factor) => Rational(numerator * factor, denominator);

  /// The representative of this value in ℚ/ℤ, in `[0, 1)`.
  ///
  /// The angle system measures constants in units of π and reads them
  /// modulo π, which is modulo 1 in those units: `perp` is `1/2` and
  /// `perp` twice over is `1`, which is `0` — that is `perp_perp_para`,
  /// arrived at by arithmetic instead of by a rule. Floor-based, so a
  /// negative value lands in `[0, 1)` rather than in `(−1, 0]`; two
  /// values are the same angle exactly when their [modOne] agree.
  Rational modOne() => Rational._(numerator % denominator, denominator);

  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  bool operator <(Rational other) => compareTo(other) < 0;

  bool operator <=(Rational other) => compareTo(other) <= 0;

  bool operator >(Rational other) => compareTo(other) > 0;

  bool operator >=(Rational other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => isInteger ? '$numerator' : '$numerator/$denominator';
}
