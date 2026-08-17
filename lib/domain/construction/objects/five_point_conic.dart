import '../../math/circle_eq.dart';
import '../../projective/absolute.dart';
import '../../projective/conic_matrix.dart';
import '../../projective/conic_shape.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The unique conic through five points — the first kind whose value is a
/// general conic rather than a circle, and the payoff of the projective
/// kernel (Phase 120).
///
/// Five points in general position determine exactly one conic
/// ([ConicMatrix.throughFivePoints]); the kind stores that matrix and every
/// view is a projection of it. [circle] is the circle projection, so a
/// five-point conic that happens to *be* a circle still takes the painter's
/// and hit-tester's circle arm — nothing special-cases it.
///
/// **[isDefined] is [ConicShape.isDrawable]**, not `GeoCircle`'s default
/// "projects to a circle" (PLAN §"A conic is drawn by its own
/// parameterization"): the migration's "real and finite after projection",
/// put to a conic. A degenerate five-point set is therefore still defined
/// when it draws — a crossing or parallel line pair, a doubled line — and
/// undefined when it does not: an imaginary ellipse, an isolated point (two
/// conjugate complex components: a real point, but a conic's ink is its
/// curve), or a set that determines no conic at all.
///
/// Undefined when a parent is undefined, or when two parents projectively
/// coincide (within `projectiveEpsilon`, the `carrierThrough` convention) —
/// coincident points leave a whole pencil of conics rather than one. The
/// remaining rank deficiencies (four or more collinear points) come back
/// from the kernel as a null and need no guard here. Near-degenerate sets
/// are *not* banded: like every V2 kind they produce the genuine, very
/// large conic they determine, and recover continuously on drag.
///
/// Conic-valued kinds live under [GeoCircle] until Phase 121's convention
/// unification renames it; adding a `GeoConic` kind now would break eleven
/// exhaustive switches for no behaviour.
class FivePointConic extends GeoCircle {
  FivePointConic({
    required super.id,
    required List<GeoPoint> points,
    super.attributes,
  }) : points = List.unmodifiable(points) {
    if (points.length != 5) {
      throw ArgumentError.value(
        points.length,
        'points',
        'A conic is determined by five points',
      );
    }
    recompute();
  }

  final List<GeoPoint> points;

  ConicMatrix? _conic;
  CircleEq? _circle;
  bool _drawable = false;

  @override
  ConicMatrix? get conic => _conic;

  @override
  CircleEq? get circle => _circle;

  @override
  bool get isDefined => _drawable;

  @override
  List<GeoObject> get parents => points;

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    _conic = _through();
    _circle = _conic?.toCircleEq();
    _drawable = _conic != null && ConicShape.of(_conic!).isDrawable;
  }

  ConicMatrix? _through() {
    final projective = <ProjPoint>[];
    for (final point in points) {
      final p = point.projPoint;
      if (p == null) {
        return null;
      }
      for (final seen in projective) {
        if (seen.closeTo(p)) {
          return null;
        }
      }
      projective.add(p);
    }
    final k = ConicMatrix.throughFivePoints(projective);
    return (k == null || k.isZero) ? null : k;
  }
}
