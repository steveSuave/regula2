import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/euclidean.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import 'relative_line.dart';

/// The line through [through], perpendicular to [reference].
///
/// The join of the through-point with the reference's conjugate direction
/// w.r.t. the circular points I, J.
class PerpendicularLine extends RelativeLine {
  PerpendicularLine({
    required super.id,
    required super.through,
    required super.reference,
    super.attributes,
  });

  @override
  ProjLine carrierFrom(ProjPoint through, ProjLine reference) =>
      perpendicularThrough(through, reference);

  @override
  Vec2 directionFrom(LineEq referenceLine) => referenceLine.normal;
}
