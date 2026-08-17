import 'dart:math' as math;

/// An immutable complex number over doubles.
///
/// This is the scalar type of the projective kernel (`lib/domain/projective/`):
/// homogeneous coordinates, conic matrices, and intersection roots are complex,
/// and realness becomes a *rendering* question answered by [isRealWithin].
///
/// Conventions pinned here (and in `complex_test.dart`):
/// - [arg] is in (−π, π], with `arg(-1) = π`.
/// - [sqrt] is the principal branch: the branch cut lies along the negative
///   real axis and results have non-negative real part; for negative real
///   inputs the root is `+i·sqrt(|x|)`.
/// - Division by zero produces NaN/infinite components rather than throwing;
///   totality is the point of the projective kernel, and NaN propagates to a
///   null projection at the rendering boundary.
///
/// Boxed `Complex` is the API type. The tracing inner loop (Phases 113–116)
/// uses `Float64List` struct-of-arrays instead — see `benchmark/` for the
/// measured gap and the SoA shape.
class Complex {
  final double re;
  final double im;

  const Complex(this.re, [this.im = 0]);

  /// The complex number `r·e^{iθ}`.
  factory Complex.polar(double r, double theta) =>
      Complex(r * math.cos(theta), r * math.sin(theta));

  static const Complex zero = Complex(0);
  static const Complex one = Complex(1);
  static const Complex i = Complex(0, 1);

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);

  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);

  Complex operator -() => Complex(-re, -im);

  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  /// Complex division via Smith's algorithm (scales by the larger component
  /// of the divisor to avoid overflow/underflow of the naive formula).
  Complex operator /(Complex other) {
    if (other.re.abs() >= other.im.abs()) {
      final r = other.im / other.re;
      final d = other.re + other.im * r;
      return Complex((re + im * r) / d, (im - re * r) / d);
    } else {
      final r = other.re / other.im;
      final d = other.re * r + other.im;
      return Complex((re * r + im) / d, (im * r - re) / d);
    }
  }

  /// This number scaled by a real factor (cheaper than `* Complex(k)`).
  Complex scale(double k) => Complex(re * k, im * k);

  /// The complex conjugate.
  Complex get conj => Complex(re, -im);

  /// The squared magnitude `re² + im²` (cheaper than [abs]; prefer it in
  /// comparisons).
  double get abs2 => re * re + im * im;

  /// The magnitude `|z|`.
  double get abs => math.sqrt(abs2);

  /// The argument in (−π, π]; `arg(-1) = π`.
  double get arg => math.atan2(im, re);

  /// The principal square root: branch cut along the negative real axis,
  /// result in the closed right half-plane, `sqrt(-x) = i·sqrt(x)` for real
  /// `x > 0`. Satisfies `sqrt(z) * sqrt(z) ≈ z`.
  ///
  /// Uses the numerically stable half-angle formulation rather than
  /// `polar(sqrt(r), θ/2)`.
  Complex get sqrt {
    if (re == 0 && im == 0) return zero;
    final t = math.sqrt((abs + re.abs()) / 2);
    if (re >= 0) {
      return Complex(t, im / (2 * t));
    }
    // -0.0 >= 0 is true, so a negative-real input (im == 0.0 or -0.0 after
    // arithmetic that preserves the sign of zero) lands on the +i side here
    // exactly when its im compares >= 0 — the principal convention.
    return Complex(im.abs() / (2 * t), im >= 0 ? t : -t);
  }

  /// The complex cosine, `cos(a+bi) = cos a·cosh b − i·sin a·sinh b`
  /// (Phase 116b: circle carriers continued to complex angles). Bitwise
  /// `Complex(cos(re), ±0)` on the real axis — `cosh 0` is exactly 1 and
  /// `sinh 0` exactly 0, so a detour entering and leaving the axis meets
  /// the real evaluation exactly.
  Complex get cos =>
      Complex(math.cos(re) * _cosh(im), -math.sin(re) * _sinh(im));

  /// The complex sine, `sin(a+bi) = sin a·cosh b + i·cos a·sinh b`.
  /// Bitwise-real on the real axis, like [cos].
  Complex get sin =>
      Complex(math.sin(re) * _cosh(im), math.cos(re) * _sinh(im));

  // dart:math has no hyperbolic functions; exp(0) is exactly 1, so both
  // are bitwise-exact at 0 (cosh → 1, sinh → 0), which [cos]/[sin]'s
  // real-axis guarantee rides on.
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

  bool get isFinite => re.isFinite && im.isFinite;

  bool get isNaN => re.isNaN || im.isNaN;

  /// Whether this number is real up to a hybrid absolute/relative tolerance:
  /// `|im| ≤ eps · max(1, |re|)`. Absolute near the unit scale, relative for
  /// large magnitudes — callers working with homogeneous coordinates should
  /// normalize before asking.
  bool isRealWithin(double eps) => im.abs() <= eps * math.max(1, re.abs());

  /// Whether this number is within a hybrid absolute/relative distance of
  /// [other]: `|this − other| ≤ eps · max(1, |this|, |other|)`.
  bool closeTo(Complex other, double eps) {
    final d = this - other;
    final scaleSq = math.max(1.0, math.max(abs2, other.abs2));
    return d.abs2 <= eps * eps * scaleSq;
  }

  @override
  bool operator ==(Object other) =>
      other is Complex && re == other.re && im == other.im;

  @override
  int get hashCode => Object.hash(re, im);

  @override
  String toString() => im >= 0 ? '$re + ${im}i' : '$re - ${-im}i';
}
