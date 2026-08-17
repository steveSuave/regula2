import '../../math/angle_geometry.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/ck_measure.dart';
import '../geo_object.dart';
import '../object_attributes.dart';

/// The angle between two lines, marked at their intersection.
///
/// Which wedge is marked depends on [sign1]/[sign2]. When absent (legacy
/// saves, direct construction) the marker always folds to the acute (or
/// right) angle, in (0, π/2]. When present, each sign picks a half of its
/// carrier — `signᵢ · d̂ᵢ` — and the marker is the wedge between those
/// half-lines, with sweep in (0, π); [LineAngle.near] bakes the signs
/// from the two tap positions so the marked wedge is the one the user
/// pointed at, obtuse pairs included. Like `TwoLineBisectorLine.branch`,
/// the signs are relative to the canonical carrier directions:
/// deterministic and drag-continuous, but a drag that reverses a
/// carrier's direction (defining points swapping order) flips which half
/// the sign means.
///
/// Undefined while the carriers are parallel — there is no vertex to mark
/// and the measure would be 0 — or a parent is undefined. Segments and
/// rays work as parents through their carriers, so the marked vertex can
/// sit outside their drawn extent, matching `IntersectionPoint`'s
/// deferred-clipping caveat.
///
/// Migrated (Phase 112): the vertex is the projective meet of the
/// carriers, projected into the chart — parallel carriers meet at
/// infinity, coincident carriers on the zero triple, and both project to
/// null, so "no vertex to mark" falls out of the projection (V1's
/// absolute `intersectLineLine` parallel band is gone; near-parallel
/// carriers mark a genuine faraway vertex, at-infinity within `toVec2`'s
/// relative tolerance goes undefined). The wedge *directions* stay reads
/// of the parents' anchored affine projections — [sign1]/[sign2] are ray
/// concepts relative to the canonical carrier orientations, which only
/// `GeoLine.line` (via `orientedAlong`) carries; same sanctioned chart
/// read as `TwoLineBisectorLine`'s branch anchoring.
class LineAngle extends GeoAngle {
  LineAngle({
    required super.id,
    required this.line1,
    required this.line2,
    this.sign1,
    this.sign2,
    super.attributes,
  }) {
    if ((sign1 == null) != (sign2 == null)) {
      throw ArgumentError('sign1 and sign2 must be both absent or both given');
    }
    final s1 = sign1;
    final s2 = sign2;
    if ((s1 != null && s1.abs() != 1) || (s2 != null && s2.abs() != 1)) {
      throw ArgumentError('sign1/sign2 must be +1 or -1');
    }
    recompute();
  }

  /// The wedge between the tapped halves: each tap picks the half of its
  /// line on the tap's side of the crossing (`sᵢ = sign((tapᵢ − v)·d̂ᵢ)`),
  /// so tapping with the obtuse pair between the taps yields the obtuse
  /// marker. Falls back to `+1/+1` while the carriers don't currently
  /// cross (the angle is undefined then anyway; it appears when they do).
  factory LineAngle.near({
    required String id,
    required GeoLine line1,
    required GeoLine line2,
    required Vec2 tap1,
    required Vec2 tap2,
    ObjectAttributes? attributes,
  }) {
    var s1 = 1;
    var s2 = 1;
    final l1 = line1.line;
    final l2 = line2.line;
    final p1 = line1.projLine;
    final p2 = line2.projLine;
    if (l1 != null && l2 != null && p1 != null && p2 != null) {
      final v = p1.meet(p2).toVec2();
      if (v != null) {
        s1 = (tap1 - v).dot(l1.direction) < 0 ? -1 : 1;
        s2 = (tap2 - v).dot(l2.direction) < 0 ? -1 : 1;
      }
    }
    return LineAngle(
      id: id,
      line1: line1,
      line2: line2,
      sign1: s1,
      sign2: s2,
      attributes: attributes,
    );
  }

  final GeoLine line1;
  final GeoLine line2;

  /// Which half of each carrier the marker opens between, +1 (along the
  /// canonical direction) or −1 — or null on both for the legacy
  /// always-acute fold.
  final int? sign1;
  final int? sign2;

  AngleGeometry? _angle;
  double? _measure;
  bool _euclidean = true;

  @override
  AngleGeometry? get angle => _angle;

  /// Chart marker, Cayley-Klein measure (Phase 124). Euclidean angle
  /// measure is already elliptic and the chart formula is exactly the CK
  /// one, so Euclidean keeps its exact chart answer; a proper absolute
  /// measures between the carriers projectively.
  @override
  double? get measure => _euclidean ? _angle?.measure : _measure;

  @override
  List<GeoObject> get parents => [line1, line2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final l1 = line1.line;
    final l2 = line2.line;
    final p1 = line1.projLine;
    final p2 = line2.projLine;
    if (l1 == null || l2 == null || p1 == null || p2 == null) {
      _angle = null;
      _measure = null;
      _euclidean = absolute.isEuclidean;
      return;
    }
    // Parallel carriers meet at infinity, coincident ones on the zero
    // triple — both project to null: no vertex to mark.
    final vertex = p1.meet(p2).toVec2();
    if (vertex == null) {
      _angle = null;
      _measure = null;
      _euclidean = absolute.isEuclidean;
      return;
    }
    final s1 = sign1;
    final s2 = sign2;
    _euclidean = absolute.isEuclidean;
    _measure = absolute.isEuclidean
        ? null
        : angleBetweenLines(absolute, p1, p2);
    _angle = (s1 == null || s2 == null)
        ? AngleGeometry.betweenLines(vertex, l1.direction, l2.direction)
        : AngleGeometry.betweenHalfLines(
            vertex,
            l1.direction * s1.toDouble(),
            l2.direction * s2.toDouble(),
          );
  }
}
