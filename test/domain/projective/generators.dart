import 'package:glados/glados.dart';
import 'package:regula/domain/projective/complex.dart';

/// Shared glados generators for the projective layer.
extension ProjectiveAnys on Any {
  /// A finite component on a 0.001 grid in [-1000, 1000].
  ///
  /// Built from ints so values shrink nicely and can never be NaN/infinite,
  /// while still exercising non-representable fractions like 0.001.
  Generator<double> get component =>
      intInRange(-1000000, 1000001).map((i) => i / 1000);

  Generator<Complex> get complex => combine2(component, component, Complex.new);

  /// A complex number bounded away from zero: both grid components, at least
  /// one with |value| ≥ 1, so multiplicative inverses stay well-conditioned.
  Generator<Complex> get nonZeroComplex => combine2(
        component,
        component,
        (double re, double im) =>
            re.abs() >= 1 || im.abs() >= 1 ? Complex(re, im) : Complex(re + 2, im),
      );
}
