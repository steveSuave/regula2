import 'package:glados/glados.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/proj_transform.dart';

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

  /// An affine point/vector with both coordinates on the component grid.
  Generator<Vec2> get vec2 => combine2(component, component, Vec2.new);

  /// A homogeneous point triple bounded away from the zero vector: three
  /// grid complex coordinates, with `w` bumped by 1 when the triple is tiny.
  Generator<ProjPoint> get projPoint =>
      combine3(complex, complex, complex, (Complex x, Complex y, Complex w) {
        final p = ProjPoint(x, y, w);
        return p.norm2 >= 1 ? p : ProjPoint(x, y, w + Complex.one);
      });

  /// A homogeneous line triple bounded away from the zero vector: three
  /// grid complex coefficients, with `c` bumped by 1 when the triple is tiny.
  Generator<ProjLine> get projLine =>
      combine3(complex, complex, complex, (Complex a, Complex b, Complex c) {
        final l = ProjLine(a, b, c);
        return l.norm2 >= 1 ? l : ProjLine(a, b, c + Complex.one);
      });

  /// A real direct similarity — translation ∘ rotation ∘ homothety with
  /// grid parameters, the ratio bounded away from zero — always invertible.
  Generator<ProjTransform> get similarity => combine4(
    vec2,
    component,
    vec2,
    component,
    (Vec2 t, double angle, Vec2 c, double r) =>
        ProjTransform.translation(t.x, t.y)
            .compose(ProjTransform.rotation(ProjPoint.lift(c), angle / 300))
            .compose(
              ProjTransform.homothety(
                ProjPoint.lift(c),
                r.abs() >= 0.5 ? r : r + 1,
              ),
            ),
  );

  /// A general complex 3×3 transform bounded away from the zero matrix.
  /// May be near-singular — tests needing invertibility must filter by
  /// `|det|` relative to the Frobenius norm.
  Generator<ProjTransform> get projTransform => combine9(
    complex,
    complex,
    complex,
    complex,
    complex,
    complex,
    complex,
    complex,
    complex,
    (
      Complex m00,
      Complex m01,
      Complex m02,
      Complex m10,
      Complex m11,
      Complex m12,
      Complex m20,
      Complex m21,
      Complex m22,
    ) {
      final t = ProjTransform(m00, m01, m02, m10, m11, m12, m20, m21, m22);
      return t.norm2 >= 1
          ? t
          : ProjTransform(
              m00,
              m01,
              m02,
              m10,
              m11,
              m12,
              m20,
              m21,
              m22 + Complex.one,
            );
    },
  );
}
