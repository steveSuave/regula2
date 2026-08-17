import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/metric.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import 'relative_line.dart';

/// The line through [through], parallel to [reference].
///
/// The join of the through-point with the reference's point at infinity
/// (its meet with the line at infinity). When [through] lies on the
/// reference the two lines coincide — that is still a defined line, not a
/// degeneracy.
class ParallelLine extends RelativeLine {
  ParallelLine({
    required super.id,
    required super.through,
    required super.reference,
    super.attributes,
  });

  @override
  ProjLine carrierFrom(ProjPoint through, ProjLine reference) =>
      parallelThrough(through, reference);

  @override
  Vec2 directionFrom(LineEq referenceLine) => referenceLine.direction;
}
