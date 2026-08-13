import '../../math/circle_relations.dart';
import '../../math/line_eq.dart';
import '../geo_object.dart';

/// The radical axis of two circles: the line of points with equal power
/// to both — through their intersections when they cross, always
/// perpendicular to the line of centers.
///
/// Undefined while either parent is, or while the circles are concentric
/// (no point has equal power); recovers when a drag separates the
/// centers.
class RadicalAxisLine extends GeoLine {
  RadicalAxisLine({
    required super.id,
    required this.circle1,
    required this.circle2,
    super.attributes,
  }) {
    if (identical(circle1, circle2)) {
      throw ArgumentError('RadicalAxisLine requires two distinct circles');
    }
    recompute();
  }

  final GeoCircle circle1;
  final GeoCircle circle2;

  LineEq? _line;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [circle1, circle2];

  @override
  void recompute() {
    final c1 = circle1.circle;
    final c2 = circle2.circle;
    _line = (c1 == null || c2 == null) ? null : radicalAxis(c1, c2);
  }
}
