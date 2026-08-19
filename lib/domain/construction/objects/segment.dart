import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';
import 'line_through_two_points.dart';

/// The segment between two points.
///
/// A [GeoLine] via its carrier [line], so segments participate in
/// intersections like infinite lines do (clipping intersection points to
/// the segment's extent is deferred — see `IntersectionPoint`; constrained
/// points do clamp, via [parameterExtent]). Undefined while the endpoints
/// coincide or a parent is undefined.
///
/// Migrated (Phase 107): the carrier is the projective join
/// ([carrierThrough]).
///
/// **The carrier is total; only the drawn extent is a chart reading**
/// (Phase 136b). A segment *is* its extent, so [line], [start], [end],
/// [parameterExtent] and therefore [isDefined] all require both
/// endpoints real and finite, exactly as in V1 — but [projLine] does
/// not, because it is the projective value and the one degeneracy
/// convention says a projective value is null only when a parent's is
/// or the join is the zero triple (see `GeoObject`). Phase 107 gated the
/// carrier on the chart too, and that made the object silently
/// *untraceable*: a complex detour drives an endpoint off the real axis,
/// the carrier vanished, and every intersection riding this segment
/// coasted through the whole arc on a stale root — so the detour
/// resolved nothing and the exit fell back to a nearest match at the
/// crossing, which is the coin flip the arc exists to remove. A chord
/// built as a `LineThroughTwoPoints` had no such problem, which is the
/// entire difference Phase 136b's reproducer was measuring.
///
/// Nothing static changes for a *complex* endpoint: `intersectionCandidates`
/// refuses complex carriers on its own (the Phase 110 realness gate), so
/// the carrier is visible only to a pass that has asked for it. An
/// endpoint at *infinity* does now yield the real line through the finite
/// endpoint in that direction, which is what `LineThroughTwoPoints` has
/// answered since Phase 107 and what `IntersectionPoint` already assumes
/// when it says segments intersect via their infinite carrier.
class Segment extends GeoLine {
  Segment({
    required super.id,
    required this.point1,
    required this.point2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point1;
  final GeoPoint point2;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  /// Current endpoints; null while the respective parent is undefined.
  /// The painter draws from these, [line] exists for intersection math.
  Vec2? get start => point1.position;
  Vec2? get end => point2.position;

  /// Both endpoints' carrier parameters, ordered.
  @override
  (double?, double?)? get parameterExtent {
    final line = _line;
    if (line == null) {
      return null;
    }
    final t1 = line.parameterAt(point1.position!);
    final t2 = line.parameterAt(point2.position!);
    return t1 <= t2 ? (t1, t2) : (t2, t1);
  }

  @override
  List<GeoObject> get parents => [point1, point2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    _carrier = carrierThrough(point1, point2);
    final p1 = point1.position;
    final p2 = point2.position;
    // The projection stays gated on the chart: a segment with an
    // endpoint that has no real finite position has no drawable extent,
    // so it stays undefined ([isDefined] reads [line]) and the painter,
    // hit tester and [parameterExtent] see exactly what they saw before.
    _line = (p1 == null || p2 == null)
        ? null
        : orientedAlong(_carrier?.toLineEq(), p2 - p1);
  }
}
