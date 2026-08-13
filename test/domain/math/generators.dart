import 'package:glados/glados.dart';
import 'package:regula/domain/math/circle_eq.dart';
import 'package:regula/domain/math/line_eq.dart';
import 'package:regula/domain/math/vec2.dart';

/// Shared glados generators for the math layer.
extension MathAnys on Any {
  /// A finite coordinate on a 0.001 grid in [-1000, 1000].
  ///
  /// Built from ints so values shrink nicely and can never be NaN/infinite,
  /// while still exercising non-representable fractions like 0.001.
  Generator<double> get coordinate =>
      intInRange(-1000000, 1000001).map((i) => i / 1000);

  Generator<Vec2> get vec2 => combine2(coordinate, coordinate, Vec2.new);

  /// An interpolation parameter in [0, 1] on a 0.001 grid.
  Generator<double> get unitInterval =>
      intInRange(0, 1001).map((i) => i / 1000);

  /// An angle in [-π, π] (approximately) on a 0.0001 grid.
  Generator<double> get angle =>
      intInRange(-31416, 31417).map((i) => i / 10000);

  /// A strictly positive radius in (0, 1000] on a 0.001 grid.
  Generator<double> get positiveRadius =>
      intInRange(1, 1000001).map((i) => i / 1000);

  /// A line through two generated points; when the points coincide the
  /// second is nudged so the generator never produces a degenerate line.
  Generator<LineEq> get lineEq => combine2(
    vec2,
    vec2,
    (Vec2 p, Vec2 q) =>
        LineEq.throughPoints(p, p == q ? q + const Vec2(1, 0) : q),
  );

  Generator<CircleEq> get circleEq =>
      combine2(vec2, positiveRadius, CircleEq.new);
}
